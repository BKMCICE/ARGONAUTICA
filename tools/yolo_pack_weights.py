"""Fold YOLO-Fastest batch norm and pack per-output-channel INT8 kernels.

This prepares weights for an RV32 port. It does not quantize activations or
implement inference; the exported float32 scale/bias still need fixed-point
calibration before the MMIO convolution unit can consume them.
"""
import hashlib
import json
from pathlib import Path

import numpy as np

from yolo_model_manifest import manifest


def pack(model_dir: Path) -> dict:
    cfg = model_dir / "yolo-fastest-1.1.cfg"
    original = model_dir / "yolo-fastest-1.1.weights"
    layout = manifest(cfg, original)
    weights = np.frombuffer(original.read_bytes(), dtype="<f4", offset=20)
    packed = bytearray()
    params = bytearray()
    entries = []
    squared_error = 0.0
    squared_reference = 0.0
    maximum_error = 0.0
    for layer in layout["layers"]:
        if layer["type"] != "convolutional":
            continue
        channels_out = layer["shape"][2]
        channels_in_group = layer["input"][2] // layer["groups"]
        kernel_count = channels_out * channels_in_group * layer["size"] ** 2
        block = weights[layer["float_offset"]:layer["float_offset"] + layer["float_count"]]
        bias = block[:channels_out].astype(np.float64)
        pos = channels_out
        if layer["batch_norm"]:
            gamma = block[pos:pos + channels_out].astype(np.float64)
            mean = block[pos + channels_out:pos + 2 * channels_out].astype(np.float64)
            var = block[pos + 2 * channels_out:pos + 3 * channels_out].astype(np.float64)
            pos += 3 * channels_out
            gain = gamma / np.sqrt(var + 1.0e-5)
            bias = bias - mean * gain
        else:
            gain = np.ones(channels_out, dtype=np.float64)
        kernel = block[pos:].reshape(channels_out, -1).astype(np.float64)
        if kernel.size != kernel_count:
            raise ValueError(f"layer {layer['index']}: kernel size mismatch")
        folded = kernel * gain[:, None]
        scale = np.max(np.abs(folded), axis=1) / 127.0
        scale[scale == 0] = 1.0
        quant = np.clip(np.rint(folded / scale[:, None]), -127, 127).astype(np.int8)
        restored = quant.astype(np.float64) * scale[:, None]
        delta = folded - restored
        squared_error += float(np.sum(delta * delta))
        squared_reference += float(np.sum(folded * folded))
        maximum_error = max(maximum_error, float(np.max(np.abs(delta))))
        weight_offset = len(packed)
        param_offset = len(params)
        packed.extend(quant.tobytes())
        # Each output channel has little-endian float32 (kernel scale, bias).
        pairs = np.column_stack((scale, bias)).astype("<f4")
        params.extend(pairs.tobytes())
        entries.append({"layer": layer["index"], "weight_offset": weight_offset,
                        "weight_bytes": kernel_count, "param_offset": param_offset,
                        "output_channels": channels_out, "input_channels_per_group": channels_in_group,
                        "kernel_size": layer["size"], "groups": layer["groups"]})
    weight_path = model_dir / "weights_int8.bin"
    param_path = model_dir / "params_fp32.bin"
    weight_path.write_bytes(packed)
    param_path.write_bytes(params)
    result = {"source_sha256": hashlib.sha256(original.read_bytes()).hexdigest(),
              "weights_sha256": hashlib.sha256(packed).hexdigest(),
              "params_sha256": hashlib.sha256(params).hexdigest(),
              "weights_bytes": len(packed), "params_bytes": len(params),
              "relative_l2_error": (squared_error / squared_reference) ** 0.5,
              "max_abs_error": maximum_error, "convolutions": entries}
    (model_dir / "quant_manifest.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


if __name__ == "__main__":
    directory = Path(__file__).resolve().parent.parent / "models/yolo_fastest_1_1"
    packed = pack(directory)
    print(f"convs={len(packed['convolutions'])} weights_bytes={packed['weights_bytes']} "
          f"params_bytes={packed['params_bytes']} relative_l2_error={packed['relative_l2_error']:.8f} "
          f"max_abs_error={packed['max_abs_error']:.8f}")

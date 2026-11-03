"""Export fixed-point Q24 requantization parameters for the YOLO layer graph.

Run yolo_pack_weights.py and yolo_int8_reference.py first. The resulting
params_q24.bin has two little-endian signed int32 values per output channel:
MAC-to-output Q24 multiplier and output-unit bias. The JSON graph records
integer rescale coefficients for route/shortcut/pool/upsample edges.
"""
import hashlib
import json
from pathlib import Path

import numpy as np

from yolo_model_manifest import manifest, parse_cfg


def q24(ratio):
    values = np.rint(np.asarray(ratio, dtype=np.float64) * (1 << 24))
    if np.any(values > np.iinfo(np.int32).max) or np.any(values < np.iinfo(np.int32).min):
        raise ValueError("Q24 multiplier overflow")
    return values.astype("<i4")


def pack(model_dir: Path) -> dict:
    layout = manifest(model_dir / "yolo-fastest-1.1.cfg",
                      model_dir / "yolo-fastest-1.1.weights")
    sections = parse_cfg(model_dir / "yolo-fastest-1.1.cfg")[1:]
    activation_path = model_dir / "activation_scales_2img.json"
    activation = json.loads(activation_path.read_text(encoding="utf-8"))
    scales = activation["scales"]
    if len(scales) != len(layout["layers"]):
        raise ValueError("activation scale count mismatch")
    quant = json.loads((model_dir / "quant_manifest.json").read_text(encoding="utf-8"))
    conv_info = {item["layer"]: item for item in quant["convolutions"]}
    fp_params = (model_dir / "params_fp32.bin").read_bytes()
    raw = bytearray()
    ops = []
    for layer, sec in zip(layout["layers"], sections):
        idx = layer["index"]
        kind = layer["type"]
        input_scale = 1 / 127 if idx == 0 else scales[idx - 1]
        output_scale = scales[idx]
        op = {"index": idx, "type": kind, "input": layer.get("input"),
              "shape": layer["shape"]}
        if kind == "convolutional":
            info = conv_info[idx]
            filters = info["output_channels"]
            pairs = np.frombuffer(fp_params, dtype="<f4", count=2 * filters,
                                  offset=info["param_offset"]).reshape(filters, 2)
            mul = q24(input_scale * pairs[:, 0].astype(np.float64) / output_scale)
            bias = np.rint(pairs[:, 1].astype(np.float64) / output_scale)
            if np.any(np.abs(bias) > np.iinfo(np.int32).max):
                raise ValueError(f"layer {idx}: bias overflow")
            offset = len(raw)
            raw.extend(np.column_stack((mul, bias.astype("<i4"))).astype("<i4").tobytes())
            op.update({"weight_offset": info["weight_offset"],
                       "weight_bytes": info["weight_bytes"], "param_offset": offset,
                       "output_channels": filters, "input_channels_per_group": info["input_channels_per_group"],
                       "kernel_size": info["kernel_size"], "groups": info["groups"],
                       "stride": layer["stride"], "activation": layer["activation"],
                       "padding": layer["size"] // 2 if int(sec.get("pad", 0)) else
                       int(sec.get("padding", 0))})
        elif kind == "route":
            op["sources"] = layer["sources"]
            op["source_q24"] = [int(q24(scales[s] / output_scale)) for s in layer["sources"]]
        elif kind == "shortcut":
            op["source"] = layer["source"]
            op["previous_q24"] = int(q24(input_scale / output_scale))
            op["source_q24"] = int(q24(scales[layer["source"]] / output_scale))
        elif kind in ("maxpool", "upsample", "dropout", "yolo"):
            op["previous_q24"] = int(q24(input_scale / output_scale))
            if kind in ("maxpool", "upsample"):
                op["size"] = layer.get("size", layer.get("stride"))
                op["stride"] = layer["stride"]
        else:
            raise ValueError(f"unsupported layer {idx}: {kind}")
        ops.append(op)
    fixed_path = model_dir / "params_q24.bin"
    fixed_path.write_bytes(raw)
    result = {"activation_sha256": hashlib.sha256(activation_path.read_bytes()).hexdigest(),
              "weights_sha256": quant["weights_sha256"],
              "params_q24_sha256": hashlib.sha256(raw).hexdigest(),
              "params_q24_bytes": len(raw), "q_fractional_bits": 24,
              "layers": ops}
    (model_dir / "fixed_manifest.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


if __name__ == "__main__":
    directory = Path(__file__).resolve().parent.parent / "models/yolo_fastest_1_1"
    result = pack(directory)
    print(f"layers={len(result['layers'])} params_q24_bytes={result['params_q24_bytes']} "
          f"sha256={result['params_q24_sha256']}")

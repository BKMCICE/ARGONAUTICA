"""Calibrate activation INT8 scales and run the complete YOLO layer graph.

Convolutions use exact integer-valued operands/accumulators (float64 is an
exact host container for their sums); output requantization and YOLO decode
remain host floating-point. This is a numerical reference, not RV32 firmware.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as f

from yolo_float_reference import decode_head, nms
from yolo_model_manifest import manifest, parse_cfg


def load_image(path: Path | None, width: int, height: int) -> torch.Tensor:
    if path is None:
        return torch.zeros((1, 3, height, width), dtype=torch.float32)
    from PIL import Image

    with Image.open(path) as img:
        rgb = img.convert("RGB").resize((width, height))
        pixels = np.asarray(rgb, dtype=np.float32).transpose(2, 0, 1) / 255.0
    return torch.from_numpy(pixels.copy())[None]


def layer_params(model_dir: Path, layout: dict) -> dict[int, tuple[torch.Tensor, torch.Tensor,
                                                                   torch.Tensor]]:
    info = json.loads((model_dir / "quant_manifest.json").read_text(encoding="utf-8"))
    raw = (model_dir / "weights_int8.bin").read_bytes()
    params = (model_dir / "params_fp32.bin").read_bytes()
    if hashlib.sha256(raw).hexdigest() != info["weights_sha256"] or \
            hashlib.sha256(params).hexdigest() != info["params_sha256"]:
        raise ValueError("packed model hash mismatch")
    layers = {layer["index"]: layer for layer in layout["layers"]}
    result = {}
    for item in info["convolutions"]:
        layer = layers[item["layer"]]
        out_channels = item["output_channels"]
        q = np.frombuffer(raw, dtype="i1", count=item["weight_bytes"],
                          offset=item["weight_offset"]).copy()
        q = torch.from_numpy(q).reshape(out_channels, item["input_channels_per_group"],
                                        item["kernel_size"], item["kernel_size"])
        pairs = np.frombuffer(params, dtype="<f4", count=2 * out_channels,
                              offset=item["param_offset"]).reshape(out_channels, 2)
        result[layer["index"]] = (q, torch.from_numpy(pairs[:, 0].copy()),
                                  torch.from_numpy(pairs[:, 1].copy()))
    return result


def forward(x: torch.Tensor, sections: list[dict], layout: dict, params: dict,
            act_scales: list[float] | None) -> tuple[list[torch.Tensor], list[float]]:
    outputs = []
    scales = []
    input_scale = 1.0 / 127.0
    if act_scales is not None:
        x = torch.clamp(torch.round(x / input_scale), -127, 127).to(torch.int8)
    for sec, layer in zip(sections, layout["layers"]):
        idx = layer["index"]
        kind = layer["type"]
        if kind == "convolutional":
            q_weight, weight_scale, bias = params[idx]
            pad = layer["size"] // 2 if int(sec.get("pad", 0)) else int(sec.get("padding", 0))
            if act_scales is None:
                weight = q_weight.float() * weight_scale.view(-1, 1, 1, 1)
                y = f.conv2d(x, weight, bias, stride=layer["stride"], padding=pad,
                             groups=layer["groups"])
            else:
                # The FP64 convolution sums integer products exactly for this
                # model's channel/kernel sizes (far below 2**53).
                acc = f.conv2d(x.double(), q_weight.double(), None,
                               stride=layer["stride"], padding=pad,
                               groups=layer["groups"])
                y = (acc * (input_scale * weight_scale.double()).view(1, -1, 1, 1) +
                     bias.double().view(1, -1, 1, 1)).float()
            if layer["activation"] == "leaky":
                y = f.leaky_relu(y, 0.1)
            elif layer["activation"] != "linear":
                raise ValueError(f"activation {layer['activation']}")
        elif kind == "route":
            y = torch.cat([outputs[i].float() * scales[i] for i in layer["sources"]], dim=1) \
                if act_scales is not None else torch.cat([outputs[i] for i in layer["sources"]], dim=1)
        elif kind == "shortcut":
            source = layer["source"]
            y = x.float() * input_scale + outputs[source].float() * scales[source] \
                if act_scales is not None else x + outputs[source]
        elif kind == "maxpool":
            source = x.float() * input_scale if act_scales is not None else x
            y = f.max_pool2d(source, layer["size"], layer["stride"], padding=layer["size"] // 2)
        elif kind == "upsample":
            source = x.float() * input_scale if act_scales is not None else x
            y = f.interpolate(source, scale_factor=layer["stride"], mode="nearest")
        elif kind in ("dropout", "yolo"):
            y = x.float() * input_scale if act_scales is not None else x
        else:
            raise ValueError(f"layer {idx}: {kind}")
        if list(y.shape[2:]) + [y.shape[1]] != layer["shape"]:
            raise ValueError(f"layer {idx} shape mismatch")
        out_scale = (max(float(y.abs().max()), 1.0e-8) / 127.0 if act_scales is None
                     else act_scales[idx])
        x = y if act_scales is None else torch.clamp(torch.round(y / out_scale), -127, 127).to(torch.int8)
        outputs.append(x)
        scales.append(out_scale)
        input_scale = out_scale
    return outputs, scales


def apply_q24(value: torch.Tensor, multiplier: torch.Tensor | int) -> torch.Tensor:
    """Symmetric rounding of signed integer values times a stored Q24 multiplier."""
    product = value.to(torch.int64) * multiplier
    return torch.where(product >= 0, (product + (1 << 23)) >> 24,
                       -(((-product) + (1 << 23)) >> 24))


def forward_fixed(x: torch.Tensor, sections: list[dict], layout: dict,
                  params: dict, act_scales: list[float], fixed: dict,
                  fixed_params: bytes) -> list[torch.Tensor]:
    """Integer requantization, bias and layer graph; FP64 only holds exact MACs."""
    input_scale = 1.0 / 127.0
    x = torch.clamp(torch.round(x / input_scale), -127, 127).to(torch.int8)
    outputs = []
    ops = fixed["layers"]
    for sec, layer in zip(sections, layout["layers"]):
        idx = layer["index"]
        out_scale = act_scales[idx]
        kind = layer["type"]
        op = ops[idx]
        if kind == "convolutional":
            q_weight, _, _ = params[idx]
            pad = layer["size"] // 2 if int(sec.get("pad", 0)) else int(sec.get("padding", 0))
            acc = f.conv2d(x.double(), q_weight.double(), None,
                           stride=layer["stride"], padding=pad,
                           groups=layer["groups"]).to(torch.int64)
            pairs = np.frombuffer(fixed_params, dtype="<i4", count=2 * op["output_channels"],
                                  offset=op["param_offset"]).reshape(op["output_channels"], 2)
            multiplier = torch.from_numpy(pairs[:, 0].astype(np.int64)).view(1, -1, 1, 1)
            bias_q = torch.from_numpy(pairs[:, 1].astype(np.int64)).view(1, -1, 1, 1)
            y = apply_q24(acc, multiplier) + bias_q
            if layer["activation"] == "leaky":
                y = torch.where(y < 0, apply_q24(y, 1677722), y)
            elif layer["activation"] != "linear":
                raise ValueError(f"activation {layer['activation']}")
        elif kind == "route":
            y = torch.cat([apply_q24(outputs[i], multiplier)
                           for i, multiplier in zip(op["sources"], op["source_q24"])], dim=1)
        elif kind == "shortcut":
            src = layer["source"]
            y = apply_q24(x, op["previous_q24"]) + \
                apply_q24(outputs[src], op["source_q24"])
        elif kind == "maxpool":
            pooled = f.max_pool2d(x.double(), layer["size"], layer["stride"],
                                  padding=layer["size"] // 2).to(torch.int64)
            y = apply_q24(pooled, op["previous_q24"])
        elif kind == "upsample":
            enlarged = f.interpolate(x.double(), scale_factor=layer["stride"],
                                     mode="nearest").to(torch.int64)
            y = apply_q24(enlarged, op["previous_q24"])
        elif kind in ("dropout", "yolo"):
            y = apply_q24(x, op["previous_q24"])
        else:
            raise ValueError(f"layer {idx}: {kind}")
        if list(y.shape[2:]) + [y.shape[1]] != layer["shape"]:
            raise ValueError(f"layer {idx} shape mismatch")
        x = torch.clamp(y, -127, 127).to(torch.int8)
        outputs.append(x)
        input_scale = out_scale
    return outputs


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    model = Path(__file__).resolve().parent.parent / "models/yolo_fastest_1_1"
    ap.add_argument("--model-dir", type=Path, default=model)
    ap.add_argument("--image", type=Path, default=model / "dog.jpg")
    ap.add_argument("--zero-input", action="store_true", help="infer an all-zero image")
    ap.add_argument("--fixed-requant", action="store_true",
                    help="use Q24 integer output scaling, bias and graph operators")
    ap.add_argument("--threshold", type=float, default=0.25)
    args = ap.parse_args()
    torch.set_num_threads(1)
    cfg = args.model_dir / "yolo-fastest-1.1.cfg"
    layout = manifest(cfg, args.model_dir / "yolo-fastest-1.1.weights")
    sections = parse_cfg(cfg)[1:]
    params = layer_params(args.model_dir, layout)
    fixed = json.loads((args.model_dir / "fixed_manifest.json").read_text(encoding="utf-8")) \
        if args.fixed_requant else None
    fixed_params = (args.model_dir / "params_q24.bin").read_bytes() if args.fixed_requant else None
    if args.fixed_requant and hashlib.sha256(fixed_params).hexdigest() != fixed["params_q24_sha256"]:
        raise ValueError("fixed parameter hash mismatch")
    height, width, _ = layout["input_shape"]
    calibration_image = load_image(args.image, width, height)
    x = load_image(None, width, height) if args.zero_input else calibration_image
    with torch.no_grad():
        _, scales = forward(calibration_image, sections, layout, params, None)
        _, zero_scales = forward(load_image(None, width, height), sections, layout, params, None)
        scales = [max(a, b) for a, b in zip(scales, zero_scales)]
        if args.fixed_requant:
            outputs = forward_fixed(x, sections, layout, params, scales, fixed, fixed_params)
        else:
            outputs, _ = forward(x, sections, layout, params, scales)
    result = {"images": [str(args.image), "zero"], "scales": scales,
              "weight_sha256": hashlib.sha256((args.model_dir / "weights_int8.bin").read_bytes()).hexdigest()}
    (args.model_dir / "activation_scales_2img.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8")
    names = (args.model_dir / "coco.names").read_text(encoding="utf-8").splitlines()
    detections = []
    for sec, layer, out in zip(sections, layout["layers"], outputs):
        if layer["type"] == "yolo":
            head = out.float() * scales[layer["index"]]
            print(f"head={layer['index']} scale={scales[layer['index']]:.8f} "
                  f"shape={tuple(head.shape)}")
            detections.extend(decode_head(head, sec, height, width, args.threshold))
    for item in nms(detections):
        print(f"detection={names[item['class']]} score={item['score']:.4f} "
              f"box={[round(v, 1) for v in item['box']]}")
    print(f"candidates={len(detections)} layers={len(scales)}")


if __name__ == "__main__":
    main()

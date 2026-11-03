"""Run a float32 Yolo-Fastest cfg/weights forward pass on a fixed image.

This is a host-side layer reference for the RV32 quantized model port. It
prints raw detection-head tensor hashes and decoded boxes after NMS.
Requires numpy and torch. Use --image for a 320x320 resized RGB input.
--packed-weights checks BN-folded INT8 kernels with float activations; it is
not a full integer inference path.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as f

from yolo_model_manifest import manifest, parse_cfg


def decode_head(x: torch.Tensor, sec: dict[str, str], image_h: int,
                image_w: int, threshold: float) -> list[dict]:
    """Decode one YOLOv3-style raw head into scored xyxy boxes."""
    masks = [int(v) for v in sec["mask"].split(",")]
    anchors_flat = [float(v) for v in sec["anchors"].split(",")]
    anchors = list(zip(anchors_flat[::2], anchors_flat[1::2]))
    classes = int(sec["classes"])
    height, width = x.shape[2:]
    raw = x[0].reshape(len(masks), classes + 5, height, width)
    confidence = torch.sigmoid(raw[:, 4:5]) * torch.sigmoid(raw[:, 5:])
    score, cls = confidence.max(dim=1)
    candidates = []
    for anchor_idx, row, col in (score >= threshold).nonzero().tolist():
        ax, ay = anchors[masks[anchor_idx]]
        rx = raw[anchor_idx, :, row, col]
        cx = (torch.sigmoid(rx[0]).item() + col) * image_w / width
        cy = (torch.sigmoid(rx[1]).item() + row) * image_h / height
        bw = torch.exp(rx[2].clamp(-20, 20)).item() * ax
        bh = torch.exp(rx[3].clamp(-20, 20)).item() * ay
        candidates.append({"class": int(cls[anchor_idx, row, col]),
                           "score": float(score[anchor_idx, row, col]),
                           "box": [cx - bw / 2, cy - bh / 2,
                                   cx + bw / 2, cy + bh / 2]})
    return candidates


def overlap(a: list[float], b: list[float]) -> float:
    area_a = max(0.0, a[2] - a[0]) * max(0.0, a[3] - a[1])
    area_b = max(0.0, b[2] - b[0]) * max(0.0, b[3] - b[1])
    intersection = (max(0.0, min(a[2], b[2]) - max(a[0], b[0])) *
                    max(0.0, min(a[3], b[3]) - max(a[1], b[1])))
    union = area_a + area_b - intersection
    return intersection / union if union else 0.0


def nms(candidates: list[dict], limit: int = 10) -> list[dict]:
    kept = []
    for item in sorted(candidates, key=lambda v: v["score"], reverse=True):
        if all(item["class"] != other["class"] or
               overlap(item["box"], other["box"]) < 0.45 for other in kept):
            kept.append(item)
            if len(kept) == limit:
                break
    return kept


def run(cfg: Path, weight_path: Path, image_path: Path | None,
        threshold: float, packed_weights: bool = False) -> list[dict]:
    torch.set_num_threads(1)
    layout = manifest(cfg, weight_path)
    sections = parse_cfg(cfg)[1:]
    raw = weight_path.read_bytes()
    weights = np.frombuffer(raw, dtype="<f4", offset=20)
    if packed_weights:
        model_dir = cfg.parent
        quant_layout = json.loads((model_dir / "quant_manifest.json").read_text(encoding="utf-8"))
        quant_info = {item["layer"]: item for item in quant_layout["convolutions"]}
        quant_data = (model_dir / "weights_int8.bin").read_bytes()
        param_data = (model_dir / "params_fp32.bin").read_bytes()
    h, w, _ = layout["input_shape"]
    if image_path is None:
        x = torch.zeros((1, 3, h, w), dtype=torch.float32)
        source = "zero image"
    else:
        from PIL import Image

        with Image.open(image_path) as img:
            rgb = img.convert("RGB").resize((w, h))
            pixels = np.asarray(rgb, dtype=np.float32).transpose(2, 0, 1) / 255.0
        x = torch.from_numpy(pixels.copy())[None]
        source = str(image_path)
    print(f"input={source} shape={tuple(x.shape)}")
    outputs: list[torch.Tensor] = []
    detections: list[dict] = []
    with torch.no_grad():
        for sec, layer in zip(sections, layout["layers"]):
            kind = layer["type"]
            if kind == "convolutional":
                filters = layer["shape"][2]
                groups = layer["groups"]
                size = layer["size"]
                if packed_weights:
                    item = quant_info[layer["index"]]
                    q = np.frombuffer(quant_data, dtype="i1", count=item["weight_bytes"],
                                      offset=item["weight_offset"]).copy()
                    pairs = np.frombuffer(param_data, dtype="<f4", count=2 * filters,
                                          offset=item["param_offset"]).reshape(filters, 2)
                    kernel = torch.from_numpy(q.astype(np.float32)).reshape(
                        filters, x.shape[1] // groups, size, size)
                    kernel = kernel * torch.from_numpy(pairs[:, 0].copy()).view(-1, 1, 1, 1)
                    bias = torch.from_numpy(pairs[:, 1].copy())
                else:
                    start = layer["float_offset"]
                    block = weights[start:start + layer["float_count"]]
                    bias = torch.from_numpy(block[:filters].copy())
                    pos = filters
                    if layer["batch_norm"]:
                        scale = torch.from_numpy(block[pos:pos + filters].copy())
                        mean = torch.from_numpy(block[pos + filters:pos + 2 * filters].copy())
                        var = torch.from_numpy(block[pos + 2 * filters:pos + 3 * filters].copy())
                        pos += 3 * filters
                    kernel = torch.from_numpy(block[pos:].copy()).reshape(
                        filters, x.shape[1] // groups, size, size)
                pad = size // 2 if int(sec.get("pad", 0)) else int(sec.get("padding", 0))
                x = f.conv2d(x, kernel, bias if packed_weights or not layer["batch_norm"] else None,
                             stride=layer["stride"], padding=pad, groups=groups)
                if layer["batch_norm"] and not packed_weights:
                    gain = (scale / torch.sqrt(var + 1.0e-5)).view(1, -1, 1, 1)
                    offset = (bias - mean * scale / torch.sqrt(var + 1.0e-5)).view(1, -1, 1, 1)
                    x = x * gain + offset
                if layer["activation"] == "leaky":
                    x = f.leaky_relu(x, 0.1)
                elif layer["activation"] != "linear":
                    raise ValueError(f"unsupported activation {layer['activation']}")
            elif kind == "route":
                x = torch.cat([outputs[i] for i in layer["sources"]], dim=1)
            elif kind == "shortcut":
                x = x + outputs[layer["source"]]
            elif kind == "maxpool":
                x = f.max_pool2d(x, layer["size"], layer["stride"],
                                 padding=layer["size"] // 2)
            elif kind == "upsample":
                x = f.interpolate(x, scale_factor=layer["stride"], mode="nearest")
            elif kind not in ("dropout", "yolo"):
                raise ValueError(f"unsupported layer {kind}")
            expected = layer["shape"]
            actual = list(x.shape[2:]) + [x.shape[1]]
            if actual != expected:
                raise ValueError(f"layer {layer['index']} shape {actual}, expected {expected}")
            outputs.append(x)
            if kind == "yolo":
                data = x.contiguous().numpy().tobytes()
                print(f"head={layer['index']} shape={tuple(x.shape)} "
                      f"min={x.min().item():.6g} max={x.max().item():.6g} "
                      f"sha256={hashlib.sha256(data).hexdigest()}")
                detections.extend(decode_head(x, sec, h, w, threshold))
    names = (cfg.parent / "coco.names").read_text(encoding="utf-8").splitlines()
    kept = nms(detections)
    for item in kept:
        box = [round(v, 1) for v in item["box"]]
        print(f"detection={names[item['class']]} score={item['score']:.4f} box={box}")
    print(f"candidates={len(detections)}")
    return kept


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    default = Path(__file__).resolve().parent.parent / "models" / "yolo_fastest_1_1"
    ap.add_argument("--cfg", type=Path, default=default / "yolo-fastest-1.1.cfg")
    ap.add_argument("--weights", type=Path, default=default / "yolo-fastest-1.1.weights")
    ap.add_argument("--image", type=Path)
    ap.add_argument("--threshold", type=float, default=0.25)
    ap.add_argument("--packed-weights", action="store_true",
                    help="use batch-norm-folded INT8 weights, with float activations")
    args = ap.parse_args()
    run(args.cfg, args.weights, args.image, args.threshold, args.packed_weights)


if __name__ == "__main__":
    main()

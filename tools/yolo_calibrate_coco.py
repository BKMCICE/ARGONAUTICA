"""Build isolated activation-scale candidates from COCO images.

The original packed weights are unchanged. Candidate files are written only
under --output-dir; no repository model file is modified.
"""
import argparse
import hashlib
import json
import random
import shutil
from pathlib import Path

import numpy as np
import torch

from yolo_int8_reference import forward, layer_params, load_image
from yolo_model_manifest import manifest, parse_cfg
from yolo_pack_fixed import pack


MODEL_FILES = ("yolo-fastest-1.1.cfg", "yolo-fastest-1.1.weights",
               "quant_manifest.json", "weights_int8.bin", "params_fp32.bin",
               "coco.names", "dog.jpg")
QUANTILES = {"max": 1.0, "p90": 0.90, "p75": 0.75}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--annotations", type=Path, required=True)
    ap.add_argument("--images", type=Path, required=True)
    ap.add_argument("--model-dir", type=Path,
                    default=root / "models/yolo_fastest_1_1")
    ap.add_argument("--output-dir", type=Path, required=True)
    ap.add_argument("--count", type=int, default=32)
    ap.add_argument("--seed", type=int, default=2027)
    args = ap.parse_args()
    if args.count <= 0:
        ap.error("--count must be positive")
    source = args.model_dir.resolve()
    target = args.output_dir.resolve()
    if source == target or source in target.parents:
        ap.error("--output-dir must be outside the source model directory")
    annotation_bytes = args.annotations.read_bytes()
    coco = json.loads(annotation_bytes)
    images = sorted(coco["images"], key=lambda entry: entry["id"])
    if args.count > len(images):
        ap.error("--count exceeds the available annotated images")
    selected = random.Random(args.seed).sample(images, args.count)
    cfg = source / "yolo-fastest-1.1.cfg"
    layout = manifest(cfg, source / "yolo-fastest-1.1.weights")
    sections = parse_cfg(cfg)[1:]
    params = layer_params(source, layout)
    height, width, _ = layout["input_shape"]
    torch.set_num_threads(1)
    paths = [args.images / item["file_name"] for item in selected]
    paths.append(source / "dog.jpg")
    observed = []
    with torch.no_grad():
        for number, path in enumerate(paths, 1):
            if not path.is_file():
                raise FileNotFoundError(path)
            _, scales = forward(load_image(path, width, height),
                                sections, layout, params, None)
            observed.append(scales)
            print(f"calibrated={number}/{len(paths) + 1} image={path.name}", flush=True)
        _, zero_scales = forward(load_image(None, width, height),
                                 sections, layout, params, None)
        observed.append(zero_scales)
    samples = np.asarray(observed, dtype=np.float64)
    if samples.shape != (args.count + 2, len(layout["layers"])):
        raise ValueError(f"unexpected calibration shape {samples.shape}")
    target.mkdir(parents=True, exist_ok=False)
    identifiers = {"seed": args.seed, "annotation_sha256":
                   hashlib.sha256(annotation_bytes).hexdigest(),
                   "image_ids": [item["id"] for item in selected]}
    (target / "calibration_image_ids.json").write_text(
        json.dumps(identifiers, indent=2) + "\n", encoding="utf-8")
    summary = {"count_coco": args.count, "seed": args.seed,
               "annotation_sha256": identifiers["annotation_sha256"],
               "candidates": {}}
    for label, quantile in QUANTILES.items():
        name = (f"max{args.count + 2}" if label == "max" else
                f"{label}_{args.count + 2}")
        candidate = target / name
        candidate.mkdir()
        for filename in MODEL_FILES:
            shutil.copy2(source / filename, candidate / filename)
        scales = np.maximum(np.quantile(samples, quantile, axis=0), 1e-8).tolist()
        calibration = {"images": [item["file_name"] for item in selected] +
                       ["dog.jpg", "zero"], "scales": scales,
                       "quantile": quantile, "seed": args.seed,
                       "weight_sha256": hashlib.sha256(
                           (candidate / "weights_int8.bin").read_bytes()).hexdigest()}
        calibration_path = candidate / "activation_scales_2img.json"
        calibration_path.write_text(json.dumps(calibration, indent=2) + "\n",
                                    encoding="utf-8")
        packed = pack(candidate)
        summary["candidates"][name] = {
            "quantile": quantile,
            "calibration_sha256": packed["activation_sha256"],
            "params_q24_sha256": packed["params_q24_sha256"],
            "head_scales": [scales[layer["index"]] for layer in layout["layers"]
                            if layer["type"] == "yolo"]}
        print(f"candidate={name} params_sha256={packed['params_q24_sha256']}", flush=True)
    (target / "summary.json").write_text(json.dumps(summary, indent=2) + "\n",
                                           encoding="utf-8")


if __name__ == "__main__":
    main()

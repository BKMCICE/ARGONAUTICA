"""COCO val2017 precision/recall for the host Q24 YOLO path.

This uses the calibration supplied by --model-dir and the same top-10 NMS
limit as the firmware. It is not COCO AP or a board performance measurement.
"""
import argparse
import contextlib
import hashlib
import io
import json
import random
import re
import time
import urllib.request
from collections import defaultdict
from pathlib import Path

import torch
from PIL import Image

from yolo_float_reference import decode_head, nms, overlap, run as run_float
from yolo_int8_reference import forward_fixed, layer_params, load_image
from yolo_model_manifest import manifest, parse_cfg


def iou(box_a: list[float], box_b: list[float]) -> float:
    return overlap(box_a, box_b)


def match_image(predictions: list[dict], annotations: list[dict],
                width: int, height: int, class_by_category: dict[int, int]) -> dict:
    ground_truth = []
    crowd = []
    for ann in annotations:
        x, y, w, h = ann["bbox"]
        box = [320.0 * x / width, 320.0 * y / height,
               320.0 * (x + w) / width, 320.0 * (y + h) / height]
        item = {"class": class_by_category[ann["category_id"]], "box": box}
        (crowd if ann.get("iscrowd") else ground_truth).append(item)
    used = set()
    tp = fp = ignored = 0
    for pred in sorted(predictions, key=lambda p: p["score"], reverse=True):
        box = [max(0.0, min(320.0, v)) for v in pred["box"]]
        choices = [(iou(box, gt["box"]), index)
                   for index, gt in enumerate(ground_truth)
                   if index not in used and gt["class"] == pred["class"]]
        best = max(choices, default=(0.0, -1))
        if best[0] >= 0.5:
            tp += 1
            used.add(best[1])
        elif any(item["class"] == pred["class"] and
                 iou(box, item["box"]) >= 0.5 for item in crowd):
            ignored += 1
        else:
            fp += 1
    return {"tp": tp, "fp": fp, "fn": len(ground_truth) - len(used),
            "ignored_crowd_predictions": ignored,
            "ground_truth": len(ground_truth), "crowd": len(crowd),
            "predictions": len(predictions)}


def ensure_image(path: Path, download: bool) -> None:
    if path.is_file():
        return
    if not download:
        raise FileNotFoundError(f"missing {path}; use --download-missing")
    if not re.fullmatch(r"[0-9]{12}\.jpg", path.name):
        raise ValueError(f"invalid COCO file name: {path.name}")
    url = f"http://images.cocodataset.org/val2017/{path.name}"
    path.parent.mkdir(parents=True, exist_ok=True)
    last_error = None
    for _ in range(3):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "ARGONAUTICA-COCO-eval/1"})
            with urllib.request.urlopen(request, timeout=45) as response:
                data = response.read()
            with Image.open(io.BytesIO(data)) as image:
                image.verify()
            path.write_bytes(data)
            return
        except (OSError, ValueError) as error:
            last_error = error
            time.sleep(1)
    raise RuntimeError(f"failed to fetch {url}: {last_error}")


def read_excluded_ids(paths: list[Path] | None, known_ids: set[int]) -> set[int]:
    result = set()
    for path in paths or []:
        payload = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(payload, dict) and "per_image" in payload:
            raw = [row["image_id"] for row in payload["per_image"]]
        else:
            raw = payload["image_ids"] if isinstance(payload, dict) else payload
        if not isinstance(raw, list) or any(type(value) is not int for value in raw):
            raise ValueError("excluded image IDs must be a JSON integer list")
        incoming = set(raw)
        if len(incoming) != len(raw) or not incoming <= known_ids or incoming & result:
            raise ValueError("excluded image IDs contain duplicates or unknown IDs")
        result.update(incoming)
    return result


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    model_default = Path(__file__).resolve().parent.parent / "models/yolo_fastest_1_1"
    ap.add_argument("--annotations", type=Path, required=True)
    ap.add_argument("--images", type=Path, required=True)
    ap.add_argument("--model-dir", type=Path, default=model_default)
    ap.add_argument("--limit", type=int, default=100)
    ap.add_argument("--seed", type=int, default=2026)
    ap.add_argument("--exclude-image-ids", type=Path, action="append",
                    help="repeatable JSON image_ids list or evaluation result to omit")
    ap.add_argument("--threshold", type=float, default=0.25)
    ap.add_argument("--download-missing", action="store_true")
    ap.add_argument("--compare-float", action="store_true",
                    help="also evaluate the original float32 weights on the same images")
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    if args.limit <= 0 or not 0 < args.threshold < 1:
        ap.error("--limit must be positive and 0 < --threshold < 1")
    annotation_bytes = args.annotations.read_bytes()
    coco = json.loads(annotation_bytes)
    images = sorted(coco["images"], key=lambda entry: entry["id"])
    excluded_ids = read_excluded_ids(args.exclude_image_ids,
                                     {entry["id"] for entry in images})
    images = [entry for entry in images if entry["id"] not in excluded_ids]
    if args.limit > len(images):
        ap.error(f"limit exceeds {len(images)} eligible annotated images")
    selected = random.Random(args.seed).sample(images, args.limit)
    anns_by_image = defaultdict(list)
    selected_ids = {entry["id"] for entry in selected}
    for ann in coco["annotations"]:
        if ann["image_id"] in selected_ids:
            anns_by_image[ann["image_id"]].append(ann)
    categories = sorted(coco["categories"], key=lambda entry: entry["id"])
    names = (args.model_dir / "coco.names").read_text(encoding="utf-8").splitlines()
    if len(categories) != len(names) or len(names) != 80:
        raise ValueError("COCO category count differs from the model's 80 classes")
    aliases = {"motorcycle": "motorbike", "airplane": "aeroplane",
               "couch": "sofa", "potted plant": "pottedplant",
               "dining table": "diningtable", "tv": "tvmonitor"}
    for category, name in zip(categories, names):
        if aliases.get(category["name"], category["name"]) != name:
            raise ValueError(f"COCO/model category order mismatch: {category['name']} vs {name}")
    class_by_category = {entry["id"]: index for index, entry in enumerate(categories)}

    cfg = args.model_dir / "yolo-fastest-1.1.cfg"
    layout = manifest(cfg, args.model_dir / "yolo-fastest-1.1.weights")
    sections = parse_cfg(cfg)[1:]
    params = layer_params(args.model_dir, layout)
    fixed = json.loads((args.model_dir / "fixed_manifest.json").read_text(encoding="utf-8"))
    calibration = (args.model_dir / "activation_scales_2img.json").read_bytes()
    if hashlib.sha256(calibration).hexdigest() != fixed["activation_sha256"]:
        raise ValueError("calibration file differs from the packed RV32 model")
    scales = json.loads(calibration)["scales"]
    fixed_params = (args.model_dir / "params_q24.bin").read_bytes()
    if hashlib.sha256(fixed_params).hexdigest() != fixed["params_q24_sha256"]:
        raise ValueError("fixed parameters differ from the packed RV32 model")
    torch.set_num_threads(1)
    totals = defaultdict(int)
    float_totals = defaultdict(int)
    per_image = []
    started = time.perf_counter()
    for number, entry in enumerate(selected, 1):
        if not re.fullmatch(r"[0-9]{12}\.jpg", entry["file_name"]):
            raise ValueError(f"invalid COCO file name: {entry['file_name']}")
        path = args.images / entry["file_name"]
        ensure_image(path, args.download_missing)
        x = load_image(path, 320, 320)
        with torch.no_grad():
            outputs = forward_fixed(x, sections, layout, params, scales, fixed, fixed_params)
        candidates = []
        for sec, layer, output in zip(sections, layout["layers"], outputs):
            if layer["type"] == "yolo":
                candidates.extend(decode_head(output.float() * scales[layer["index"]],
                                              sec, 320, 320, args.threshold))
        detections = nms(candidates, limit=10)
        metrics = match_image(detections, anns_by_image[entry["id"]],
                              entry["width"], entry["height"], class_by_category)
        metrics["raw_candidates"] = len(candidates)
        metrics["over_firmware_cap"] = int(len(candidates) > 256)
        for key, value in metrics.items():
            totals[key] += value
        row = {"image_id": entry["id"], "file_name": entry["file_name"], **metrics}
        if args.compare_float:
            with contextlib.redirect_stdout(io.StringIO()):
                float_detections = run_float(cfg, args.model_dir / "yolo-fastest-1.1.weights",
                                             path, args.threshold)
            float_metrics = match_image(float_detections, anns_by_image[entry["id"]],
                                        entry["width"], entry["height"], class_by_category)
            for key, value in float_metrics.items():
                float_totals[key] += value
            row["float"] = float_metrics
        per_image.append(row)
        if number % 10 == 0 or number == len(selected):
            print(f"evaluated={number}/{len(selected)} tp={totals['tp']} "
                  f"fp={totals['fp']} fn={totals['fn']}", flush=True)
    precision = totals["tp"] / max(1, totals["tp"] + totals["fp"])
    recall = totals["tp"] / max(1, totals["tp"] + totals["fn"])
    result = {
        "kind": "COCO val2017 host-Q24 operating-point evaluation; not COCO AP or board accuracy",
        "annotation_sha256": hashlib.sha256(annotation_bytes).hexdigest(),
        "calibration_sha256": hashlib.sha256(calibration).hexdigest(),
        "fixed_params_sha256": hashlib.sha256(fixed_params).hexdigest(),
        "seed": args.seed, "images_evaluated": len(selected),
        "excluded_image_count": len(excluded_ids),
        "score_threshold": args.threshold, "match_iou": 0.5, "max_detections": 10,
        "totals": dict(totals), "precision": precision, "recall": recall,
        "f1": 2 * precision * recall / max(1e-12, precision + recall),
        "host_elapsed_seconds": round(time.perf_counter() - started, 3),
        "per_image": per_image,
    }
    if args.compare_float:
        float_precision = float_totals["tp"] / max(1, float_totals["tp"] + float_totals["fp"])
        float_recall = float_totals["tp"] / max(1, float_totals["tp"] + float_totals["fn"])
        result["float32"] = {
            "totals": dict(float_totals), "precision": float_precision,
            "recall": float_recall,
            "f1": 2 * float_precision * float_recall /
                  max(1e-12, float_precision + float_recall),
        }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"precision={precision:.4f} recall={recall:.4f} f1={result['f1']:.4f} "
          f"output={args.output}")
    if args.compare_float:
        print(f"float_precision={float_precision:.4f} float_recall={float_recall:.4f} "
              f"float_f1={result['float32']['f1']:.4f}")


if __name__ == "__main__":
    main()

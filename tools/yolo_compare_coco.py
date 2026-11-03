"""Compare two COCO operating-point evaluations on the same images.

The candidate's image IDs select a matching subset from the reference result.
Paired image bootstrap intervals describe sampling uncertainty in the reported
F1 difference; they do not account for model-selection or annotation errors.
"""
import argparse
import json
from pathlib import Path

import numpy as np


KEYS = ("tp", "fp", "fn")


def rates(counts: np.ndarray) -> dict[str, float]:
    tp, fp, fn = (int(value) for value in counts)
    precision = tp / max(1, tp + fp)
    recall = tp / max(1, tp + fn)
    return {"tp": tp, "fp": fp, "fn": fn, "precision": precision,
            "recall": recall,
            "f1": 2 * precision * recall / max(1e-12, precision + recall)}


def rows_by_id(result: dict) -> dict[int, dict]:
    rows = {row["image_id"]: row for row in result["per_image"]}
    if len(rows) != len(result["per_image"]) or len(rows) != result["images_evaluated"]:
        raise ValueError("duplicate or missing image IDs")
    if any(sum(row[key] for row in rows.values()) != result["totals"][key]
           for key in KEYS):
        raise ValueError("per-image counts differ from the result totals")
    return rows


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--reference", type=Path, required=True)
    ap.add_argument("--candidate", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--bootstrap-samples", type=int, default=2000)
    ap.add_argument("--seed", type=int, default=2030)
    args = ap.parse_args()
    if args.bootstrap_samples <= 0:
        ap.error("--bootstrap-samples must be positive")
    reference = json.loads(args.reference.read_text(encoding="utf-8"))
    candidate = json.loads(args.candidate.read_text(encoding="utf-8"))
    for field in ("annotation_sha256", "score_threshold", "match_iou",
                  "max_detections"):
        if reference[field] != candidate[field]:
            raise ValueError(f"evaluation protocol mismatch: {field}")
    ref_rows = rows_by_id(reference)
    cand_rows = rows_by_id(candidate)
    if not cand_rows.keys() <= ref_rows.keys():
        raise ValueError("candidate contains images missing from reference")
    ids = sorted(cand_rows)
    ref_counts = np.asarray([[ref_rows[image_id][key] for key in KEYS]
                             for image_id in ids], dtype=np.int64)
    cand_counts = np.asarray([[cand_rows[image_id][key] for key in KEYS]
                              for image_id in ids], dtype=np.int64)
    before = rates(ref_counts.sum(axis=0))
    after = rates(cand_counts.sum(axis=0))
    point_pp = 100 * (after["f1"] - before["f1"])
    rng = np.random.default_rng(args.seed)
    differences = np.empty(args.bootstrap_samples, dtype=np.float64)
    for number in range(args.bootstrap_samples):
        selected = rng.integers(0, len(ids), len(ids))
        differences[number] = 100 * (
            rates(cand_counts[selected].sum(axis=0))["f1"] -
            rates(ref_counts[selected].sum(axis=0))["f1"])
    report = {
        "reference": str(args.reference), "candidate": str(args.candidate),
        "images_compared": len(ids), "annotation_sha256": candidate["annotation_sha256"],
        "score_threshold": candidate["score_threshold"],
        "match_iou": candidate["match_iou"],
        "max_detections": candidate["max_detections"],
        "reference_counts_and_rates": before,
        "candidate_counts_and_rates": after,
        "f1_delta_percentage_points": point_pp,
        "bootstrap_samples": args.bootstrap_samples, "bootstrap_seed": args.seed,
        "paired_bootstrap_f1_delta_pp_95":
            np.quantile(differences, [0.025, 0.975]).tolist(),
        "bootstrap_fraction_candidate_better": float(np.mean(differences > 0)),
    }
    if all("float" in ref_rows[image_id] for image_id in ids):
        float_counts = np.asarray([[ref_rows[image_id]["float"][key] for key in KEYS]
                                   for image_id in ids], dtype=np.int64)
        report["float_reference_counts_and_rates"] = rates(float_counts.sum(axis=0))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"images={len(ids)} reference_f1={before['f1']:.4f} "
          f"candidate_f1={after['f1']:.4f} delta_pp={point_pp:+.3f} "
          f"ci95={report['paired_bootstrap_f1_delta_pp_95']}")


if __name__ == "__main__":
    main()

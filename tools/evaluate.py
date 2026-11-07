"""Detection accuracy on the labelled test set, from the app's own predictions.

Inputs: predictions.json from `tool/eval/predict_test.dart` (the real app
detector) and the YOLO .txt labels next to each image (or in a mirrored
labels/ folder; same lookup as split_dataset.py).

Per class (the app's 20) and overall:
- **At the app's speaking threshold** (default 0.5, `AppSettings.
  confidenceThreshold`), which is what users actually hear: true positives,
  false positives, missed objects, Precision and Recall.
- **At the best-F1 threshold**, for comparison.
- **AP@0.5** with Ultralytics' method: the precision envelope sampled at 101
  recall points and integrated with the trapezoid rule. **mAP@0.5** is the mean
  over classes that have at least one label. Like Ultralytics' `mAP50`, a
  perfect detector scores 0.995, not 1.0 (its padding sets precision to 0 at
  recall 1.0, halving the last trapezoid), so the numbers are comparable with
  Ultralytics' but not identical to pycocotools'. A class with labels but no
  predictions scores 0, as in Ultralytics.

Matching: per image and class, predictions in descending confidence each take
the unmatched label with the highest IoU, if that IoU >= 0.5 (COCO style).
Anything else is a false positive. Labels of classes outside the app's set are
excluded and counted.

Usage:
    python tools/evaluate.py <predictions.json> [--threshold 0.5] [--names assets/models/labels.txt] [--json]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from split_dataset import label_path  # noqa: E402

IOU_THRESHOLD = 0.5
RECALL_POINTS = np.linspace(0, 1, 101)


def iou(a: list[float], b: list[float]) -> float:
    w = min(a[2], b[2]) - max(a[0], b[0])
    h = min(a[3], b[3]) - max(a[1], b[1])
    if w <= 0 or h <= 0:
        return 0.0
    inter = w * h
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / union if union > 0 else 0.0


def read_labels(path: Path) -> list[tuple[int, list[float]]]:
    """YOLO lines `class cx cy w h` (normalized) as (class, [x1, y1, x2, y2])."""
    boxes = []
    for line in path.read_text(encoding="utf-8").splitlines():
        f = line.split()
        if len(f) < 5:
            continue
        cx, cy, w, h = (float(v) for v in f[1:5])
        boxes.append((int(float(f[0])), [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2]))
    return boxes


def compute_ap(recall: np.ndarray, precision: np.ndarray) -> float:
    """Ultralytics' AP: envelope over sentinel-padded curves, 101-point trapezoid."""
    mrec = np.concatenate(([0.0], recall, [recall[-1] if len(recall) else 1.0], [1.0]))
    mpre = np.concatenate(([1.0], precision, [0.0], [0.0]))
    mpre = np.flip(np.maximum.accumulate(np.flip(mpre)))
    return float(np.trapezoid(np.interp(RECALL_POINTS, mrec, mpre), RECALL_POINTS))


def match(predictions: list[dict], labels: list[list[float]]) -> list[tuple[float, bool]]:
    """(confidence, is_true_positive) for one image and one class."""
    taken = [False] * len(labels)
    results = []
    for p in sorted(predictions, key=lambda d: -d["confidence"]):
        best, best_j = 0.0, -1
        for j, box in enumerate(labels):
            if not taken[j]:
                v = iou(p["box"], box)
                if v > best:
                    best, best_j = v, j
        if best_j >= 0 and best >= IOU_THRESHOLD:
            taken[best_j] = True
            results.append((p["confidence"], True))
        else:
            results.append((p["confidence"], False))
    return results


def class_metrics(scored: list[tuple[float, bool]], n_labels: int, threshold: float) -> dict:
    scored = sorted(scored, key=lambda s: -s[0])
    conf = np.array([s[0] for s in scored], dtype=float)
    tp = np.array([s[1] for s in scored], dtype=bool)
    tp_cum, fp_cum = np.cumsum(tp), np.cumsum(~tp)
    recall = tp_cum / n_labels if n_labels else np.zeros(len(tp))
    precision = tp_cum / np.maximum(tp_cum + fp_cum, 1)

    at = conf >= threshold
    tp_at, fp_at = int(tp[at].sum()), int((~tp[at]).sum())
    result = {
        "labels": n_labels,
        "predictions": len(scored),
        "tp": tp_at,
        "fp": fp_at,
        "missed": n_labels - tp_at,
        "precision": tp_at / (tp_at + fp_at) if tp_at + fp_at else None,
        "recall": tp_at / n_labels if n_labels else None,
        # No predictions: AP is 0 (Ultralytics skips the curve). Computing it on
        # empty arrays would give 0.5 from the padding alone.
        "ap50": (compute_ap(recall, precision) if len(scored) else 0.0) if n_labels else None,
        "best_f1": None,
        "best_f1_threshold": None,
    }
    if n_labels and len(scored):
        f1 = 2 * precision * recall / np.maximum(precision + recall, 1e-16)
        i = int(np.argmax(f1))
        result["best_f1"] = float(f1[i])
        result["best_f1_threshold"] = float(conf[i])
    return result


def evaluate(predictions_path: Path, threshold: float = 0.5) -> dict:
    data = json.loads(predictions_path.read_text(encoding="utf-8"))
    root = Path(data["root"])
    classes = set(data["classes"])
    scored: dict[int, list[tuple[float, bool]]] = {c: [] for c in classes}
    n_labels: dict[int, int] = dict.fromkeys(classes, 0)
    excluded_labels = 0
    missing_labels = []

    for image in data["images"]:
        lp = label_path(root / image["file"])
        if lp is None:
            missing_labels.append(image["file"])
            gt = []
        else:
            gt = read_labels(lp)
        by_class: dict[int, list[list[float]]] = {}
        for c, box in gt:
            if c in classes:
                by_class.setdefault(c, []).append(box)
                n_labels[c] += 1
            else:
                excluded_labels += 1
        for c in classes:
            preds = [d for d in image["detections"] if d["class"] == c]
            if preds or c in by_class:
                scored[c] += match(preds, by_class.get(c, []))

    per_class = {c: class_metrics(scored[c], n_labels[c], threshold) for c in sorted(classes)}
    with_labels = [m for m in per_class.values() if m["labels"]]
    tp = sum(m["tp"] for m in per_class.values())
    fp = sum(m["fp"] for m in per_class.values())
    total_labels = sum(n_labels.values())
    return {
        "predictions_file": str(predictions_path),
        "model_sha256": data.get("model", {}).get("sha256"),
        "accelerator": data.get("accelerator"),
        "git_commit": data.get("git_commit"),
        "images": len(data["images"]),
        "threshold": threshold,
        "iou": IOU_THRESHOLD,
        "map50": float(np.mean([m["ap50"] for m in with_labels])) if with_labels else None,
        "classes_with_labels": len(with_labels),
        "overall_at_threshold": {
            "labels": total_labels,
            "tp": tp,
            "fp": fp,
            "missed": total_labels - tp,
            "precision": tp / (tp + fp) if tp + fp else None,
            "recall": tp / total_labels if total_labels else None,
            "fp_per_image": fp / len(data["images"]) if data["images"] else None,
        },
        "excluded_labels_outside_classes": excluded_labels,
        "images_without_labels": missing_labels,
        "per_class": per_class,
    }


def _f(v, d=3):
    return "–" if v is None else f"{v:.{d}f}"


def to_markdown(r: dict, names: list[str] | None) -> str:
    o = r["overall_at_threshold"]
    lines = [
        f"## Detection accuracy ({r['images']} images, IoU {r['iou']}, speaking threshold {r['threshold']})",
        "",
        f"- **mAP@0.5:** {_f(r['map50'])} over {r['classes_with_labels']} classes with labels",
        f"- **At the speaking threshold:** precision {_f(o['precision'])}, recall {_f(o['recall'])}, "
        f"{o['fp']} false positives ({_f(o['fp_per_image'], 2)} per image), {o['missed']} missed of {o['labels']}",
        f"- Model {str(r['model_sha256'])[:12]}…, accelerator {r['accelerator']}, commit {r['git_commit']}",
    ]
    if r["excluded_labels_outside_classes"]:
        lines.append(f"- {r['excluded_labels_outside_classes']} labels of other classes excluded")
    if r["images_without_labels"]:
        lines.append(f"- WARNING: {len(r['images_without_labels'])} images have no label file (counted as empty)")
    lines += [
        "",
        "| Class | Labels | AP@0.5 | P | R | TP | FP | Missed | Best F1 (at conf) |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for c, m in r["per_class"].items():
        if not m["labels"] and not m["fp"]:
            continue  # Nothing labelled and nothing spoken wrongly.
        name = names[c] if names and c < len(names) else str(c)
        best = "–" if m["best_f1"] is None else f"{m['best_f1']:.3f} ({m['best_f1_threshold']:.2f})"
        lines.append(
            f"| {c} {name} | {m['labels']} | {_f(m['ap50'])} | {_f(m['precision'])} | {_f(m['recall'])} | "
            f"{m['tp']} | {m['fp']} | {m['missed']} | {best} |"
        )
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("predictions", type=Path)
    p.add_argument("--threshold", type=float, default=0.5, help="app speaking threshold (AppSettings)")
    p.add_argument("--names", type=Path, help="labels.txt for class names")
    p.add_argument("--json", action="store_true")
    args = p.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    result = evaluate(args.predictions, args.threshold)
    names = args.names.read_text(encoding="utf-8").splitlines() if args.names else None
    if args.json:
        result["per_class"] = {str(k): v for k, v in result["per_class"].items()}
        sys.stdout.write(json.dumps(result, indent=2) + "\n")
    else:
        sys.stdout.write(to_markdown(result, names))
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Export a YOLO nano model for the app and verify the exports.

Produces, for every requested input size:
  * LiteRT/TFLite fp32  (no quantization; GPU delegates may still run it at fp16)
  * LiteRT/TFLite int8  (static INT8, calibrated on a fixed COCO subset)
  * LiteRT/TFLite w8a32 (dynamic: int8 weights, float activations, no calibration)
  * Core ML .mlpackage fp16 (iOS)

Ultralytics 8.4.198's `litert` exporter has no fp16 option (it accepts
quantize = 8 / 'w8a16' / 'w8a32' / 32 / None), hence fp32 rather than fp16.

and writes build/models/export_manifest.json with tool versions, export
arguments, SHA-256 hashes, input/output tensor signatures and a fidelity check
of every TFLite export against the original PyTorch model.

Runs ONLY on Linux x86_64 or macOS. Ultralytics 8.4.198 rejects LiteRT and
Core ML export on Windows, so use the Docker image (docs/decisions.md D-012):

    docker build -f tools/docker/export.Dockerfile -t kurdish-vision-export .
    docker run --rm -v "${PWD}:/work" -e GIT_COMMIT=$(git rev-parse HEAD) kurdish-vision-export

Fidelity check: the same images run through the .pt model and each export.
Match rate = share of reference detections that the export also finds (same
class, IoU >= --iou). It measures export DAMAGE, not accuracy; accuracy on
our own test set is Phase 5 (tools/evaluate.py).
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.metadata as md
import json
import os
import platform
import shutil
import sys
import tempfile
import traceback
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEFAULT_OUT = REPO / "build" / "models"

VERSIONED_PACKAGES = (
    "ultralytics",
    "torch",
    "torchvision",
    "numpy",
    "litert-torch",
    "ai-edge-litert",
    "ai-edge-quantizer",
    "coremltools",
)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--weights", default="yolo26n.pt", help="Ultralytics weights (downloaded if missing)")
    p.add_argument("--imgsz", type=int, nargs="+", default=[640, 320], help="square input sizes")
    p.add_argument(
        "--variants",
        nargs="+",
        default=["fp32", "int8", "w8a32", "coreml"],
        choices=["fp32", "int8", "w8a32", "coreml"],
    )
    p.add_argument("--calib-data", default="coco128.yaml", help="INT8 calibration dataset (Ultralytics yaml)")
    p.add_argument("--calib-fraction", type=float, default=1.0, help="fraction of the calibration split to use")
    p.add_argument("--check-images", type=int, default=32, help="number of images for the fidelity check")
    p.add_argument("--conf", type=float, default=0.25, help="confidence threshold for the fidelity check")
    p.add_argument("--iou", type=float, default=0.5, help="IoU for matching detections in the fidelity check")
    p.add_argument("--min-match-fp32", type=float, default=0.95, help="fail if fp32 match rate is lower")
    p.add_argument("--min-match-int8", type=float, default=0.70, help="fail if int8 match rate is lower")
    p.add_argument("--min-match-w8a32", type=float, default=0.85, help="fail if w8a32 match rate is lower")
    p.add_argument("--out", type=Path, default=DEFAULT_OUT)
    return p.parse_args()


def require_supported_os() -> None:
    if platform.system() == "Linux" and platform.machine() in {"x86_64", "AMD64"}:
        return
    if platform.system() == "Darwin":
        return
    sys.exit(
        f"Unsupported host {platform.system()}/{platform.machine()}: Ultralytics only exports LiteRT on "
        "Linux x86_64 or macOS. Use the Docker image (see this file's docstring)."
    )


def configure_ultralytics() -> None:
    """Disable analytics. Directory settings are read by Ultralytics at import time, so they are
    set in the Docker image (`yolo settings ...`), not here."""
    from ultralytics import settings

    settings.update({"sync": False})


def sha256_of(path: Path) -> str:
    """SHA-256 of a file, or of a directory's files in sorted relative-path order."""
    h = hashlib.sha256()
    files = [path] if path.is_file() else sorted(p for p in path.rglob("*") if p.is_file())
    for f in files:
        if path.is_dir():
            h.update(str(f.relative_to(path)).replace(os.sep, "/").encode())
        with f.open("rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
    return h.hexdigest()


def size_bytes(path: Path) -> int:
    return path.stat().st_size if path.is_file() else sum(p.stat().st_size for p in path.rglob("*") if p.is_file())


def tflite_signature(path: Path) -> dict:
    from ai_edge_litert.interpreter import Interpreter

    interp = Interpreter(model_path=str(path))

    def describe(details: list[dict]) -> list[dict]:
        out = []
        for d in details:
            scale, zero = d.get("quantization", (0.0, 0))
            out.append(
                {
                    "name": d["name"],
                    "shape": [int(x) for x in d["shape"]],
                    "dtype": str(d["dtype"].__name__ if hasattr(d["dtype"], "__name__") else d["dtype"]),
                    "quant_scale": float(scale),
                    "quant_zero_point": int(zero),
                }
            )
        return out

    inputs = describe(interp.get_input_details())
    outputs = describe(interp.get_output_details())
    return {"inputs": inputs, "outputs": outputs, "layout": guess_layout(outputs)}


def guess_layout(outputs: list[dict]) -> str:
    """'end2end' = boxes already de-duplicated (no NMS needed); 'raw' = needs NMS in the app."""
    if len(outputs) == 1:
        shape = outputs[0]["shape"]
        if len(shape) == 3 and shape[2] == 6:
            return "end2end [1, max_det, (x1, y1, x2, y2, score, class)]"
        if len(shape) == 3 and shape[1] > shape[2]:
            return "raw [1, anchors, 4 + classes] -- NMS required"
        if len(shape) == 3:
            return "raw [1, 4 + classes, anchors] -- NMS required"
    return "unknown -- inspect shapes"


def coreml_signature(path: Path) -> dict:
    import coremltools as ct

    spec = ct.models.MLModel(str(path), skip_model_load=True).get_spec()

    def describe(features) -> list[dict]:
        out = []
        for f in features:
            kind = f.type.WhichOneof("Type")
            entry = {"name": f.name, "type": kind}
            if kind == "multiArrayType":
                entry["shape"] = [int(x) for x in f.type.multiArrayType.shape]
            elif kind == "imageType":
                entry["shape"] = [int(f.type.imageType.height), int(f.type.imageType.width)]
            out.append(entry)
        return out

    return {"inputs": describe(spec.description.input), "outputs": describe(spec.description.output)}


def check_image_paths(limit: int) -> list[str]:
    """First `limit` coco128 images (sorted, deterministic). Downloaded with the calibration data."""
    from ultralytics.data.utils import check_det_dataset

    data = check_det_dataset("coco128.yaml")
    images = sorted(Path(data["train"]).glob("*.jpg"))
    return [str(p) for p in images[:limit]]


def detections(model, images: list[str], imgsz: int, conf: float) -> list[list[tuple[int, float, list[float]]]]:
    results = model.predict(images, imgsz=imgsz, conf=conf, verbose=False, batch=1)
    return [
        [(int(c), float(s), [float(v) for v in box]) for c, s, box in zip(r.boxes.cls, r.boxes.conf, r.boxes.xyxyn)]
        for r in results
    ]


def iou(a: list[float], b: list[float]) -> float:
    ix = max(0.0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0.0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / union if union > 0 else 0.0


def fidelity(reference, candidate, iou_thr: float) -> dict:
    matched, total, conf_deltas = 0, 0, []
    for ref_img, cand_img in zip(reference, candidate):
        used: set[int] = set()
        for cls, score, box in ref_img:
            total += 1
            best, best_j = 0.0, None
            for j, (c2, _, b2) in enumerate(cand_img):
                if j in used or c2 != cls:
                    continue
                v = iou(box, b2)
                if v > best:
                    best, best_j = v, j
            if best_j is not None and best >= iou_thr:
                matched += 1
                used.add(best_j)
                conf_deltas.append(abs(score - cand_img[best_j][1]))
    extra = sum(len(c) for c in candidate) - matched
    return {
        "reference_detections": total,
        "matched": matched,
        "match_rate": round(matched / total, 4) if total else None,
        "extra_detections": extra,
        "mean_abs_conf_delta": round(sum(conf_deltas) / len(conf_deltas), 4) if conf_deltas else None,
    }


def export_one(weights: str, variant: str, imgsz: int, args: argparse.Namespace, out_dir: Path) -> tuple[Path, dict]:
    """Exports next to `weights` (Ultralytics' behaviour) and moves the result into `out_dir`.

    Both must be on a LOCAL filesystem: LiteRT memory-maps .tflite files, which fails on
    Docker Desktop's Windows bind mounts ("model allocation is null/empty").
    """
    from ultralytics import YOLO

    model = YOLO(weights)
    stem = Path(weights).stem
    if variant == "fp32":
        kwargs = {"format": "litert", "imgsz": imgsz, "quantize": None}
    elif variant == "w8a32":
        kwargs = {"format": "litert", "imgsz": imgsz, "quantize": "w8a32"}
    elif variant == "int8":
        kwargs = {
            "format": "litert",
            "imgsz": imgsz,
            "quantize": 8,
            "data": args.calib_data,
            "fraction": args.calib_fraction,
        }
    else:
        kwargs = {"format": "coreml", "imgsz": imgsz, "quantize": 16}

    produced = Path(model.export(**kwargs))
    suffix = ".mlpackage" if variant == "coreml" else ".tflite"
    target = out_dir / f"{stem}_{imgsz}_{variant}{suffix}"
    if target.exists():
        shutil.rmtree(target) if target.is_dir() else target.unlink()
    shutil.move(str(produced), str(target))
    return target, kwargs


def versions() -> dict:
    found = {"python": platform.python_version(), "platform": platform.platform()}
    for pkg in VERSIONED_PACKAGES:
        try:
            found[pkg] = md.version(pkg)
        except md.PackageNotFoundError:
            found[pkg] = None
    return found


def main() -> int:
    args = parse_args()
    require_supported_os()
    configure_ultralytics()
    from ultralytics import YOLO

    args.out.mkdir(parents=True, exist_ok=True)
    # All export work happens on local disk; only finished artifacts are copied to args.out.
    work = Path(tempfile.mkdtemp(prefix="yolo-export-"))
    staging = work / "out"
    staging.mkdir()

    reference_model = YOLO(args.weights)  # downloads official weights if missing
    source_weights = Path(args.weights) if Path(args.weights).exists() else Path(reference_model.ckpt_path)
    weights_path = work / source_weights.name
    shutil.copy2(source_weights, weights_path)

    labels = [reference_model.names[i] for i in sorted(reference_model.names)]
    (staging / "labels.txt").write_text("\n".join(labels) + "\n", encoding="utf-8")

    images = check_image_paths(args.check_images)
    manifest: dict = {
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "git_commit": os.environ.get("GIT_COMMIT"),
        "versions": versions(),
        "weights": {"file": weights_path.name, "sha256": sha256_of(weights_path)},
        "labels": {"file": "labels.txt", "count": len(labels)},
        "fidelity_check": {
            "images": len(images),
            "source": "coco128 train2017, first N sorted (also used for INT8 calibration)",
            "conf": args.conf,
            "iou": args.iou,
        },
        "artifacts": [],
    }

    failures: list[str] = []
    for imgsz in args.imgsz:
        reference = detections(reference_model, images, imgsz, args.conf)
        for variant in args.variants:
            print(f"\n=== {variant} @ {imgsz} ===", flush=True)
            try:
                path, kwargs = export_one(str(weights_path), variant, imgsz, args, staging)
            except Exception as e:  # record, show, and continue with the other variants
                traceback.print_exc()
                failures.append(f"{variant}@{imgsz}: export failed: {e!r}")
                manifest["artifacts"].append({"variant": variant, "imgsz": imgsz, "error": repr(e)})
                continue

            entry: dict = {
                "variant": variant,
                "imgsz": imgsz,
                "file": path.name,
                "export_args": kwargs,
                "sha256": sha256_of(path),
                "size_bytes": size_bytes(path),
            }
            if variant == "coreml":
                entry["signature"] = coreml_signature(path)
                entry["fidelity"] = "not run: Core ML prediction requires macOS"
            else:
                try:
                    entry["signature"] = tflite_signature(path)
                    candidate = detections(YOLO(str(path), task="detect"), images, imgsz, args.conf)
                    result = fidelity(reference, candidate, args.iou)
                except Exception as e:
                    traceback.print_exc()
                    failures.append(f"{variant}@{imgsz}: verification failed: {e!r}")
                    entry["fidelity"] = {"error": repr(e)}
                else:
                    entry["fidelity"] = result
                    minimum = getattr(args, f"min_match_{variant}")
                    if result["match_rate"] is not None and result["match_rate"] < minimum:
                        failures.append(f"{variant}@{imgsz}: match rate {result['match_rate']} < {minimum}")
            manifest["artifacts"].append(entry)
            print(json.dumps(entry, indent=2), flush=True)

    manifest["failures"] = failures
    (staging / "export_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    for item in staging.iterdir():
        target = args.out / item.name
        if target.exists():
            shutil.rmtree(target) if target.is_dir() else target.unlink()
        shutil.copytree(item, target) if item.is_dir() else shutil.copy2(item, target)
    shutil.rmtree(work, ignore_errors=True)
    print(f"\nwrote {args.out / 'export_manifest.json'}")
    if failures:
        print("FAILURES:\n  " + "\n  ".join(failures))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

# tools/

Python scripts for the research workflow. They are not shipped in the app.

| Script | Phase | Purpose |
|---|---|---|
| `make_placeholder_clips.py` | 1A | Tone placeholders in `assets/audio/placeholder/` (stdlib only, deterministic) |
| `export_model.py` | 1B | Export YOLO26n to LiteRT fp32/int8/w8a32 and Core ML, with a fidelity check and manifest |
| `make_detector_fixtures.py` | 3 | Reference numbers in `test/fixtures/` for the Dart resize and decode tests |
| `split_dataset.py` | 5 | train/val/test split with perceptual-hash de-duplication |
| `evaluate.py` | 5 | Precision, Recall, mAP@0.5, false positives per class |
| `analyze_metrics.py` | 5 | Median/P95 latency tables and charts from app CSV |

## Model export (Docker)

Ultralytics 8.4.198 cannot export LiteRT or Core ML on Windows, so the
export runs in a pinned Linux image (`docker/export.Dockerfile`,
`requirements-export.txt`). From the repository root:

```
docker build -f tools/docker/export.Dockerfile -t kurdish-vision-export .
docker run --rm -v "${PWD}:/work" -e GIT_COMMIT=$(git rev-parse HEAD) kurdish-vision-export
```

In Windows PowerShell use `-v "${PWD}:/work"` as written, and
`-e GIT_COMMIT=$(git rev-parse HEAD)` also works there.

Outputs go to `build/models/` (git-ignored): the `.tflite` / `.mlpackage`
files, `labels.txt` and `export_manifest.json`. The manifest records tool
versions, SHA-256 hashes, tensor signatures and the fidelity check. Weights
(`*.pt`) and calibration data (`tools/datasets/`) are downloaded on first run
and are not committed.

The exact resolved package set of the image is saved as
`tools/requirements-export.lock.txt` after each image rebuild:

```
docker run --rm --entrypoint cat kurdish-vision-export /opt/requirements-export.lock.txt > tools/requirements-export.lock.txt
```

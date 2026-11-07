# tools/

Python scripts for the research workflow. They are not shipped in the app.

| Script | Phase | Purpose |
|---|---|---|
| `make_placeholder_clips.py` | 1A | Tone placeholders in `assets/audio/placeholder/` (stdlib only, deterministic) |
| `export_model.py` | 1B | Export YOLO26n to LiteRT fp32/int8/w8a32 and Core ML, with a fidelity check and manifest |
| `make_detector_fixtures.py` | 3 | Reference numbers in `test/fixtures/` for the Dart resize and decode tests |
| `analyze_metrics.py` | 4–5 | Median/P95 per stage for one session; `compare` for several, with box-plot charts |
| `split_dataset.py` | 5 | train/val/test split without near-duplicate leakage (dHash + capture folder) |
| `../tool/eval/predict_test.dart` | 5 | Runs the app's own detector over test photos → `predictions.json` |
| `evaluate.py` | 5 | Precision, Recall, FP at the speaking threshold; AP/mAP@0.5 per class |

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

## Evaluation sessions (metrics)

1. Build a **profile or release** build (debug numbers are not valid, D-021):
   `flutter build apk --profile --dart-define=GIT_COMMIT=$(git rev-parse HEAD)`
2. On the phone: Settings → turn on «دۆخی هەڵسەنگاندن» (evaluation mode), use the
   app, then turn it off.
3. Settings → «ناردنی تۆمارەکان» (share recordings) sends the session's three files.
   In a debug build on Android you can also pull them over USB:
   `adb shell run-as com.mir.kurdish_vision ls app_flutter/metrics`
4. Summarise: `python tools/analyze_metrics.py <session-folder>` (add `--json`
   for machine-readable output). Tests: `python tools/test_analyze_metrics.py`.

## Accuracy evaluation

Setup: `python -m pip install -r tools/requirements-tools.txt` (Python 3.11+),
and the model file in `assets/models/` (see the main README).

1. Label photos in YOLO format, one sub-folder per capture session.
2. Split: `python tools/split_dataset.py <dataset>`. Check
   `closest_pairs_across_splits` in `split_report.json`.
3. Predict with the app's code:
   `flutter test tool/eval/predict_test.dart --dart-define=EVAL_LIST=<dataset>/splits/test.txt --dart-define=EVAL_OUT=<dataset>/predictions.json --dart-define=GIT_COMMIT=$(git rev-parse HEAD)`
4. Score: `python tools/evaluate.py <dataset>/predictions.json --names assets/models/labels.txt`

Tests: `python tools/test_split_dataset.py`, `python tools/test_evaluate.py`,
`python tools/test_analyze_metrics.py`.


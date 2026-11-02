# tools/

Python scripts for the research workflow. They are not shipped in the app.

| Script | Phase | Purpose |
|---|---|---|
| `make_placeholder_clips.py` | 1A | Tone placeholders in `assets/audio/placeholder/` (stdlib only, deterministic) |
| `export_model.py` | 1B | Export YOLO nano to TFLite (float16, int8) and Core ML |
| `split_dataset.py` | 5 | train/val/test split with perceptual-hash de-duplication |
| `evaluate.py` | 5 | Precision, Recall, mAP@0.5, false positives per class |
| `analyze_metrics.py` | 5 | Median/P95 latency tables and charts from app CSV |

Pin exact package versions in a `requirements.txt` so results can be reproduced.

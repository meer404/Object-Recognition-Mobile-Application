# Evaluation plan

_Drafted in Phase 5. Headings are fixed now so data collection in earlier
phases lines up with them._

## 1. Detection accuracy
Precision, Recall, mAP@0.5 and false positives per class on the labelled
test set (`tools/evaluate.py`).

## 2. Speed and resource use
Per-stage latency (preprocessing, inference, post-processing,
frame-to-speech-start), FPS, RAM and battery from the app's CSV export
(`tools/analyze_metrics.py`). Report median and P95.

## 3. Kurdish speech quality
Native-speaker rating form.

## 4. User study
5–10 consenting participants: tasks, SUS questionnaire, safety rules.

## 5. Test configuration log
Device models, OS versions, model variant, AppSettings values for every run.

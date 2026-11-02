# ڕێبەری دروستکردنی پڕۆژەکە بە Claude Code

## پێش دەستپێکردن
1. Flutter و Android Studio دابمەزرێنە (بۆ iOS پێویستت بە Mac + Xcode هەیە).
2. فۆڵدەرێکی بەتاڵ دروست بکە، `CLAUDE.md` بخەرە ناوی، پاشان `git init`.
3. لەو فۆڵدەرەدا `claude` بکەرەوە.
4. پرۆمپتەکان بە ئینگلیزی بنووسە (کۆد و پلانی باشتر دەدات). یەک قۆناغ لە هەر جارێکدا.
5. بۆ قۆناغە گەورەکان Plan Mode بەکاربهێنە (Shift+Tab دووجار)، پلانەکە بخوێنەوە، پاشان ڕێگە بدە.
6. دوای هەر قۆناغێک لەسەر مۆبایلی ڕاستەقینە تاقی بکەرەوە، نەک emulator.

---

## قۆناغی 0 — دروستکردنی پڕۆژە
```
Read CLAUDE.md carefully. Create the Flutter project in this folder
(org: com.mir, name: kurdish_vision). Set up the folder structure exactly as
in CLAUDE.md with empty, documented stubs and abstract interfaces
(ObjectDetector, SpeechService). Add flutter_lints, configure RTL + Sorani
locale, camera permissions for Android and iOS, and create docs/decisions.md.
Make sure `flutter analyze` and `flutter test` pass. Propose the plan first.
```

## قۆناغی 1 — تاقیکردنەوەی تەکنەلۆژیا (هەفتە 1–2)
گرنگترین قۆناغ. پێش نووسینی ئەپ، سێ شت بسەلمێنە.

**A. دەنگی سۆرانی:**
```
Build a small debug screen that lists all TTS voices/languages available on
this device via flutter_tts and tries to speak a Sorani test sentence
(«لەبەردەمت مێزێک هەیە»). Also implement AudioClipSpeech that plays
pre-recorded clips from assets/audio. Log results to docs/decisions.md.
Do not assume ckb is supported.
```
> ئەنجامی چاوەڕوانکراو: زۆربەی مۆبایلەکان دەنگی سۆرانییان نییە، بۆیە دەنگی پێشتۆمارکراو ڕێگای سەرەکی دەبێت. ناوی 20 شتەکە و چەند پارچە ڕستەیەک بە دەنگی ڕوون تۆمار بکە (یان قسەکەرێکی سۆرانی).

**B. مۆدێل:**
```
Write tools/export_model.py that exports a YOLO nano model (latest stable
Ultralytics release — check the docs) to TFLite (float16 and int8) and
Core ML. Then compare the official Ultralytics Flutter plugin vs
tflite_flutter for our needs (camera stream, isolates, iOS support,
maintenance). Recommend one, record it in docs/decisions.md, wait for my answer.
```

**C. لیستی پۆلەکان:**
```
From the COCO classes, propose 15–20 classes most useful indoors for blind
users. Create lib/speech/kurdish_labels.dart and docs/kurdish_labels.md with
Sorani word + indefinite form for each, marked // REVIEW.
```
> ناوە کوردییەکان خۆت پێداچوونەوەیان بۆ بکە.

## قۆناغی 2 — کامێرا و بنەمای ئەپ (هەفتە 3–4)
```
Implement CameraService with a continuous image stream and FrameScheduler
(configurable 3–5 inferences/sec, drop frames while busy — never queue).
Build the main screen: full-screen camera preview, accessible gestures
(tap = repeat, double tap = pause/resume, long press = settings), Sorani
Semantics labels, haptics. Add unit tests for FrameScheduler.
```

## قۆناغی 3 — یەکخستنی AI (هەفتە 5–6)
```
Implement YoloDetector behind ObjectDetector: YUV/BGRA → RGB preprocessing,
letterbox resize, inference in a background isolate, NMS, map to
DetectionResult (class, confidence, normalized box, position left/center/right).
Android: try GPU delegate, fall back to CPU. Add a debug overlay that draws
boxes (hidden by default). Measure and log each stage's time.
```
```
Implement DetectionFilter and Tracker as specified in CLAUDE.md
(N-of-M confirmation, confidence threshold, cooldown, re-announce on
position change). Then PhraseBuilder that produces natural Sorani sentences
for up to 3 objects. Full unit tests with edge cases.
```

## قۆناغی 4 — باشترکردن (هەفتە 7–8)
```
Implement MetricsLogger (per-frame latency stages, frame-to-speech-start,
FPS, RAM, battery) with CSV export and a hidden evaluation mode toggle.
Then profile the app on a real device for 10 minutes and list the top
bottlenecks with concrete fixes.
```
```
Review the whole codebase as a senior Flutter + accessibility reviewer:
memory leaks, camera lifecycle (app pause/resume), isolate cleanup,
TalkBack/VoiceOver issues, error handling (no camera, model load fail).
Fix the issues, one commit per fix.
```

## قۆناغی 5 — هەڵسەنگاندن (هەفتە 9–10)
```
Write tools/split_dataset.py (train/val/test, preventing near-duplicate
leakage using perceptual hashing) and tools/evaluate.py that computes
Precision, Recall, mAP@0.5 and false positives per class on our labeled
test set. Write tools/analyze_metrics.py that reads the app CSV and outputs
median/P95 latency tables and charts for the paper.
```
```
Draft docs/evaluation.md: methodology for detection accuracy, speed,
Kurdish speech quality (native speaker rating form), and the small user
study (5–10 consenting participants, tasks, SUS questionnaire, safety rules).
```

---

## ئامۆژگاری بۆ کارکردن لەگەڵ Claude Code
- ئەگەر سێشنەکە درێژ بوو، `/clear` بکە و قۆناغی دواتر لە سێشنێکی نوێدا دەست پێ بکە — `CLAUDE.md` هەمیشە دەخوێندرێتەوە.
- هەر کاتێک بڕیارێکی گرنگت دا، بڵێ: `Add this decision to CLAUDE.md`.
- ئەگەر هەڵەیەک هات، دەقی تەواوی error ـەکە بدە، نەک تەنها "کار ناکات".
- `docs/decisions.md` دواتر بەشی Methodology ـی توێژینەوەکەت بۆ دەنووسێت.

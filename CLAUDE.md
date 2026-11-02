# CLAUDE.md — Kurdish Voice Object Recognition App

## Project
Real-time object recognition mobile app (Android + iOS) for blind and visually
impaired users. The camera runs continuously, an on-device YOLO model detects
everyday objects, and the app speaks them in **Sorani Kurdish (ckb)**.

Research title: *Development and Evaluation of a Real-Time Kurdish Voice-Based
Object Recognition Mobile Application for Blind and Visually Impaired People.*

This is a university research project: code quality, measurability and
reproducibility matter as much as features. Every performance claim must be
backed by a measurement the app can log.

## Scope (v1)
- IN: 15–20 everyday object classes (chair, table, door, cup, phone, person,
  car, bottle, laptop, bag, book, ...), real-time detection, Sorani speech,
  stop/repeat controls, full screen-reader support.
- OUT: hazard detection, navigation/route guidance, OCR, face recognition,
  cloud inference, user accounts. Do not add these unless explicitly asked.

## Tech stack
- Flutter (stable channel), Dart null-safety, minimum Android API 24, iOS 13+.
- Camera: `camera` plugin, image stream (YUV420 on Android, BGRA8888 on iOS).
- Inference: YOLO (nano/small variant) on-device.
  - Android: TFLite / LiteRT (try GPU delegate, fall back to CPU/XNNPACK).
  - iOS: Core ML export preferred; TFLite acceptable if simpler.
  - Evaluate the official Ultralytics Flutter plugin vs. `tflite_flutter`
    in Phase 1 and record the decision in `docs/decisions.md`.
- Speech: pre-recorded Sorani audio clips as the **primary** path
  (`assets/audio/`), system TTS (`flutter_tts`) as an optional path only if a
  Sorani voice is verified on the device. Never assume a device has ckb TTS.
- State management: keep it simple (ChangeNotifier or Riverpod — pick one in
  Phase 1, then never mix).
- Always check pub.dev for the current version of a package before adding it.

## Architecture (pipeline)
CameraStream → FrameScheduler → Preprocessing → Detector (on-device)
→ DetectionFilter & Tracker → KurdishPhraseBuilder → SpeechOutput

Rules:
- Each stage lives behind an abstract interface so it can be swapped
  (e.g. `ObjectDetector`, `SpeechService`). Platform-specific inference is an
  implementation detail behind `ObjectDetector`.
- Inference must not block the UI isolate. Run preprocessing + inference in a
  background isolate or native thread.
- FrameScheduler: target 3–5 inferences/sec (configurable). If an inference is
  still running, DROP the new frame — never queue frames.
- Announce an object only after it is confirmed in N of the last M results
  (default 2 of 3) above the confidence threshold (default 0.5, configurable).
- Do not repeat the same object unless: it disappeared and came back, its
  relative position changed (left / center / right), a cooldown expired
  (default 5 s), or the user pressed Repeat.
- Speech priority: at most 3 objects per sentence, ordered by confidence ×
  box size (closest/largest first). New speech never overlaps old speech.

## Folder structure
```
lib/
  main.dart
  app/            app_controller.dart, app_theme.dart
  camera/         camera_service.dart, frame_scheduler.dart
  detection/      object_detector.dart (interface), yolo_detector.dart,
                  detection_result.dart, detection_filter.dart, tracker.dart
  speech/         speech_service.dart (interface), audio_clip_speech.dart,
                  tts_speech.dart, phrase_builder.dart, kurdish_labels.dart
  accessibility/  accessibility_controls.dart, haptics.dart
  metrics/        metrics_logger.dart (latency, FPS, memory → CSV)
  settings/       app_settings.dart
assets/
  models/         *.tflite, labels.txt
  audio/          <class_id>.m4a + phrase fragments
docs/             decisions.md, evaluation.md, kurdish_labels.md
test/             unit tests per module
tools/            Python scripts: model export, dataset split, metric analysis
```

## Kurdish language rules
- All user-facing text and speech in Sorani (Arabic script), RTL layout.
- Labels live in ONE place: `lib/speech/kurdish_labels.dart` (class id →
  Sorani word + indefinite form, e.g. مێز / مێزێک). Mirror them in
  `docs/kurdish_labels.md` for native-speaker review.
- Position words: لای چەپ / لە ناوەڕاست / لای ڕاست.
- Sentence template example: «لەبەردەمت مێزێک هەیە. پەرداخێک و کورسییەکیش دەبینرێن.»
- Never machine-translate new labels silently — add them with a `// REVIEW`
  comment so a native speaker can verify.

## Accessibility (non-negotiable)
- Fully usable with TalkBack and VoiceOver; every control has a Semantics label
  in Sorani.
- Large touch targets (≥ 48 dp). Whole-screen gestures: single tap = repeat,
  double tap = pause/resume, long press = settings (configurable).
- Haptic feedback on start/stop.
- App speech must duck, not mask, environmental sound — keep volume and
  verbosity adjustable.
- The UI must never imply detections are certain. Low-confidence results are
  not spoken.

## Privacy
- All frames processed on-device. No network calls for inference.
- No images are saved unless the user enables a debug/evaluation mode, and
  then only locally.

## Metrics (for the research paper)
`metrics_logger.dart` must record per frame: timestamp, preprocessing ms,
inference ms, post-processing ms, frame-to-speech-start ms, detections,
and periodically RAM and battery level. Export to CSV in app documents dir.
Report median and P95, not just averages.

## Coding standards
- `flutter analyze` must pass with zero warnings; use `flutter_lints`.
- Format with `dart format`. Small files, single responsibility.
- Unit tests for: frame scheduler, detection filter, tracker, phrase builder.
  Run `flutter test` before saying a task is done.
- No hard-coded magic numbers — thresholds go in `app_settings.dart`.
- Comments and identifiers in English; user-facing strings in Sorani.

## Workflow for Claude Code
1. Before coding a phase, propose a short plan and wait for approval.
2. Work in small steps; after each step run `flutter analyze` and tests.
3. Record every non-trivial technical choice in `docs/decisions.md`
   (what, alternatives, why).
4. If something cannot be verified (e.g. a package's Sorani support), say so
   explicitly instead of guessing.
5. Commit after each completed step with a clear message.

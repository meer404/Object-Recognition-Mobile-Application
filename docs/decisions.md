# Technical decisions

Every non-trivial technical choice is recorded here: **what** was decided, the
**alternatives** considered, and **why**. This log feeds the Methodology
section of the paper. Entries are append-only; a reversed decision gets a new
entry that references the old one.

Status values: `accepted`, `provisional` (to be confirmed in a later phase),
`superseded by D-xxx`.

---

## D-001 — Project creation
- **Date:** 2026-11-02 · **Phase:** 0 · **Status:** accepted
- **What:** `flutter create --org com.mir --project-name kurdish_vision --platforms android,ios`
  on Flutter 3.41.6 (stable), Dart 3.11.4. Application ID / bundle prefix
  `com.mir.kurdish_vision`.
- **Alternatives:** including web/desktop platforms.
- **Why:** the study targets phones only; fewer platforms means less
  maintenance and a smaller test matrix.

## D-002 — Static analysis
- **Date:** 2026-11-02 · **Phase:** 0 · **Status:** accepted
- **What:** `flutter_lints` 6.0.0 (latest on pub.dev, checked 2026-11-02) plus
  `strict-casts`, `strict-inference`, `strict-raw-types` and extra rules
  (`avoid_dynamic_calls`, `cancel_subscriptions`, `close_sinks`,
  `unawaited_futures`, `prefer_final_locals`, ...). See `analysis_options.yaml`.
- **Alternatives:** plain `flutter_lints`; `very_good_analysis`.
- **Why:** the strict modes catch type errors that matter in isolate and
  plugin code. The stream/sink rules guard against camera and audio resource
  leaks. `very_good_analysis` would be another dependency to keep in sync.
  `require_trailing_commas` was left out because it conflicts with the
  Dart ≥ 3.7 formatter, which manages trailing commas itself.

## D-003 — State management
- **Date:** 2026-11-02 · **Phase:** 0 · **Status:** provisional (confirm in Phase 1)
- **What:** `ChangeNotifier` (Flutter SDK). `AppController` is the single
  notifier.
- **Alternatives:** Riverpod.
- **Why:** there are no extra dependencies, and the app has one screen and a
  linear pipeline. Pipeline stages are plain Dart classes, so they stay
  testable without any state library. CLAUDE.md: choose one and never mix.

## D-004 — Sorani locale and RTL
- **Date:** 2026-11-02 · **Phase:** 0 · **Status:** accepted
- **What:** the app locale is `ckb`. Flutter 3.41.6 has **no** `ckb`
  Material/Cupertino/Widgets localizations (verified: no `*_ckb.arb` in
  `flutter_localizations/lib/src/l10n`). Custom delegates
  (`lib/app/sorani_localizations.dart`) map `ckb` to the Arabic (`ar`)
  built-ins, and `MaterialApp.builder` also forces `TextDirection.rtl`.
- **Alternatives:** (a) use `Locale('ar')` directly, which reports the wrong
  language to the platform and screen readers; (b) write a full
  `MaterialLocalizations` subclass in Sorani, which is about 80 strings to
  translate and verify.
- **Why:** this gives correct RTL layout and script now at minimal cost.
- **Known limitation:** framework-owned strings (e.g. tooltips of built-in
  buttons) are in Arabic. Mitigation: the app avoids framework widgets with
  built-in text, and all app strings come from `lib/app/ui_strings.dart`.
  Revisit (option b) if a built-in string turns out to be user-audible.
- **Open (Phase 2):** verify on real devices that the system font renders
  every Sorani letter (ڕ ێ ۆ ڵ ڤ). Otherwise bundle Noto Sans Arabic.

## D-005 — Platform minimums and permissions
- **Date:** 2026-11-02 · **Phase:** 0 · **Status:** accepted
- **What:** Android `minSdk = 24` pinned explicitly (equal to the Flutter
  3.41 default today); `CAMERA` and `VIBRATE` permissions; no `INTERNET`
  permission in the release manifest (Flutter adds it only to debug/profile).
  iOS deployment target 13.0 and a Sorani `NSCameraUsageDescription` that
  states frames stay on the device.
- **Why:** this follows the CLAUDE.md scope and privacy rules. Pinning keeps
  the research baseline stable across Flutter upgrades. The `camera` plugin
  is added in Phase 2, where its own minimums get checked.
- **Unverified:** the iOS build (needs macOS + Xcode). No Podfile exists yet;
  CocoaPods creates it on the first iOS build.

## D-006 — Structure additions beyond CLAUDE.md
- **Date:** 2026-11-02 · **Phase:** 0 · **Status:** accepted
- **What:** files that CLAUDE.md's tree does not list:
  `lib/camera/camera_frame.dart` (platform-neutral frame, sendable to
  isolates), `lib/app/sorani_localizations.dart` (D-004),
  `lib/app/ui_strings.dart` (single place for UI text).
- **Why:** these keep `CameraService` and `ObjectDetector` independent of the
  `camera` plugin types, so detectors can be tested with synthetic frames.
  They also keep user-facing text in one reviewable file.

## D-007 — Audio playback stack for recorded clips
- **Date:** 2026-11-02 · **Phase:** 1A · **Status:** accepted
- **What:** `just_audio` 0.10.6 plays the clips and `audio_session` 0.2.4
  configures the audio session. Versions are pinned exactly in `pubspec.yaml`
  for reproducibility. The session is set up so speech briefly lowers other
  audio: iOS `playback` + `duckOthers` + `spokenAudio`; Android focus
  `gainTransientMayDuck`, content type `speech`, usage `media`. The session
  is turned off after every utterance with `notifyOthersOnDeactivation`.
- **Alternatives:** `audioplayers` 6.8.1, which has no built-in playlist, so
  each clip would have to be started manually with an audible gap; Android
  usage `assistanceAccessibility`.
- **Why:** a built-in playlist plays the sentence pieces with almost no gap
  between them. `just_audio` never turns the session off, and other apps stay
  ducked until it is off, so we do it explicitly. Usage `media` means the
  hardware volume keys control speech volume. The accessibility stream would
  follow the separate accessibility volume, which users may not find.
- **Measurement note:** "speech start" is the moment the player reports
  `playing && ready`. Audio output latency on the device adds a few ms that
  this does not capture; state that in the paper.
- **Unverified:** whether ducking works on real devices (Phase 2 device test).

## D-008 — Speech overlap rule
- **Date:** 2026-11-02 · **Phase:** 1A · **Status:** accepted (approved by author)
- **What:** `SpeechSerializer` is shared by all speech back-ends. Speech in
  progress always finishes. While it plays, only the newest request waits and
  older waiting requests are dropped. Repeat (`interrupt: true`) and `stop()`
  cut current speech off.
- **Alternatives:** (a) every new request interrupts at once, which cuts
  words mid-way and is hard to follow; (b) a FIFO queue, which would announce
  scene descriptions that are out of date.
- **Why:** the same drop-don't-queue idea as the FrameScheduler. `speak()`
  completes when playback starts, so the queueing delay is included in the
  measured frame-to-speech-start latency.

## D-009 — Is Sorani system TTS usable? (device results)
- **Date:** opened 2026-11-02 · **Phase:** 1A · **Status:** OPEN, awaiting
  real-device runs
- **What is known without devices:** Flutter's `flutter_tts` 4.2.5 just
  passes through whatever the OS engine reports, so it adds no Sorani
  support of its own. The app treats only `ckb*` as Sorani. `ku` usually
  means Kurmanji (Latin script) and is never used for Sorani text
  (`lib/speech/sorani_tts_selector.dart`).
- **Expectation, not evidence:** most devices will report no `ckb` voice, so
  recorded clips stay the primary path. This entry must be decided by the
  device results below, not by this expectation.
- **Procedure:** debug build → home → "Speech probe (debug)" → enter the
  device model → tap every TTS button and both clip buttons → rate each attempt
  by ear (ideally by a native speaker) → "Copy Markdown report" → paste below.
- **Decision rule:** TTS becomes an optional user setting only on devices
  where a `ckb` attempt is rated "Understood". Otherwise it stays disabled.

### Device results
_None yet. Paste one probe report per device here._

## D-010 — Speech probe screen is debug-only and in English
- **Date:** 2026-11-02 · **Phase:** 1A · **Status:** accepted (approved by author)
- **What:** `lib/debug/speech_probe_screen.dart` opens from a button on the
  home screen that exists only when `kDebugMode` is true, so it is compiled
  out of release builds. Its labels are in English.
- **Alternatives:** Sorani labels; a hidden gesture in release builds.
- **Why:** the only user is the researcher, and the report it produces goes
  into this (English) log. The Sorani-only rule in CLAUDE.md covers
  user-facing text, and end users never see this screen. Keeping it out of
  release builds also keeps it out of the user study.
- **What it records:** engines, default engine, every language and voice,
  `isLanguageAvailable` for ckb/ckb-IQ/ckb-IR/ku/ku-IQ/ku-TR, and for each
  speak attempt: whether it started, the start latency, any error, and a
  **human verdict**. Only the human verdict counts as evidence of Sorani
  intelligibility; the engine lists alone do not.

## D-011 — Web platform for quick local testing only
- **Date:** 2026-11-03 · **Phase:** 1A · **Status:** accepted (requested by author)
- **What:** added the Flutter web platform (`web/`) so the UI and clip
  playback can be checked with `flutter run -d chrome` without a phone.
  The page is `lang="ckb" dir="rtl"`.
- **Not a target platform:** the study targets Android and iOS only
  (CLAUDE.md). In a browser, the speech probe reports the **browser's**
  voices (e.g. Windows/Chrome voices), and ducking does not apply. The
  report says so on its OS line, and browser results are **never** valid
  evidence for D-009.

## D-012 — Model and export pipeline
- **Date:** 2026-11-03 · **Phase:** 1B · **Status:** accepted (choice of
  variant for the app: provisional until on-device latency in Phase 4)
- **Model:** **YOLO26n** (`yolo26n.pt`, SHA-256 `9b09cc8b…8ad4fef`), the
  current Ultralytics family per docs.ultralytics.com/modes/export, 2.41 M
  parameters, 5.5 GFLOPs at 640. COCO-pretrained (80 classes); our 15–20
  classes are chosen from these in Phase 1C.
- **Export environment:** Ultralytics **8.4.198**. Its exporter refuses LiteRT
  export on Windows ("only supported on Linux x86 and macOS") and Core ML
  export on Windows, so exports run in `tools/docker/export.Dockerfile`
  (Python 3.11.9, torch 2.14.1 CPU, litert-torch 0.10.0, ai-edge-litert 2.3.0,
  ai-edge-quantizer 0.10.1, coremltools 9.0, numpy 2.3.5). The full resolved
  set is in `tools/requirements-export.lock.txt`. Weights and calibration data
  are baked into the image. Full results with hashes:
  `docs/model_export_manifest.json` (export run at commit `97b9e1a`).
- **Constraints found while pinning:** litert-torch 0.10.0 requires
  torch < 2.15; Ultralytics' Core ML path requires numpy ≤ 2.3.5; LiteRT
  cannot memory-map files on Docker Desktop's Windows bind mounts, so work
  happens on container-local disk.
- **Correction to the Phase 1B plan:** the `litert` exporter has **no fp16
  option** (accepts 8 / w8a16 / w8a32 / 32 / None), so fp32 replaces fp16.
  Android GPU delegates can still execute fp32 models at fp16 precision.

### Results (fidelity vs. the .pt model; 32 coco128 images, conf 0.25, IoU 0.5)

| Artifact | Size | Match rate | Extra dets | Mean \|Δconf\| |
|---|---|---|---|---|
| 640 fp32 | 9.97 MB | 1.000 (142/142) | 0 | 0.000 |
| 640 w8a32 | 2.88 MB | 0.951 (135/142) | 4 | 0.020 |
| 640 int8 | 2.93 MB | 0.887 (126/142) | 30 | 0.098 |
| 320 fp32 | 9.89 MB | 1.000 (102/102) | 0 | 0.000 |
| 320 w8a32 | 2.80 MB | 0.931 (95/102) | 2 | 0.022 |
| 320 int8 | 2.91 MB | 0.853 (87/102) | 6 | 0.162 |
| 640 / 320 Core ML (.mlpackage) | 5.07 / 5.03 MB | not run (needs macOS) | | |

- Match rate measures **export damage**, not accuracy; real accuracy on our
  own indoor test set is Phase 5. The check images also served as INT8
  calibration data, which flatters int8 if anything.
- **Output layout:** every TFLite export (fp32 too) and Core ML export has
  the **raw** head `[1, 84, anchors]` (4 box + 80 class scores, channels
  first). YOLO26's NMS-free end-to-end head is **not** preserved in these
  exports, so **the app must run NMS** (Phase 3). Input is float32
  **NCHW** `[1, 3, S, S]`.
- **int8 is not reproducible:** two runs with identical inputs gave
  640: 0.845 → 0.887 and 320: 0.833 → 0.853. Calibration is
  nondeterministic, and only 128 calibration images were used (Ultralytics
  recommends > 300). int8 also shifts confidences by ~0.1–0.16, which
  matters because the app only speaks results ≥ 0.5.
- **Decision:** int8 is set aside. **w8a32** (small, deterministic, ≥ 0.93
  match) and **fp32** (exact) go forward. 640 vs 320 and w8a32 vs fp32 are
  decided by on-device latency in Phase 4. The 3–5 inferences/sec target
  decides, not this table.
- **Licence:** Ultralytics releases YOLO26 weights under **AGPL-3.0**. A
  distributed app using them must be AGPL-compatible open source, or needs
  an Ultralytics Enterprise licence. To be confirmed with the supervisor.

## D-013 — On-device inference plugin
- **Date:** 2026-11-03 · **Phase:** 1B · **Status:** accepted (chosen by author,
  2026-11-07)
- **Candidates** (pub.dev / GitHub build files, checked 2026-11-03):

| | `ultralytics_yolo` 0.7.1 | `flutter_litert` 3.9.4 | `tflite_flutter` 0.12.1 |
|---|---|---|---|
| Maintainer | Ultralytics (official) | one developer (hugo.ml) | TensorFlow, last release 2025-10-28 |
| Licence | AGPL-3.0 | Apache-2.0 | Apache-2.0 |
| Android minSdk / iOS | 24 / 13.0 | 21 / 13.0 | 19 (docs say 26) / – |
| Runtime | LiteRT 2.3 | LiteRT 1.4.2 + 2.x | LiteRT 1.4.0 |
| Camera | its own native `YOLOView` | our `camera` stream | ours |
| Our FrameScheduler / per-stage timing | no documented throttle or timing API | yes, we own every stage | yes |
| Background inference | native | `IsolateInterpreter` | `IsolateInterpreter` |
| Delegates | automatic GPU → CPU | GPU (V2), XNNPACK, Metal, Core ML | GPU, Metal, Core ML |
| iOS model | Core ML `.mlpackage` | same `.tflite` via Core ML / Metal delegate | same `.tflite` |

- **Decision: `flutter_litert`** (3.9.4; added to `pubspec.yaml` in Phase 3). CLAUDE.md requires our own
  FrameScheduler (drop, don't queue), an `ObjectDetector` interface and
  per-stage timings (preprocess / inference / postprocess). `YOLOView`
  owns the camera and the inference loop, so stages could not be measured
  separately. `ultralytics_yolo`'s `predict(imageBytes)` takes encoded image
  bytes, so every frame would need JPEG encoding first (unverified cost).
  `flutter_litert` keeps the `tflite_flutter` API, bundles its native
  runtimes, and is actively released. One `.tflite` serves both platforms,
  which simplifies the paper's methodology.
- **Costs of the recommendation:** we write preprocessing (YUV/BGRA →
  NCHW float), letterboxing and NMS ourselves (Phase 3). The plugin depends
  on one maintainer (mitigated: the API matches `tflite_flutter`, so it can
  be swapped behind `ObjectDetector`). On iOS it uses TFLite + delegate
  rather than the Core ML export that CLAUDE.md prefers; CLAUDE.md allows
  TFLite "if simpler". The `.mlpackage` exports are kept in case.
- **Not chosen, and why:** `tflite_flutter`, because its own fork describes
  it as unmaintained, it had no release for 12 months, and its docs and
  build file disagree on the Android minimum.

## D-014 — Object classes for v1
- **Date:** 2026-11-07 · **Phase:** 1C · **Status:** accepted (approved by
  author); Sorani wording awaits native-speaker review
- **What:** 20 of the model's 80 COCO classes: person, car, backpack, handbag,
  bottle, cup, bowl, chair, couch, bed, dining table, toilet, tv, laptop,
  remote, cell phone, sink, refrigerator, book, clock. Source of truth:
  `lib/speech/kurdish_labels.dart`; review sheet: `docs/kurdish_labels.md`.
  `assets/models/labels.txt` is the model's label file, and a test checks each
  id against it. Phase 3 must filter detections to these classes.
- **Criteria:** common indoors and useful to a blind user, plus the examples in
  CLAUDE.md. Left out as low value or easily confused: mouse, keyboard,
  microwave, oven, suitcase, potted plant. This is a judgement call, not a
  measurement; the user study can test it.
- **Limitation: no door.** CLAUDE.md lists door as an example, but COCO has no
  door class, so `yolo26n` cannot detect one. The author chose to drop it for
  v1 rather than train a custom model. State this in the paper.
- **Other mismatches with CLAUDE.md's examples:** "table" is COCO `dining table`
  (a desk may not be detected as one; unmeasured); "bag" is split into
  backpack and handbag.

## D-015 — kurdishtts.com audio stays local (free-plan terms)
- **Date:** 2026-11-07 · **Phase:** 1A follow-up · **Status:** accepted for
  testing; shipping is an open decision for the author
- **What:** one synthetic test clip («لەبەردەمت مێزێک هەیە.», voice `sorani_85`,
  model `v3`, MP3, 24 kHz mono, 12.5 KB) is stored in the git-ignored
  `assets/audio/local/`. It plays from the debug speech probe only, and is
  not in the committed manifest. The app never calls the service at runtime.
- **Why:** kurdishtts.com/privacyterms (read 2026-11-07), Terms §7: "Free:
  evaluation and testing only, with no publication and no commercial use."
  The right to "include the output inside a product you sell or operate" is
  listed under the Pro plan. Committing the clip to the public repository could
  count as publication. This is a reading of the terms, not legal advice.
- **Open question:** shipping synthetic clips would need the Pro plan (listed at
  USD 29/month on 2026-11-07) and a native-speaker rating. Recorded clips from a
  native speaker remain the default. Whether the user study may use free-plan
  audio is unconfirmed; ask the vendor or use recordings.
- **Release risk:** `assets/audio/local/` is bundled into every build made on
  a machine that has the file. Empty it before building anything for other
  people, including the user study.
- **Update (2026-11-07):** the full test set of 48 clips (D-020) was generated the
  same way, using about 400 characters of the free quota. It is also git-ignored
  and is listed by `assets/audio/local/manifest.json`, which debug and profile
  builds read (profile since D-024's session, which was silent without it);
  release builds never do. Release builds would still bundle the files, so the release-risk note
  above applies to them too.
- **For the paper:** any synthetic audio used must be reported as synthetic,
  with its voice and model version.

## D-016 — Camera packages and frame scheduling
- **Date:** 2026-11-07 · **Phase:** 2 · **Status:** accepted (author chose to
  keep the toolchain)
- **Toolchain:** stays on Flutter 3.41.6 / Dart 3.11.4 (current stable is
  3.47.9). So `camera` is pinned to **0.12.0+2** and `wakelock_plus` to
  **1.7.0**, the newest that support it; `camera` 0.12.1+ needs Flutter 3.44+.
  Upgrading would be a separate, deliberate step.
- **Permission:** `camera` requests it, so no `permission_handler`. Audio is off
  (`enableAudio: false`), so the microphone is never requested at runtime. The
  Android manifest declaration is handled in D-018.
- **Scheduling:** the interval runs from the start of the last accepted frame,
  on a monotonic clock, and a frame is accepted only when idle.
- **Effective rate is below the target:** frames only arrive at camera rate, so
  the rate is rounded down to it. In a unit test, target 4/s on a 30 fps stream
  gives every 8th frame, **3.75/s**. Compensating for drift would add complexity
  for little gain; report the measured rate, not the setting.
- **Unsupported pixel formats are dropped**, never misread.

## D-017 — Screen, gestures and screen readers
- **Date:** 2026-11-07 · **Phase:** 2 · **Status:** accepted (plan approved by
  author)
- **Portrait lock:** the app and the capture orientation are locked to portrait,
  so left and right in the image match the user's while the phone is upright.
- **Screen readers:** TalkBack and VoiceOver consume raw gestures. Their activate
  gesture runs repeat (or retry), their long press opens settings, and
  pause/resume is a named custom action. Its name changes with the state, and it
  is absent when there is nothing to pause. Status changes are announced in
  Sorani. Whether real screen readers offer these actions as intended is
  **unverified**; widget tests only check what the app exposes.
- **Double-tap cost:** recognising a double tap makes a plain single tap wait for
  the double-tap window (about 300 ms in Flutter) before Repeat runs. Screen-reader
  activation has no such wait. Measure in Phase 4 if it matters.
- **Lifecycle:** the camera is released on `hidden`/`paused` and restored on
  return, keeping a user pause. `inactive` is ignored, because the permission
  dialog and multi-window focus changes cause it. Automatic retry needs a real
  trip to the background, or denying the dialog would reopen it in a loop.
- **Settings pause the camera** so speech cannot talk over them, and the settings
  back button has a Sorani tooltip (the built-in one is Arabic, D-004).
- **Not done yet:** CLAUDE.md says gestures are configurable; the mapping is fixed
  until the settings screen is built. Repeat has nothing to say until Phase 3.
- **Structure additions:** `lib/app/camera_screen.dart`,
  `lib/camera/plugin_camera_service.dart`, `lib/settings/settings_screen.dart`.

## D-018 — Android permissions in the merged manifest
- **Date:** 2026-11-07 · **Phase:** 2 · **Status:** accepted
- **Found by** inspecting the built APK: `camera_android_camerax` 0.7.2 declares
  `RECORD_AUDIO` and `WRITE_EXTERNAL_STORAGE` (which implies
  `READ_EXTERNAL_STORAGE`) for video recording. The app uses none of them, so
  `AndroidManifest.xml` removes them with `tools:node="remove"`. A test keeps
  those markers in place.
- **Kept:** `ACCESS_NETWORK_STATE` and `WAKE_LOCK` from media3 (the audio player
  behind `just_audio`). Neither prompts the user or exposes camera or audio data,
  and removing them could break playback.
- **Verified on 2026-11-07:** the generated release manifest lists only CAMERA,
  VIBRATE, ACCESS_NETWORK_STATE, WAKE_LOCK and androidx's internal receiver
  permission, with **no INTERNET**. INTERNET comes only from Flutter's debug and
  profile manifests, which confirms D-005. No model file ships yet, and Phase 3
  must repeat this check after adding `flutter_litert`.
- **Unverified:** that the camera opens correctly on a real phone with these
  removed. It should, since none is needed without video recording.

## D-019 — Detector implementation
- **Date:** 2026-11-07 · **Phase:** 3 · **Status:** accepted (plan approved by
  author); the model and input size are provisional until Phase 4 measures them
  on a phone
- **Model:** `yolo26n_320_fp32.tflite` (9.9 MB, D-012) via `flutter_litert` 3.10.0.
  **Git-ignored**, chosen by the author until the AGPL-3.0 weights are confirmed
  with the supervisor. A fresh clone must run `tools/export_model.py` and copy the
  file into `assets/models/`; without it the app shows a Sorani error, and the
  real-model tests skip.
- **Model I/O, confirmed against the file (not only the docs):** input float32
  NCHW `[1, 3, 320, 320]`, RGB, 0–1. Output `[1, 84, 2100]`: centre x, y, width,
  height normalized to the input, then 80 class scores already in 0–1. NMS is
  our job.
- **Bilinear, not nearest:** compared with bilinear on 128 COCO images (PIL, same
  model), nearest-neighbour matched 88.5 % of detections at conf ≥ 0.25 and 91.7 %
  at conf ≥ 0.5. Box averaging matched 94.0 % / 96.9 %. Bilinear reads 4× as many
  pixels per output pixel, and its real cost on a phone is unmeasured.
- **Isolate:** one long-lived worker does preprocessing, inference and
  postprocessing, and owns the interpreter because GPU delegates are bound to the
  thread that creates them. `IsolateInterpreter` alone would leave preprocessing
  on the UI isolate. If the worker dies, the waiting frame fails rather than
  hanging the FrameScheduler.
- **Accelerators:** Android GPU delegate with precision loss allowed (fp16), iOS
  Metal, then XNNPACK, then plain CPU. **Which of these really works on a phone
  is unverified.** The Core ML delegate is not used yet.
- **Rotation:** a frame taller than it is wide is treated as already upright, since
  the app is portrait-locked. Android is expected to deliver landscape sensor
  frames; iOS behaviour is unverified, and the rule holds either way.
- **Evidence so far:** tests run the real model through the real Dart code on a
  real photo, on Windows. As an upright BGRA frame and as a rotated YUV frame, it
  finds every reference object above 0.5 (same class, IoU ≥ 0.8). Resizing is
  within 2/255 of `cv2.INTER_LINEAR`, and decoding matches an independent Python
  decode of real output. The YUV frame is simulated: a real camera's colour range
  and strides are still unverified.
- **Sensitivity to note in the paper:** one person's confidence ranged from 0.56 to
  0.75 between the `.pt` and `.tflite` runs at 320, partly from padding and resizing.
  Evaluate through the app's own preprocessing, not Ultralytics' defaults.

## D-020 — Announcing and sentences
- **Date:** 2026-11-07 · **Phase:** 3 · **Status:** accepted (approved by author);
  wording awaits native-speaker review
- **Sentences:** at most 3 objects by confidence × box area. Only the main object
  has a position, by the author's choice. Each class is named once. Centre uses
  «لەبەردەمت» from CLAUDE.md's template, so «لە ناوەڕاست» from its position list is
  currently unused; the review sheet asks which is right. Repeat with nothing
  confirmed says «هیچ شتێک نەناسرایەوە» rather than staying silent.
- **«ـیش» is a whole recorded word** (`class_<id>_also`), not a suffix clip. The set
  is 48 clips: 20 × 2 word forms plus 8 pieces.
- **Tracks:** a detection continues a track of its class at IoU ≥ 0.3. Confirmation
  is per track, so two chairs are two objects.
- **Definitions that go beyond CLAUDE.md:**
  - "Disappeared" means no hits in the whole N-of-M window. Merely dropping below
    N keeps its cooldown, or flicker around the threshold would repeat forever.
  - A position changes only once the centre is 0.05 past a boundary (hysteresis).
  - New objects are only announced while speech is idle, and stay due until spoken.
- **Known limits:** tracking matches by overlap only, so an object moving fast
  between frames counts as new and is re-announced. An object that leaves for
  about a second and returns is announced again, as CLAUDE.md's rule says, which
  may feel chatty. Neither has been tried with users.
- **Metrics:** `RecognitionPipeline` reports `FrameMetrics` per frame. Frame-to-speech
  runs from frame arrival to `speak()` starting. Writing them to CSV is Phase 4.

## D-021 — Measurement sessions
- **Date:** 2026-11-08 · **Phase:** 4 · **Status:** accepted (plan approved by
  author); real numbers need a phone
- **Build mode rule:** debug builds run Dart in JIT mode and are much slower, so
  **only profile or release sessions may back a performance claim**. Every session
  records its build mode, `session.json` has `valid_for_performance_claims`, and
  the analyzer prints a warning for debug sessions. Build with
  `--dart-define=GIT_COMMIT=$(git rev-parse HEAD)` so each session names its code.
- **Evaluation mode:** a labelled Sorani switch in Settings, in every build, off
  by default. The Phase 4 prompt says "hidden", but the author chose a visible
  switch, because a hidden gesture is hard to find and use with a screen reader.
  It is not persisted: it is off again after a restart. Nothing is recorded while
  it is off, and **no images are ever saved** (CLAUDE.md privacy rule).
- **Files** (one folder per session in the app documents directory,
  `metrics/<UTC timestamp>/`):
  - `session.json`: build mode, app version, git commit, device and OS,
    accelerator, model file and size, every `AppSettings` value. A test checks
    that no setting is missing.
  - `frames.csv`: per processed frame, the preprocess, inference, postprocess and
    total ms (time inside the detector, excluding the wait for a free worker), the
    detection count, and frame-to-speech-start ms (empty, not zero, when the frame
    started no speech).
  - `device.csv`: every 10 s, RSS MB, battery % and state, camera frames/s,
    inferences/s, and frames dropped while busy or by the rate limit. Rates and
    drops cover the interval since the previous sample; the first sample has none.
- **What RSS measures:** the resident memory of the whole app process as the OS
  reports it (`ProcessInfo.currentRss`), including native memory such as the model
  and camera buffers. It is not the Dart heap alone, and it is not peak memory
  between samples.
- **Battery:** whole-device level in whole percent, so short sessions show little
  change; it is also affected by screen brightness and other apps. Profile for at
  least 10 minutes, with the same brightness, and report the drop per hour.
- **Durability:** rows are flushed every 5 s and on pause, background and close,
  so a crash loses at most about 5 s.
- **Export:** a Sorani button shares the latest session through the system share
  sheet (`share_plus`). The user chooses the destination; the app makes no network
  calls. In debug builds on Android, `adb shell run-as` also works.
- **Analysis:** `tools/analyze_metrics.py` gives n, median, P95 (linear
  interpolation, as numpy's default), min and max per stage. Its tests run on a
  session written by the Dart logger (`test/fixtures/metrics_session/`).
- **Permissions:** the four new plugins declare no Android permissions. The release
  manifest was re-checked after adding them (below).

## D-022 — Code review (Phase 4)
- **Date:** 2026-11-08 · **Phase:** 4 · **Status:** done for what can be checked
  without a phone
- **Scope:** memory and resource leaks, camera lifecycle, isolate cleanup, error
  handling and screen-reader behaviour. Each bug was first reproduced with a
  failing test, then fixed in its own commit.
- **Fixed:**
  1. One failed camera call froze the controller: its operation chain stayed
     failed, so pause, resume, background release and dispose were all skipped.
  2. The same pattern in metrics: one failed write dropped all later rows, and
     one failed session start disabled the evaluation switch for the run.
  3. A hung inference stopped detection and speech forever, silently. It now
     times out (`detectionTimeout`, 10 s), and the app shows its error message
     and can reload.
  4. Disposing during model load left the worker running. Late messages from
     an old worker could disturb its replacement.
  5. A repeated long press opened Settings twice and resumed the camera behind
     them.
  6. A tap while paused did nothing at all. It now vibrates and announces the
     paused state.
- **Checked, no change needed:** releasing the audio player mid-sentence still
  restores other apps' volume (`just_audio`'s `stop()` is safe after dispose).
  The camera is released on background even while still opening, because
  lifecycle events queue behind the open.
- **Found, not fixed (decisions for later):**
  - **A release build is silent.** Only debug builds read the local test clips
    (D-015), and no recordings exist yet, so every sentence resolves to no clips.
    Native-speaker recordings, or a Pro-plan decision, are needed before any
    release or user study.
  - **Every camera frame crosses to Dart** (about 30/s at roughly 460 KB each)
    even though about 4/s are used. A likely CPU and battery cost to measure in
    the profiling run before changing anything.
  - **TalkBack and the app can speak at the same time.** The app's speech ducks
    other audio but not the screen reader. Behaviour on a real phone is unknown.
  - Evaluation mode is not remembered across restarts (D-021).

## D-023 — Evaluation tooling
- **Date:** 2026-11-08 · **Phase:** 5 · **Status:** accepted (plan approved by
  author); not yet run on real data
- **Predictions from the app's own code (author's choice):**
  `tool/eval/predict_test.dart` runs the real `YoloDetector` on each photo on a
  laptop, through the same preprocessing, NMS and class filter as the phone, and
  not a Python reimplementation, because D-019 found preprocessing shifts
  confidence by up to about 0.2. Photos are EXIF-rotated upright and scaled to a
  longer side of 720 px (about a medium camera frame), using the `image` package.
  The candidate floor is 0.001 so AP sees the whole curve. The laptop uses fp32
  on CPU, the phone's GPU fp16, so small differences remain (to spot-check).
- **Metrics (`tools/evaluate.py`):** precision, recall, false positives and
  misses **at the speaking threshold 0.5**, because that is what users hear,
  plus AP@0.5 and mAP@0.5 with Ultralytics' method. Tests confirm it equals
  Ultralytics' `compute_ap` on 50 random curves, and that a perfect detector
  scores 0.995. Bug found by tests: a labelled class with no predictions must
  score 0, not the 0.5 produced by the curve padding.
- **Split (`tools/split_dataset.py`):** groups by dHash (≤ 8 of 64 bits) and by
  capture folder, then splits whole groups 70/15/15 with a seed. The threshold
  comes from synthetic scenes (near-copies 0–7 bits apart, distinct scenes ≥ 9).
  Because real photos may differ, the report lists similar pairs that crossed
  splits.
- **Charts:** box plots per stage (P25–P75, median, whiskers P5–P95), with
  colours from the validated categorical order. Every box is named on its axis.
- **Labels:** YOLO .txt with COCO class ids (author's choice).

## D-024 — First run on a real phone
- **Date:** 2026-11-08 · **Device:** Infinix X690B (Note 7), Android 10 (API 29)
  · **Build:** debug (not valid for speed claims, D-021)
- **Confirmed working:**
  - Build, install and camera permission.
  - Back camera at 720×480 through CameraX; the preview is upright and fills the
    screen without distortion.
  - **The model runs entirely on the GPU:** LiteRT reported "Replacing 414 out of
    414 node(s) with delegate (TfLiteGpuDelegateV2)… 1 partitions", via OpenCL.
  - Speech played: a 24 kHz track of about 2.9 s, the length of a full sentence.
  - The long press opens Settings, and the evaluation and debug switches toggle.
  - Native heap was about 81 MB.
- **Bugs found and fixed:**
  - Back on the main screen crashed the app: the camera was still streaming when
    the engine detached. Now the camera is released before closing; verified on
    the phone.
  - The settings back button was read as Arabic then Sorani («رجوع گەڕانەوە»).
    Now Sorani only; verified on the phone.
- **To measure:**
  - The camera delivered only about **12.5 frames/s**. The room was dark at the
    time, and longer exposure lowers the frame rate. Re-check in normal light;
    at 12.5/s the 3–5 inferences/s target still fits.
  - `just_audio` releases its native player on every `stop()`, so a new
    ExoPlayer is created for every sentence, which probably adds to
    frame-to-speech-start. Measure in the profile session before changing it.
- **Not yet checked:** whether detections and positions are correct, whether the
  debug boxes line up (the camera faced darkness), returning from the background,
  TalkBack in use, and the speech probe report (D-009).

## D-025 — Bottlenecks from the first profile session
- **Date:** 2026-11-08 · **Phase:** 4 part 2 · **Status:** measured; fixes
  proposed, not yet applied
- **Data:** `docs/measurements/2026-11-08_infinix_x690b_profile_gpu/` (10 min,
  profile build, GPU, dark scene, charging). See its README for the limits.
- **What the numbers show:**
  - The detector takes 138 ms median (P95 166 ms): inference 76 %,
    preprocessing 18 %, postprocessing 4 %.
  - Inference ran at 3.10/s, below the target of 4, but **the camera, not the
    detector, sets that limit**. At 12.5 frames/s a frame arrives every 80 ms,
    so the first frame at least 250 ms after the last comes 320 ms later:
    3.125/s (D-016). The detector alone could do about 7/s.
  - 7,824 frames arrived and 1,971 were used. Each of the other 5,853 still
    crossed the platform channel into Dart (about 460 KB each at 720×480 YUV)
    only to be dropped.
  - Memory was stable at 309–351 MB, with no leak over 10 minutes.
- **Bottlenecks, ranked, each with a concrete fix to measure:**
  1. **GPU inference, 105 ms median.** Mali-class GPUs are often no faster than
     a good CPU path for a model this small. *Fix:* an `AppSettings` accelerator
     override (auto, GPU or CPU) for evaluation builds, then A/B sessions: GPU
     fp32, CPU XNNPACK fp32 and CPU XNNPACK w8a32 (D-012) on this phone.
  2. **Camera resolution larger than the model needs.** The model sees 320 px; a
     720×480 frame is downscaled to 320×213 anyway. *Fix:* `CameraQuality.low`
     (about 320×240) gives the model nearly the same pixels, while cutting the
     data per frame about 4.5×, the transfer of dropped frames, and the
     preprocessing time. The preview gets blurrier, which only affects the debug
     overlay. Needs an accuracy spot-check (tools/evaluate.py at both sizes) and
     a session.
  3. **Rate rounding to the camera's frame interval.** *Fix:* schedule against a
     running "due time" (the next frame becomes eligible at the previous due time
     plus the interval, not the previous accept time), so the average reaches the
     target, e.g. 4/s alternating 240 and 320 ms gaps at 12.5 fps. A pure
     FrameScheduler change, testable without a phone. Also re-measure the camera
     rate in normal light, since dark scenes lower it.
  4. **Preprocessing, 25 ms in Dart.** *Fix:* fixed-point bilinear and no
     per-pixel virtual call. Worth less than 1 or 2, and must keep the
     2/255 match with cv2 that the fixture test checks.
- **Not yet measured:** frame-to-speech-start (no speech in this session), and
  the per-sentence ExoPlayer re-creation (D-024). Profile builds now load the
  local clips (`92c9558`); a session pointed at real objects is needed.
- **Order of work:** 3 (no phone needed), then 1 and 2 as A/B sessions on the
  phone, then 4 only if needed.


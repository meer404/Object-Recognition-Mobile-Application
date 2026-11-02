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
  device model → tap every TTS button and "Recorded clip" → rate each attempt
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

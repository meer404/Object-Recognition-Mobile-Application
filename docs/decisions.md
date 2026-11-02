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

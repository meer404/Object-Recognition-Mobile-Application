# Object-Recognition-Mobile-Application

**Development and Evaluation of a Real-Time Kurdish Voice-Based Object
Recognition Mobile Application for Blind and Visually Impaired People**
(university research project).

A Flutter app (Android + iOS). The camera runs continuously, an on-device
YOLO model detects everyday objects, and the app speaks them in **Sorani
Kurdish (ckb)**. All processing happens on the phone; no images leave the
device.

## Status
| Phase | Content | State |
|---|---|---|
| 0 | Project scaffold, interfaces, RTL/Sorani locale, permissions | done |
| 1A | Sorani speech: recorded clips (primary), TTS probe | done, device results pending |
| 1B | YOLO26n export, inference plugin (`flutter_litert`) | done |
| 1C | 20 object classes with draft Sorani labels | done, native-speaker review pending |
| 2 | Camera, frame scheduler, main screen, gestures | done, device test pending |
| 3 | On-device detection, tracking, Sorani sentences | done, device test pending |
| 4 | Metrics logging and export | logger done; on-device profiling pending |
| 5 | Evaluation | planned |

## Build and test
Requires Flutter (stable channel). Android API 24+, iOS 13+.

```
flutter pub get
flutter analyze
flutter test
flutter run            # on a real device; in debug builds, Settings has a "Speech probe"
```

The model file is not in this repository (AGPL-3.0 weights, `docs/decisions.md`
D-019). To enable detection, run the export in `tools/README.md` and copy
`build/models/yolo26n_320_fp32.tflite` into `assets/models/`. Without it, the app
shows an error and the tests that need it skip.

## Documentation
- [`CLAUDE.md`](CLAUDE.md): project rules, architecture and scope
- [`docs/decisions.md`](docs/decisions.md): every technical decision (what / alternatives / why)
- [`docs/audio_recording.md`](docs/audio_recording.md): how to record the Sorani clips
- [`docs/kurdish_labels.md`](docs/kurdish_labels.md): Sorani strings awaiting native-speaker review
- [`docs/evaluation.md`](docs/evaluation.md): evaluation plan

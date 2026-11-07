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
| 3 | On-device detection, tracking, Sorani sentences | next |
| 4–5 | Optimisation, evaluation | planned |

## Build and test
Requires Flutter (stable channel). Android API 24+, iOS 13+.

```
flutter pub get
flutter analyze
flutter test
flutter run            # on a real device; in debug builds, Settings has a "Speech probe"
```

## Documentation
- [`CLAUDE.md`](CLAUDE.md): project rules, architecture and scope
- [`docs/decisions.md`](docs/decisions.md): every technical decision (what / alternatives / why)
- [`docs/audio_recording.md`](docs/audio_recording.md): how to record the Sorani clips
- [`docs/kurdish_labels.md`](docs/kurdish_labels.md): Sorani strings awaiting native-speaker review
- [`docs/evaluation.md`](docs/evaluation.md): evaluation plan

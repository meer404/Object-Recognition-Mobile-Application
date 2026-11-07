# Session 2026-11-08, Infinix X690B, profile build, GPU

Raw files exported by the app's evaluation mode (D-021); summary with
`python tools/analyze_metrics.py docs/measurements/2026-11-08_infinix_x690b_profile_gpu`.

| | |
|---|---|
| Device | Infinix X690B (Note 7), Android 10 (API 29) |
| Build | profile, commit `6fa17ea` |
| Accelerator | GPU via OpenCL, all 414 model nodes delegated |
| Model | `yolo26n_320_fp32.tflite`, 9,894,796 bytes |
| Duration | 635 s (23:00:50–23:11:25 UTC) |

**Conditions and limits.** The phone lay still facing a dark scene, so there
were almost no detections and **no speech** (profile builds also had no clips
then, since fixed), so frame-to-speech-start was not measured. The phone was
**charging**, so the battery figures are not valid. Stage timings, camera and
inference rates, and memory are valid for this device in low light.

**Known artefact.** The first `device.csv` row shows 42 / 108 dropped frames
counted since app start, not since the session began. This was fixed in
`88a673c` (the first row is now empty). Ignore that row's drop columns.

| Stage | Median ms | P95 ms |
|---|---|---|
| Preprocessing | 25.3 | 38.6 |
| Inference (GPU) | 104.9 | 121.4 |
| Postprocessing | 5.4 | 12.4 |
| Detector total | 138.4 | 165.6 |

Camera 12.50 frames/s, inference 3.10/s (target 4), RSS 309–351 MB with no
upward trend over the session. Interpretation and next steps: D-025.

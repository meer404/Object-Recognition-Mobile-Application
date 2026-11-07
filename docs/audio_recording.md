# Recording the Sorani audio clips

Recorded clips are the **primary** speech path (CLAUDE.md, D-007). Their
quality directly limits how intelligible the app is, so record them
consistently and document every session.

> **Have a native speaker review the wording first.** The recording list is now
> fixed in code: `allClipTexts()` in `lib/speech/kurdish_labels.dart` gives all 48
> clips, and the wording is in `docs/kurdish_labels.md`. Recording before the review
> risks doing it twice. Words joined from separate clips may also still sound
> choppy; try the sentence examples on a phone before recording everything.

> **Synthetic clips are for evaluation only, for now.** A test clip from
> kurdishtts.com lives in the git-ignored `assets/audio/local/`. Under the free
> plan's terms it must not be committed, published or shipped (D-015).

## 1. Speaker and consent
- One native Sorani speaker for the whole set (consistent voice). Note their
  dialect (e.g. Sulaymaniyah / Erbil).
- Written consent that the recordings may be bundled in the app and used in
  the research. Store the consent form outside this repository.

## 2. Setup
- Quiet, soft-furnished room. No fan or air-conditioning noise.
- Same microphone, distance (~20 cm) and gain for every session. Use a pop
  filter if available.
- Record **masters** as WAV, 48 kHz, 24-bit, mono. Keep masters outside
  `assets/` (they are large). Only processed files are bundled.
- Record 3 takes of each item and keep the clearest one.
- Speak at a calm, slightly slower than conversational pace.

## 3. Processing (each clip)
1. Trim leading silence to **≤ 20 ms**. Leading silence adds directly to the
   measured frame-to-speech-start latency.
2. Keep ~50 ms of trailing silence so joined pieces don't run together.
3. Normalise loudness so all clips sound equally loud: target
   **-16 LUFS integrated**, true peak ≤ -1 dBTP.
4. Export as **AAC in .m4a**, mono, 44.1 kHz, 64–96 kbps. `just_audio` plays
   it on Android and iOS.

Suggested `ffmpeg` command. ffmpeg is not part of this project and this
exact command has not been tested in it, so check the result by ear:

```
ffmpeg -i master.wav -af "silenceremove=start_periods=1:start_threshold=-50dB,loudnorm=I=-16:TP=-1" -ac 1 -ar 44100 -c:a aac -b:a 80k out.m4a
```

## 4. Naming and the manifest
- Files go in `assets/audio/`. Names: lowercase ASCII, snake_case.
  - Object classes need two clips: the indefinite form, `<class_id>.m4a`
    with key `class_<id>` (e.g. مێزێک), and the «ـیش» form,
    `<class_id>_also.m4a` with key `class_<id>_also` (e.g. مێزێکیش).
  - Phrase pieces use the keys in `allClipTexts()`, e.g. `in_front.m4a` for
    «لەبەردەمت».
- Add every file to `assets/audio/manifest.json`:
  ```json
  { "version": 1, "clips": { "class_60": "60.m4a", "in_front": "in_front.m4a" } }
  ```
- A unit test (`test/speech/clip_manifest_test.dart`) fails if the manifest
  points to a file that does not exist.
- A key the app requests that is missing from the manifest is skipped, not a
  crash. The speech probe and `AudioClipSpeech.missingClipKeys` show gaps.

## 5. Placeholders
`assets/audio/placeholder/` holds **tones, not speech**, made by
`tools/make_placeholder_clips.py`. To replace one, put the real file in
`assets/audio/` and point the manifest key at it. Delete the placeholder
before the user study.

## 6. Session log (fill in)

| Date | Speaker (code) | Dialect | Mic / room | Items recorded | Notes |
|---|---|---|---|---|---|
| | | | | | |

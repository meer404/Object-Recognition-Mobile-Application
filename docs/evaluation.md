# Evaluation plan (draft)

Methodology for the paper *Development and Evaluation of a Real-Time Kurdish
Voice-Based Object Recognition Mobile Application for Blind and Visually
Impaired People*. Tooling: `tools/README.md`. Decisions referenced as D-xxx are
in `docs/decisions.md`.

> **Status: draft.** Nothing here has been run on real data yet. The user study
> (section 4) needs **approval from the university's research ethics committee
> before any participant is contacted**. This document is input for that
> application, not a substitute for it.

---

## 1. Detection accuracy

**Question:** how often does the app find, and correctly name, the 20 object
classes in realistic indoor scenes, and how often does it speak something that
is not there?

### 1.1 Test set
- **Scenes:** indoor rooms where the app would be used: kitchen, living room,
  bedroom, office, bathroom. Several homes, not one.
- **Capture:** the researcher's phone, held at chest height pointing forward, as
  a user would. Vary the lighting (daylight, lamp, dim), distance (about 0.5–4 m)
  and clutter. Record the device and date per session folder.
- **People:** if anyone is identifiable in a photo, get their written consent, or
  leave them out. Photos stay on the researcher's computer and are not
  published.
- **Size (guidance, not a rule):** aim for at least 30–50 labelled instances per
  class in the test split, so per-class AP is not dominated by a few images.
  Classes with fewer get reported with their count and marked as low-confidence.
- **Folder layout:** one sub-folder per capture session (for example
  `kitchen_home1_2026-11-20/`). The splitter keeps each folder in a single split.

### 1.2 Labelling
- Tool: CVAT or Label Studio, exported in **YOLO format** (one `.txt` per image,
  `class cx cy w h`, normalized). Class ids are the COCO ids in
  `assets/models/labels.txt` (for example chair = 56).
- Label every visible instance of the 20 classes, including partly visible ones
  if a person would recognise them. Skip objects under about 2 % of the image
  width.
- A second person re-labels a random 10 % of the images, and the agreement is
  reported (share of boxes matched at IoU ≥ 0.5).

### 1.3 Split
`python tools/split_dataset.py <dataset>` (D-023): 70/15/15 by whole groups. A
group is a perceptual-hash near-duplicate cluster (dHash, ≤ 8 of 64 bits) or a
capture-session folder, so near-copies never cross splits. Check
`closest_pairs_across_splits` in the report by eye. **The test split is only
used for the final numbers**, never for tuning thresholds.

### 1.4 Predictions and metrics
- Predictions come from **the app's own detector code**, run on a laptop
  (`tool/eval/predict_test.dart`). Each photo is EXIF-rotated upright and scaled
  to camera size (longer side 720 px) first.
- `python tools/evaluate.py predictions.json --names assets/models/labels.txt`
  reports per class and overall:
  - **At the app's speaking threshold (0.5):** true positives, false positives,
    missed objects, Precision = TP/(TP+FP), Recall = TP/labels. These describe
    what a user actually hears.
  - **AP@0.5 and mAP@0.5:** Ultralytics' definition (101-point envelope,
    trapezoid rule), so a perfect detector scores 0.995. mAP is the mean over
    classes that have labels.
  - **False positives per image** at the speaking threshold, the main safety
    measure: a wrong announcement can mislead a blind user.
- Matching: same class, IoU ≥ 0.5, each label matched once, highest confidence
  first.
- **Known gap:** the laptop runs the model in fp32 on CPU, while the phone's GPU
  uses fp16 (D-019), so confidences can differ slightly. Spot-check by comparing
  a few images' detections on the phone (debug overlay) with the laptop output.

### 1.5 Reporting
Per-class table (labels, AP@0.5, P, R, FP), mAP@0.5, overall P/R/FP per image at
0.5, the split report summary, the model SHA-256 and the git commit. Discuss the
classes that are weak and why (size, look-alikes such as dining table vs desk).

---

## 2. Speed and resource use

**Question:** does the app keep up in real time, and what does it cost in
memory and battery?

### 2.1 Protocol
- **Build:** profile or release only (D-021). Debug numbers are not valid:
  `flutter build apk --profile --dart-define=GIT_COMMIT=$(git rev-parse HEAD)`.
- **Devices:** at least one mid-range and one older Android phone (and an iPhone
  if available). Record model, OS and accelerator; `session.json` does this.
- **Conditions:** battery 50–90 % and not charging, screen brightness fixed (for
  example 50 %), the same room and lighting, other apps closed, phone at room
  temperature at the start.
- **Session:** turn evaluation mode on, point at a typical scene for **10
  minutes**, moving slowly as a user would, then turn it off and export.
  **3 sessions per device**, each starting from a cold app start.

### 2.2 Measures
Per stage (preprocessing, inference, postprocessing, detector total) and
frame-to-speech-start: **median and P95** (`tools/analyze_metrics.py`, linear
interpolation). Also inferences per second against the 3–5 target, frames
dropped (busy vs rate limit), peak RSS, and battery % per hour.
`analyze_metrics.py compare … --charts` produces the comparison table and box
plots.

### 2.3 Caveats to report
Frame-to-speech-start is measured from frame arrival to `speak()` starting; it
excludes the device's audio output latency (D-007). RSS is the whole process,
sampled every 10 s, not peak memory (D-021). Battery is in whole percent and
depends on screen brightness.

---

## 3. Sorani speech quality

**Question:** are the spoken words and sentences correct, intelligible and
natural for native Sorani speakers?

### 3.1 Raters
At least **two native Sorani speakers**, ideally from different dialect areas
(for example Sulaymaniyah and Erbil), not involved in writing the labels. Record
each rater's dialect area.

### 3.2 Material
- All 48 clips from `allClipTexts()` (20 objects × 2 forms + 8 sentence pieces).
- Example sentences as the app plays them: one, two and three objects, each
  position, and the "nothing recognised" message. At least 10 sentences.
- Play each item twice through the phone speaker at normal volume, in random
  order. Raters do not see the text first.

### 3.3 Rating form (one row per item)

| Item | What did you hear? (write it) | Correct word form? (yes / no / suggest) | Intelligibility 1–5 | Naturalness 1–5 | Comment |
|---|---|---|---|---|---|
| class_56 | | | | | |
| sentence_03 | | | | | |

- **Intelligibility:** 1 = could not understand, 3 = understood with effort, 5 =
  understood immediately.
- **Naturalness:** 1 = very unnatural or robotic, 3 = acceptable, 5 = like a
  natural speaker.
- **Transcription accuracy** (heard vs intended) is the objective measure; the
  1–5 scores give the mean opinion score (MOS) per item.

### 3.4 Use of results
Report MOS per item type (word, sentence), transcription accuracy, and agreement
between raters. Any word marked incorrect is fixed in `kurdish_labels.dart`
(its `// REVIEW` comment removed only when verified) and re-recorded. If
synthetic audio is used anywhere, report it as synthetic with voice and model
version (D-015).

---

## 4. User study (5–10 participants)

**Question:** can blind and visually impaired people use the app to find and
identify everyday objects, and how usable do they find it?

### 4.1 Ethics and consent
- **Ethics committee approval first.** Include this section, the consent form
  and the safety rules in the application.
- Informed consent in Sorani, read aloud and in an accessible format.
  Participants can withdraw at any time without giving a reason, and their data
  is then deleted.
- Data collected: task times, success, SUS answers, comments. **No images or
  audio of participants.** The app saves no camera images. Participants are
  identified by a code only.

### 4.2 Participants
5–10 adults who are blind or have low vision, who use a smartphone, and who are
Sorani speakers. Record (by code) the level of vision, screen-reader use, and
age range.

### 4.3 Safety rules
- **The app is not a mobility aid.** It does not detect hazards or guide
  movement (CLAUDE.md scope). Participants are told this in the briefing.
- Sessions are **seated or standing still**, in a quiet indoor room arranged
  beforehand, with no obstacles in reach. Participants do not walk while using
  the app.
- The researcher stays next to the participant throughout and can stop the
  session at any time. So can the participant.
- No sharp, hot or fragile objects in the task area.

### 4.4 Procedure (about 45 minutes)
1. Briefing, consent and a short training: tap, double tap and long press, with
   and without TalkBack/VoiceOver.
2. **Tasks** (order randomized per participant, objects placed by the
   researcher):
   - T1: "Tell me what is on the table in front of you." (2–3 objects)
   - T2: "Is there a cup? Is it on your left or right?"
   - T3: "Find the chair in this room, without getting up." (turn the phone)
   - T4: Pause the app, then resume it.
   - T5: Ask the app to repeat what it sees.
3. SUS questionnaire, then a short interview: what helped, what confused you,
   what is missing.

### 4.5 Measures
- Per task: success (yes / partial / no), time to completion, and errors (wrong
  object or side named, or the participant misled by a false announcement).
- **SUS** (System Usability Scale; Brooke, 1996), the standard 10 items on a
  1–5 scale, scored 0–100. A **validated Sorani version is required**: translate,
  back-translate and pilot it with native speakers. Do not machine-translate it
  (CLAUDE.md).
- Qualitative comments, grouped into themes.

### 4.6 Reporting
Task success rates and times (median and range, since n is small), SUS mean and
range against the usual benchmark of about 68, and the main themes. With 5–10
participants the results are exploratory; avoid significance claims.

---

## 5. Test configuration log

Fill in for every run.

| Date | What (accuracy / speed / speech / study) | Device(s) and OS | Build mode | App commit | Model SHA-256 | Settings changed from defaults | Notes |
|---|---|---|---|---|---|---|---|
| | | | | | | | |

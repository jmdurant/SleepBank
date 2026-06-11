# YASA nap-staging tool (Mac side)

Turns a SleepBank raw-EEG export into a sleep-stage hypnogram + per-epoch labels,
in one double-click. Those labels are the ground truth for training SleepBank's
on-device onset/deep-sleep model.

## One-time setup
```sh
cd tools/yasa
./setup.sh          # creates a venv, installs YASA + MNE + deps (~a few minutes)
```

## The loop (mostly automatic)
1. **On the phone:** just take naps with the Muse connected. Each nap's raw EEG
   is written to the app's **iCloud Drive** container and **syncs to this Mac
   automatically** (Finder → iCloud Drive → SleepBank). No AirDrop needed.
   *(Fallback: Validation → Export raw EEG → AirDrop to ~/Downloads also works.)*
2. **On the Mac, whenever:** double-click **`Stage Naps.command`**.
   - It finds **every** `eeg-*.csv` that hasn't been staged yet (in the iCloud
     folder, Downloads, or Desktop), runs YASA on each, and for each writes:
     - **`<name>_hypnogram.csv`** (per-30s-epoch stage + probabilities),
     - **`<name>_hypnogram.png`** (the hypnogram),
   - merges YASA stages onto the sensor features → `labeled-*.csv` + a combined
     `training.csv`,
   - builds **`report.html`** and opens it — a dashboard with one card per nap:
     hypnogram, stage breakdown, and **SleepBank's calls vs YASA** (onset latency,
     deep-sleep timing, asleep/awake agreement %).
   - Re-running only stages *new* naps; the report always rebuilds from all.

That's it — nap on the phone, batch-process on the Mac later. No Python commands.
The `report.html` is your validation view: how well the app's detector tracks the
EEG ground truth, nap by nap.

## What you get
- `eeg-…_hypnogram.png` — the staged hypnogram (W / REM / N1 / N2 / N3 over time).
- `eeg-…_hypnogram.csv` — `epoch, start_sec, stage, <stage probabilities>`. These
  are the labels to merge with the per-epoch sensor features (the other CSV the
  Validation screen exports) to build the training set.

## Honest caveats
- YASA is validated on **central PSG**, not frontal Muse — labels are a strong
  *silver* standard, not true gold. Sanity-check the hypnogram against the raw
  trace, especially N1 (the hardest stage frontally).
- Staging needs **≥5 min**; very short naps will warn.
- Muse→µV scaling here is approximate (`0.488 µV/unit`); fine for staging, which
  is shape/relative driven.

## Training the on-device model
Once you have a few naps' `training.csv` (built automatically by Stage Naps), train:

- Double-click **`Train Model.command`** (or `./train.py`).
- It fits a classifier per target with **leave-one-nap-out cross-validation** (the
  only honest estimate on n=1 / a few naps) and exports:
  - **`NapOnsetClassifier.mlmodel`** — matches `CoreMLOnsetDetector`'s contract
    exactly (inputs `hr, hrv, movement, stillSeconds, eegOnset, eegDeep`; output
    `labelProbability → {"asleep", "awake"}`).
  - **`NapDeepClassifier.mlmodel`** — N3-approach head-start (not yet consumed by
    the app; deep-wake is engine logic today).
- **Drag `NapOnsetClassifier.mlmodel` into the watch target in Xcode.**
  `CoreMLOnsetDetector` picks it up automatically; without it the app keeps using
  the heuristic, so nothing breaks.

**Honest n=1 reality:** with 1 nap `train.py` reports in-sample *fit* and says so
loudly — take ≥3 naps before trusting a number. YASA labels are **silver** (frontal
Muse, not PSG): n=1 *calibrates the thresholds to you*; only PSG (the pilot)
*validates*.

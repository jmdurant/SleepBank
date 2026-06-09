# YASA nap-staging tool (Mac side)

Turns a SleepBank raw-EEG export into a sleep-stage hypnogram + per-epoch labels,
in one double-click. Those labels are the ground truth for training SleepBank's
on-device onset/deep-sleep model.

## One-time setup
```sh
cd tools/yasa
./setup.sh          # creates a venv, installs YASA + MNE + deps (~a few minutes)
```

## Each nap (the simple loop)
1. **On the phone:** Validation → **Export last nap's raw EEG** → AirDrop the
   `eeg-*.csv` to this Mac (it lands in ~/Downloads).
2. **On the Mac:** double-click **`Stage Latest Nap.command`**.
   - It finds the newest `eeg-*.csv`, runs YASA on the AF7 channel, and:
     - opens a **hypnogram PNG**,
     - writes **`<name>_hypnogram.csv`** (per-30s-epoch stage + probabilities),
     - prints onset latency / time asleep / stage counts.

That's it — no Python commands.

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

## Next step (training)
Once you have several `*_hypnogram.csv` + the matching feature CSVs, a small merge
script aligns YASA stage → each feature epoch by time, producing the labeled
table to train a CreateML/CoreML model → drop into `CoreMLOnsetDetector`.

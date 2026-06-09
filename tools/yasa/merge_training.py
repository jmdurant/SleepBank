#!/usr/bin/env python3
"""Merge YASA stage labels onto SleepBank sensor features → a labeled training set.

For each `features-<stamp>.csv` that has a matching `eeg-<stamp>_hypnogram.csv`
(produced by stage_nap.py), assigns every feature row the YASA stage of its 30 s
epoch, writes `labeled-<stamp>.csv`, and concatenates all naps into `training.csv`
— the table to train SleepBank's on-device onset/deep model.

Label columns added: yasa_stage (W/N1/N2/N3/REM), asleep (0/1), yasa_deep (0/1, N3).
Train on the sensor features (hr, hrv, movement, stillSeconds, eegOnset, eegDeep,
breathing, spo2) → asleep (onset) and/or yasa_deep (deep-sleep approach).
"""
import os
import sys
import glob

SEARCH_DIRS = [
    os.path.expanduser("~/Library/Mobile Documents/iCloud~com~doctordurant~sleepbank/Documents"),
    os.path.expanduser("~/Downloads"),
    os.path.expanduser("~/Desktop"),
]
ASLEEP = {"N1", "N2", "N3", "REM"}


def main():
    try:
        import pandas as pd
    except ImportError as e:
        sys.exit(f"Missing dependency ({e.name}). Run ./setup.sh once.")

    feature_files = []
    for d in SEARCH_DIRS:
        feature_files += glob.glob(os.path.join(d, "features-*.csv"))
    feature_files = sorted(set(feature_files))
    if not feature_files:
        print("No features-*.csv found yet. Take a nap, then run staging.")
        return

    labeled = []
    for fpath in feature_files:
        stamp = os.path.basename(fpath)[len("features-"):-len(".csv")]
        d = os.path.dirname(fpath)
        hyp = os.path.join(d, f"eeg-{stamp}_hypnogram.csv")
        if not os.path.exists(hyp):
            print(f"  skip {stamp}: no hypnogram yet (stage the EEG first)")
            continue

        df = pd.read_csv(fpath)
        stages = pd.read_csv(hyp)["stage"].tolist()

        def stage_at(t):
            i = int(t // 30)
            return stages[i] if 0 <= i < len(stages) else "W"

        df["yasa_stage"] = df["t"].apply(stage_at)
        df["asleep"] = df["yasa_stage"].isin(ASLEEP).astype(int)
        df["yasa_deep"] = (df["yasa_stage"] == "N3").astype(int)
        df["nap"] = stamp

        out = os.path.join(d, f"labeled-{stamp}.csv")
        df.to_csv(out, index=False)
        labeled.append(df)
        print(f"  {stamp}: {len(df)} rows, asleep {df['asleep'].mean() * 100:.0f}%"
              f", N3 {df['yasa_deep'].mean() * 100:.0f}%  -> {os.path.basename(out)}")

    if not labeled:
        print("Nothing merged — stage the EEG first (Stage Naps.command).")
        return

    master = pd.concat(labeled, ignore_index=True)
    outdir = next((d for d in SEARCH_DIRS if os.path.isdir(d)), os.path.expanduser("~/Downloads"))
    mpath = os.path.join(outdir, "training.csv")
    master.to_csv(mpath, index=False)
    print(f"\nTraining set: {len(master)} rows from {len(labeled)} nap(s) -> {mpath}")
    print("Columns:", list(master.columns))


if __name__ == "__main__":
    main()

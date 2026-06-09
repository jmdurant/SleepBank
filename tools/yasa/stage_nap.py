#!/usr/bin/env python3
"""Stage the most recent SleepBank raw-EEG export with YASA.

Finds the newest `eeg-*.csv` (in ~/Downloads or ~/Desktop, or a path you pass),
runs YASA single-channel sleep staging on the AF7 column, writes a hypnogram PNG
+ a per-epoch labels CSV, prints a summary, and opens the PNG. Those per-epoch
stage labels are the ground truth for training SleepBank's on-device model.

Note: YASA is validated on central PSG, not frontal Muse — treat the labels as a
strong "silver standard," and sanity-check against the raw trace.
"""
import sys
import os
import glob
import subprocess

SEARCH_DIRS = [os.path.expanduser("~/Downloads"), os.path.expanduser("~/Desktop")]
MUSE_UV_PER_UNIT = 0.48828125   # 12-bit Muse ADC -> microvolts (approx)
SF = 256
STAGE_ORDER = {"W": 0, "REM": 1, "N1": 2, "N2": 3, "N3": 4}


def find_latest():
    if len(sys.argv) > 1 and sys.argv[1].endswith(".csv"):
        return sys.argv[1]
    files = []
    for d in SEARCH_DIRS:
        files += glob.glob(os.path.join(d, "eeg-*.csv"))
    if not files:
        sys.exit("No eeg-*.csv found in ~/Downloads or ~/Desktop. "
                 "AirDrop one from SleepBank first (Validation → Export raw EEG).")
    return max(files, key=os.path.getmtime)


def main():
    try:
        import numpy as np
        import pandas as pd
        import mne
        import yasa
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError as e:
        sys.exit(f"Missing dependency ({e.name}). Run ./setup.sh once to install YASA.")

    path = find_latest()
    print(f"Staging: {path}")
    df = pd.read_csv(path)
    if "af7" not in df.columns:
        sys.exit("CSV has no 'af7' column — is this a SleepBank EEG export?")

    af7 = df["af7"].to_numpy(dtype=float)
    af7 = (af7 - np.nanmean(af7)) * MUSE_UV_PER_UNIT     # center -> microvolts
    dur_min = len(af7) / SF / 60
    print(f"  {len(af7)} samples (~{dur_min:.1f} min) at {SF} Hz")
    if dur_min < 5:
        print("  WARNING: <5 min — YASA staging is unreliable on very short naps.")

    info = mne.create_info(["AF7"], SF, "eeg", verbose=False)
    raw = mne.io.RawArray(af7[np.newaxis, :] * 1e-6, info, verbose=False)  # MNE wants Volts

    sls = yasa.SleepStaging(raw, eeg_name="AF7")
    hypno = sls.predict()
    proba = sls.predict_proba()

    base = os.path.splitext(path)[0]

    # Per-epoch labels CSV (the training ground truth).
    out_csv = base + "_hypnogram.csv"
    epochs = pd.DataFrame({
        "epoch": range(len(hypno)),
        "start_sec": [i * 30 for i in range(len(hypno))],
        "stage": hypno,
    })
    epochs = pd.concat([epochs, proba.reset_index(drop=True)], axis=1)
    epochs.to_csv(out_csv, index=False)
    print(f"  Labels  -> {out_csv}")

    # Summary.
    counts = pd.Series(hypno).value_counts().to_dict()
    print("  Stages (30s epochs):", counts)
    asleep = [i for i, s in enumerate(hypno) if s != "W"]
    if asleep:
        print(f"  Onset latency ~{asleep[0] * 30 / 60:.1f} min;"
              f" asleep ~{len(asleep) * 30 / 60:.1f} min")

    # Hypnogram PNG (plotted manually for YASA-version independence).
    out_png = base + "_hypnogram.png"
    codes = [STAGE_ORDER.get(s, 0) for s in hypno]
    t = [i * 0.5 for i in range(len(codes))]   # minutes (30s epochs)
    fig, ax = plt.subplots(figsize=(11, 3))
    ax.step(t, codes, where="post", color="#3b3bb5")
    ax.set_yticks(list(STAGE_ORDER.values()))
    ax.set_yticklabels(list(STAGE_ORDER.keys()))
    ax.invert_yaxis()
    ax.set_xlabel("minutes")
    ax.set_title(os.path.basename(path))
    fig.tight_layout()
    fig.savefig(out_png, dpi=120)
    print(f"  Hypno   -> {out_png}")
    subprocess.run(["open", out_png])


if __name__ == "__main__":
    main()

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

SEARCH_DIRS = [
    # iCloud Drive container — SleepBank syncs nap EEG here automatically.
    os.path.expanduser("~/Library/Mobile Documents/iCloud~com~doctordurant~sleepbank/Documents"),
    os.path.expanduser("~/Downloads"),   # AirDrop fallback
    os.path.expanduser("~/Desktop"),
]
MUSE_UV_PER_UNIT = 0.48828125   # 12-bit Muse ADC -> microvolts (approx)
SF = 256
STAGE_ORDER = {"W": 0, "REM": 1, "N1": 2, "N2": 3, "N3": 4}


def find_unprocessed():
    """All eeg-*.csv across the search dirs that don't yet have a hypnogram."""
    if len(sys.argv) > 1 and sys.argv[1].endswith(".csv"):
        return [sys.argv[1]]
    found = []
    for d in SEARCH_DIRS:
        for f in glob.glob(os.path.join(d, "eeg-*.csv")):
            if not os.path.exists(os.path.splitext(f)[0] + "_hypnogram.csv"):
                found.append(f)
    return sorted(set(found), key=os.path.getmtime)


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

    pending = find_unprocessed()
    if not pending:
        print("No new naps to stage. (Export from SleepBank → Validation, or it "
              "syncs via iCloud Drive automatically.)")
        return
    print(f"Staging {len(pending)} nap(s)…\n")
    last_png = None
    for path in pending:
        png = stage_one(path, np, pd, mne, yasa, plt)
        if png:
            last_png = png
    if last_png:
        subprocess.run(["open", last_png])   # open the most recent result


def stage_one(path, np, pd, mne, yasa, plt):
    print(f"=== {os.path.basename(path)} ===")
    try:
        df = pd.read_csv(path)
    except Exception as e:
        print(f"  skip (unreadable: {e})")
        return None
    if "af7" not in df.columns:
        print("  skip (no 'af7' column — not a SleepBank EEG export)")
        return None

    af7 = df["af7"].to_numpy(dtype=float)
    af7 = (af7 - np.nanmean(af7)) * MUSE_UV_PER_UNIT     # center -> microvolts
    dur_min = len(af7) / SF / 60
    print(f"  {len(af7)} samples (~{dur_min:.1f} min) at {SF} Hz")
    if dur_min < 5:
        print("  skip (<5 min — too short for reliable YASA staging)")
        return None

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
    plt.close(fig)
    print(f"  Hypno   -> {out_png}\n")
    return out_png


if __name__ == "__main__":
    main()

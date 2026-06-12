#!/usr/bin/env python3
"""The validation measuring stick: score SleepBank's live onset detector against
YASA-staged ground truth, per nap and in aggregate.

Reads the `labeled-<stamp>.csv` files (sensor features + YASA stage per row, written
by merge_training.py) and computes the metrics from HYPOTHESES_AND_ANALYSIS_PLAN.md
Aim 1: onset-latency error, sleep/wake sensitivity & specificity, Cohen's kappa, and
deep-sleep (N3) timing error — for each nap and pooled across all of them.

The detector's call lives in the `phase` column (what actually drove the wake live);
`asleep`/`yasa_deep` are the YASA truth. So this compares the detector to the ground
truth on the very session it ran on — an honest replay, no re-simulation.

Honest caveats (carried from the README):
- YASA on frontal Muse is a *silver* standard, not PSG gold. These numbers calibrate
  and sanity-check; only the PSG pilot validates.
- Sleep/wake agreement is scored per 30 s epoch (PSG convention) to avoid the
  autocorrelation inflation you'd get scoring per-second rows.

Run: ./validate.py            (prints a text report over all labeled naps)
     imported by build_report.py for the HTML dashboard.
"""
import os
import sys
import glob

# Detector phases that mean "the app believes you're asleep" (waking = smart-wake
# window, still asleep). settling/monitoring/finished = awake.
ASLEEP_PHASES = {"asleep", "waking"}
EPOCH_SEC = 30

SEARCH_DIRS = [
    os.path.expanduser("~/Library/Mobile Documents/iCloud~com~doctordurant~sleepbank/Documents"),
    os.path.expanduser("~/Downloads"),
    os.path.expanduser("~/Desktop"),
]


def per_nap_metrics(df):
    """Compute the validation metrics for one nap's labeled dataframe."""
    n_rows = len(df)
    dur_min = float(df["t"].max()) / 60 if n_rows else 0.0

    pred_asleep = df["phase"].isin(ASLEEP_PHASES).astype(int)
    truth_asleep = df["asleep"].astype(int)

    # --- Onset latency (per-second precision): first 'asleep' call vs first YASA sleep
    our_onset = float(df.loc[pred_asleep == 1, "t"].min()) if (pred_asleep == 1).any() else None
    yasa_onset = float(df.loc[truth_asleep == 1, "t"].min()) if (truth_asleep == 1).any() else None
    onset_err = (our_onset - yasa_onset) if (our_onset is not None and yasa_onset is not None) else None

    our_deep = float(df.loc[df["eegDeep"] == 1, "t"].min()) if (df["eegDeep"] == 1).any() else None
    yasa_deep = float(df.loc[df["yasa_stage"] == "N3", "t"].min()) if (df["yasa_stage"] == "N3").any() else None
    deep_err = (our_deep - yasa_deep) if (our_deep is not None and yasa_deep is not None) else None

    # --- Sleep/wake agreement, scored per 30 s epoch (PSG convention) ---
    epoch = (df["t"] // EPOCH_SEC).astype(int)
    by = df.assign(_epoch=epoch, _pred=pred_asleep, _truth=truth_asleep).groupby("_epoch")
    ep_pred = (by["_pred"].mean() >= 0.5).astype(int)      # detector majority for the epoch
    ep_truth = (by["_truth"].mean() >= 0.5).astype(int)    # YASA (constant within epoch)

    tp = int(((ep_pred == 1) & (ep_truth == 1)).sum())
    tn = int(((ep_pred == 0) & (ep_truth == 0)).sum())
    fp = int(((ep_pred == 1) & (ep_truth == 0)).sum())
    fn = int(((ep_pred == 0) & (ep_truth == 1)).sum())

    return {
        "nap": str(df["nap"].iloc[0]) if "nap" in df and n_rows else "?",
        "dur_min": dur_min,
        "our_onset": our_onset, "yasa_onset": yasa_onset, "onset_err": onset_err,
        "our_deep": our_deep, "yasa_deep": yasa_deep, "deep_err": deep_err,
        "tp": tp, "tn": tn, "fp": fp, "fn": fn,
        **_rates(tp, tn, fp, fn),
    }


def _rates(tp, tn, fp, fn):
    total = tp + tn + fp + fn
    sens = tp / (tp + fn) if (tp + fn) else None        # detect sleep
    spec = tn / (tn + fp) if (tn + fp) else None        # detect wake
    acc = (tp + tn) / total if total else None
    if total:
        po = (tp + tn) / total
        pe = (((tp + fp) * (tp + fn)) + ((fn + tn) * (fp + tn))) / (total * total)
        kappa = (po - pe) / (1 - pe) if (1 - pe) else None
    else:
        kappa = None
    return {"sens": sens, "spec": spec, "acc": acc, "kappa": kappa, "epochs": total}


def aggregate(naps):
    """Pool metrics across naps: confusion pooled over all epochs; onset/deep errors
    summarized as mean/SD/MAE and within-5-min hit rate."""
    import numpy as np
    if not naps:
        return None

    tp = sum(n["tp"] for n in naps); tn = sum(n["tn"] for n in naps)
    fp = sum(n["fp"] for n in naps); fn = sum(n["fn"] for n in naps)

    onset_errs = np.array([n["onset_err"] for n in naps if n["onset_err"] is not None], float)
    deep_errs = np.array([n["deep_err"] for n in naps if n["deep_err"] is not None], float)
    kappas = np.array([n["kappa"] for n in naps if n["kappa"] is not None], float)

    def summ(a):
        if not len(a):
            return None
        return {"mean": float(a.mean()), "sd": float(a.std(ddof=1)) if len(a) > 1 else 0.0,
                "mae": float(np.abs(a).mean()), "n": int(len(a)),
                "within5": int((np.abs(a) <= 300).sum())}

    return {
        "n_naps": len(naps),
        "pooled": _rates(tp, tn, fp, fn),
        "onset": summ(onset_errs),
        "deep": summ(deep_errs),
        "kappa_mean": float(kappas.mean()) if len(kappas) else None,
        "tp": tp, "tn": tn, "fp": fp, "fn": fn,
    }


# ---------------------------------------------------------------- formatting

def signed_min(t):
    return "—" if t is None else f"{t / 60:+.1f}m"


def dur_min(t):
    return "—" if t is None else f"{t / 60:.1f}m"


def pct(x):
    return "—" if x is None else f"{x * 100:.0f}%"


def k2(x):
    return "—" if x is None else f"{x:.2f}"


def load_naps():
    import pandas as pd
    files = []
    for d in SEARCH_DIRS:
        files += glob.glob(os.path.join(d, "labeled-*.csv"))
    files = sorted(set(files), key=os.path.getmtime)
    naps = []
    for path in files:
        try:
            naps.append(per_nap_metrics(pd.read_csv(path)))
        except Exception as e:
            print(f"  skip {os.path.basename(path)}: {e}")
    return naps


def main():
    try:
        import pandas  # noqa: F401
    except ImportError as e:
        sys.exit(f"Missing dependency ({e.name}). Run ./setup.sh once.")

    naps = load_naps()
    if not naps:
        print("No labeled-*.csv yet — run Stage Naps first.")
        return

    print("\n  SleepBank onset detector vs YASA (silver standard)\n")
    print(f"  {'nap':<17}{'dur':>6}{'onset Δ':>9}{'sens':>7}{'spec':>7}{'κ':>7}")
    print("  " + "-" * 53)
    for n in naps:
        print(f"  {n['nap']:<17}{n['dur_min']:>5.0f}m{signed_min(n['onset_err']):>9}"
              f"{pct(n['sens']):>7}{pct(n['spec']):>7}{k2(n['kappa']):>7}")
    print("  " + "-" * 53)

    agg = aggregate(naps)
    p = agg["pooled"]
    print(f"\n  AGGREGATE — {agg['n_naps']} nap(s), {p['epochs']} epochs (30 s)\n")
    if agg["onset"]:
        o = agg["onset"]
        print(f"  Onset latency error : {o['mean'] / 60:+.1f} ± {o['sd'] / 60:.1f} min   "
              f"(MAE {o['mae'] / 60:.1f} min, within ±5 min: {o['within5']}/{o['n']})")
    print(f"  Sensitivity (sleep) : {pct(p['sens'])}      Specificity (wake): {pct(p['spec'])}")
    print(f"  Accuracy            : {pct(p['acc'])}      Cohen's kappa     : "
          f"{k2(p['kappa'])}  (per-nap mean {k2(agg['kappa_mean'])})")
    if agg["deep"]:
        d = agg["deep"]
        print(f"  Deep (N3) timing err: {d['mean'] / 60:+.1f} ± {d['sd'] / 60:.1f} min   (MAE {d['mae'] / 60:.1f} min)")
    print()
    if agg["n_naps"] < 3:
        print("  ⚠️  < 3 naps — directional only. YASA is silver (frontal Muse, not PSG).\n")


if __name__ == "__main__":
    main()

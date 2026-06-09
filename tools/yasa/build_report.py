#!/usr/bin/env python3
"""Build an HTML dashboard from staged + merged naps.

One card per nap: the YASA hypnogram, stage breakdown, and a side-by-side of
SleepBank's own calls vs YASA — onset latency (our first 'asleep'/'waking' epoch
vs YASA's first non-W), asleep agreement %, and deep-sleep timing (our EEG-deep
flag vs YASA's first N3). This is the validation view: each batch shows how well
the app's detector tracks the EEG ground truth.
"""
import os
import sys
import glob
import subprocess

SEARCH_DIRS = [
    os.path.expanduser("~/Library/Mobile Documents/iCloud~com~doctordurant~sleepbank/Documents"),
    os.path.expanduser("~/Downloads"),
    os.path.expanduser("~/Desktop"),
]
ASLEEP_PHASES = {"asleep", "waking"}

CSS = """
* { box-sizing: border-box; }
body { font: 15px -apple-system, system-ui, sans-serif; background:#0f1020; color:#e9e9f2; margin:0; padding:24px; }
h1 { font-size:20px; margin:0 0 4px; }
.sub { color:#9a9ab5; margin:0 0 24px; font-size:13px; }
.card { background:#1a1b33; border:1px solid #2a2b48; border-radius:16px; padding:16px 18px; margin-bottom:18px; }
.card h2 { font-size:15px; margin:0 0 10px; color:#c9c9e8; }
img { width:100%; border-radius:10px; background:#fff; }
.grid { display:grid; grid-template-columns:1fr 1fr; gap:8px 24px; margin-top:12px; }
.row { display:flex; justify-content:space-between; border-bottom:1px solid #25264180; padding:4px 0; }
.row .k { color:#9a9ab5; } .row .v { font-variant-numeric:tabular-nums; }
.ours { color:#8a8aff; } .yasa { color:#5ad18a; }
.agree { font-size:22px; font-weight:600; }
.tag { font-size:11px; padding:2px 8px; border-radius:999px; background:#2a2b48; color:#c9c9e8; }
"""

PAGE_HEAD = f"<!doctype html><meta charset=utf-8><title>SleepBank naps</title><style>{CSS}</style>"


def fmt_min(t):
    return f"{t / 60:.1f} min" if t is not None else "—"


def build_card(stamp, df, png, pd):
    dur = float(df["t"].max()) / 60 if len(df) else 0.0

    our = df[df["phase"].isin(ASLEEP_PHASES)]
    our_onset = float(our["t"].min()) if len(our) else None
    ya = df[df["yasa_stage"] != "W"]
    yasa_onset = float(ya["t"].min()) if len(ya) else None

    our_asleep = df["phase"].isin(ASLEEP_PHASES).astype(int)
    agree = (our_asleep == df["asleep"]).mean() * 100 if len(df) else 0

    deep_ours = float(df[df["eegDeep"] == 1]["t"].min()) if (df["eegDeep"] == 1).any() else None
    deep_yasa = float(df[df["yasa_stage"] == "N3"]["t"].min()) if (df["yasa_stage"] == "N3").any() else None

    counts = df["yasa_stage"].value_counts()
    breakdown = " · ".join(
        f"{s} {counts[s] / len(df) * dur:.0f}m" for s in ["W", "N1", "N2", "N3", "REM"] if s in counts
    )
    img = f'<img src="file://{png}">' if os.path.exists(png) else "<p>(no hypnogram)</p>"

    return f"""
    <div class="card">
      <h2>{stamp} <span class="tag">{dur:.0f} min · {breakdown}</span></h2>
      {img}
      <div class="grid">
        <div class="row"><span class="k">Onset — <span class="ours">ours</span></span><span class="v">{fmt_min(our_onset)}</span></div>
        <div class="row"><span class="k">Onset — <span class="yasa">YASA</span></span><span class="v">{fmt_min(yasa_onset)}</span></div>
        <div class="row"><span class="k">Deep — <span class="ours">ours (EEG flag)</span></span><span class="v">{fmt_min(deep_ours)}</span></div>
        <div class="row"><span class="k">Deep — <span class="yasa">YASA (first N3)</span></span><span class="v">{fmt_min(deep_yasa)}</span></div>
      </div>
      <p style="margin:12px 0 0;color:#9a9ab5">Asleep/awake agreement vs YASA: <span class="agree">{agree:.0f}%</span></p>
    </div>
    """


def main():
    try:
        import pandas as pd
    except ImportError as e:
        sys.exit(f"Missing dependency ({e.name}). Run ./setup.sh once.")

    files = []
    for d in SEARCH_DIRS:
        files += glob.glob(os.path.join(d, "labeled-*.csv"))
    files = sorted(set(files), key=os.path.getmtime, reverse=True)
    if not files:
        print("No labeled-*.csv yet — run staging + merge first.")
        return

    cards = []
    for path in files:
        stamp = os.path.basename(path)[len("labeled-"):-len(".csv")]
        png = os.path.join(os.path.dirname(path), f"eeg-{stamp}_hypnogram.png")
        try:
            df = pd.read_csv(path)
            cards.append(build_card(stamp, df, png, pd))
        except Exception as e:
            print(f"  skip {stamp}: {e}")

    out = os.path.join(os.path.expanduser("~/Downloads"), "report.html")
    body = (f"{PAGE_HEAD}<h1>SleepBank naps</h1>"
            f"<p class=sub>{len(cards)} nap(s) · ours (blue) vs YASA (green)</p>"
            + "".join(cards))
    with open(out, "w") as f:
        f.write(body)
    print(f"Report -> {out}")
    subprocess.run(["open", out])


if __name__ == "__main__":
    main()

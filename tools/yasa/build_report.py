#!/usr/bin/env python3
"""Build an HTML dashboard from staged + merged naps — the validation view.

A top summary card pools the detector-vs-YASA metrics across all naps (onset MAE,
sensitivity/specificity, Cohen's kappa), then one card per nap: the YASA hypnogram,
stage breakdown, and SleepBank's calls vs YASA (onset latency error, sleep/wake
sens/spec + kappa, deep-sleep timing). Metrics come from validate.py so the HTML
and the text report (./validate.py) never drift.
"""
import os
import sys
import glob
import subprocess

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import validate  # noqa: E402
from validate import per_nap_metrics, aggregate, signed_min, dur_min, pct, k2  # noqa: E402

SEARCH_DIRS = validate.SEARCH_DIRS

CSS = """
* { box-sizing: border-box; }
body { font: 15px -apple-system, system-ui, sans-serif; background:#0f1020; color:#e9e9f2; margin:0; padding:24px; }
h1 { font-size:20px; margin:0 0 4px; }
.sub { color:#9a9ab5; margin:0 0 24px; font-size:13px; }
.card { background:#1a1b33; border:1px solid #2a2b48; border-radius:16px; padding:16px 18px; margin-bottom:18px; }
.card h2 { font-size:15px; margin:0 0 10px; color:#c9c9e8; }
.summary { border-color:#3a3b68; background:#191a38; }
img { width:100%; border-radius:10px; background:#fff; }
.grid { display:grid; grid-template-columns:1fr 1fr; gap:8px 24px; margin-top:12px; }
.row { display:flex; justify-content:space-between; border-bottom:1px solid #25264180; padding:4px 0; }
.row .k { color:#9a9ab5; } .row .v { font-variant-numeric:tabular-nums; }
.big { display:flex; gap:28px; flex-wrap:wrap; margin:6px 0 2px; }
.big .stat { } .big .n { font-size:26px; font-weight:650; font-variant-numeric:tabular-nums; }
.big .l { font-size:11px; color:#9a9ab5; }
.ours { color:#8a8aff; } .yasa { color:#5ad18a; }
.tag { font-size:11px; padding:2px 8px; border-radius:999px; background:#2a2b48; color:#c9c9e8; }
.warn { color:#e2c275; font-size:13px; margin-top:8px; }
"""

PAGE_HEAD = f"<!doctype html><meta charset=utf-8><title>SleepBank naps</title><style>{CSS}</style>"


def summary_card(agg):
    o = agg["onset"]
    p = agg["pooled"]
    onset = (f"{o['mean'] / 60:+.1f} ± {o['sd'] / 60:.1f} min" if o else "—")
    onset_mae = (f"{o['mae'] / 60:.1f} min" if o else "—")
    within = (f"{o['within5']}/{o['n']}" if o else "—")
    deep = agg["deep"]
    deep_s = (f"{deep['mean'] / 60:+.1f} ± {deep['sd'] / 60:.1f} min" if deep else "—")
    warn = ("<p class=warn>⚠️ &lt; 3 naps — directional only. YASA is a silver standard "
            "(frontal Muse, not PSG); only the PSG pilot validates.</p>"
            if agg["n_naps"] < 3 else "")
    return f"""
    <div class="card summary">
      <h2>Detector vs YASA — aggregate <span class="tag">{agg['n_naps']} nap(s) · {p['epochs']} epochs</span></h2>
      <div class="big">
        <div class="stat"><div class="n">{pct(p['sens'])}</div><div class="l">Sensitivity (sleep)</div></div>
        <div class="stat"><div class="n">{pct(p['spec'])}</div><div class="l">Specificity (wake)</div></div>
        <div class="stat"><div class="n">{pct(p['acc'])}</div><div class="l">Accuracy</div></div>
        <div class="stat"><div class="n">{k2(p['kappa'])}</div><div class="l">Cohen's κ</div></div>
      </div>
      <div class="grid">
        <div class="row"><span class="k">Onset latency error</span><span class="v">{onset}</span></div>
        <div class="row"><span class="k">Onset MAE · within ±5 min</span><span class="v">{onset_mae} · {within}</span></div>
        <div class="row"><span class="k">Deep (N3) timing error</span><span class="v">{deep_s}</span></div>
        <div class="row"><span class="k">Per-nap mean κ</span><span class="v">{k2(agg['kappa_mean'])}</span></div>
      </div>
      {warn}
    </div>
    """


def build_card(stamp, df, png):
    m = per_nap_metrics(df)
    dur = m["dur_min"]
    counts = df["yasa_stage"].value_counts()
    breakdown = " · ".join(
        f"{s} {counts[s] / len(df) * dur:.0f}m" for s in ["W", "N1", "N2", "N3", "REM"] if s in counts
    )
    img = f'<img src="file://{png}">' if os.path.exists(png) else "<p>(no hypnogram)</p>"
    return f"""
    <div class="card">
      <h2>{stamp} <span class="tag">{dur:.0f} min · {breakdown}</span></h2>
      {img}
      <div class="big">
        <div class="stat"><div class="n">{signed_min(m['onset_err'])}</div><div class="l">onset error vs YASA</div></div>
        <div class="stat"><div class="n">{pct(m['sens'])}</div><div class="l">sensitivity</div></div>
        <div class="stat"><div class="n">{pct(m['spec'])}</div><div class="l">specificity</div></div>
        <div class="stat"><div class="n">{k2(m['kappa'])}</div><div class="l">κ</div></div>
      </div>
      <div class="grid">
        <div class="row"><span class="k">Onset — <span class="ours">ours</span> / <span class="yasa">YASA</span></span><span class="v">{dur_min(m['our_onset'])} / {dur_min(m['yasa_onset'])}</span></div>
        <div class="row"><span class="k">Deep — <span class="ours">ours</span> / <span class="yasa">YASA N3</span></span><span class="v">{dur_min(m['our_deep'])} / {dur_min(m['yasa_deep'])}</span></div>
      </div>
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

    naps, cards = [], []
    for path in files:
        stamp = os.path.basename(path)[len("labeled-"):-len(".csv")]
        png = os.path.join(os.path.dirname(path), f"eeg-{stamp}_hypnogram.png")
        try:
            df = pd.read_csv(path)
            naps.append(per_nap_metrics(df))
            cards.append(build_card(stamp, df, png))
        except Exception as e:
            print(f"  skip {stamp}: {e}")

    agg = aggregate(naps)
    out = os.path.join(os.path.expanduser("~/Downloads"), "report.html")
    body = (f"{PAGE_HEAD}<h1>SleepBank naps</h1>"
            f"<p class=sub>{len(cards)} nap(s) · detector (blue) vs YASA (green)</p>"
            + (summary_card(agg) if agg else "")
            + "".join(cards))
    with open(out, "w") as f:
        f.write(body)
    print(f"Report -> {out}")
    subprocess.run(["open", out])


if __name__ == "__main__":
    main()

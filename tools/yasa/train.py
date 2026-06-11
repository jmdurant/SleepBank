#!/usr/bin/env python3
"""Train SleepBank's on-device models from training.csv → CoreML.

Reads `training.csv` (built by merge_training.py: YASA silver labels joined onto the
app's per-epoch sensor features) and fits a classifier for each target, then exports
a CoreML model that matches `CoreMLOnsetDetector`'s contract exactly:

  NapOnsetClassifier.mlmodel
    inputs:  hr, hrv, movement, stillSeconds, eegOnset, eegDeep   (all Double)
    output:  labelProbability  → {"asleep": p, "awake": 1-p}

Validation is **leave-one-nap-out** (group = nap), so rows from the same nap never
straddle train/test — the only honest way to estimate generalization on n=1 / a few
naps. With <2 naps it reports the in-sample fit and loudly says so.

A second model (NapDeepClassifier, target = N3 approach) is trained as a head-start;
the watch doesn't consume it yet (deep-wake is engine logic today), so it's optional.

Usage:  ./train.py            # finds training.csv in the usual sync folders
        ./train.py <path-to-training.csv>
"""
import os
import sys
import glob

# The features the watch actually feeds the model (CoreMLOnsetDetector.update()).
FEATURES = ["hr", "hrv", "movement", "stillSeconds", "eegOnset", "eegDeep"]

SEARCH_DIRS = [
    os.path.expanduser("~/Library/Mobile Documents/iCloud~com~doctordurant~sleepbank/Documents"),
    os.path.expanduser("~/Downloads"),
    os.path.expanduser("~/Desktop"),
]

# (csv target column, positive label, negative label, output model name)
TARGETS = [
    ("asleep", "asleep", "awake", "NapOnsetClassifier"),
    ("yasa_deep", "deep", "shallow", "NapDeepClassifier"),
]


def find_training_csv():
    if len(sys.argv) > 1:
        return sys.argv[1]
    for d in SEARCH_DIRS:
        p = os.path.join(d, "training.csv")
        if os.path.exists(p):
            return p
    return None


def main():
    try:
        import numpy as np
        import pandas as pd
        from sklearn.ensemble import RandomForestClassifier
        from sklearn.model_selection import LeaveOneGroupOut
        from sklearn.metrics import roc_auc_score, balanced_accuracy_score
    except ImportError as e:
        sys.exit(f"Missing dependency ({e.name}). Run ./setup.sh once.")
    try:
        import coremltools as ct
    except ImportError:
        sys.exit("Missing coremltools. Run ./setup.sh (it now installs it), "
                 "or: .venv/bin/pip install coremltools")

    path = find_training_csv()
    if not path:
        sys.exit("No training.csv found. Take a few naps, run 'Stage Naps.command', then retry.")
    df = pd.read_csv(path)
    outdir = os.path.dirname(path)
    print(f"Loaded {len(df)} epochs from {path}")

    # Match the app's "missing → 0" convention (the Swift passes 0 for absent sensors).
    for f in FEATURES:
        if f not in df.columns:
            print(f"  note: feature '{f}' absent in data → filled with 0")
            df[f] = 0.0
    X = df[FEATURES].fillna(0.0)

    groups = df["nap"] if "nap" in df.columns else pd.Series(["one"] * len(df))
    n_naps = groups.nunique()
    print(f"{n_naps} nap(s) in the training set.\n")

    for target, pos, neg, model_name in TARGETS:
        if target not in df.columns:
            continue
        y = df[target].map({1: pos, 0: neg})
        print(f"=== {model_name}  (target: {target}) ===")
        if y.nunique() < 2:
            print(f"  only one class present ({y.iloc[0]}) — need both to train. Skipping.\n")
            continue
        pos_rate = (df[target] == 1).mean()
        print(f"  class balance: {pos} {pos_rate*100:.0f}% / {neg} {(1-pos_rate)*100:.0f}%")

        clf = RandomForestClassifier(
            n_estimators=200, max_depth=5, min_samples_leaf=10,
            class_weight="balanced", random_state=0)

        # Honest validation: leave-one-nap-out.
        if n_naps >= 2:
            logo = LeaveOneGroupOut()
            aucs, baccs = [], []
            for tr, te in logo.split(X, y, groups):
                if y.iloc[tr].nunique() < 2 or y.iloc[te].nunique() < 2:
                    continue
                clf.fit(X.iloc[tr], y.iloc[tr])
                proba = clf.predict_proba(X.iloc[te])
                pidx = list(clf.classes_).index(pos)
                ytrue = (y.iloc[te] == pos).astype(int)
                aucs.append(roc_auc_score(ytrue, proba[:, pidx]))
                baccs.append(balanced_accuracy_score(y.iloc[te], clf.predict(X.iloc[te])))
            if aucs:
                print(f"  leave-one-nap-out: AUC {np.mean(aucs):.2f} ± {np.std(aucs):.2f}"
                      f", balanced acc {np.mean(baccs):.2f}  (n={len(aucs)} folds)")
            else:
                print("  not enough per-nap class variety for grouped CV — fit only.")
        else:
            print("  ⚠️  ONLY 1 NAP — this is in-sample fit, NOT validation. "
                  "Take ≥3 naps before trusting any number.")

        # Fit on everything, export CoreML.
        clf.fit(X, y)
        try:
            mlmodel = ct.converters.sklearn.convert(
                clf, input_features=FEATURES, output_feature_names="label")
            spec = mlmodel.get_spec()
            prob_name = spec.description.predictedProbabilitiesName or "classProbability"
            if prob_name != "labelProbability":
                ct.utils.rename_feature(spec, prob_name, "labelProbability")
                spec.description.predictedProbabilitiesName = "labelProbability"
            mlmodel = ct.models.MLModel(spec)
            mlmodel.short_description = (
                f"SleepBank {target} classifier — YASA-silver-labeled, "
                f"{n_naps} nap(s), {len(df)} epochs. Validate vs PSG before clinical use.")
            out = os.path.join(outdir, f"{model_name}.mlmodel")
            mlmodel.save(out)
            print(f"  ✅ {os.path.basename(out)}  "
                  f"(labelProbability → '{pos}'/'{neg}')\n")
        except Exception as e:
            print(f"  ⚠️  CoreML export failed: {e}\n")

    print("Done. Drag NapOnsetClassifier.mlmodel into the watch target (Xcode) to enable "
          "the model — CoreMLOnsetDetector picks it up automatically; otherwise the app "
          "keeps using the heuristic.\nReminder: YASA labels are silver (frontal Muse, "
          "not PSG). n=1 calibrates to you; PSG validates.")


if __name__ == "__main__":
    main()

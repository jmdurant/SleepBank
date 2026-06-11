#!/bin/bash
# One-time setup: create a venv and install YASA + deps.
set -e
cd "$(dirname "$0")"
echo "Setting up YASA (one-time, a few minutes)…"
# YASA's classifier (LightGBM) needs the OpenMP runtime (libomp).
if command -v brew >/dev/null 2>&1; then
  brew list libomp >/dev/null 2>&1 || brew install libomp
else
  echo "⚠️  Homebrew not found — if staging fails with a libomp error, install it: brew install libomp"
fi
python3 -m venv .venv
source .venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet numpy pandas matplotlib mne yasa lightgbm scikit-learn coremltools
echo "✅ Done. AirDrop a nap's EEG CSV to your Mac, then double-click 'Stage Latest Nap.command'."

#!/bin/bash
# One-time setup: create a venv and install YASA + deps.
set -e
cd "$(dirname "$0")"
echo "Setting up YASA (one-time, a few minutes)…"
python3 -m venv .venv
source .venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet numpy pandas matplotlib mne yasa lightgbm
echo "✅ Done. AirDrop a nap's EEG CSV to your Mac, then double-click 'Stage Latest Nap.command'."

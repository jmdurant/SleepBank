#!/bin/bash
# Double-click this to stage every new nap's EEG with YASA (batch).
cd "$(dirname "$0")"
if [ ! -d ".venv" ]; then
  echo "First run — installing YASA…"
  bash setup.sh || { echo "Setup failed."; read -p "Press Enter to close."; exit 1; }
fi
source .venv/bin/activate
echo "── Staging EEG with YASA ──"
python3 stage_nap.py "$@"
echo
echo "── Building labeled training set ──"
python3 merge_training.py
echo
read -p "Press Enter to close."

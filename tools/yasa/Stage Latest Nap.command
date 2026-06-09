#!/bin/bash
# Double-click this to stage the most recent nap's EEG with YASA.
cd "$(dirname "$0")"
if [ ! -d ".venv" ]; then
  echo "First run — installing YASA…"
  bash setup.sh || { echo "Setup failed."; read -p "Press Enter to close."; exit 1; }
fi
source .venv/bin/activate
python3 stage_nap.py "$@"
echo
read -p "Press Enter to close."

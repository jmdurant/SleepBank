#!/bin/bash
# Double-click to print the detector-vs-YASA validation report (text) for every
# labeled nap — onset error, sensitivity/specificity, Cohen's kappa, deep timing.
cd "$(dirname "$0")"
if [ ! -d ".venv" ]; then
  echo "First run — installing deps…"
  bash setup.sh || { echo "Setup failed."; read -p "Press Enter to close."; exit 1; }
fi
source .venv/bin/activate
python3 validate.py "$@"
echo
read -p "Press Enter to close."

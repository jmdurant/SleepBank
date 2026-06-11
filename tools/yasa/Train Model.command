#!/bin/bash
# Double-click to train the on-device models from training.csv → CoreML.
cd "$(dirname "$0")"
if [ ! -d ".venv" ]; then
  echo "First run — installing deps…"
  bash setup.sh || { echo "Setup failed."; read -p "Press Enter to close."; exit 1; }
fi
source .venv/bin/activate
echo "── Training models (leave-one-nap-out CV) ──"
python3 train.py "$@"
echo
read -p "Press Enter to close."

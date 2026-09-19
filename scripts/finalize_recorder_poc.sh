#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <recorder-poc-evidence-dir>" >&2
  exit 1
fi

DIR="$1"
python3 tools/summarize_recorder_poc.py "$DIR"

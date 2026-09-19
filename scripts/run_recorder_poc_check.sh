#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <audio-file> [more-audio-files...]" >&2
  exit 1
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="verification/evidence/${STAMP}/recorder-poc"
mkdir -p "$OUT_DIR"

INDEX=1
for file in "$@"; do
  if [ ! -f "$file" ]; then
    echo "Missing file: $file" >&2
    exit 1
  fi
  BASENAME="$(basename "$file")"
  OUT_JSON="$OUT_DIR/${INDEX}-${BASENAME}.json"
  echo "Checking $file -> $OUT_JSON"
  python3 tools/check_recorder_baseline.py "$file" | tee "$OUT_JSON"
  INDEX=$((INDEX + 1))
done

echo
printf 'Recorder PoC evidence written to: %s\n' "$OUT_DIR"

#!/usr/bin/env bash
set -euo pipefail

missing=0

check_cmd() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    printf '[OK] %s: %s\n' "$name" "$(command -v "$name")"
  else
    printf '[MISSING] %s\n' "$name"
    missing=1
  fi
}

check_path() {
  local path="$1"
  if [ -e "$path" ]; then
    printf '[OK] %s\n' "$path"
  else
    printf '[MISSING] %s\n' "$path"
    missing=1
  fi
}

printf '=== Flutter Recorder PoC Preflight ===\n'
check_cmd flutter
check_cmd dart
check_cmd python3
check_cmd ffprobe
check_cmd ffmpeg

printf '\n=== Required repo artifacts ===\n'
check_path docs/implementation/flutter-recorder-poc-task.md
check_path docs/mobile/flutter-recorder-poc-runbook.md
check_path docs/mobile/flutter-recorder-poc-template.md
check_path docs/mobile/flutter-recorder-plugin-comparison.md
check_path tools/check_recorder_baseline.py
check_path scripts/run_recorder_poc_check.sh
check_path NEXT_ACTION.md

printf '\n=== Verdict ===\n'
if [ "$missing" -eq 0 ]; then
  printf 'Environment looks ready to run the Flutter recorder PoC.\n'
  printf 'Next: open NEXT_ACTION.md and execute the recorder PoC workflow.\n'
else
  printf 'Environment is NOT ready yet. Install missing tools or restore missing files before running the PoC.\n'
  exit 1
fi

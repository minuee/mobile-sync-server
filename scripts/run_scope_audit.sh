#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="${1:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT_DIR="$ROOT_DIR/verification/evidence/$STAMP/scope-audit"
TARGETS=(
  "$ROOT_DIR/docs"
  "$ROOT_DIR/src/audio_sync"
  "$ROOT_DIR/tests"
  "$ROOT_DIR/testkit"
  "$ROOT_DIR/tools"
  "$ROOT_DIR/scripts"
)
mkdir -p "$OUT_DIR"

if ! command -v rg >/dev/null 2>&1; then
  echo "rg is required for scope audit" >&2
  exit 1
fi

run_check() {
  local name="$1"
  local pattern="$2"
  local existing_targets=()
  local target
  for target in "${TARGETS[@]}"; do
    if [ -e "$target" ]; then
      existing_targets+=("$target")
    fi
  done
  {
    printf '# pattern: %s\n' "$pattern"
    printf '# targets: %s\n' "${existing_targets[*]}"
    rg -n "$pattern" "${existing_targets[@]}" || true
  } >"$OUT_DIR/$name.log"
}

run_check realtime 'realtime|real-time|streaming|websocket'
run_check speaker 'diarization|speaker id|speaker identification'
run_check video 'video sync|video alignment|ffmpeg.*video'
run_check editor 'waveform|manual edit|trim UI|editor'

printf 'scope audit output written to %s\n' "$OUT_DIR"

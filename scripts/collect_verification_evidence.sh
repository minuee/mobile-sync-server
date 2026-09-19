#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="${1:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT_DIR="$ROOT_DIR/verification/evidence/$STAMP"
PYTHONPATH_PREFIX="$ROOT_DIR/src:$ROOT_DIR"
mkdir -p "$OUT_DIR"
OVERALL_RC=0

log() {
  printf '[collect_verification_evidence] %s\n' "$*"
}

run_and_capture() {
  local name="$1"
  shift
  log "running: $name"
  {
    printf '$ %s\n' "$*"
    "$@"
  } >"$OUT_DIR/$name.log" 2>&1 || {
    echo "FAIL" >"$OUT_DIR/$name.status"
    return 1
  }
  echo "PASS" >"$OUT_DIR/$name.status"
}

capture_check() {
  if ! run_and_capture "$@"; then
    OVERALL_RC=1
  fi
}

log "writing evidence to $OUT_DIR"
printf '%s\n' "$STAMP" >"$OUT_DIR/timestamp.txt"
find "$ROOT_DIR" -maxdepth 2 \( -type d -o -type f \) | sort >"$OUT_DIR/tree.txt"
cp "$ROOT_DIR/.omx/plans/prd-audio-sync-merge-service.md" "$OUT_DIR/prd.md"
cp "$ROOT_DIR/.omx/plans/test-spec-audio-sync-merge-service.md" "$OUT_DIR/test-spec.md"

if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  run_and_capture git-status git -C "$ROOT_DIR" status --short
else
  printf 'SKIP\n' >"$OUT_DIR/git-status.status"
  printf 'Not a git work tree\n' >"$OUT_DIR/git-status.log"
fi

if command -v python3 >/dev/null 2>&1; then
  capture_check python-version python3 --version
  capture_check manifest-example-json python3 -c "import json, pathlib; json.loads(pathlib.Path('$ROOT_DIR/docs/examples/audio-sync-merge-manifest-example.json').read_text())"
  capture_check manifest-contract python3 "$ROOT_DIR/scripts/validate_manifest_contract.py" "$ROOT_DIR/docs/examples/audio-sync-merge-manifest-example.json"
  capture_check manifest-schema-json python3 -c "import json, pathlib; json.loads(pathlib.Path('$ROOT_DIR/docs/schema/audio-sync-merge-manifest.schema.json').read_text())"

  if [ -d "$ROOT_DIR/tests/export" ]; then
    capture_check export-tests env PYTHONPATH="$PYTHONPATH_PREFIX${PYTHONPATH:+:$PYTHONPATH}" python3 -m unittest discover -s "$ROOT_DIR/tests/export" -v
  else
    printf 'SKIP\n' >"$OUT_DIR/export-tests.status"
    printf 'tests/export not present\n' >"$OUT_DIR/export-tests.log"
  fi

  if [ -f "$ROOT_DIR/tests/test_synthetic_corpus.py" ]; then
    capture_check synthetic-tests env PYTHONPATH="$PYTHONPATH_PREFIX${PYTHONPATH:+:$PYTHONPATH}" python3 -m unittest tests.test_synthetic_corpus -v
  else
    printf 'SKIP\n' >"$OUT_DIR/synthetic-tests.status"
    printf 'tests/test_synthetic_corpus.py not present\n' >"$OUT_DIR/synthetic-tests.log"
  fi
else
  printf 'SKIP\n' >"$OUT_DIR/python-version.status"
  printf 'python3 not available\n' >"$OUT_DIR/python-version.log"
  printf 'SKIP\n' >"$OUT_DIR/manifest-example-json.status"
  printf 'python3 not available\n' >"$OUT_DIR/manifest-example-json.log"
  printf 'SKIP\n' >"$OUT_DIR/manifest-contract.status"
  printf 'python3 not available\n' >"$OUT_DIR/manifest-contract.log"
  printf 'SKIP\n' >"$OUT_DIR/manifest-schema-json.status"
  printf 'python3 not available\n' >"$OUT_DIR/manifest-schema-json.log"
  printf 'SKIP\n' >"$OUT_DIR/export-tests.status"
  printf 'python3 not available\n' >"$OUT_DIR/export-tests.log"
  printf 'SKIP\n' >"$OUT_DIR/synthetic-tests.status"
  printf 'python3 not available\n' >"$OUT_DIR/synthetic-tests.log"
fi

capture_check bash-syntax bash -n "$ROOT_DIR/scripts/collect_verification_evidence.sh"
capture_check manifest-validator-syntax python3 -m py_compile "$ROOT_DIR/scripts/validate_manifest_contract.py"
capture_check docs-index find "$ROOT_DIR/docs" -maxdepth 3 -type f

if [ -f "$ROOT_DIR/scripts/run_scope_audit.sh" ]; then
  capture_check scope-audit "$ROOT_DIR/scripts/run_scope_audit.sh" "$STAMP"
else
  printf 'SKIP\n' >"$OUT_DIR/scope-audit.status"
  printf 'scripts/run_scope_audit.sh not present\n' >"$OUT_DIR/scope-audit.log"
fi

log "done"
exit "$OVERALL_RC"

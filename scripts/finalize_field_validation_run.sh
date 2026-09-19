#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "usage: $0 <data_root> <session_id> <evidence_root> <run_id> [reviewer] [ledger_path]" >&2
  exit 1
fi

DATA_ROOT="$1"
SESSION_ID="$2"
EVIDENCE_ROOT="$3"
RUN_ID="$4"
REVIEWER="${5:-operator}"
LEDGER_PATH="${6:-.omx/plans/experiment-ledger-audio-sync-platform.md}"
TODAY="$(date -u +%F)"

python3 scripts/export_session_to_evidence_bundle.py \
  --data-root "$DATA_ROOT" \
  --session-id "$SESSION_ID" \
  --evidence-root "$EVIDENCE_ROOT" \
  --run-type field \
  --reviewer "$REVIEWER"

python3 scripts/append_experiment_ledger.py \
  --bundle "$EVIDENCE_ROOT/bundle.json" \
  --ledger "$LEDGER_PATH" \
  --run-id "$RUN_ID" \
  --date "$TODAY" \
  --key-outcome "field validation run finalized" \
  --notes "auto-appended by finalize_field_validation_run.sh"

printf 'finalized field run into %s and appended ledger\n' "$EVIDENCE_ROOT"

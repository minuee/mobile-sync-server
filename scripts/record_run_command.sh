#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "usage: $0 <evidence_root> <kind> <status> <command...>" >&2
  exit 1
fi

ROOT="$1"
KIND="$2"
STATUS="$3"
shift 3
COMMAND="$*"

mkdir -p "$ROOT"
printf '{"at":"%s","kind":"%s","command":%s,"status":"%s","artifact":null}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$KIND" \
  "$(python3 - <<'PY' "$COMMAND"
import json,sys
print(json.dumps(sys.argv[1]))
PY
)" \
  "$STATUS" >> "$ROOT/commands.ndjson"

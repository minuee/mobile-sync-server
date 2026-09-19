#!/usr/bin/env bash
set -euo pipefail

STAMP="${1:-$(date -u +%Y%m%dT%H%M%SZ)}"
ROOT="verification/evidence/$STAMP"

mkdir -p "$ROOT"/{room,uploads,processing,artifacts,review,metrics}

cp verification/evidence/template-bundle.json "$ROOT/bundle.json"
cp verification/evidence/template-bundle.md "$ROOT/bundle.md"
cp verification/evidence/template-classification.json "$ROOT/classification.json"
cp verification/evidence/template-artifacts-index.json "$ROOT/artifacts-index.json"
cp verification/evidence/template-commands.ndjson "$ROOT/commands.ndjson"
cp apps/recorder-mobile/docs/field-validation-result-template.md "$ROOT/review/field-result-template.md"
cp apps/recorder-mobile/docs/stt-comparison-template.md "$ROOT/review/stt-comparison.md"

printf '%s\n' "$STAMP" > "$ROOT/timestamp.txt"

python3 - <<'PY' "$ROOT" "$STAMP"
import json
import sys
from pathlib import Path
root = Path(sys.argv[1])
stamp = sys.argv[2]

bundle_path = root / 'bundle.json'
bundle = json.loads(bundle_path.read_text())
bundle['bundle_id'] = f'evidence_{stamp}'
bundle['run_type'] = 'field'
bundle['protocol_version'] = 'recording-protocol/v1'
bundle['classification'] = 'degraded'
bundle['classification_reason'] = 'pending operator review for field run'
bundle_path.write_text(json.dumps(bundle, indent=2) + '\n')

classification_path = root / 'classification.json'
classification = json.loads(classification_path.read_text())
classification['classification'] = 'degraded'
classification['classification_reason'] = 'pending operator review for field run'
classification['reviewer'] = 'pending'
classification['decided_at'] = 'pending'
classification_path.write_text(json.dumps(classification, indent=2) + '\n')
PY

cat > "$ROOT/room/README.md" <<'MD'
Store room/session control artifacts here:
- room-created.json
- join-events.ndjson
- start-event.json
- optional ready-state snapshots
MD

cat > "$ROOT/uploads/README.md" <<'MD'
Store upload-side artifacts here:
- one metadata JSON per participant
- upload-summary.json
- optional file inventory with hashes/sizes
MD

cat > "$ROOT/processing/README.md" <<'MD'
Store processing execution artifacts here:
- process.log
- metrics.json
- metrics-summary.md
- optional benchmark or STT output notes
MD

cat > "$ROOT/review/operator-notes.md" <<'MD'
# Operator Notes

- room condition:
- notable overlap moments:
- quiet speaker notes:
- device movement / interruptions:
- operator friction:
MD

printf 'initialized field-validation evidence bundle: %s\n' "$ROOT"

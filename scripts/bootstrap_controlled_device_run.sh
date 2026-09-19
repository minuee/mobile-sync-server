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
cp verification/evidence/template-first-controlled-device-run.md "$ROOT/first-run-packet.md"

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
bundle['run_type'] = 'controlled_device'
bundle['protocol_version'] = 'recording-protocol/v1'
bundle['classification'] = 'baseline-valid'
bundle['classification_reason'] = 'pending operator review'
bundle_path.write_text(json.dumps(bundle, indent=2) + '\n')

classification_path = root / 'classification.json'
classification = json.loads(classification_path.read_text())
classification['classification'] = 'baseline-valid'
classification['classification_reason'] = 'pending operator review'
classification['reviewer'] = 'pending'
classification['decided_at'] = 'pending'
classification_path.write_text(json.dumps(classification, indent=2) + '\n')
PY

cat > "$ROOT/room/README.md" <<'MD'
Store room/session control artifacts here:
- room-created.json
- join-events.ndjson
- ready-snapshots.json
- start-event.json
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
- optional benchmark outputs
MD

cat > "$ROOT/review/README.md" <<'MD'
Store review/operator artifacts here:
- listening-review.md
- stt-comparison.md
- operator-notes.md
MD

printf 'initialized controlled-device evidence bundle: %s\n' "$ROOT"

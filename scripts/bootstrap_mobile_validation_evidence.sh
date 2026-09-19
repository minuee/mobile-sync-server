#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <run-id>" >&2
  exit 1
fi

RUN_ID="$1"
ROOT="verification/evidence/mobile/${RUN_ID}"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "${ROOT}"/{analyze,test,mock-baseline,mock-degraded,mock-rejected,runtime-dev,runtime-device,notes}

python3 - "$RUN_ID" "$ROOT" "$GENERATED_AT" <<'PY'
from pathlib import Path
import sys
run_id = sys.argv[1]
root = Path(sys.argv[2])
generated_at = sys.argv[3]
index_template = Path('verification/evidence/mobile-index-template.md').read_text()
index_template = index_template.replace('`<timestamp>`', f'`{run_id}`', 1)
index_template = index_template.replace('`<generated-at>`', f'`{generated_at}`', 1)
(root / 'index.md').write_text(index_template)
PY

cp verification/evidence/mobile-checks-template.md "${ROOT}/CHECKS.md"
cp apps/recorder-mobile/docs/flutter-validation-screenshot-checklist.md "${ROOT}/screenshot-checklist.md"
cp verification/evidence/mobile-index-example.md "${ROOT}/index-example.md"

cat > "${ROOT}/analyze/flutter-analyze.txt" <<'TXT'
# Paste `flutter analyze` output here.
TXT

cat > "${ROOT}/test/flutter-test.txt" <<'TXT'
# Paste `flutter test` output here.
TXT

cat > "${ROOT}/analyze/README.md" <<'MD'
# Analyze Output

- [ ] Save `flutter analyze` output here
- Suggested file: `flutter-analyze.txt`
- Done when: analyzer output is captured without truncation
MD

cat > "${ROOT}/test/README.md" <<'MD'
# Test Output

- [ ] Save `flutter test` output here
- Suggested file: `flutter-test.txt`
- Done when: test summary and failures/passes are visible in the saved output
MD

cat > "${ROOT}/mock-baseline/README.md" <<'MD'
# Mock Baseline Captures

- [ ] development-context-baseline.png
- [ ] recommended-focus-baseline.png
- [ ] outcome-summary-baseline.png
- [ ] telemetry-summary-baseline.png
- [ ] debug-log-baseline.png
- Done when: baseline flow can be visually reviewed end-to-end without missing key cards
MD

cat > "${ROOT}/mock-degraded/README.md" <<'MD'
# Mock Degraded Captures

- [ ] outcome-summary-degraded.png
- [ ] recovery-actions-degraded.png
- [ ] debug-log-degraded.png
- Done when: degraded cues and rule-specific shortcuts are visible in saved captures
MD

cat > "${ROOT}/mock-rejected/README.md" <<'MD'
# Mock Rejected Captures

- [ ] outcome-summary-rejected.png
- [ ] recovery-actions-rejected.png
- [ ] debug-log-failures.png
- Done when: rejected/failure-debug path is visually evident in the saved captures
MD

cat > "${ROOT}/runtime-dev/README.md" <<'MD'
# Runtime-dev Captures

- [ ] development-context-backend-on.png
- [ ] debug-tools-upload-events.png
- [ ] telemetry-summary-events.png
- [ ] recovery-runtime-dev.png
- Done when: backend-connected path and event upload affordances are visible
MD

cat > "${ROOT}/runtime-device/README.md" <<'MD'
# Runtime-device Captures

- [ ] development-context-device.png
- [ ] debug-tools-bridge-smoke.png
- [ ] outcome-or-recovery-device.png
- Done when: one real device capture attempt is documented with outcome or recovery state
MD

cat > "${ROOT}/notes/run-metadata.md" <<MD
# Run Metadata

- Generated at (UTC): ${GENERATED_AT}
- Validator: <name>
- Machine: <host/os>
- Flutter version: <flutter --version>
- Bootstrap mode(s): <mock|runtime-dev|runtime-device>
- Notes: <optional>
MD

cat > "${ROOT}/notes/layout-issues.md" <<'MD'
# Layout Issues

## Screens checked
- <screen 1>
- <screen 2>

## Findings
- <none recorded yet>

## Follow-up
- <optional>
MD

cat > "${ROOT}/notes/button-state-mismatches.md" <<'MD'
# Button State Mismatches

## Buttons checked
- <button 1>
- <button 2>

## Findings
- <none recorded yet>

## Follow-up
- <optional>
MD

cat > "${ROOT}/notes/runtime-device-findings.md" <<'MD'
# Runtime Device Findings

## Device
- <device model / os>

## Bridge checks
- <prepare/start/stop result>

## Findings
- <not run yet>

## Follow-up
- <optional>
MD

OPEN_ITEMS=$(python3 - <<'PY'
from pathlib import Path
text = Path('verification/evidence/mobile-checks-template.md').read_text().splitlines()
count = sum(1 for line in text if line.lstrip().startswith('- [ ]'))
print(count)
PY
)

cat > "${ROOT}/README.md" <<README
# Mobile Validation Evidence Root

Run ID: ${RUN_ID}
Generated at (UTC): ${GENERATED_AT}
Open checklist items: ${OPEN_ITEMS}
Last status refresh (UTC): ${GENERATED_AT}
## Index placeholder status
- Metadata: 3
- Commands: 1
- Pass / Fail Summary: 5
- Evidence Links: 5
- Key Findings: 3
- UI / State Mismatch Notes: 1
- Follow-up Actions: 2

## Seed files
- [x] index.md
- [x] index-example.md
- [x] screenshot-checklist.md
- [x] CHECKS.md
- [x] analyze/flutter-analyze.txt
- [x] test/flutter-test.txt
- [x] analyze/README.md
- [x] test/README.md
- [x] mock-baseline/README.md
- [x] mock-degraded/README.md
- [x] mock-rejected/README.md
- [x] runtime-dev/README.md
- [x] runtime-device/README.md
- [x] notes/run-metadata.md
- [x] notes/layout-issues.md
- [x] notes/button-state-mismatches.md
- [x] notes/runtime-device-findings.md

## Validation progress checklist
- [ ] Metadata consistency checked in CHECKS.md
- [ ] Analyze / test outputs saved in analyze/ and test/
- [ ] Screenshot checklist reviewed and captures stored in the correct subdirectories
- [ ] Notes updated in notes/
- [ ] Finalization items completed in index.md

## Metadata references
- CHECKS.md
- notes/run-metadata.md
- index.md

## Subdirectories
- analyze/
- test/
- mock-baseline/
- mock-degraded/
- mock-rejected/
- runtime-dev/
- runtime-device/
- notes/

## Quick commands
```bash
bash scripts/sync_mobile_validation_metadata.sh ${ROOT}
# save flutter outputs into:
#   ${ROOT}/analyze/flutter-analyze.txt
#   ${ROOT}/test/flutter-test.txt
bash scripts/update_mobile_validation_status.sh ${ROOT}
```
README

bash scripts/update_mobile_validation_status.sh "${ROOT}" >/dev/null
echo "created ${ROOT}"

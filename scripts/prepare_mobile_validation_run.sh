#!/usr/bin/env bash
set -euo pipefail

RUN_ID="${1:-$(date -u +%Y%m%dT%H%M%SZ)}"
ROOT="verification/evidence/mobile/${RUN_ID}"

bash scripts/bootstrap_mobile_validation_evidence.sh "${RUN_ID}"

echo
cat <<MSG
Prepared mobile validation root: ${ROOT}

Next steps:
1. Edit ${ROOT}/notes/run-metadata.md
2. Run: bash scripts/sync_mobile_validation_metadata.sh ${ROOT}
3. Run Flutter commands and save outputs into:
   - ${ROOT}/analyze/flutter-analyze.txt
   - ${ROOT}/test/flutter-test.txt
4. Capture screenshots per:
   - ${ROOT}/screenshot-checklist.md
5. Refresh status:
   - bash scripts/update_mobile_validation_status.sh ${ROOT}
MSG

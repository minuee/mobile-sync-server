#!/usr/bin/env bash
set -euo pipefail

echo 'Step 1: Run the preflight check'
echo
echo '  scripts/check_flutter_poc_prereqs.sh'
echo
scripts/check_flutter_poc_prereqs.sh || {
  echo
  echo 'Preflight failed. Install missing prerequisites first, then rerun this script.'
  exit 1
}

echo
echo 'Preflight passed. Next follow:'
echo '  docs/mobile/flutter-recorder-poc-runbook.md'
echo

#!/usr/bin/env bash
set -euo pipefail

echo '=== Flutter Run-Ready Checks ==='

echo
echo '[1/4] mobile scaffold check'
python3 tools/check_mobile_scaffold.py

echo
echo '[2/4] mobile contract check'
python3 tools/check_mobile_contracts.py

echo
echo '[3/4] mobile mock-flow check'
python3 tools/check_mobile_mock_flow.py

echo
echo '[4/4] Flutter/SDK preflight'
./run_flutter_poc_first_step.sh

echo
echo 'All run-ready checks passed.'
echo 'Next: follow docs/mobile/flutter-run-ready-checklist.md'

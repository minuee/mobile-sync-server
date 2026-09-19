#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <mobile-evidence-root>" >&2
  exit 1
fi

ROOT="$1"
METADATA_FILE="${ROOT}/notes/run-metadata.md"
INDEX_FILE="${ROOT}/index.md"

if [[ ! -f "${METADATA_FILE}" ]]; then
  echo "missing ${METADATA_FILE}" >&2
  exit 1
fi
if [[ ! -f "${INDEX_FILE}" ]]; then
  echo "missing ${INDEX_FILE}" >&2
  exit 1
fi

python3 - <<'PY' "${METADATA_FILE}" "${INDEX_FILE}"
from pathlib import Path
import sys
import re
metadata_path = Path(sys.argv[1])
index_path = Path(sys.argv[2])
meta = metadata_path.read_text().splitlines()
index = index_path.read_text()

patterns = {
    'Validator': r'^- Validator: (.*)$',
    'Machine': r'^- Machine: (.*)$',
    'Flutter version': r'^- Flutter version: (.*)$',
    'Bootstrap mode(s)': r'^- Bootstrap mode\(s\): (.*)$',
}
values = {}
for line in meta:
    for key, pat in patterns.items():
        m = re.match(pat, line.strip())
        if m:
            values[key] = m.group(1).strip()

replacements = {
    '<name>': values.get('Validator'),
    '<host/os>': values.get('Machine'),
    '<flutter --version>': values.get('Flutter version'),
    '<mock|runtime-dev|runtime-device>': values.get('Bootstrap mode(s)'),
}

for placeholder, value in replacements.items():
    if value and value != placeholder:
        index = index.replace(f'`{placeholder}`', f'`{value}`', 1)

index_path.write_text(index)
print('synced metadata into index.md')
PY

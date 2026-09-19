#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <mobile-evidence-root>" >&2
  exit 1
fi

ROOT="$1"
CHECKS_FILE="${ROOT}/CHECKS.md"
README_FILE="${ROOT}/README.md"
INDEX_FILE="${ROOT}/index.md"
METADATA_FILE="${ROOT}/notes/run-metadata.md"
REFRESHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

for file in "${CHECKS_FILE}" "${README_FILE}" "${INDEX_FILE}" "${METADATA_FILE}"; do
  if [[ ! -f "${file}" ]]; then
    echo "missing ${file}" >&2
    exit 1
  fi
done

OPEN_ITEMS=$(python3 - <<'PY' "${CHECKS_FILE}"
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text().splitlines()
print(sum(1 for line in text if line.lstrip().startswith('- [ ]')))
PY
)

SECTION_LINES=$(python3 - <<'PY' "${INDEX_FILE}"
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text().splitlines()
markers = ['<name>', '<host/os>', '<flutter --version>', '<list>', '<pass|fail>', '<pass|fail|not-run>', '<paths>', '<finding 1>', '<finding 2>', '<finding 3>', '<optional>', '<action 1>', '<action 2>']
section = 'Metadata'
counts = {section: 0}
for line in text:
    if line.startswith('## '):
        section = line[3:].strip()
        counts.setdefault(section, 0)
        continue
    counts[section] += sum(line.count(marker) for marker in markers)
order = ['Metadata', 'Commands', 'Pass / Fail Summary', 'Evidence Links', 'Key Findings', 'UI / State Mismatch Notes', 'Follow-up Actions']
for key in order:
    print(f'- {key}: {counts.get(key, 0)}')
PY
)

DERIVED_FLAGS=$(python3 - <<'PY' "${ROOT}" "${INDEX_FILE}" "${METADATA_FILE}"
from pathlib import Path
import sys
import re
root = Path(sys.argv[1])
index_text = Path(sys.argv[2]).read_text()
metadata_text = Path(sys.argv[3]).read_text()
run_id = root.name

def file_has_real_content(path_str, placeholder_prefix):
    path = root / path_str
    if not path.exists():
        return False
    content = path.read_text().strip()
    return bool(content) and placeholder_prefix not in content

def count_pngs(dir_name):
    base = root / dir_name
    if not base.exists():
        return 0
    return sum(1 for p in base.rglob('*.png'))

def note_touched(path_str, placeholders):
    path = root / path_str
    if not path.exists():
        return False
    text = path.read_text()
    return all(ph not in text for ph in placeholders)

def extract_md_value(text, label):
    m = re.search(rf"- {re.escape(label)}: `(.*?)`", text)
    return m.group(1) if m else None

def extract_note_value(text, label):
    m = re.search(rf"- {re.escape(label)}: (.*)", text)
    return m.group(1).strip() if m else None

metadata_placeholders_cleared = all(token not in index_text for token in ['<name>', '<host/os>', '<flutter --version>', '<mock|runtime-dev|runtime-device>'])
index_run_id = extract_md_value(index_text, 'Run ID')
index_generated = extract_md_value(index_text, 'Generated at (UTC)')
index_validator = extract_md_value(index_text, 'Validator')
index_machine = extract_md_value(index_text, 'Machine')
index_flutter = extract_md_value(index_text, 'Flutter version')
index_modes = extract_md_value(index_text, 'Bootstrap mode(s)')
note_generated = extract_note_value(metadata_text, 'Generated at (UTC)')
note_validator = extract_note_value(metadata_text, 'Validator')
note_machine = extract_note_value(metadata_text, 'Machine')
note_flutter = extract_note_value(metadata_text, 'Flutter version')
note_modes = extract_note_value(metadata_text, 'Bootstrap mode(s)')
metadata_synced = all([
    index_run_id == run_id,
    index_generated == note_generated,
    index_validator == note_validator and note_validator != '<name>',
    index_machine == note_machine and note_machine != '<host/os>',
    index_flutter == note_flutter and note_flutter != '<flutter --version>',
    index_modes == note_modes and note_modes != '<mock|runtime-dev|runtime-device>',
])
analyze_saved = file_has_real_content('analyze/flutter-analyze.txt', 'Paste `flutter analyze` output here.')
test_saved = file_has_real_content('test/flutter-test.txt', 'Paste `flutter test` output here.')
screenshot_count = sum(count_pngs(name) for name in ['mock-baseline', 'mock-degraded', 'mock-rejected', 'runtime-dev', 'runtime-device'])
notes_updated = sum([
    note_touched('notes/layout-issues.md', ['<none recorded yet>', '<screen 1>', '<screen 2>']),
    note_touched('notes/button-state-mismatches.md', ['<none recorded yet>', '<button 1>', '<button 2>']),
    note_touched('notes/runtime-device-findings.md', ['<not run yet>', '<device model / os>', '<prepare/start/stop result>']),
])
finalization_complete = all(token not in index_text for token in ['<pass|fail>', '<pass|fail|not-run>', '<paths>', '<finding 1>', '<finding 2>', '<finding 3>', '<optional>', '<action 1>', '<action 2>'])
print(f"METADATA_PLACEHOLDERS_CLEARED={'true' if metadata_placeholders_cleared else 'false'}")
print(f"METADATA_SYNCED={'true' if metadata_synced else 'false'}")
print(f"ANALYZE_SAVED={'true' if analyze_saved else 'false'}")
print(f"TEST_SAVED={'true' if test_saved else 'false'}")
print(f"SCREENSHOT_COUNT={screenshot_count}")
print(f"NOTES_UPDATED={notes_updated}")
print(f"FINALIZATION_COMPLETE={'true' if finalization_complete else 'false'}")
PY
)

eval "$DERIVED_FLAGS"

DERIVED_STATUS=$(cat <<EOF2
- metadata placeholders cleared: ${METADATA_PLACEHOLDERS_CLEARED}
- metadata synced with run-metadata: ${METADATA_SYNCED}
- analyze saved: ${ANALYZE_SAVED}
- test saved: ${TEST_SAVED}
- screenshots captured: ${SCREENSHOT_COUNT}
- notes updated: ${NOTES_UPDATED}/3
- finalization complete: ${FINALIZATION_COMPLETE}
EOF2
)

PROGRESS_LINES=$(python3 - <<'PY' "$METADATA_SYNCED" "$ANALYZE_SAVED" "$TEST_SAVED" "$SCREENSHOT_COUNT" "$NOTES_UPDATED" "$FINALIZATION_COMPLETE"
import sys
metadata_synced = sys.argv[1] == 'true'
analyze_saved = sys.argv[2] == 'true'
test_saved = sys.argv[3] == 'true'
screenshot_count = int(sys.argv[4])
notes_updated = int(sys.argv[5])
finalization_complete = sys.argv[6] == 'true'
items = [
    ('Metadata consistency checked in CHECKS.md', metadata_synced),
    ('Analyze / test outputs saved in analyze/ and test/', analyze_saved and test_saved),
    ('Screenshot checklist reviewed and captures stored in the correct subdirectories', screenshot_count > 0),
    ('Notes updated in notes/', notes_updated >= 1),
    ('Finalization items completed in index.md', finalization_complete),
]
for label, done in items:
    mark = 'x' if done else ' '
    print(f'- [{mark}] {label}')
PY
)

python3 - <<'PY' "${README_FILE}" "${OPEN_ITEMS}" "${REFRESHED_AT}" "${SECTION_LINES}" "${DERIVED_STATUS}" "${PROGRESS_LINES}"
from pathlib import Path
import re
import sys
readme = Path(sys.argv[1])
count = sys.argv[2]
refreshed = sys.argv[3]
section_lines = sys.argv[4].splitlines()
derived_lines = sys.argv[5].splitlines()
progress_lines = sys.argv[6].splitlines()
text = readme.read_text()
text, n1 = re.subn(r'Open checklist items: \d+', f'Open checklist items: {count}', text, count=1)
if n1 != 1:
    raise SystemExit('could not update checklist count in README')
if 'Last status refresh (UTC):' in text:
    text, n2 = re.subn(r'Last status refresh \(UTC\): .*', f'Last status refresh (UTC): {refreshed}', text, count=1)
    if n2 != 1:
        raise SystemExit('could not update refresh time in README')
else:
    text = text.replace(f'Open checklist items: {count}', f'Open checklist items: {count}\nLast status refresh (UTC): {refreshed}', 1)
section_block = '## Index placeholder status\n' + '\n'.join(section_lines)
if '## Index placeholder status' in text:
    text = re.sub(r'## Index placeholder status\n(?:- .*\n)+', section_block + '\n', text, count=1)
else:
    anchor = f'Last status refresh (UTC): {refreshed}'
    text = text.replace(anchor, anchor + '\n' + section_block, 1)
derived_block = '## Derived status\n' + '\n'.join(derived_lines)
if '## Derived status' in text:
    text = re.sub(r'## Derived status\n(?:- .*\n)+', derived_block + '\n', text, count=1)
else:
    text = text.replace(section_block + '\n', section_block + '\n' + derived_block + '\n', 1)
progress_block = '## Validation progress checklist\n' + '\n'.join(progress_lines)
if '## Validation progress checklist' in text:
    text = re.sub(r'## Validation progress checklist\n(?:- \[[ x]\] .*\n)+', progress_block + '\n', text, count=1)
else:
    text = text.replace('## Seed files', progress_block + '\n\n## Seed files', 1)
readme.write_text(text)
PY

echo "updated ${README_FILE} (open checklist items: ${OPEN_ITEMS})"

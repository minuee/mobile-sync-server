#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <mobile-evidence-root>" >&2
  exit 1
fi

ROOT="$1"
README_FILE="${ROOT}/README.md"
INDEX_FILE="${ROOT}/index.md"
CHECKS_FILE="${ROOT}/CHECKS.md"
SCREENSHOT_CHECKLIST_FILE="${ROOT}/screenshot-checklist.md"
METADATA_FILE="${ROOT}/notes/run-metadata.md"

for file in "${README_FILE}" "${INDEX_FILE}" "${CHECKS_FILE}" "${SCREENSHOT_CHECKLIST_FILE}" "${METADATA_FILE}"; do
  if [[ ! -f "${file}" ]]; then
    echo "missing ${file}" >&2
    exit 1
  fi
done

python3 - <<'PY' "${README_FILE}" "${ROOT}" "${SCREENSHOT_CHECKLIST_FILE}" "${CHECKS_FILE}" "${INDEX_FILE}" "${METADATA_FILE}"
from pathlib import Path
import sys
import re
readme_lines = Path(sys.argv[1]).read_text().splitlines()
root = Path(sys.argv[2])
screenshot_checklist = Path(sys.argv[3]).read_text().splitlines()
checks_lines = Path(sys.argv[4]).read_text().splitlines()
index_text = Path(sys.argv[5]).read_text()
metadata_text = Path(sys.argv[6]).read_text()

keys = [
    'Run ID:',
    'Generated at (UTC):',
    'Open checklist items:',
    'Last status refresh (UTC):',
]
for line in readme_lines:
    if any(line.startswith(key) for key in keys):
        print(line)
print('')
for header in ['## Index placeholder status', '## Derived status', '## Validation progress checklist']:
    inside = False
    for line in readme_lines:
        if line.startswith(header):
            inside = True
            print(line)
            continue
        if inside:
            if line.startswith('## '):
                break
            if line.strip():
                print(line)
    print('')

s_total = sum(1 for line in screenshot_checklist if line.lstrip().startswith('- [ ]') or line.lstrip().startswith('- [x]'))
s_done = sum(1 for line in screenshot_checklist if line.lstrip().startswith('- [x]'))
pending_screens = [line.strip()[6:] for line in screenshot_checklist if line.lstrip().startswith('- [ ]')]
print('## Screenshot checklist status')
print(f'- completed: {s_done}/{s_total}')
if pending_screens:
    print('- pending examples:')
    for item in pending_screens[:5]:
        print(f'  - {item}')
print('')

subdirs = ['analyze', 'test', 'mock-baseline', 'mock-degraded', 'mock-rejected', 'runtime-dev', 'runtime-device']
print('## Subdirectory file snapshot')
for name in subdirs:
    base = root / name
    files = sorted(p.name for p in base.iterdir() if p.is_file()) if base.exists() else []
    pngs = sorted(p.name for p in base.glob('*.png')) if base.exists() else []
    readme = base / 'README.md'
    checklist_total = 0
    checklist_done = 0
    if readme.exists():
        lines = readme.read_text().splitlines()
        checklist_total = sum(1 for line in lines if line.lstrip().startswith('- [ ]') or line.lstrip().startswith('- [x]'))
        checklist_done = sum(1 for line in lines if line.lstrip().startswith('- [x]'))
    print(f'- {name}: files={len(files)} screenshots={len(pngs)} checklist={checklist_done}/{checklist_total}')
print('')

notes = root / 'notes'
notes_status = {}
if notes.exists():
    note_files = sorted(p.name for p in notes.iterdir() if p.is_file())
    print('## Notes files')
    for name in note_files:
        print(f'- {name}')
    print('')
    print('## Notes content status')
    placeholders = {
        'layout-issues.md': ['<none recorded yet>', '<screen 1>', '<screen 2>'],
        'button-state-mismatches.md': ['<none recorded yet>', '<button 1>', '<button 2>'],
        'runtime-device-findings.md': ['<not run yet>', '<device model / os>', '<prepare/start/stop result>'],
        'run-metadata.md': ['<name>', '<host/os>', '<flutter --version>', '<mock|runtime-dev|runtime-device>', '<optional>'],
    }
    for name in note_files:
        path = notes / name
        text = path.read_text()
        if name in placeholders:
            complete = all(ph not in text for ph in placeholders[name])
            status = 'complete' if complete else 'placeholder-remaining'
            notes_status[name] = status
            print(f'- {name}: {status}')
        else:
            notes_status[name] = 'tracked'
            print(f'- {name}: tracked')
    print('')

def extract_md_value(text, label):
    m = re.search(rf"- {re.escape(label)}: `(.*?)`", text)
    return m.group(1) if m else None

def extract_note_value(text, label):
    m = re.search(rf"- {re.escape(label)}: (.*)", text)
    return m.group(1).strip() if m else None

run_id = root.name
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
metadata_placeholders_cleared = all(token not in index_text for token in ['<name>', '<host/os>', '<flutter --version>', '<mock|runtime-dev|runtime-device>'])
metadata_synced = all([
    index_run_id == run_id,
    index_generated == note_generated,
    index_validator == note_validator and note_validator != '<name>',
    index_machine == note_machine and note_machine != '<host/os>',
    index_flutter == note_flutter and note_flutter != '<flutter --version>',
    index_modes == note_modes and note_modes != '<mock|runtime-dev|runtime-device>',
])
remaining_index = index_text.count('<pass|fail>') + index_text.count('<pass|fail|not-run>') + index_text.count('<paths>') + index_text.count('<finding 1>') + index_text.count('<finding 2>') + index_text.count('<finding 3>') + index_text.count('<optional>') + index_text.count('<action 1>') + index_text.count('<action 2>')

print('## Top blockers')
blockers = []
if not metadata_placeholders_cleared:
    blockers.append('metadata placeholders still remain in index.md')
if not metadata_synced:
    blockers.append('index.md and notes/run-metadata.md are not fully synchronized')
unchecked_checks = [line.strip()[6:] for line in checks_lines if line.lstrip().startswith('- [ ]')]
for item in unchecked_checks[:3]:
    blockers.append(item)
if s_done < s_total:
    blockers.append(f'screenshot checklist incomplete ({s_done}/{s_total})')
    for item in pending_screens[:3]:
        blockers.append(f'missing screenshot: {item}')
for name, status in notes_status.items():
    if status == 'placeholder-remaining':
        blockers.append(f'note incomplete: {name}')
if remaining_index:
    blockers.append(f'index placeholders remaining: {remaining_index}')
seen = set()
for blocker in blockers:
    if blocker not in seen:
        print(f'- {blocker}')
        seen.add(blocker)
if not blockers:
    print('- none')
PY

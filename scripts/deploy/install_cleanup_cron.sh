#!/usr/bin/env bash
# install_cleanup_cron.sh — install the host-side recog cleanup timer on 192.168.0.146.
#
# Target layout:
#   /opt/recog/bin/cleanup.py                (from repo: scripts/cleanup.py)
#   /opt/recog/etc/cleanup.env               (from repo: scripts/deploy/cleanup.env.example — edited)
#   /etc/systemd/system/recog-cleanup.service
#   /etc/systemd/system/recog-cleanup.timer
#   /etc/logrotate.d/recog
#
# Run ON the host:
#   sudo ./install_cleanup_cron.sh
#
# Assumes the repo is cloned somewhere (script resolves its own location).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OPT_BIN="/opt/recog/bin"
OPT_ETC="/opt/recog/etc"
UNIT_DIR="/etc/systemd/system"
LOGROTATE_DIR="/etc/logrotate.d"

log() { printf '[install-cron] %s\n' "$*"; }
fail() { printf '[install-cron][FAIL] %s\n' "$*" >&2; exit 1; }

if [[ $EUID -ne 0 ]]; then
  fail "must run as root (sudo)"
fi

command -v systemctl >/dev/null 2>&1 || fail "systemd not available"
command -v python3 >/dev/null 2>&1 || fail "python3 not on PATH"

log "1) install cleanup.py -> ${OPT_BIN}/cleanup.py"
install -d -m 0755 "${OPT_BIN}"
install -m 0755 "${REPO_ROOT}/scripts/cleanup.py" "${OPT_BIN}/cleanup.py"

log "2) ensure EnvironmentFile ${OPT_ETC}/cleanup.env exists"
install -d -m 0755 "${OPT_ETC}"
if [[ ! -f "${OPT_ETC}/cleanup.env" ]]; then
  install -m 0644 "${REPO_ROOT}/scripts/deploy/cleanup.env.example" "${OPT_ETC}/cleanup.env"
  log "   created from example — EDIT ${OPT_ETC}/cleanup.env to set RUNTIME_DIR before the first run"
else
  log "   kept existing ${OPT_ETC}/cleanup.env"
fi

# Fail-fast sanity: ensure RUNTIME_DIR is present in the env file.
if ! grep -q '^RUNTIME_DIR=' "${OPT_ETC}/cleanup.env"; then
  fail "${OPT_ETC}/cleanup.env is missing RUNTIME_DIR=<path>"
fi

log "3) install systemd service + timer"
install -m 0644 "${REPO_ROOT}/scripts/deploy/recog-cleanup.service" "${UNIT_DIR}/recog-cleanup.service"
install -m 0644 "${REPO_ROOT}/scripts/deploy/recog-cleanup.timer"   "${UNIT_DIR}/recog-cleanup.timer"

log "4) install logrotate rule"
install -m 0644 "${REPO_ROOT}/scripts/deploy/logrotate-recog.conf" "${LOGROTATE_DIR}/recog"

log "5) reload systemd and enable timer"
systemctl daemon-reload
systemctl enable --now recog-cleanup.timer

log "6) verify timer is active"
if ! systemctl is-active --quiet recog-cleanup.timer; then
  systemctl status --no-pager recog-cleanup.timer || true
  fail "recog-cleanup.timer did not activate"
fi

log "ALL DONE. Next scheduled run:"
systemctl list-timers --no-pager recog-cleanup.timer || true
log "Trigger a manual reconciliation with:"
log "  sudo systemctl start recog-cleanup.service && journalctl -u recog-cleanup.service -n 20 --no-pager"

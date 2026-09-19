#!/usr/bin/env bash
# install_on_host.sh — deploy recog WSGI service on 192.168.0.146
#
# Run THIS script ON the target host (192.168.0.146) after SSH'ing in.
# Executes RALPLAN steps T1-2 through T1-9 in one shot.
#
# Usage (from target host):
#   sudo ./install_on_host.sh
#
# Prerequisites (T1-1, user-gated):
#   - SSH access to 192.168.0.146 with sudo
#   - Repository cloned to /opt/recog (adjust DEPLOY_ROOT below if different)

set -euo pipefail

DEPLOY_ROOT="${DEPLOY_ROOT:-/opt/recog}"
RUNTIME_DIR="${RUNTIME_DIR:-/var/lib/recog/runtime}"
LOG_DIR="${LOG_DIR:-/var/log/recog}"
SERVICE_USER="${SERVICE_USER:-recog}"
RECOG_PORT="${RECOG_PORT:-8080}"
LAN_CIDR="${LAN_CIDR:-192.168.0.0/24}"

log() { printf '[install] %s\n' "$*"; }
fail() { printf '[install][FAIL] %s\n' "$*" >&2; exit 1; }

log "T1-2: verify Python 3.9+, ffmpeg, ffprobe"
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' \
  || fail "Python 3.9+ required"
command -v ffmpeg >/dev/null 2>&1 || fail "ffmpeg not on PATH"
command -v ffprobe >/dev/null 2>&1 || fail "ffprobe not on PATH"

log "T1-3: verify repo at ${DEPLOY_ROOT}"
[[ -f "${DEPLOY_ROOT}/src/recog/api.py" ]] \
  || fail "${DEPLOY_ROOT}/src/recog/api.py not found. Clone/sync the repo first."

log "T1-4: confirm api.py supports RECOG_HOST env var"
grep -q "_resolve_bind" "${DEPLOY_ROOT}/src/recog/api.py" \
  || fail "api.py does not have _resolve_bind helper (pre-T1-4 version); update repo."

log "T1-5: confirm /health endpoint in api.py"
grep -q 'path == "/health"' "${DEPLOY_ROOT}/src/recog/api.py" \
  || fail "api.py does not have /health endpoint (pre-T1-5 version); update repo."

log "T1-6: install systemd unit"
install -m 0644 "${DEPLOY_ROOT}/scripts/deploy/recog.service" /etc/systemd/system/recog.service
# Substitute User if SERVICE_USER is not 'recog'
if [[ "${SERVICE_USER}" != "recog" ]]; then
  sed -i "s/^User=recog$/User=${SERVICE_USER}/" /etc/systemd/system/recog.service
fi
# Substitute WorkingDirectory / PYTHONPATH if DEPLOY_ROOT differs
if [[ "${DEPLOY_ROOT}" != "/opt/recog" ]]; then
  sed -i "s|WorkingDirectory=/opt/recog|WorkingDirectory=${DEPLOY_ROOT}|" /etc/systemd/system/recog.service
  sed -i "s|PYTHONPATH=/opt/recog/src|PYTHONPATH=${DEPLOY_ROOT}/src|" /etc/systemd/system/recog.service
fi
# Substitute runtime dir if RUNTIME_DIR differs
if [[ "${RUNTIME_DIR}" != "/var/lib/recog/runtime" ]]; then
  sed -i "s|/var/lib/recog/runtime|${RUNTIME_DIR}|g" /etc/systemd/system/recog.service
fi
# Substitute port if RECOG_PORT differs
if [[ "${RECOG_PORT}" != "8080" ]]; then
  sed -i "s/RECOG_PORT=8080/RECOG_PORT=${RECOG_PORT}/" /etc/systemd/system/recog.service
fi

log "T1-7: prepare runtime + log directories"
mkdir -p "${RUNTIME_DIR}" "${LOG_DIR}"
if id "${SERVICE_USER}" >/dev/null 2>&1; then
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "${RUNTIME_DIR}" "${LOG_DIR}" "${DEPLOY_ROOT}"
else
  log "SERVICE_USER=${SERVICE_USER} not found; skipping chown (adjust manually)"
fi

log "T1-8: open firewall port ${RECOG_PORT} to ${LAN_CIDR}"
if command -v ufw >/dev/null 2>&1; then
  ufw allow from "${LAN_CIDR}" to any port "${RECOG_PORT}" || true
  log "  (ufw rule added)"
elif command -v iptables >/dev/null 2>&1; then
  iptables -C INPUT -s "${LAN_CIDR}" -p tcp --dport "${RECOG_PORT}" -j ACCEPT 2>/dev/null \
    || iptables -I INPUT -s "${LAN_CIDR}" -p tcp --dport "${RECOG_PORT}" -j ACCEPT
  log "  (iptables rule added; persist via netfilter-persistent if needed)"
else
  log "  (neither ufw nor iptables found; configure firewall manually for port ${RECOG_PORT})"
fi

log "T1-9: enable + start recog.service"
systemctl daemon-reload
systemctl enable --now recog.service

sleep 2
if ! systemctl is-active --quiet recog.service; then
  log "service failed to start; dumping last 50 log lines:"
  journalctl -u recog.service -n 50 --no-pager
  fail "recog.service not active"
fi

log "T1-9 verify: curl /health from localhost"
if ! curl -fsS "http://127.0.0.1:${RECOG_PORT}/health" >/dev/null; then
  fail "/health not responding on localhost"
fi

log "ALL DONE. Next check from a LAN client:"
log "  curl http://192.168.0.146:${RECOG_PORT}/health"
log "  curl -X POST http://192.168.0.146:${RECOG_PORT}/rooms \\"
log "       -d '{\"host_participant_id\":\"test\"}' \\"
log "       -H 'Content-Type: application/json'"

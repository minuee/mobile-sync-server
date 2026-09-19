#!/usr/bin/env bash
#
# install_offline.sh — install recog-backend on the air-gapped host.
#
# Run this from inside the unpacked bundle directory. It never touches the
# network: the image comes from the bundled tar, not a registry.
#
# Usage:
#   ./install_offline.sh [install_dir]
#
#   install_dir   where the deployment lives (default: current directory)
#
# Environment overrides:
#   SKIP_CHECKSUM=1   skip SHA256SUMS verification
#   SKIP_START=1      load and configure, but do not start the container
#
set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${1:-$PWD}" && pwd)"

log()  { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install] WARN:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[install] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -f "${BUNDLE_DIR}/bundle.env" ]] || die "bundle.env missing — run this from inside the unpacked bundle."
# shellcheck disable=SC1091
source "${BUNDLE_DIR}/bundle.env"

log "recog-backend ${BUNDLE_VERSION} (${BUNDLE_PLATFORM}, built ${BUNDLE_BUILT_AT}, git ${BUNDLE_GIT_SHA})"

# ------------------------------------------------------------- prerequisites
command -v docker >/dev/null 2>&1 || die "docker not found on this host."
docker version >/dev/null 2>&1 || die "docker daemon is not responding (try: sudo systemctl start docker)."

if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
else
    die "neither 'docker compose' nor 'docker-compose' is available."
fi
log "compose command: ${COMPOSE[*]}"

# Architecture mismatch is the most common air-gapped failure: the image was
# built on an Apple Silicon laptop and silently will not run here.
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    x86_64|amd64)  HOST_PLATFORM="linux/amd64" ;;
    aarch64|arm64) HOST_PLATFORM="linux/arm64" ;;
    *)             HOST_PLATFORM="linux/${HOST_ARCH}" ;;
esac
if [[ -n "${BUNDLE_PLATFORM:-}" && "$BUNDLE_PLATFORM" != "$HOST_PLATFORM" ]]; then
    die "image is ${BUNDLE_PLATFORM} but this host is ${HOST_PLATFORM}. Rebuild the bundle with: build_offline_bundle.sh <version> ${HOST_PLATFORM}"
fi

# ---------------------------------------------------------------- integrity
if [[ "${SKIP_CHECKSUM:-0}" != "1" && -f "${BUNDLE_DIR}/SHA256SUMS" ]]; then
    log "verifying checksums"
    if command -v sha256sum >/dev/null 2>&1; then
        ( cd "$BUNDLE_DIR" && sha256sum -c SHA256SUMS --quiet ) || die "checksum mismatch — the transfer is corrupt."
    elif command -v shasum >/dev/null 2>&1; then
        ( cd "$BUNDLE_DIR" && shasum -a 256 -c SHA256SUMS --quiet ) || die "checksum mismatch — the transfer is corrupt."
    else
        warn "no sha256sum/shasum available; skipping verification."
    fi
fi

# --------------------------------------------------------------- load image
if docker image inspect "$BUNDLE_IMAGE_REF" >/dev/null 2>&1; then
    log "image ${BUNDLE_IMAGE_REF} already present; skipping load"
else
    log "loading ${BUNDLE_IMAGE_FILE} (this takes a minute)"
    gunzip -c "${BUNDLE_DIR}/${BUNDLE_IMAGE_FILE}" | docker load
fi
docker image inspect "$BUNDLE_IMAGE_REF" >/dev/null 2>&1 || die "image ${BUNDLE_IMAGE_REF} not found after load."

# ------------------------------------------------------------ install files
log "installing to ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"

if [[ "${BUNDLE_DIR}" != "${INSTALL_DIR}" ]]; then
    install -m 0644 "${BUNDLE_DIR}/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
fi

ENV_FILE="${INSTALL_DIR}/.env.recog"
if [[ -f "$ENV_FILE" ]]; then
    log ".env.recog already exists; leaving it untouched"
else
    log "creating .env.recog from template"
    install -m 0644 "${BUNDLE_DIR}/.env.recog.example" "$ENV_FILE"
fi

# Point the compose file at the image we just loaded, not at the registry.
set_env() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$ENV_FILE"; then
        # Portable in-place edit: BSD and GNU sed disagree about -i.
        sed "s|^${key}=.*|${key}=${value}|" "$ENV_FILE" > "${ENV_FILE}.tmp"
        mv "${ENV_FILE}.tmp" "$ENV_FILE"
    else
        printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
    fi
}
set_env IMAGE_NAME "${BUNDLE_IMAGE_REF%%:*}"
set_env RECOG_VERSION "${BUNDLE_IMAGE_REF##*:}"
log "pinned IMAGE_NAME=${BUNDLE_IMAGE_REF%%:*} RECOG_VERSION=${BUNDLE_IMAGE_REF##*:}"

# Data lives wherever RUNTIME_DIR points; ./runtime by default. The container
# runs as uid 10001 and needs to own it.
RUNTIME_DIR="$(grep -E '^RUNTIME_DIR=' "$ENV_FILE" | cut -d= -f2- | tr -d '[:space:]')"
RUNTIME_DIR="${RUNTIME_DIR:-./runtime}"
case "$RUNTIME_DIR" in
    /*) DATA_PATH="$RUNTIME_DIR" ;;
    *)  DATA_PATH="${INSTALL_DIR}/${RUNTIME_DIR#./}" ;;
esac
mkdir -p "$DATA_PATH"
log "data directory: ${DATA_PATH}"
if [[ -f "${DATA_PATH}/merge.db" ]]; then
    log "existing merge.db found — history is preserved"
fi

if chown -R 10001:10001 "$DATA_PATH" 2>/dev/null; then
    log "data directory ownership set to 10001:10001"
else
    warn "could not chown the data directory (not root?). If the container reports"
    warn "permission errors, run:  sudo chown -R 10001:10001 ${DATA_PATH}"
fi

# ------------------------------------------------------------------ network
NETWORK="$(grep -oE '^[[:space:]]+[A-Za-z0-9_.-]+:$' "${INSTALL_DIR}/docker-compose.yml" | tail -1 | tr -d ' :' || true)"
NETWORK="${NETWORK:-timblo-net-package}"
if docker network inspect "$NETWORK" >/dev/null 2>&1; then
    log "external network '${NETWORK}' found"
else
    warn "external network '${NETWORK}' does not exist."
    warn "It normally already exists because MinIO and master-api run on it."
    warn "If this host is standalone, create it first:"
    warn "  docker network create ${NETWORK}"
    die  "aborting: compose would fail with 'network not found'."
fi

# -------------------------------------------------------------------- start
if [[ "${SKIP_START:-0}" == "1" ]]; then
    log "SKIP_START=1 — not starting. Bring it up with:"
    echo "  cd ${INSTALL_DIR} && ${COMPOSE[*]} --env-file .env.recog up -d"
    exit 0
fi

log "starting container"
( cd "$INSTALL_DIR" && "${COMPOSE[@]}" --env-file .env.recog up -d )

# ------------------------------------------------------------- health check
HOST_PORT="$(grep -E '^HOST_PORT=' "$ENV_FILE" | cut -d= -f2 | tr -d '[:space:]')"
HOST_PORT="${HOST_PORT:-28080}"
HEALTH_URL="http://127.0.0.1:${HOST_PORT}/health"

log "waiting for ${HEALTH_URL}"
for attempt in $(seq 1 30); do
    if curl -fsS --max-time 3 "$HEALTH_URL" >/dev/null 2>&1; then
        log "healthy after ${attempt} attempt(s)"
        echo
        echo "  상태 확인 : curl ${HEALTH_URL}"
        echo "  API 문서  : http://<이 호스트>:${HOST_PORT}/docs"
        echo "  로그      : docker logs -f aimm-recog-backend"
        echo "  중지      : cd ${INSTALL_DIR} && ${COMPOSE[*]} --env-file .env.recog down"
        exit 0
    fi
    sleep 2
done

warn "health check did not pass within 60s. Recent logs:"
docker logs --tail 60 aimm-recog-backend 2>&1 || true
die "startup failed."

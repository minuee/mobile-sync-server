#!/usr/bin/env bash
#
# build.sh — 망분리 서버에 반입할 도커 이미지를 만든다.
#
#   ★ 인터넷이 되는 PC 에서 실행한다. 망분리 서버에서 실행하는 스크립트가 아니다.
#
# 하는 일:
#   1. ffmpeg static 바이너리 확보 (한 번 받으면 캐시된다)
#   2. linux/amd64 로 이미지 빌드
#   3. 진짜 amd64 로 나왔는지 확인      ← 아니면 여기서 중단
#   4. 컨테이너를 띄워 실제로 병합을 한 번 돌려본다  ← 실패하면 여기서 중단
#   5. docker save 로 tar 생성
#
# 3번을 통과하지 못하면 tar 를 만들지 않는다. 서버에 가서야 안 되는 걸
# 알게 되는 일을 막기 위해서다.
#
# 환경변수:
#   FFMPEG_URL   static 빌드 주소를 직접 지정 (기본값은 아래 참조)
#
# 사용법:
#   ./deploy/build.sh [버전]
#
#   버전  이미지 태그. 생략하면 저장소 루트의 VERSION 파일을 읽고,
#         그것도 없으면 오늘 날짜를 쓴다 (예 20260921).
#
# 결과물:
#   dist/mobile-sync-server_<버전>_amd64.tar
#   dist/mobile-sync-server_<버전>_amd64.tar.sha256
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# 버전 결정 순서: 인자 > 저장소 루트의 VERSION 파일 > 오늘 날짜
VERSION_FILE="${REPO_ROOT}/VERSION"
if [[ -n "${1:-}" ]]; then
    VERSION="$1"
elif [[ -s "$VERSION_FILE" ]]; then
    VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
else
    VERSION="$(date +%Y%m%d)"
fi
[[ -n "$VERSION" ]] || { printf 'ERROR: 버전이 비어 있다. VERSION 파일을 확인할 것.\n' >&2; exit 1; }
PLATFORM="linux/amd64"
IMAGE_REPO="mobile-sync-server"
IMAGE_REF="${IMAGE_REPO}:${VERSION}"
TEST_CONTAINER="mobile-sync-server-smoke-${VERSION}"
DIST_DIR="${REPO_ROOT}/dist"
OUT_TAR="${DIST_DIR}/${IMAGE_REPO}_${VERSION}_amd64.tar"

# ffmpeg static 빌드.
#   lgpl 변종을 쓴다. 우리가 쓰는 기능(flac/aac/opus/mp3 디코딩, flac 인코딩,
#   amix/adelay/alimiter/apad/atrim/aresample/volume 필터)은 전부 코어라
#   LGPL 빌드로 충분하고, 고객사에 이미지를 넘기는 상황에서 GPL 보다 깔끔하다.
FFMPEG_URL="${FFMPEG_URL:-https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n9.0-latest-linux64-lgpl-9.0.tar.xz}"
FFMPEG_DIR="${REPO_ROOT}/deploy/.ffmpeg"

log()  { printf '\033[1;34m[build]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[build]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[build] 중단:\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() {
    docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ------------------------------------------------------------- 0. 사전 확인
command -v docker >/dev/null 2>&1 || die "docker 가 설치되어 있지 않다."
docker version >/dev/null 2>&1 || die "docker 데몬이 응답하지 않는다. (colima start / Docker Desktop 실행)"
[[ -d src/recog ]] || die "src/recog 가 없다. 저장소 루트에서 실행해야 한다."

log "버전      : ${VERSION}"
log "이미지    : ${IMAGE_REF}"
log "타겟      : ${PLATFORM}"
log "빌드 호스트: $(uname -m)"
echo

# ------------------------------------------------------------ 1. ffmpeg
log "1/5 ffmpeg static 바이너리 확보"
mkdir -p "$FFMPEG_DIR"
if [[ -x "${FFMPEG_DIR}/ffmpeg" && -x "${FFMPEG_DIR}/ffprobe" ]]; then
    ok "이미 있음 — 다시 받지 않는다 ($("${FFMPEG_DIR}/ffmpeg" -version 2>/dev/null | head -1 | cut -d' ' -f1-3 || echo 'amd64 바이너리'))"
else
    log "내려받는 중: $(basename "$FFMPEG_URL")"
    TMP_XZ="$(mktemp -t ffmpeg-static).tar.xz"
    curl -fL --progress-bar -o "$TMP_XZ" "$FFMPEG_URL" \
        || die "ffmpeg static 빌드를 받지 못했다. 주소를 확인하거나 FFMPEG_URL 로 지정할 것."

    TMP_DIR="$(mktemp -d)"
    tar xJf "$TMP_XZ" -C "$TMP_DIR" || die "압축 해제 실패."
    for tool in ffmpeg ffprobe; do
        found="$(find "$TMP_DIR" -type f -name "$tool" -perm -u+x | head -1)"
        [[ -n "$found" ]] || die "받은 아카이브에 ${tool} 이 없다."
        install -m 0755 "$found" "${FFMPEG_DIR}/${tool}"
    done
    rm -rf "$TMP_XZ" "$TMP_DIR"
    ok "ffmpeg / ffprobe 준비됨 ($(du -sh "$FFMPEG_DIR" | cut -f1))"
fi
echo

# --------------------------------------------------------------- 2. 빌드
log "2/5 이미지 빌드 (네트워크를 타는 건 베이스 이미지 pull 하나뿐이다)"
if docker buildx version >/dev/null 2>&1; then
    # provenance / sbom 을 끈다. 켜져 있으면 buildx 가 tar 안에
    # attestation manifest 를 끼워 넣어 manifest list 구조로 만드는데,
    # 구버전 도커에서 docker load 가 이것 때문에 실패할 수 있다.
    docker buildx build \
        --platform "$PLATFORM" \
        --provenance=false \
        --sbom=false \
        --tag "$IMAGE_REF" \
        --file deploy/Dockerfile \
        --load \
        .
else
    log "buildx 없음 — 일반 build 로 진행 (플랫폼 지정이 무시될 수 있다)"
    DOCKER_DEFAULT_PLATFORM="$PLATFORM" docker build \
        --tag "$IMAGE_REF" \
        --file deploy/Dockerfile \
        .
fi
ok "빌드 완료"
echo

# ------------------------------------------------------- 2. 아키텍처 확인
log "3/5 아키텍처 확인"
BUILT="$(docker image inspect "$IMAGE_REF" --format '{{.Os}}/{{.Architecture}}')"
if [[ "$BUILT" != "$PLATFORM" ]]; then
    die "$(cat <<MSG
${BUILT} 로 빌드되었다. 목표는 ${PLATFORM} 다.
이대로 서버에 올리면 컨테이너가 'exec format error' 로 기동조차 안 된다.
buildx 와 QEMU 가 설치되어 있는지 확인하고 다시 실행할 것.
MSG
)"
fi
ok "${BUILT} — 서버 아키텍처와 일치"
echo

# --------------------------------------------------------- 3. 동작 검증
log "4/5 실제 동작 검증 (컨테이너를 띄워 병합을 한 번 돌린다)"
docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true
# 서버에서는 이미지 기본 계정(10001)이 아니라 서버 계정(aimm)의 uid 로 돈다.
# 검증도 같은 조건으로 한다 — 이미지에 없는 uid 로 띄워서, 권한 때문에
# 서버에서만 터지는 일이 없는지 여기서 확인한다.
TEST_UID="${TEST_UID:-1000}"
log "실행 계정 ${TEST_UID}:${TEST_UID} (이미지 기본 10001 이 아닌 값으로 확인)"
docker run -d --name "$TEST_CONTAINER" --platform "$PLATFORM" \
    --user "${TEST_UID}:${TEST_UID}" "$IMAGE_REF" >/dev/null \
    || die "컨테이너가 기동하지 않는다. docker logs ${TEST_CONTAINER} 확인."

sleep 2
if [[ "$(docker inspect -f '{{.State.Running}}' "$TEST_CONTAINER" 2>/dev/null)" != "true" ]]; then
    echo "--- 컨테이너 로그 ---" >&2
    docker logs "$TEST_CONTAINER" >&2 2>&1 || true
    die "컨테이너가 바로 죽었다."
fi

docker cp deploy/smoke_test.py "${TEST_CONTAINER}:/tmp/smoke_test.py" >/dev/null
if ! docker exec "$TEST_CONTAINER" python /tmp/smoke_test.py; then
    echo "--- 컨테이너 로그 ---" >&2
    docker logs --tail 80 "$TEST_CONTAINER" >&2 2>&1 || true
    die "검증 실패. tar 를 만들지 않는다."
fi
docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true
ok "검증 통과"
echo

# ------------------------------------------------------------- 4. tar 생성
log "5/5 tar 생성 (1~2분 걸린다)"
mkdir -p "$DIST_DIR"
docker save "$IMAGE_REF" -o "$OUT_TAR"
if command -v sha256sum >/dev/null 2>&1; then
    ( cd "$DIST_DIR" && sha256sum "$(basename "$OUT_TAR")" > "$(basename "$OUT_TAR").sha256" )
else
    ( cd "$DIST_DIR" && shasum -a 256 "$(basename "$OUT_TAR")" > "$(basename "$OUT_TAR").sha256" )
fi
ok "완료"

echo
echo "  파일   : ${OUT_TAR}"
echo "  크기   : $(du -h "$OUT_TAR" | cut -f1)"
echo "  이미지 : ${IMAGE_REF}"
echo "  sha256 : $(cut -d' ' -f1 < "${OUT_TAR}.sha256")"
echo
echo "  이 파일과 .sha256 을 서버에 반입한 뒤, deploy/ 의"
echo "  install.sh / docker-compose.yml / .env.example 과 함께"
echo "  README.md 절차대로 진행하면 된다."

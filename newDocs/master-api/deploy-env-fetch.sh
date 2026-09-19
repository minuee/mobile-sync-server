#!/bin/bash

set -e

# Consul 기본 설정
CONSUL_ADDR="${CONSUL_ADDR:-http://localhost:38500}"
CONSUL_KEY="${CONSUL_KEY:-timblo/master/deploy}"

# 저장할 .env 파일 경로
ENV_PATH="./.env"

# fallback 기본값 세팅
DEFAULT_ENV_VARS=$(cat <<EOF
CONTAINER_NAME=aimm-master-api
PINPOINT_AGENT_ID=be-master-service
VOLUME_TMP_PATH=/data/aimm/master/tmp
VOLUME_BACKUP_PATH=/data/aimm/master/masterBackUp
DOCKER_NETWORK_NAME=aimm-net
EOF
)

echo "Consul에서 환경변수(.env) 파일 가져오기 시도 중..."

# Consul에서 .env 가져오기 시도 (파이프 종료코드 함정 회피: 단계별로 검증)
#  - curl --fail 실패(404/연결불가) → CONSUL_JSON 비어 success=0
#  - jq/base64 결과가 비면 → fallback
DECODED=""
if CONSUL_JSON=$(curl --silent --fail "${CONSUL_ADDR}/v1/kv/${CONSUL_KEY}" 2>/dev/null) && [ -n "$CONSUL_JSON" ]; then
    DECODED=$(printf '%s' "$CONSUL_JSON" | jq -r '.[0].Value // empty' 2>/dev/null | base64 --decode 2>/dev/null || true)
fi

if [ -n "$DECODED" ]; then
    printf '%s\n' "$DECODED" > "$ENV_PATH"
    echo ".env 파일 생성 완료 (Consul): $ENV_PATH"
else
    echo "⚠️ Consul 응답 없음/실패 → 기본 fallback 환경변수로 .env 생성"
    printf '%s\n' "$DEFAULT_ENV_VARS" > "$ENV_PATH"
fi

if [ -n "$IMAGE_TAG" ]; then
  if ! grep -q "^IMAGE_TAG=" "$ENV_PATH"; then
    tail -c1 "$ENV_PATH" 2>/dev/null | read -r _ || echo >> "$ENV_PATH"
    echo "IMAGE_TAG=$IMAGE_TAG" >> "$ENV_PATH"
    echo "추가: IMAGE_TAG=$IMAGE_TAG"
  else
    echo "주의: .env에 이미 IMAGE_TAG가 존재합니다 (덮어쓰지 않음)"
  fi
else
  echo "⚠️ 주의: IMAGE_TAG 값이 비어있습니다 (추가하지 않음)"
fi
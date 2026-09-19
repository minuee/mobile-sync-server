#!/bin/sh
set -e

INIT_FILE="/data/minio_data/.initialized"

echo "[entrypoint.sh] MinIO 서버 시작"

/usr/bin/docker-entrypoint.sh "$@" &
MINIO_PID=$!


if [ ! -f "$INIT_FILE" ]; then
  echo "[ENTRYPOINT] 최초 실행 감지: 초기 설정 진행합니다."
  sleep 5

  echo "[custom-entrypoint.sh] init.sh 실행"
  sh /usr/local/bin/timbloInit.sh
  touch "$INIT_FILE"
else
  echo "[ENTRYPOINT] 이미 초기화가 완료된 컨테이너입니다. 초기 스크립트 스킵."
fi

wait $MINIO_PID

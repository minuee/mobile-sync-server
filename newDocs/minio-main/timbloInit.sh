#!/bin/sh
set -e

echo "[init.sh] MinIO 초기화 스크립트 시작"

mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc mb "local/$BUCKET_NAME"
mc mb "local/$PUB_BUCKET_NAME"

mc anonymous set public "local/$PUB_BUCKET_NAME"

ACCESS_KEY_OUTPUT=$(mc admin accesskey create local)
CONTAINER_NAME=$()

# 초기 변수 설정
NEW_ACCESS_KEY=""
NEW_SECRET_KEY=""

# 문자열을 한 줄씩 읽어가며 Access Key와 Secret Key 추출
while IFS= read -r line; do
  case "$line" in
    "Access Key:"*)
      NEW_ACCESS_KEY=$(echo "$line" | cut -d':' -f2 | cut -c 2-)  # 앞 공백 제거
      ;;
    "Secret Key:"*)
      NEW_SECRET_KEY=$(echo "$line" | cut -d':' -f2 | cut -c 2-)  # 앞 공백 제거
      ;;
  esac
done <<< "$ACCESS_KEY_OUTPUT"

# 추출된 결과 출력
echo "[init.sh] 발급된 AccessKey: $NEW_ACCESS_KEY"
echo "[init.sh] 발급된 SecretKey: $NEW_SECRET_KEY"

# Consul에 JSON 형태로 키 저장
echo "[init.sh] timblo-discovery 컨테이너(Consul)에 credentials JSON PUT 요청..."
CREDS_JSON="{\"ACCESS_KEY_ID\":\"${NEW_ACCESS_KEY}\",\"SECRET_ACCESS_KEY\":\"${NEW_SECRET_KEY}\", \"REGION\":\"${MINIO_REGION}\"}"
curl -X PUT --data "$CREDS_JSON" "http://timblo-discovery:8500/v1/kv/timblo/common/credentials"

echo "[init.sh] MinIO 초기화 스크립트 완료"
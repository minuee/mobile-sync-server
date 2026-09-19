#!/bin/bash
set -e

# 1) 인자로 새 버전 받아오기
VERSION="$1"

if [ -z "$VERSION" ]; then
  echo "Usage: $0 <new_version>"
  echo "Ex)   $0 1.0.0"
  exit 1
fi

# 2) 환경설정: GHCR의 계정/레포, 토큰(로그인)은 미리 docker login으로 처리하거나 아래에서 해도 됨
OWNER="timbel-timblo-onpremise"
REPO="minio"
IMAGE="ghcr.io/${OWNER}/${REPO}"

# 3) Docker 빌드 (버전 태그)
echo "[INFO] Docker build for version: $VERSION"
docker build -t "$IMAGE:$VERSION" .

# 4) latest 태그
echo "[INFO] Tagging to 'latest'"
docker tag "$IMAGE:$VERSION" "$IMAGE:latest"

# 5) 푸시 (버전, latest)
echo "[INFO] Pushing version $VERSION and 'latest'"
docker push "$IMAGE:$VERSION"
docker push "$IMAGE:latest"

echo "[INFO] Done."
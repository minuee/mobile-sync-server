
#!/bin/bash

CS="\033[44;37m  "
CE=" \033[0m"

PREFIX="sk-timblo-be-master-service"
CONTAINER_NAME="sk-timblo-be-master-service"
NETWORK="timblo-net"

if [ -n ${NETWORK} ]; then
   NETWORK="--network $NETWORK"
fi
echo $NETWORK


rm -rf ./dist

echo -e "${CS}React Client Project Build${CE}"
npm run build


cp -rf ./src/ecosystem.config.cjs ./dist


echo -e "${CS}'dist/' set chmod 777 ${CE}"
chmod 777 "./dist" -R

echo -e "${CS} 도커 빌드  ${CE}"
docker build -f DockerFile -t $PREFIX . 
docker build -f DockerFile -t  ghcr.io/timbel-timblo-onpremise/master-api:latest . 
docker push ghcr.io/timbel-timblo-onpremise/master-api:latest

# docker stop $CONTAINER_NAME
# docker rm $CONTAINER_NAME

echo -e "${CS}새로 빌드된 도커 이미지를 실행${CE}"
# docker run -d --name $CONTAINER_NAME $NETWORK $PREFIX --restart unless-stopped -v /data/timblo/masterBackUp:/usr/src/app/failedUploadFile
docker-compose up -d 

echo -e "${CS}실행시킨 도커의 프로세스 상태를 조회${CE}"
docker ps -a | grep $CONTAINER_NAME

noneClean


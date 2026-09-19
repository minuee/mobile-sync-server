#!/bin/bash
# 09~17 산출물 빌드: video/meta-*.json 의 원본 영상에서 gif / gif-light / mp4 를 만든다.
#   ./build.sh            → 전부
#   ./build.sh 12_calendar → 하나만
set -e
OUT=../manual
mkdir -p $OUT/gif $OUT/gif-light $OUT/mp4

# 이름 | meta | crop(-=없음) | 배속(-=1배) | gif폭 gif_fps gif_색 | light폭 light_fps light_색
ITEMS=(
"09_home-left|home-left|700:1080:0:0|-|660 11 96|470 8 56"
"10_home-right|home-right|1680:910:240:0|-|1060 10 80|760 8 48"
"11_search|search|880:600:560:0|-|880 11 88|630 8 48"
"12_calendar|calendar|-|-|1100 10 88|780 8 48"
"13_inbox|inbox|-|-|1100 10 88|780 8 48"
"14_bookmark|bookmark|-|-|1100 10 88|780 8 48"
"15_recycle|recycle|-|-|1100 10 88|780 8 48"
"16_usage|usage|-|-|1040 8 72|700 7 40"
"17_dictionary|dict|1640:910:0:150|1.3|1150 10 88|820 8 48"
"18_lnb-menus|lnb|700:1080:0:0|-|660 9 80|460 7 48"
)

for row in "${ITEMS[@]}"; do
  IFS='|' read -r NAME META CROP SPEED G L <<< "$row"
  [ -n "$1" ] && [ "$1" != "$NAME" ] && continue
  read -r GW GF GC <<< "$G"; read -r LW LF LC <<< "$L"
  V=$(node -e "console.log(require('./video/meta-$META.json').vpath)")
  O=$(node -e "console.log(require('./video/meta-$META.json').offset)")

  PRE=""
  [ "$CROP" != "-" ] && PRE="crop=$CROP,"
  [ "$SPEED" != "-" ] && PRE="${PRE}setpts=PTS/$SPEED,"

  # 디더링은 화면마다 유불리가 갈린다(차트가 많으면 none, 단색 UI 는 bayer 가 작다).
  # 둘 다 만들어 작은 쪽만 남긴다.
  mkgif () {  # $1=폭 $2=fps $3=색 $4=결과경로
    local best="" bestsz=0
    for D in none "bayer:bayer_scale=3"; do
      ffmpeg -y -loglevel error -ss "$O" -i "$V" \
        -vf "${PRE}fps=$2,scale=$1:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=$3[p];[s1][p]paletteuse=dither=$D" \
        -loop 0 "$4.tmp.gif"
      local sz=$(stat -f%z "$4.tmp.gif")
      if [ -z "$best" ] || [ "$sz" -lt "$bestsz" ]; then best="$D"; bestsz=$sz; mv "$4.tmp.gif" "$4"; else rm -f "$4.tmp.gif"; fi
    done
  }
  mkgif "$GW" "$GF" "$GC" "$OUT/gif/$NAME.gif"
  mkgif "$LW" "$LF" "$LC" "$OUT/gif-light/$NAME.gif"
  # mp4 는 폭을 짝수로 맞춰야 h264 인코딩이 된다 (-2)
  ffmpeg -y -loglevel error -ss "$O" -i "$V" \
    -vf "${PRE}scale=$GW:-2:flags=lanczos" -an \
    -c:v libx264 -pix_fmt yuv420p -crf 26 -movflags +faststart "$OUT/mp4/$NAME.mp4"

  # du 는 디스크 블록 단위라 부풀어 보인다 → 실제 바이트로 찍는다
  mb () { echo "scale=2; $(stat -f%z "$1")/1048576" | bc; }
  printf '%-16s gif %6sMB   light %6sMB   mp4 %6sMB\n' "$NAME" \
    "$(mb "$OUT/gif/$NAME.gif")" "$(mb "$OUT/gif-light/$NAME.gif")" "$(mb "$OUT/mp4/$NAME.mp4")"
done

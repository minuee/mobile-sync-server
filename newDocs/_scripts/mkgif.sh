#!/bin/bash
# mkgif.sh <meta이름> <출력경로> <crop|-> <scale> <fps> <colors>
set -e
META="video/meta-$1.json"
V=$(node -e "console.log(require('./$META').vpath)")
O=$(node -e "console.log(require('./$META').offset)")
CROP="$3"; SCALE="$4"; FPS="$5"; COL="$6"
VF="fps=$FPS,scale=$SCALE:-1:flags=lanczos"
[ "$CROP" != "-" ] && VF="crop=$CROP,$VF"
ffmpeg -y -loglevel error -ss "$O" -i "$V" \
  -vf "$VF,split[s0][s1];[s0]palettegen=max_colors=$COL[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3" \
  -loop 0 "$2"
printf '%-28s %6s  %5.1fs  %s\n' "$(basename "$2")" "$(du -h "$2" | cut -f1)" \
  "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$2")" \
  "$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 "$2")"

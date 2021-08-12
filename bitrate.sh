#!/bin/bash

_bpp=0.1
audio_bit_rate=128

width=$(ffprobe -loglevel error -show_format -show_streams $1 -print_format flat | grep "\.width=" | cut -d "=" -f 2)
height=$(ffprobe -loglevel error -show_format -show_streams $1 -print_format flat | grep "\.height=" | cut -d "=" -f 2)

_bitrate=$(ffprobe -loglevel error -show_format -show_streams $1 -print_format flat | grep "format.bit_rate=" | cut -d "\"" -f 2)
bitrate=$(echo "${_bitrate}/1024" | bc)

frame_rate=$(ffprobe -loglevel error -show_format -show_streams $1 -print_format flat | grep "r_frame_rate=" | cut -d "\"" -f 2 | head -1)

fps=$(echo "scale=2; $frame_rate" | bc -l)

ratio=$(echo "$width/$height" | bc -l)

echo "Width  : $width"
echo "Height : $height"
echo "bitrate: $bitrate"
echo "fps    : $fps"
echo "ratio  : $ratio"

bpp=$(echo "scale=2; $_bitrate/($width*$height*$frame_rate)" | bc -l)

echo "bpp    : $bpp"

ratio=$(echo "$width/$height" | bc -l)

declare -a p_res 
p_res=(240 360 480 720 1080 1440 2160)

declare -a h_res

i=0
for v in ${p_res[@]}
do
  h_res[$i]=$(echo "$v*$ratio" | bc | awk '{print ($0-int($0)<0.499)?int($0):int($0)+1}')
  let "i=i+1"
done

declare -a bitstr

i=0
for b in ${p_res[@]}
do
  bitstr[$i]=$(echo "(${h_res[i]}*${p_res[i]}*${fps}*${_bpp}/1000)+${audio_bit_rate}" | bc)
  let "i=i+1"
done

i=0
for h in ${p_res[@]}
do
  if [[ $( echo "$height-$h" | bc ) -ge 0 ]]; then
    echo "${h_res[i]}x${h}p   : ${bitstr[i]}"
  fi
  let "i=i+1"
done

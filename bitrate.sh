#!/bin/bash

target_bpp=0.1
audio_bit_rate=128
declare -a vertical_res
vertical_res=(240 360 480 720 1080 1440 2160)

width=$(ffprobe -loglevel error -show_format -show_streams $1 -print_format flat | grep "\.width=" | cut -d "=" -f 2)
height=$(ffprobe -loglevel error -show_format -show_streams $1 -print_format flat | grep "\.height=" | cut -d "=" -f 2)

bitrate_bytes=$(ffprobe -loglevel error -show_format -show_streams $1 -print_format flat | grep "format.bit_rate=" | cut -d "\"" -f 2)
bitrate=$(echo "${bitrate_bytes}/1024" | bc)

frame_rate=$(ffprobe -loglevel error -show_format -show_streams $1 -print_format flat | grep "r_frame_rate=" | cut -d "\"" -f 2 | head -1)
fps=$(echo "scale=2; $frame_rate" | bc -l)

ratio=$(echo "$width/$height" | bc -l)

echo "Width  : $width"
echo "Height : $height"
echo "bitrate: $bitrate"
echo "fps    : $fps"
echo "ratio  : $ratio"

bpp=$(echo "scale=2; $bitrate_bytes/($width*$height*$frame_rate)" | bc -l)

echo "bpp    : $bpp"

ratio=$(echo "$width/$height" | bc -l)

declare -a horizontal_res

i=0
for v in "${vertical_res[@]}"
do
  horizontal_res[$i]=$(echo "$v*$ratio" | bc | awk '{print ($0-int($0)<0.499)?int($0):int($0)+1}')
  ((i=i+1))
done

declare -a bit_rates

i=0
for b in "${vertical_res[@]}"
do
  bit_rates[$i]=$(echo "(${horizontal_res[i]}*${vertical_res[i]}*${fps}*${target_bpp}/1000)+${audio_bit_rate}" | bc)
  ((i=i+1))
done

split=0
for h in "${vertical_res[@]}"
do
  if [[ $( echo "$height-$h" | bc ) -ge 0 ]]; then
    echo "${horizontal_res[split]}x${h}p   : ${bit_rates[split]}k"
  fi
  ((split=split+1))
done


filter_complex="[v:0]split=${split}"

i=0
filter=""
for h in "${vertical_res[@]}"
do
  pad=$(printf "%03d" $i)
  filter="${filter}[vtemp${pad}]"
  ((i=i+1))
done

filter_complex="$filter_complex${filter};"

i=0
filter=""
for h in "${vertical_res[@]}"
do
  pad1=$(printf "%03d" $i)
  pad2=$(printf "%03d" $i)
  filter="${filter}[vtemp${pad1}]scale=w=${horizontal_res[i]}:h=${vertical_res[i]}[vout${pad2}];"
  ((i=i+1))
done

filter_complex="$filter_complex${filter};"
echo "$filter_complex"

i=0
map=""
nl=$'\n'
for h in "${vertical_res[@]}"
do
  pad=$(printf "%03d" $i)
  max_rate=$( echo "${bit_rates[i]}+(${bit_rates[i]}*10/100)" | bc)
  buf_size=$( echo "${bit_rates[i]}*1.5" | bc | awk '{print ($0-int($0)<0.499)?int($0):int($0)+1}')

  map="-map [vout${pad}] -c:v:${i} libx264 -b:v:${i} ${bit_rates[i]}k -maxrate:v:0 ${max_rate}k -bufsize:v:${i} ${buf_size}k"
  line="${map} \\${nl}"
  lines="${lines}${line}"
  ((i=i+1))
done
echo "$lines"

i=0
audio_map=""
stream_map=""
for h in "${vertical_res[@]}"
do
  audio_map="${audio_map} -map a:0"
  stream_map="${stream_map} v:${i},a:${i}"
  ((i=i+1))
done
audio_map="${audio_map} -c:a aac -b:a 128k -ac 2"

echo $audio_map
echo $stream_map
#"v:0,a:0 v:1,a:1 v:2,a:2"
echo
echo

threads=8
duration=6
out="stream"

echo "ffmpeg -i $1 \\
    -threads $threads \\
    -filter_complex \"$filter_complex\" \\
    -preset veryfast -g ${fps} -sc_threshold 0 \\
     ${lines} \\
     ${audio_map} \\
    -f hls -hls_time ${duration} -hls_playlist_type event -hls_flags independent_segments \\
    -master_pl_name master.m3u8 \\
    -hls_segment_filename ${out}_%v/data%06d.ts \\
    -use_localtime_mkdir 1 \\
    -var_stream_map \"${stream_map}\" ${out}_%v.m3u8"

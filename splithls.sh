#!/bin/bash

playlist="master.m3u8"
duration=6
out="stream"
target_bpp=0.1
audio_bit_rate=128
def_vertical_res=(240 360 480 720 1080 1440 2160)
declare -a vertical_res
declare -a horizontal_res
declare -a bit_rates

function detect_threads()
{
  OS=$(uname -s)

  if [ "$OS" == "Darwin" ]; then
    threads=$(sysctl -n hw.ncpu)
  else
    threads=$(grep -c ^processor /proc/cpuinfo)
  fi
}

function usage()
{
  echo "Usage:" 
  echo "  splithls -i /path/to/file"
  echo "          [-a audiorate] (in k, ex. -a 128) [default: 128]"
  echo "          [-b bits per pixel] (ex. -b 0.1  - for avg movement, slideshows)"
  echo "                              (ex. -b 0.4  - for high movement, racing )"
  echo "                              (ex. -b 0.06 - for low movement, static imgs)"
  echo "              higher bpp means higher quality and larger files [default: 0.1]"
  echo "          [-p \"res1 res2 .. resn\"] (vertical resolutions, es. \"240 720 1080\")"
  echo "              [default: \"240 360 480 720 1080 1440 2160\"]"
  echo "          [-d DURATION] (in seconds per segment, ex. -d 6)"
  echo "          [-o SEGMENTS BASENAME] (ex. -o \"out\") [default: \"stream\"]"
}

function get_video_stats()
{
  width=$(ffprobe -loglevel error -show_format -show_streams "$1" -print_format flat | grep "\.width=" | cut -d "=" -f 2)
  height=$(ffprobe -loglevel error -show_format -show_streams "$1" -print_format flat | grep "\.height=" | cut -d "=" -f 2)

  bitrate_bytes=$(ffprobe -loglevel error -show_format -show_streams "$1" -print_format flat | grep "format.bit_rate=" | cut -d "\"" -f 2)
  bitrate=$(echo "${bitrate_bytes}/1024" | bc)

  frame_rate=$(ffprobe -loglevel error -show_format -show_streams "$1" -print_format flat | grep "r_frame_rate=" | cut -d "\"" -f 2 | head -1)
  fps=$(echo "scale=2; $frame_rate" | bc -l)

  video_duration=$(ffprobe -loglevel error -show_format -show_streams "$1" -print_format flat | grep "format.duration=" | cut -d "\"" -f 2)

  ratio=$(echo "$width/$height" | bc -l)
  bpp=$(echo "scale=2; $bitrate_bytes/($width*$height*$frame_rate)" | bc -l)
}

function exclude_vertical_resolutions_bigger_than_default_ones()
{
  split=0
  #declare -a vertical_res
  for h in "${def_vertical_res[@]}"
  do
    if [[ $( echo "$height-$h" | bc ) -ge 0 ]]; then
      vertical_res[$split]=$h
      ((split=split+1))
    fi
  done
}

function calculate_horizontal_resolutions_with_aspect_ratio()
{
#  declare -a horizontal_res

  i=0
  for v in "${vertical_res[@]}"
  do
    num=$(echo "$v*$ratio" | bc | awk '{print ($0-int($0)<0.499)?int($0):int($0)+1}')
    (( num++ ))
    num=$(( $num - ($num %2) ))
    horizontal_res[$i]=$num
    ((i=i+1))
  done
}

function calculate_bit_rates()
{
  #declare -a bit_rates

  i=0
  for b in "${vertical_res[@]}"
  do
    bit_rates[$i]=$(echo "(${horizontal_res[i]}*${vertical_res[i]}*${fps}*${target_bpp}/1000)+${audio_bit_rate}" | bc)
    ((i=i+1))
  done
}


function print_bit_rates_stats()
{
  i=0
  for h in "${vertical_res[@]}"
  do
    if [[ $( echo "$height-$h" | bc ) -ge 0 ]]; then
      echo "${horizontal_res[i]}x${h}p   : ${bit_rates[i]}k"
    fi
    ((i=i+1))
  done
}


function generate_filters_to_resize_videos()
{
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

  filter_complex="$filter_complex${filter}"
  filter_complex=${filter_complex%?}
}
#echo "$filter_complex"

function maps_filters_to_bitrates()
{
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
  lines=${lines%??}
}
#echo "$lines"

function generate_audio_and_stream_maps()
{
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
}

#echo $audio_map
#echo $stream_map
function print_stats()
{
  echo "--- $filename stats ---"
  echo "Width  : $width"
  echo "Height : $height"
  echo "bitrate: $bitrate"
  echo "fps    : $fps"
  echo "ratio  : $ratio"
  echo "bpp    : $bpp"
  echo
  echo "--- Target bit rates ---"
  print_bit_rates_stats
}

function progress()
{
  sleep 1
  segments=$(echo "$video_duration/$duration" | bc)
  current=0
  while [[ $current -le $segments ]]; do
    current=$(ls -b stream_0 | cut -d "." -f 1 | awk '{print substr($0,5) }' | sort -n | tail -n 1 | bc)
    echo -e -n "\rSegment generation progress: $current / $segments"
  done
  echo
}

function main()
{
  if [ -z "$filename" ]; then
    usage
    exit
  fi

  detect_threads
  get_video_stats $1
  exclude_vertical_resolutions_bigger_than_default_ones
  calculate_horizontal_resolutions_with_aspect_ratio
  calculate_bit_rates
  generate_filters_to_resize_videos
  maps_filters_to_bitrates
  generate_audio_and_stream_maps

  echo "* Splithls (C) by Luca Viola *"
  echo
  print_stats
  echo
  progress &
  pid=$!

  cmd="ffmpeg -i \"$filename\" \\
      -hide_banner \\
      -loglevel panic \\
      -threads $threads \\
      -filter_complex \"$filter_complex\" \\
      -preset veryfast -g ${frame_rate} -sc_threshold 0 \\
       ${lines} \\
       ${audio_map} \\
      -f hls -hls_time ${duration} -hls_playlist_type event -hls_flags independent_segments \\
      -master_pl_name ${playlist} \\
      -hls_segment_filename ${out}_%v/data%06d.ts \\
      -use_localtime_mkdir 1 \\
      -var_stream_map \"${stream_map}\" ${out}_%v.m3u8"
  sh -c "$cmd"
  #echo "$cmd"
  kill -15 $pid
  echo
}

while getopts ":a:b:d:i:o:t:p:" opt; do
  case $opt in
    d)
      duration=$OPTARG
      ;;
    a)
      audio_bit_rate=$OPTARG
      ;;
    b)
      target_bpp=$OPTARG
      ;;
    i)
      filename=$OPTARG
      ;;
    o)
      out=$OPTARG
      ;;
    t)
      threads=$OPTARG
      ;;
    p)
      vres=$OPTARG

      def_vertical_res=()
      for i in $vres; do
        def_vertical_res+=($i)
      done
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

main "$filename"

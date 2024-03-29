#!/bin/bash

OS=$(uname -s)

codec="libx264"
preset="-preset veryfast"
if [ "$OS" == "Darwin" ]; then
  codec="h264_videotoolbox"
  preset=""
else
  model=$(cat /proc/device-tree/model 2> /dev/null | tr '[:upper:]' '[:lower:]' | awk '{ print $1 }')
  if [ "$model" = "raspberry" ]; then
    codec="h264_v4l2m2m"
    preset=""
  else
    ffmpeg -loglevel error -f lavfi -i color=black:s=1080x1080 -vframes 1 -an -c:v hevc_nvenc -f null - 2> /dev/null
    if [ $? -eq 0 ]; then
      codec="h264_nvenc"
      preset=""
    fi
  fi
fi

playlist="master.m3u8"
duration=6
out="stream"
target_bpp=0.1
audio_bit_rate=128
def_vertical_res=(240 360 480 720 1080 1440 2160)
work_dir="."
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
  echo "          [-d duration] (in seconds per segment, ex. -d 6)"
  echo "          [-r frame rate] (in frames per second, ex: -r 23.976023976)"
  echo "              [default: same as original video]"
  echo "          [-o segments basename] (ex. -o \"out\") [default: \"stream\"]"
}

function get_video_stats()
{
  width=$(ffprobe -loglevel error -show_format -show_streams "$1" -print_format flat | grep "\.width=" | cut -d "=" -f 2)
  height=$(ffprobe -loglevel error -show_format -show_streams "$1" -print_format flat | grep "\.height=" | cut -d "=" -f 2)
  frame_count=$(ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 "$1")
  bitrate_bytes=$(ffprobe -loglevel error -show_format -show_streams "$1" -print_format flat | grep "format.bit_rate=" | cut -d "\"" -f 2)
  bitrate=$(echo "${bitrate_bytes}/1024" | bc)

  if [ -z $frame_rate ]; then 
    frame_rate=$(ffprobe -loglevel error -show_format -show_streams "$1" -print_format flat | grep "r_frame_rate=" | cut -d "\"" -f 2 | head -1)
  fi
  fps=$(echo "scale=2; $frame_rate" | bc -l)

  video_duration=$(ffprobe -loglevel error -show_format -show_streams "$1" -print_format flat | grep "format.duration=" | cut -d "\"" -f 2)

  ratio=$(echo "$width/$height" | bc -l)
  bpp=$(echo "scale=2; $bitrate_bytes/($width*$height*$frame_rate)" | bc -l)
}

function exclude_vertical_resolutions_bigger_than_default_ones()
{
  split=0
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

    map="-map [vout${pad}] -c:v:${i} ${codec} -b:v:${i} ${bit_rates[i]}k -maxrate:v:0 ${max_rate}k -bufsize:v:${i} ${buf_size}k"
    line="${map} \\${nl}"
    lines="${lines}${line}"
    ((i=i+1))
  done
  lines=${lines%??}
}

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

function print_stats()
{
  echo "--- $filename stats ---"
  echo "Width  : $width"
  echo "Height : $height"
  echo "Frames : $frame_count"
  echo "bitrate: $bitrate"
  echo "fps    : $fps"
  echo "ratio  : $ratio"
  echo "bpp    : $bpp"
  echo
  echo "--- Target bit rates ---"
  echo "Target bpp: ${target_bpp}"
  echo "codec: ${codec}"
  echo
  print_bit_rates_stats
}

function progress()
{
  sleep 1
  segments=$(echo "$video_duration/$duration" | bc)
  current=0
  while [[ $current -lt $segments ]]; do
    current=$(ls -b $work_dir/stream_0 | cut -d "." -f 1 | awk '{print substr($0,5) }' | sort -n | tail -n 1 | bc)
    echo -e -n "\rSegment generation progress: $current / $segments"
    sleep 1
  done
  echo
}

function check_bit_rates
{
  idx=0
  for i in "${bit_rates[@]}"
  do
     if [[ $i -gt $bitrate ]]; then
       echo
       echo "[WARNING] in ${horizontal_res[$idx]}x${vertical_res[$idx]} the bitrate is higher than the source ($i vs. $bitrate)"
       echo "[WARNING] You might want to try a bpp < ${target_bpp} in the -b option"
       echo
     fi
     ((idx=idx+1))
  done
}

function splithls()
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
  check_bit_rates
  echo
  progress &
  pid=$!

  cmd="ffmpeg -i \"$filename\" \\
      -hide_banner \\
      -loglevel panic \\
      -threads $threads \\
      -filter_complex \"$filter_complex\" \\
       ${preset} -r ${frame_rate} -g ${frame_rate} -sc_threshold 0 \\
       ${lines} \\
       ${audio_map} \\
      -f hls -hls_time ${duration} -hls_playlist_type event -hls_flags independent_segments \\
      -master_pl_name ${playlist} \\
      -hls_segment_filename $work_dir/${out}_%v/data%06d.ts \\
      -strftime_mkdir 1 \\
      -var_stream_map \"${stream_map}\" $work_dir/${out}_%v.m3u8"
  echo "$cmd" > cmd.log
  start_time=$(date +%s)
  sh -c "$cmd"
  end_time=$(date +%s)
  elapsed=$(( end_time - start_time ))
  fps_enc=$(echo "scale=2; ${frame_count}/${elapsed}" | bc -l)
  kill -15 $pid
  wait $pid 2>/dev/null 
  segments=$(echo "$video_duration/$duration" | bc)
  echo -e -n "\rDone, all segments processed.                     "
  echo -e "\nTime elapsed: ${elapsed} seconds ($fps_enc frames/s)"
  echo
}

function main()
{
  local OPTIND opt
  while getopts ":w:s:r:a:b:d:i:o:t:p:" opt; do
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
      r)
        frame_rate=$OPTARG
        ;;
      t)
        threads=$OPTARG
        ;;
      s)
         url_sync=$OPTARG
         if $(echo "$url_sync" | egrep -q "^(s3:|rsync:).*$"); then
           has_sync=1
     protocol=$(echo "$url_sync" | cut -d ":" -f 1)
     if [ "$protocol" == "rsync" ]; then
       url_sync=$(echo "$url_sync" | cut -d "/" -f 3-)
           fi
     echo $protocol
     echo $url_sync
         else
           echo -e "\nerror: the -s (sync) option supports only s3:// and rsync:// urls\n"
     exit 1
         fi
         ;;
      w)
         work_dir=$OPTARG
         if [ ! -d ${work_dir} ]; then
            echo -e "\nWorking directoy ${work_dir} does not exists\n"
            exit 1
         fi
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
  splithls "$filename"
}

main "$@"

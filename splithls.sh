#!/bin/bash

playlist="playlist.m3u8"
duration=6
out="stream"

function usage()
{
  echo "Usage:" 
  echo "  splithls -i FILENAME"
  echo "          [-d DURATION] (in seconds per segment, ex. -d 6)"
  echo "          [-o SEGMENTS BASENAME] (ex. -o out)"
}

while getopts ":d:i:o:t:" opt; do
  case $opt in
    d)
      duration=$OPTARG
      ;;
    i)
      filename=$OPTARG
      ;;
    o)
      out=$OPTARG
      ;;
    t)
      THREADS=$OPTARG
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

if [ -z "$filename" ]; then
  usage
  exit 
fi

frame_rate=$(ffprobe -loglevel error -show_format -show_streams $filename -print_format flat | grep "r_frame_rate=" | cut -d "\"" -f 2 | head -1)
fps=$(echo "scale=2; $frame_rate" | bc -l)


ffmpeg -i $filename \
    -threads 8 \
    -filter_complex "[v:0]split=3[vtemp001][vtemp002][vout003];[vtemp001]scale=w=640:h=360[vout001];[vtemp002]scale=w=1280:h=720[vout002]" \
    -preset veryfast -g ${frame_rate} -sc_threshold 0 \
    -map [vout001] -c:v:0 libx264 -b:v:0 1000k -maxrate:v:0 1100k -bufsize:v:0 2000k \
    -map [vout002] -c:v:1 libx264 -b:v:1 4000k -maxrate:v:1 4400k -bufsize:v:1 6000k \
    -map [vout003] -c:v:2 libx264 -b:v:2 12000k -maxrate:v:2 13200k -bufsize:v:2 16000k \
    -map a:0 -map a:0 -map a:0 -c:a aac -b:a 128k -ac 2 \
    -f hls -hls_time ${duration} -hls_playlist_type event -hls_flags independent_segments \
    -master_pl_name master.m3u8 \
    -hls_segment_filename ${out}_%v/data%06d.ts \
    -use_localtime_mkdir 1 \
    -var_stream_map "v:0,a:0 v:1,a:1 v:2,a:2" ${out}_%v.m3u8

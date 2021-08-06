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
      FILE=$OPTARG
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

if [ -z "$FILE" ]; then
  usage
  exit 
fi

#ffmpeg -i $FILE -map 0  -codec:v libx264 -pix_fmt yuv420p -codec:a aac -f ssegment -segment_list ${playlist} -segment_list_flags +live -segment_time $duration ${out}%04d.ts


#ffmpeg -i $FILE -c:v libx264 -crf 21 -preset veryfast -g 25 -sc_threshold 0 -c:a aac -b:a 128k -ac 2 -f hls -hls_time ${duration} -hls_playlist_type event ${playlist} 



ffmpeg -i $FILE \
    -filter_complex "[v:0]split=2[vtemp001][vout002];[vtemp001]scale=w=960:h=540[vout001]" \
    -preset veryfast -g 25 -sc_threshold 0 \
    -map [vout001] -c:v:0 libx264 -b:v:0 2000k -maxrate:v:0 2200k -bufsize:v:0 3000k \
    -map [vout002] -c:v:1 libx264 -b:v:1 6000k -maxrate:v:1 6600k -bufsize:v:1 8000k \
    -map a:0 -map a:0 -c:a aac -b:a 128k -ac 2 \
    -f hls -hls_time ${duration} -hls_playlist_type event -hls_flags independent_segments \
    -master_pl_name master.m3u8 \
    -hls_segment_filename ${out}_%v/data%06d.ts \
    -use_localtime_mkdir 1 \
    -var_stream_map "v:0,a:0 v:1,a:1" ${out}_%v.m3u8

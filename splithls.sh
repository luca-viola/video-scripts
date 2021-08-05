#!/bin/bash

playlist="playlist.m3u8"
duration=6
out="out"

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


ffmpeg -i $FILE -c:v libx264 -crf 21 -preset veryfast -g 25 -sc_threshold 0 -c:a aac -b:a 128k -ac 2 -f hls -hls_time ${duration} -hls_playlist_type event ${playlist} 

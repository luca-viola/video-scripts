#!/bin/bash

ABR=128
W=640
H=360
SIZE=80

HAS_W=0
HAS_H=0

OS=$(uname -s)

if [ "$OS" == "Darwin" ]; then
  THREADS=$(sysctl -n hw.ncpu)
else
  THREADS=$(grep -c ^processor /proc/cpuinfo)
fi


function usage()
{
  echo "Usage:" 
  echo "  convert -i FILENAME"
  echo "          [-s SIZE] (in mega bytes, ex. -s 80)"
  echo "          [-a AUDIOBITRATE] (in k, es. -a 128)"
  echo "          [-w WIDTH [-h HEIGHT]]"
  echo "          [-o OUTFILE]"
}

while getopts ":a:w:h:s:i:o:t:" opt; do
  case $opt in
    a)
      ABR=$OPTARG
      ;;
    w)
      W=$OPTARG
      HAS_W=1
      ;;
    h)
      H=$OPTARG
      HAS_H=1
      ;;
    s)
      SIZE=$OPTARG
      ;;
    i)
      FILE=$OPTARG
      ;;
    o)
      OUTFILE=$OPTARG
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

let "WH=$HAS_W ^ $HAS_H"

if [ $WH == 1 ]; then
  echo "The -w and -h options must be declared together."
  exit
fi

if [ -z "$OUTFILE" ]; then
  EXT=`echo $FILE | awk -F . '{print $NF}'`
  BASENAME=`basename $FILE .$EXT`
  OUTFILE="$BASENAME-out-`date +"%Y%m%d%H%M%S"`.mp4"
else
  EXT=`echo $OUTFILE | awk -F . '{print $NF}'`
  BASENAME=`basename $OUTFILE .$EXT`
  OUTFILE="$BASENAME"
fi

DURATION=$(ffprobe -loglevel error -show_format -show_streams $FILE -print_format flat | grep "format.duration=" | cut -d "\"" -f 2)

VBR=$(echo "(($SIZE*8192)/$DURATION)-$ABR" | bc)
let "BUFSIZE=(VBR*2)"

let "WEBMAXSIZEPASS2=(VBR+ABR)"
let "WEBBUFSIZEPASS2=(WEBMAXSIZEPASS2*2)"

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

echo "Starting conversion"
echo "Input:           $FILE"
echo "Output:          $OUTFILE"
echo "Video width :    $W"
echo "Video height:    $H"
echo "Video duration:  $DURATION sec"
echo "Final size:      $SIZE mb"
echo "Audio bitrate:   $ABR kb/s"
echo "Video bitrate:   $VBR kb/s"
echo "Threads:         $THREADS"
echo "Codec:           $codec"
echo
echo


echo "*******************************************"
echo "*********** GENERATING MP4 FILE ***********"
echo "*******************************************"

ffmpeg -y -i $FILE -c:v ${codec} -profile:v baseline -b:v "$VBR"k -pass 1 -an -s "$W"x"$H" -pix_fmt yuv420p -threads $THREADS -f mp4 /dev/null
 
ffmpeg -y -i $FILE -c:v ${codec} -profile:v baseline -b:v "$VBR"k -s "$W"x"$H" -pass 2 -pix_fmt yuv420p -strict -2 -c:a aac -b:a "$ABR"k -movflags faststart -threads $THREADS "$OUTFILE".mp4

if [ "$webm" == "1" ]; then
  echo "********************************************"
  echo "*********** GENERATING WEBM FILE ***********"
  echo "********************************************"

  ffmpeg -i $FILE  -codec:v libvpx -quality good -cpu-used 0 -b:v "$VBR"k -qmin 10 -qmax 42 -maxrate "$VBR"k -bufsize "$BUFSIZE"k -vf scale=$W:$H -an -pass 1 -threads $THREADS -f webm /dev/null

  ffmpeg -i $FILE -codec:v libvpx -quality good -cpu-used 0 -b:v "$VBR"k -qmin 10 -qmax 42 -maxrate "$WEBMAXSIZEPASS2"k -bufsize "$WEBBUFSIZEPASS2"k -threads $THREADS -vf scale=$W:$H -codec:a libvorbis -b:a "$ABR"k -pass 2 -f webm "$OUTFILE".webm
fi

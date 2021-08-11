#!/bin/bash

_bpp=0.1
audio_bit_rate=128

width=$(ffprobe -loglevel error -show_format -show_streams $1 -print_format flat | grep "\.width=" | cut -d "=" -f 2)
height=$(ffprobe -loglevel error -show_format -show_streams $1 -print_format flat | grep "\.height=" | cut -d "=" -f 2)

_bitrate=$(ffprobe -loglevel error -show_format -show_streams $1 -print_format flat | grep "format.bit_rate=" | cut -d "\"" -f 2)
bitrate=$(echo "${_bitrate}/1024" | bc)

frame_rate=$(ffprobe -loglevel error -show_format -show_streams $1 -print_format flat | grep "r_frame_rate=" | cut -d "\"" -f 2 | head -1)

fps=$(echo "scale=2; $frame_rate" | bc -l)

echo "Width  : $width"
echo "Height : $height"
echo "bitrate: $bitrate"
echo "fps    : $fps"

bpp=$(echo "scale=2; $_bitrate/($width*$height*$frame_rate)" | bc -l)

echo "bpp    : $bpp"

bitstr1=$(echo "(426*240*${fps}*${_bpp}/1000)+${audio_bit_rate}" | bc)
bitstr2=$(echo "(640*360*${fps}*${_bpp}/1000)+${audio_bit_rate}" | bc)
bitstr3=$(echo "(852*480*${fps}*${_bpp}/1000)+${audio_bit_rate}" | bc)
bitstr4=$(echo "(1280*720*${fps}*${_bpp}/1000)+${audio_bit_rate}" | bc)
bitstr5=$(echo "(1920*1080*${fps}*${_bpp}/1000)+${audio_bit_rate}" | bc)

echo $bitstr1
echo $bitstr2
echo $bitstr3
echo $bitstr4
echo $bitstr5

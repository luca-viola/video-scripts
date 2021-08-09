#!/bin/bash

scale=2

width=$(ffprobe -loglevel error -show_format -show_streams $1 -print_format flat | grep "\.width=" | cut -d "=" -f 2)
height=$(ffprobe -loglevel error -show_format -show_streams $1 -print_format flat | grep "\.height=" | cut -d "=" -f 2)
bitrate=$(ffprobe -loglevel error -show_format -show_streams $1 -print_format flat | grep "format.bit_rate=" | cut -d "\"" -f 2)

frame_rate=$(ffprobe -loglevel error -show_format -show_streams $1 -print_format flat | grep "r_frame_rate=" | cut -d "\"" -f 2 | head -1)

fps=$(echo "scale=2; $frame_rate" | bc -l)

echo "Width  : $width"
echo "Height : $height"
echo "bitrate: $bitrate"
echo "fps    : $fps"

bpp=$(echo "scale=2; $bitrate/($width*$height*$frame_rate)" | bc -l)

echo "bpp    : $bpp"

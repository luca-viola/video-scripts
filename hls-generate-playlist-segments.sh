#!/bin/bash

source=$1
out="out"

ffmpeg -i $source -map 0  -codec:v libx264 -pix_fmt yuv420p -codec:a aac -f ssegment -segment_list playlist.m3u8  -segment_list_flags +live -segment_time 10 ${out}%03d.ts

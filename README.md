# video-scripts
Scripts to manipulate video files

## convert
Convert takes a video file as an input, and using a 2-pass 
ffmpeg encoding it can reduce it to a desired size in megabytes.
Convert can also manipulate the final audio bitrate, and
can resize the final video to a specified resolution.
The command will try to detect the number of logical
(hyperthreaded) CPUs on the machine and use it to speed up
the process. The output will be an .mp4 and .webm files,
the .mp4 will use the baseline profile and should be 
playable out of the box from chrome, edge, safari and
Android/iOS devices.

###Usage:
```
  convert -i FILENAME
          [-s SIZE] (in mega bytes, ex. -s 80)
          [-a AUDIOBITRATE] (in k, es. -a 128)
          [-w WIDTH [-h HEIGHT]]
          [-o OUTFILE]
```

## splithls
Splithls takes a video file in input and generates Http
Live Streaming data segements, with a specified duration
(default 6 seconds per segment, per Apple specification)
This will also generate a master m3u8 playlist, and two
streams with different bitrates and related folder
structure. The "-o" parameters specifies the baseline
name for the output streams, can be chosen aarbitrarily.

### Usage:
```
splithls -i FILENAME
          [-d DURATION] (in seconds per segment, ex. -d 6)
          [-o SEGMENTS BASENAME] (ex. -o out)
```


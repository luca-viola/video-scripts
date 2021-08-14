# video-scripts
Scripts to manipulate video files

## Prerequisites
To use these scripts you need to have installed the ffmpeg
package, and to have ffprobe in the path (usually comes with
ffmpeg). The scripts make usage of bash and some unix tools
(awk, bc, etc).
Tests have been made against MacOS Big Sur and Fedora 33,
the scripts work against bash version 3 (as found on MacOS)
or higher.

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
Live Streaming data segments, with a specified duration
(default 6 seconds per segment, per Apple specification)
It will  generate a master m3u8 playlist, and many
streams with different bitrates and related folder
structure. The "-o" parameters specifies the baseline
name for the output streams, can be chosen arbitrarily.

The script generates streams for the most common
vertical  resolutions (default: 240p, 360p, 480p, 720p,
1080p, 1440p, 2160p) and will calculate suitable bit rates
for each of them. The resolution list can be overridden 
with the flag **-p**. The script will calculate proper
horizontal resolutions to maintain aspect ratio, and
will round them to the nearest even number to avoid
errors with ffmpeg. It will use information from the
original video to do this. It will also keep the same
frame rate as the original video, to keep the playing
smooth. With all this information it will generate
the ffmpeg filters and video/audio stream maps to 
create HLS streams at different resolutions.

The general quality can be affected with the **-b** 
option that will set the expected *bits per pixel*:
this number will influence the bitrate calculation.

Some common values of bit per pixels are:

| BPP          | Video types and characteristics                                                                        |
| ------------ | -------------------------------------------------------------------------------------------------------|
| 0.06 or less | Low motion, static images, slideshows, no sharp scene changes => low bitrates, smaller file sizes.     |
| 0.1          | Average motion, smooth scene changes, low speed => good in most cases, files get smaller than original |
| 0.3 or more  | Fast motion, high speed, sharp scene changes, racing, sports => best quality, files tend to be larger  |


### Usage:
```
Usage:
  splithls -i /path/to/file
          [-a audiorate] (in k, ex. -a 128) [default: 128]
          [-b bits per pixel] (ex. -b 0.1  - for avg movement, slideshows)
                              (ex. -b 0.4  - for high movement, racing )
                              (ex. -b 0.06 - for low movement, static imgs)
              higher bpp means higher quality and larger files [default: 0.1]
          [-p "res1 res2 .. resn"] (vertical resolutions, es. "240 720 1080")
              [default: "240 360 480 720 1080 1440 2160"]
          [-d DURATION] (in seconds per segment, ex. -d 6)
          [-o SEGMENTS BASENAME] (ex. -o "out") [default: "stream"]
```
### Examples:

`splithls -i file.mp4`

Creates an hls master playlist with all the default vertical
resolutions, segments duration at 6 seconds default, and
0.1 bit per pixels default.

`splithls -i file.mp4 -d 4 -b 0.06 -p "360 720 1080"`

Creates an hls master playlist with three streams of
360p, 720p, 1080p. The segment duration is 4 seconds and
the quality is set for a video with low motion and no 
frequent drastic scene changes.



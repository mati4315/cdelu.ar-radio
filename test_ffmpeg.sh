#!/bin/bash
ffmpeg -y -f lavfi -i testsrc=duration=2 -map 0:v -c:v libx264 -flags +global_header -f tee "[f=matroska]/tmp/test.mkv|[f=flv]/tmp/test.flv"
echo "FFmpeg exit code: $?"

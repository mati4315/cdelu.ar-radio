#!/bin/bash
# Test ffmpeg -> curl -> source
FILE="$1"
if [ -z "$FILE" ]; then
  FILE="/opt/radio-relay/music/musica.mp3"
fi

echo "=== Probando ffmpeg -> curl ==="
ffmpeg -re -i "$FILE" -vn -f mp3 - 2>/tmp/ffmpeg-test.log | \
  curl -s -X PUT \
    -u matias4315:w35115415 \
    -H "Content-Type: application/octet-stream" \
    -H "Transfer-Encoding: chunked" \
    -T - \
    --max-time 5 \
    http://127.0.0.1:3000/source 2>/tmp/curl-test.log

echo "ffmpeg exit: ${PIPESTATUS[0]}"
echo "curl exit: ${PIPESTATUS[1]}"
echo "--- ffmpeg log ---"
cat /tmp/ffmpeg-test.log
echo "--- curl log ---"
cat /tmp/curl-test.log

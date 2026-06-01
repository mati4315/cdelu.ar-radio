#!/bin/bash
# Kill zombies and restart loop
pkill -f ffmpeg 2>/dev/null || true
pkill -f 'curl.*source' 2>/dev/null || true
sleep 1
pm2 restart radio-loop
sleep 8
echo "STATUS_CHECK:"
curl -s --max-time 5 http://127.0.0.1:3000/status

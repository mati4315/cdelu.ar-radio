#!/bin/bash
# Debug del loop.sh
source /var/www/radio/debug-loop.sh 2>/dev/null || true
MUSIC_DIR="${MUSIC_DIR:-/opt/radio-relay/music}"
ENV_FILE="${ENV_FILE:-/var/www/radio/.env}"
SOURCE_URL="${SOURCE_URL:-http://127.0.0.1:3000/source}"

SOURCE_USER=""
SOURCE_PASS=""
if [ -f "$ENV_FILE" ]; then
  while IFS='=' read -r key value; do
    case "$key" in
      SOURCE_USER) SOURCE_USER="$value" ;;
      SOURCE_PASS) SOURCE_PASS="$value" ;;
    esac
  done < <(grep -E '^(SOURCE_USER|SOURCE_PASS)=' "$ENV_FILE" 2>/dev/null || true)
fi

SOURCE_USER="${SOURCE_USER:-matias4315}"
SOURCE_PASS="${SOURCE_PASS:-w35115415}"

echo "=== DEBUG ==="
echo "ENV_FILE=$ENV_FILE"
echo "SOURCE_USER=$SOURCE_USER"
echo "SOURCE_PASS=${SOURCE_PASS:0:3}..."
echo "Auth=$(echo -n "$SOURCE_USER:$SOURCE_PASS" | base64)"
echo "Expected=$(echo -n 'matias4315:w35115415' | base64)"
echo "Matches expected: $([ "$SOURCE_USER:$SOURCE_PASS" = 'matias4315:w35115415' ] && echo YES || echo NO)"

echo "=== Curl test ==="
RESULT=$(curl -s -X PUT -u "$SOURCE_USER:$SOURCE_PASS" -H 'Content-Type: application/octet-stream' -T /dev/null --max-time 3 http://127.0.0.1:3000/source 2>&1)
echo "Result: $RESULT"
echo "Exit: $?"

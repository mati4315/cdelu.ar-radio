#!/bin/bash
# Restreamer SRT -> Facebook Live + Radio Web

ENV_FILE="${ENV_FILE:-./.env}"
SOURCE_URL="${SOURCE_URL:-http://127.0.0.1:3000/source}"
RECORDINGS_DIR="${RECORDINGS_DIR:-/opt/radio-relay/recordings}"

# Cargar credenciales desde .env
SOURCE_USER=""
SOURCE_PASS=""
SRT_PASSPHRASE=""
RECORDINGS_DIR_FROM_ENV=""
if [ -f "$ENV_FILE" ]; then
  while IFS='=' read -r key value; do
    case "$key" in
      SOURCE_USER) SOURCE_USER="$value" ;;
      SOURCE_PASS) SOURCE_PASS="$value" ;;
      SRT_PASSPHRASE) SRT_PASSPHRASE="$value" ;;
      RECORDINGS_DIR) RECORDINGS_DIR_FROM_ENV="$value" ;;
    esac
  done < <(grep -E '^(SOURCE_USER|SOURCE_PASS|SRT_PASSPHRASE|RECORDINGS_DIR)=' "$ENV_FILE" 2>/dev/null || true)
fi

if [ -z "$SOURCE_USER" ] || [ -z "$SOURCE_PASS" ]; then
  echo "ERROR: No se encontraron SOURCE_USER/SOURCE_PASS en $ENV_FILE"
  exit 1
fi

if [ -n "$RECORDINGS_DIR_FROM_ENV" ]; then
  RECORDINGS_DIR="$RECORDINGS_DIR_FROM_ENV"
fi

# --- CONFIGURAR FACEBOOK ---
FACEBOOK_URL="rtmps://live-api-s.facebook.com:443/rtmp/"
FACEBOOK_KEY="${FACEBOOK_KEY:-TU_CLAVE_DE_TRANSMISION}"

if [ "$FACEBOOK_KEY" = "TU_CLAVE_DE_TRANSMISION" ]; then
  echo "⚠️  FACEBOOK_KEY no configurada. Solo se transmitirá a la Radio Web."
fi

SRT_PORT="${SRT_PORT:-8890}"

# Construir URL SRT con o sin passphrase
if [ -n "$SRT_PASSPHRASE" ]; then
  SRT_LISTENER_URL="srt://0.0.0.0:${SRT_PORT}?mode=listener&latency=300000&passphrase=${SRT_PASSPHRASE}"
  echo "Esperando conexión SRT de OBS en el puerto $SRT_PORT (con passphrase)..."
else
  SRT_LISTENER_URL="srt://0.0.0.0:${SRT_PORT}?mode=listener&latency=300000"
  echo "Esperando conexión SRT de OBS en el puerto $SRT_PORT (sin passphrase)..."
fi

mkdir -p "$RECORDINGS_DIR"

# Bucle de reconexión automática: si ffmpeg/curl se cae, vuelve a intentarlo
while true; do
  RECORDING_FILE="${RECORDINGS_DIR}/obs-$(date +%Y-%m-%d_%H-%M-%S).mkv"
  echo "[$(date -u +%FT%TZ)] Iniciando pipeline SRT..."
  echo "Grabación local en VPS: $RECORDING_FILE"

  if [ "$FACEBOOK_KEY" != "TU_CLAVE_DE_TRANSMISION" ]; then
    ffmpeg \
      -i "${SRT_LISTENER_URL}" \
      -c copy -f flv "${FACEBOOK_URL}${FACEBOOK_KEY}" \
      -map 0:v:0 -map 0:a:0 -c copy -f matroska "$RECORDING_FILE" \
      -vn -c:a libmp3lame -b:a 128k -f mp3 - \
      2>>/tmp/ffmpeg-restream.log | \
    curl \
      -v \
      -X PUT \
      -H 'Content-Type: application/octet-stream' \
      -H 'Transfer-Encoding: chunked' \
      -H 'Connection: keep-alive' \
      --keepalive-time 30 \
      --speed-limit 0 \
      --speed-time 0 \
      --max-time 0 \
      --no-buffer \
      -u "${SOURCE_USER}:${SOURCE_PASS}" \
      -T - \
      "$SOURCE_URL" \
      2>>/tmp/curl-restream.log
  else
    ffmpeg \
      -i "${SRT_LISTENER_URL}" \
      -map 0:v:0 -map 0:a:0 -c copy -f matroska "$RECORDING_FILE" \
      -vn -c:a libmp3lame -b:a 128k -f mp3 - \
      2>>/tmp/ffmpeg-restream.log | \
    curl \
      -v \
      -X PUT \
      -H 'Content-Type: application/octet-stream' \
      -H 'Transfer-Encoding: chunked' \
      -H 'Connection: keep-alive' \
      --keepalive-time 30 \
      --speed-limit 0 \
      --speed-time 0 \
      --max-time 0 \
      --no-buffer \
      -u "${SOURCE_USER}:${SOURCE_PASS}" \
      -T - \
      "$SOURCE_URL" \
      2>>/tmp/curl-restream.log
  fi

  EXIT_CODE=$?
  echo "[$(date -u +%FT%TZ)] Pipeline terminó (código $EXIT_CODE). Reintentando en 3s..."
  sleep 3
done

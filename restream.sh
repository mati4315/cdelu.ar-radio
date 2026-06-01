#!/bin/bash
# Restreamer SRT → Facebook Live + Radio Web

ENV_FILE="${ENV_FILE:-./.env}"
SOURCE_URL="${SOURCE_URL:-http://127.0.0.1:3000/source}"

# Cargar credenciales desde .env
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

if [ -z "$SOURCE_USER" ] || [ -z "$SOURCE_PASS" ]; then
  echo "ERROR: No se encontraron SOURCE_USER/SOURCE_PASS en $ENV_FILE"
  exit 1
fi

# --- CONFIGURAR FACEBOOK ---
FACEBOOK_URL="rtmps://live-api-s.facebook.com:443/rtmp/"
FACEBOOK_KEY="${FACEBOOK_KEY:-TU_CLAVE_DE_TRANSMISION}"

if [ "$FACEBOOK_KEY" = "TU_CLAVE_DE_TRANSMISION" ]; then
  echo "⚠️  FACEBOOK_KEY no configurada. Solo se transmitirá a la Radio Web."
fi

SRT_PORT="${SRT_PORT:-8890}"

echo "Esperando conexión SRT de OBS en el puerto $SRT_PORT..."

# Bucle de reconexión automática: si ffmpeg/curl se cae, vuelve a intentarlo
while true; do
  echo "[$(date -u +%FT%TZ)] Iniciando pipeline SRT..."

  if [ "$FACEBOOK_KEY" != "TU_CLAVE_DE_TRANSMISION" ]; then
    # MODO DUAL: Facebook Live + Radio Web
    ffmpeg \
      -i "srt://0.0.0.0:${SRT_PORT}?mode=listener&latency=300000" \
      -c copy -f flv "${FACEBOOK_URL}${FACEBOOK_KEY}" \
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
    # MODO SOLO RADIO: Sin Facebook
    ffmpeg \
      -i "srt://0.0.0.0:${SRT_PORT}?mode=listener&latency=300000" \
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

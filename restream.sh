#!/bin/bash
# Restreamer SRT → Facebook Live + Radio Web

ENV_FILE="${ENV_FILE:-./.env}"
SOURCE_URL="${SOURCE_URL:-http://127.0.0.1:3000/source}"

# Cargar credenciales desde .env
SOURCE_USER=""
SOURCE_PASS=""
SRT_PASSPHRASE=""
if [ -f "$ENV_FILE" ]; then
  while IFS='=' read -r key value; do
    case "$key" in
      SOURCE_USER) SOURCE_USER="$value" ;;
      SOURCE_PASS) SOURCE_PASS="$value" ;;
      SRT_PASSPHRASE) SRT_PASSPHRASE="$value" ;;
    esac
  done < <(grep -E '^(SOURCE_USER|SOURCE_PASS|SRT_PASSPHRASE)=' "$ENV_FILE" 2>/dev/null || true)
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

# Construir URL SRT con o sin passphrase
if [ -n "$SRT_PASSPHRASE" ]; then
  SRT_LISTENER_URL="srt://0.0.0.0:${SRT_PORT}?mode=listener&latency=300000&passphrase=${SRT_PASSPHRASE}"
  echo "Esperando conexión SRT de OBS en el puerto $SRT_PORT (con passphrase)..."
else
  SRT_LISTENER_URL="srt://0.0.0.0:${SRT_PORT}?mode=listener&latency=300000"
  echo "Esperando conexión SRT de OBS en el puerto $SRT_PORT (sin passphrase)..."
fi

# Directorio de grabaciones (servido por el servidor web)
RECORDINGS_DIR="/var/www/radio/public/recordings"
mkdir -p "$RECORDINGS_DIR"

# Bucle de reconexión automática: si ffmpeg/curl se cae, vuelve a intentarlo
while true; do
  RECORDING_FILE="${RECORDINGS_DIR}/$(date +%Y-%m-%d_%H-%M-%S).mp4"
  echo "[$(date -u +%FT%TZ)] Iniciando pipeline SRT... Grabando en: $RECORDING_FILE"

  if [ "$FACEBOOK_KEY" != "TU_CLAVE_DE_TRANSMISION" ]; then
    # MODO DUAL: Facebook Live + Radio Web + Grabación
    ffmpeg \
      -i "${SRT_LISTENER_URL}" \
      -map 0 -c copy -f flv "${FACEBOOK_URL}${FACEBOOK_KEY}" \
      -map 0:a -c:a libmp3lame -b:a 128k -f mp3 - \
      -map 0 -c copy -f mp4 -movflags frag_keyframe+empty_moov+default_base_moof "$RECORDING_FILE" \
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
    # MODO SOLO RADIO: Sin Facebook + Grabación
    ffmpeg \
      -i "${SRT_LISTENER_URL}" \
      -map 0:a -c:a libmp3lame -b:a 128k -f mp3 - \
      -map 0 -c copy -f mp4 -movflags frag_keyframe+empty_moov+default_base_moof "$RECORDING_FILE" \
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

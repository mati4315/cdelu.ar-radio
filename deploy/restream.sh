#!/bin/bash
# Restreamer SRT -> Facebook Live + Radio Web + Grabacion
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
SOURCE_URL="${SOURCE_URL:-http://127.0.0.1:3000/source}"
RECORDINGS_DIR="${RECORDINGS_DIR:-/opt/radio-relay/recordings}"
SRT_PORT="${SRT_PORT:-8890}"
SRT_LATENCY="${SRT_LATENCY:-3000000}"
FACEBOOK_ENABLE="${FACEBOOK_ENABLE:-0}"

# Cargar .env
if [ -f "$ENV_FILE" ]; then
  export $(grep -E '^(SOURCE_USER|SOURCE_PASS|SRT_PASSPHRASE|RECORDINGS_DIR|FACEBOOK_KEY|FACEBOOK_KEY_2|FACEBOOK_KEY2|FACEBOOK_ENABLE|SRT_PORT|SRT_LATENCY)=' "$ENV_FILE" 2>/dev/null | xargs)
fi

SOURCE_USER="${SOURCE_USER:-}"
SOURCE_PASS="${SOURCE_PASS:-}"
SRT_PASSPHRASE="${SRT_PASSPHRASE:-}"
FACEBOOK_KEY="${FACEBOOK_KEY:-TU_CLAVE_DE_TRANSMISION}"
FACEBOOK_KEY_2="${FACEBOOK_KEY_2:-${FACEBOOK_KEY2:-}}"

if [ -z "$SOURCE_USER" ] || [ -z "$SOURCE_PASS" ]; then
  echo "ERROR: SOURCE_USER/SOURCE_PASS no configurados en $ENV_FILE"
  exit 1
fi

mkdir -p "$RECORDINGS_DIR"

# Construir URL SRT con mejor manejo de reconexion
if [ -n "$SRT_PASSPHRASE" ]; then
  SRT_LISTENER_URL="srt://0.0.0.0:${SRT_PORT}?mode=listener&latency=${SRT_LATENCY}&passphrase=${SRT_PASSPHRASE}&rcvbuf=12582912"
  echo "[$(date -u +%FT%TZ)] Escuchando SRT en puerto $SRT_PORT (passphrase: si)"
else
  SRT_LISTENER_URL="srt://0.0.0.0:${SRT_PORT}?mode=listener&latency=${SRT_LATENCY}&rcvbuf=12582912"
  echo "[$(date -u +%FT%TZ)] Escuchando SRT en puerto $SRT_PORT (passphrase: no)"
fi

RECORDING_FILE="${RECORDINGS_DIR}/obs-$(date +%Y-%m-%d_%H-%M-%S).mkv"
echo "[$(date -u +%FT%TZ)] Grabacion local: $RECORDING_FILE"

FACEBOOK_URL="rtmps://live-api-s.facebook.com:443/rtmp/"

# Construir tee de salidas opcionales
TEE_OUTPUTS="[f=matroska]$RECORDING_FILE"

if [ "$FACEBOOK_ENABLE" = "1" ] && [ "$FACEBOOK_KEY" != "TU_CLAVE_DE_TRANSMISION" ] && [ -n "$FACEBOOK_KEY" ]; then
  TEE_OUTPUTS="$TEE_OUTPUTS|[onfail=ignore:use_fifo=1:f=flv]${FACEBOOK_URL}${FACEBOOK_KEY}"
  echo "[$(date -u +%FT%TZ)] Facebook 1: CONFIGURADO (fallo no detiene la radio)"
else
  echo "[$(date -u +%FT%TZ)] Facebook 1: deshabilitado"
fi

if [ "$FACEBOOK_ENABLE" = "1" ] && [ "$FACEBOOK_KEY_2" != "TU_CLAVE_DE_TRANSMISION" ] && [ -n "$FACEBOOK_KEY_2" ]; then
  TEE_OUTPUTS="$TEE_OUTPUTS|[onfail=ignore:use_fifo=1:f=flv]${FACEBOOK_URL}${FACEBOOK_KEY_2}"
  echo "[$(date -u +%FT%TZ)] Facebook 2: CONFIGURADO (fallo no detiene la radio)"
else
  echo "[$(date -u +%FT%TZ)] Facebook 2: deshabilitado"
fi

# Configurar argumentos de redaccion para sed (evitando patrones vacios)
SED_ARGS=()
if [ -n "$FACEBOOK_KEY" ] && [ "$FACEBOOK_KEY" != "TU_CLAVE_DE_TRANSMISION" ]; then
  SED_ARGS+=("-e" "s#${FACEBOOK_KEY}#***REDACTED***#g")
fi
if [ -n "$FACEBOOK_KEY_2" ] && [ "$FACEBOOK_KEY_2" != "TU_CLAVE_DE_TRANSMISION" ]; then
  SED_ARGS+=("-e" "s#${FACEBOOK_KEY_2}#***REDACTED***#g")
fi
if [ ${#SED_ARGS[@]} -eq 0 ]; then
  SED_ARGS+=("-e" "s#dummy_pattern_to_not_match_anything#***REDACTED***#g")
fi

echo "[$(date -u +%FT%TZ)] Iniciando pipeline..."

ffmpeg \
  -hide_banner -nostats -loglevel warning \
  -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 5 \
  -i "$SRT_LISTENER_URL" \
  -map 0:v:0 -map 0:a:0 -c copy \
  -f tee "$TEE_OUTPUTS" \
  -map 0:a:0 -c:a libmp3lame -b:a 128k -f mp3 - \
  2> >(sed "${SED_ARGS[@]}" >>/tmp/ffmpeg-restream.log) | \
curl \
  --silent --show-error \
  -X PUT \
  -H 'Content-Type: application/octet-stream' \
  -H 'Transfer-Encoding: chunked' \
  -H 'Connection: keep-alive' \
  -H 'Expect:' \
  --keepalive-time 60 \
  --connect-timeout 30 \
  --max-time 0 \
  --no-buffer \
  -u "${SOURCE_USER}:${SOURCE_PASS}" \
  -T - \
  "$SOURCE_URL" \
  2>>/tmp/curl-restream.log

EXIT_CODE=$?
echo "[$(date -u +%FT%TZ)] Pipeline termino (codigo $EXIT_CODE). Reiniciando en 5s..."
sleep 5

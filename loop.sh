#!/bin/bash
# Auto-DJ - Reproduce musica automaticamente
# Lee credenciales del .env para no hardcodearlas

MUSIC_DIR="${MUSIC_DIR:-/opt/radio-relay/music}"
ENV_FILE="${ENV_FILE:-/var/www/radio/.env}"
SOURCE_URL="${SOURCE_URL:-http://127.0.0.1:3000/source}"

# Cargar credenciales desde .env (sin fallo si no existe)
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

# Verificar que se cargaron las credenciales
if [ -z "$SOURCE_USER" ] || [ -z "$SOURCE_PASS" ]; then
  echo "ERROR: No se encontraron SOURCE_USER/SOURCE_PASS en $ENV_FILE"
  echo "Asegurate de que el archivo .env existe y tiene las variables configuradas."
  exit 1
fi

while true; do
  # Buscar archivos, manejando espacios correctamente
  FILES=("$MUSIC_DIR"/*.mp3)
  if [ ${#FILES[@]} -eq 0 ] || [ ! -f "${FILES[0]}" ]; then
    echo "No se encontraron archivos MP3 en $MUSIC_DIR. Reintentando en 5 segundos..."
    sleep 5
    continue
  fi

  # Seleccionar aleatoriamente
  FILE="${FILES[RANDOM % ${#FILES[@]}]}"
  
  echo "Reproduciendo ahora: $(basename "$FILE")"
  
  # -re: leer a velocidad de tiempo real
  ffmpeg -re -i "$FILE" -vn -f mp3 - 2>/dev/null | \
    curl -s -X PUT \
      -H 'Content-Type: application/octet-stream' \
      -H 'Transfer-Encoding: chunked' \
      -u "${SOURCE_USER}:${SOURCE_PASS}" \
      -T - "$SOURCE_URL" \
      2>/dev/null || true
  
  echo "Terminó la canción, buscando la siguiente..."
  sleep 1
done

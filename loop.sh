#!/bin/bash
MUSIC_DIR="/opt/radio-relay/music"

while true; do
  # Seleccionar un archivo al azar de la carpeta de música
  FILE=$(ls "$MUSIC_DIR"/*.mp3 | shuf -n 1)
  
  if [ -z "$FILE" ]; then
    echo "No se encontraron archivos MP3 en $MUSIC_DIR. Reintentando en 5 segundos..."
    sleep 5
    continue
  fi

  echo "Reproduciendo ahora: $FILE"
  # -re: leer a velocidad de tiempo real
  # Sin -stream_loop para que pase al siguiente al terminar
  ffmpeg -re -i "$FILE" -vn -f mp3 - | curl -s -X PUT -H 'Content-Type: application/octet-stream' -H 'Transfer-Encoding: chunked' -u matias4315:w35115415 -T - http://127.0.0.1:3000/source
  
  echo "Terminó la canción, buscando la siguiente..."
  sleep 1
done

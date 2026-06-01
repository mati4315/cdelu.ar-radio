#!/bin/bash
# Test de carga de .env para loop.sh
cd /var/www/radio || exit 1
echo "=== Probando carga de .env ==="
while IFS='=' read -r key value; do
  case "$key" in
    SOURCE_USER|SOURCE_PASS)
      echo "Cargada: $key=$value"
      export "$key=$value"
      ;;
  esac
done < <(grep -E '^(SOURCE_USER|SOURCE_PASS)=' .env)

echo ""
echo "=== Variables exportadas ==="
echo "SOURCE_USER=$SOURCE_USER"
echo "SOURCE_PASS=${SOURCE_PASS:0:3}... (truncado)"
echo ""

if [ -n "$SOURCE_USER" ] && [ -n "$SOURCE_PASS" ]; then
  echo "=== Probando curl al source ==="
  curl -s -X PUT -u "$SOURCE_USER:$SOURCE_PASS" \
    -H "Content-Type: application/octet-stream" \
    -T /dev/null http://127.0.0.1:3000/source &
  CURL_PID=$!
  sleep 2
  kill $CURL_PID 2>/dev/null
  wait $CURL_PID 2>/dev/null
  echo "Curl exit code: $?"
else
  echo "ERROR: No se pudieron cargar las credenciales"
  exit 1
fi

#!/bin/bash
# Test de auth para la radio
echo "=== Test auth radio ==="
echo "Respuesta: $(curl -s -X PUT -u 'matias4315:w35115415' -H 'Content-Type: application/octet-stream' -T /dev/null --max-time 3 http://127.0.0.1:3000/source 2>&1)"
echo "Exit: $?"

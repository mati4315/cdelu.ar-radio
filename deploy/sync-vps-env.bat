@echo off
setlocal EnableExtensions

set "PROJECT_DIR=D:\RADIO\Radio web Nodejs"
set "VPS_IP=212.147.253.221"
set "SSH_KEY=%PROJECT_DIR%\upcloud_key"
set "LOCAL_ENV=%PROJECT_DIR%\.env"

if not exist "%LOCAL_ENV%" (
  echo ERROR: No se encontro "%LOCAL_ENV%"
  exit /b 1
)

echo Creando respaldo remoto de .env...
ssh -i "%SSH_KEY%" -o StrictHostKeyChecking=no root@%VPS_IP% "cd /var/www/radio && cp .env .env.backup.$(date +%%Y%%m%%d-%%H%%M%%S) 2>/dev/null || true"
if errorlevel 1 (
  echo WARNING: No se pudo crear el respaldo remoto, continuo de todos modos.
)

echo Subiendo .env al VPS...
scp -i "%SSH_KEY%" -o StrictHostKeyChecking=no "%LOCAL_ENV%" root@%VPS_IP%:/var/www/radio/.env
if errorlevel 1 (
  echo ERROR: No se pudo copiar el .env al VPS.
  exit /b 1
)

echo Verificando variables criticas en el VPS...
ssh -i "%SSH_KEY%" -o StrictHostKeyChecking=no root@%VPS_IP% "cd /var/www/radio && grep -q '^FACEBOOK_KEY=' .env && grep -q '^SRT_PASSPHRASE=' .env && grep -q '^SOURCE_USER=' .env && grep -q '^SOURCE_PASS=' .env"
if errorlevel 1 (
  echo ERROR: Falta alguna variable critica en .env.
  exit /b 1
)

echo Asegurando Facebook deshabilitado y video bitrate por defecto...
ssh -i "%SSH_KEY%" -o StrictHostKeyChecking=no root@%VPS_IP% "cd /var/www/radio && grep -q '^FACEBOOK_ENABLE=' .env || printf '\nFACEBOOK_ENABLE=0' >> .env && grep -q '^VIDEO_BITRATE=' .env || printf '\nVIDEO_BITRATE=4000k' >> .env"
if errorlevel 1 (
  echo ERROR: No se pudo asegurar FACEBOOK_ENABLE=0.
  exit /b 1
)

echo Reiniciando srt-listener y apagando Auto-DJ...
ssh -i "%SSH_KEY%" -o StrictHostKeyChecking=no root@%VPS_IP% "cd /var/www/radio && pm2 stop radio-loop && pm2 restart srt-listener --update-env && pm2 save"
if errorlevel 1 (
  echo ERROR: No se pudo reiniciar srt-listener.
  exit /b 1
)

echo Mostrando estado reciente...
ssh -i "%SSH_KEY%" -o StrictHostKeyChecking=no root@%VPS_IP% "tail -n 10 /var/log/radio/srt-output.log 2>/dev/null || true"

echo Listo. El VPS ya usa el .env local actualizado.
exit /b 0

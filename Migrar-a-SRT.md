# Guía de Migración a SRT (Secure Reliable Transport) y Restreaming

_Actualizado: Junio 2026 — Compatible con la arquitectura mejorada (ecosystem.config.cjs + .env centralizado)_

Este documento está diseñado para que una futura IA entienda el contexto y pueda implementar un sistema de **Restreaming Automático** utilizando SRT desde OBS Studio hacia el VPS, y desde el VPS hacia Facebook Live + la Radio Web Node.js.

---

## Objetivo
Reemplazar BUTT por OBS Studio utilizando el protocolo SRT para lograr una transmisión de bajísima latencia y altísima estabilidad frente a caídas de red local. 
Además, el VPS actuará como un "restreamer", ahorrando ancho de banda en la conexión local del usuario.

## Arquitectura Planeada

```
OBS Studio (PC local)
    │
    │  SRT (UDP, puerto 8890)
    ▼
VPS (ffmpeg en modo listener)
    ├──► RTMP ──► Facebook Live (video + audio)
    └──► MP3  ──► http://127.0.0.1:3000/source (solo audio → Radio Web)
```

1. **Emisor (OBS Studio en PC local):** 
   Transmite Audio + Video a través del protocolo SRT hacia la IP del VPS.
2. **Receptor/Restreamer (VPS):**
   Un proceso (usando FFMPEG en modo `listener`) recibe el stream de OBS.
3. **Distribución (VPS):**
   - **Video+Audio:** Se envía vía RTMP hacia los servidores de Facebook Live.
   - **Solo Audio:** Se convierte a MP3 y se envía vía HTTP PUT al servidor de la radio (`http://127.0.0.1:3000/source`).

### ⚠️ Importante sobre Facebook Live
**NO se necesita una app en Facebook Developers.** La clave de stream se obtiene directamente desde:
- `facebook.com/live/producer` (para perfiles personales)
- O desde tu Página de Facebook → "En vivo"

Facebook te da una URL RTMP y una clave. Eso es todo lo que necesitás.

---

## Pasos para la IA que implemente esto:

### 1. Preparar el Firewall en el VPS
Abrir el puerto UDP para SRT:
```bash
ufw allow 8890/udp
ufw reload
```

### 2. Verificar que ffmpeg soporte SRT
```bash
ffmpeg -protocols 2>&1 | grep srt
# Debería mostrar "srt" en la lista de input/output
# Si no aparece, instalar una versión más nueva:
# apt install ffmpeg   (Ubuntu 24.04+ ya lo tiene)
```

### 3. Crear el Script de Re-transmisión (`restream.sh`)
Crear en `/var/www/radio/restream.sh`. **Debe leer credenciales del `.env`**, igual que `loop.sh`:

```bash
#!/bin/bash
# Restreamer SRT → Facebook Live + Radio Web
# Lee credenciales del .env para no hardcodearlas

ENV_FILE="${ENV_FILE:-/var/www/radio/.env}"
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
# Obtener la clave desde facebook.com/live/producer
FACEBOOK_URL="rtmps://live-api-s.facebook.com:443/rtmp/"
FACEBOOK_KEY="${FACEBOOK_KEY:-TU_CLAVE_DE_TRANSMISION}"

if [ "$FACEBOOK_KEY" = "TU_CLAVE_DE_TRANSMISION" ]; then
  echo "⚠️  FACEBOOK_KEY no configurada. Solo se transmitirá a la Radio Web."
  echo "Para transmitir a Facebook, configurá FACEBOOK_KEY en el .env o exportala."
fi

SRT_PORT="${SRT_PORT:-8890}"

echo "Esperando conexión SRT de OBS en el puerto $SRT_PORT..."

if [ "$FACEBOOK_KEY" != "TU_CLAVE_DE_TRANSMISION" ]; then
  # MODO DUAL: Facebook Live + Radio Web
  ffmpeg -mode listener -i "srt://0.0.0.0:${SRT_PORT}?mode=listener&latency=300000" \
    -c copy -f flv "${FACEBOOK_URL}${FACEBOOK_KEY}" \
    -vn -c:a libmp3lame -b:a 128k -f mp3 - 2>/dev/null | \
    curl -s -X PUT \
      -H 'Content-Type: application/octet-stream' \
      -H 'Transfer-Encoding: chunked' \
      -u "${SOURCE_USER}:${SOURCE_PASS}" \
      -T - "$SOURCE_URL" \
      2>/dev/null || true
else
  # MODO SOLO RADIO: Sin Facebook
  ffmpeg -mode listener -i "srt://0.0.0.0:${SRT_PORT}?mode=listener&latency=300000" \
    -vn -c:a libmp3lame -b:a 128k -f mp3 - 2>/dev/null | \
    curl -s -X PUT \
      -H 'Content-Type: application/octet-stream' \
      -H 'Transfer-Encoding: chunked' \
      -u "${SOURCE_USER}:${SOURCE_PASS}" \
      -T - "$SOURCE_URL" \
      2>/dev/null || true
fi
```

### 4. Agregar al `ecosystem.config.cjs`
Añadir el proceso `srt-listener` al archivo `deploy/ecosystem.config.cjs`:

```javascript
// Agregar este objeto al array `apps`:
{
  name: 'srt-listener',
  script: 'restream.sh',
  autorestart: false,  // NO auto-restart — se inicia manualmente
  max_restarts: 0,
  error_file: '/var/log/radio/srt-error.log',
  out_file: '/var/log/radio/srt-output.log',
  log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
  merge_logs: true
}
```

> **NOTA:** `autorestart: false` porque el SRT listener es para uso bajo demanda.
> El usuario lo enciende cuando va a transmitir y lo apaga al terminar.

### 5. Agregar Variables al `.env` (opcionales)
```env
# SRT Restreaming (opcional, para Facebook Live)
FACEBOOK_KEY=TU_CLAVE_DE_TRANSMISION
SRT_PORT=8890
```

### 6. Actualizar el Dashboard (`public/index.html`)
La IA debe agregar un **segundo switch** en la sección de Controles de Admin:

- **Label:** "SRT Restreamer (OBS → Radio + Facebook)"
- **Descripción:** "Activalo antes de transmitir desde OBS Studio."
- **API Endpoint:** Crear `/api/srt` (POST) con acciones `start`/`stop`
- **PM2 commands:** `pm2 start srt-listener` / `pm2 stop srt-listener`

El flujo del Dashboard quedaría:
1. Apagar Auto-DJ (switch existente)
2. Encender SRT Restreamer (switch nuevo)
3. Transmitir desde OBS
4. Al terminar: apagar SRT, encender Auto-DJ

### 3. Modificar `server.js` (Timeouts y Rutas)
En `src/server.js`, es CRÍTICO permitir que la conexión espere si OBS demora en conectar:
```javascript
function isLive() {
  if (!sourceReq || !lastSeen) return false;
  // EVITAR TIMEOUT INICIAL de ffmpeg esperando a OBS:
  if (totalBytesIn === 0) return Date.now() - lastSeen <= 12 * 3600 * 1000;
  return Date.now() - lastSeen <= OFFLINE_TIMEOUT_MS;
}
```
También agregamos un endpoint `/api/srt` para controlar el relay desde la web:

```javascript
// Misma lógica que /api/autodj pero para srt-listener
app.post('/api/srt', async (request, reply) => {
  // ... parsear action igual que autodj ...
  if (action === 'start') {
    await execAsync('pm2 start srt-listener');
  } else if (action === 'stop') {
    await execAsync('pm2 stop srt-listener');
    try { await execAsync('pkill -f "ffmpeg.*srt"'); } catch(e) {}
  }
  return { success: true };
});

app.get('/api/srt/status', async (request, reply) => {
  const { stdout } = await execAsync('pm2 jlist');
  const list = JSON.parse(stdout);
  const proc = list.find(p => p.name === 'srt-listener');
  return { isRunning: proc && proc.pm2_env.status === 'online' };
});
```

---

## Configuración en OBS Studio

1. Ir a **Ajustes → Emisión (Stream)**
2. **Servicio:** Personalizado (Custom)
3. **Servidor:** `srt://radio.cdelu.io:8890?mode=caller`
4. **Clave de transmisión:** *(Dejar en blanco)*
5. Dar a "Iniciar Transmisión"

### Ajustes recomendados de OBS:
- **Codificador de Video:** x264 (si no tenés GPU) o NVENC (si tenés NVIDIA)
- **Bitrate de Video:** 2500-4000 kbps (para Facebook)
- **Codificador de Audio:** AAC
- **Bitrate de Audio:** 128-192 kbps
- **Resolución de salida:** 1280x720 (720p recomendado para Facebook)
- **FPS:** 30

### Si solo querés transmitir audio (sin video):
En OBS → **Fuentes** → eliminá toda fuente de video. Dejá solo la captura de audio.
El script del VPS igualmente extraerá solo el audio para la Radio Web.

---

## Notas Técnicas para la IA

1. **Credenciales:** SIEMPRE leerlas del `.env`. NUNCA hardcodear. El patrón está en `loop.sh`.
2. **Facebook RTMPS:** Facebook requiere `rtmps://` (RTMP seguro). FFMPEG en Ubuntu 24.04+ soporta TLS nativo. Si falla, verificar con `ffmpeg -protocols | grep tls`.
3. **`-c copy` para Facebook:** Esto evita re-codificar el video en el VPS (usa 0% de CPU extra). El video pasa intacto de OBS a Facebook.
4. **`-vn -c:a libmp3lame`:** Esto descarta el video y convierte solo el audio a MP3 para la Radio Web.
5. **Latency:** El parámetro `latency=300000` (300ms) en la URL SRT es un buen balance. Si hay cortes, subir a `500000` o `1000000`.
6. **Procesos huérfanos:** Al detener el SRT listener, ejecutar `pkill -f "ffmpeg.*srt"` para matar procesos zombie, igual que con el Auto-DJ.
7. **El server.js ya soporta SOURCE method (BUTT):** El `serverFactory` intercepta el método HTTP `SOURCE` y lo convierte a `PUT`. Si en el futuro se migra a SRT, esto sigue funcionando como fallback.
8. **Graceful shutdown ya implementado:** El `server.js` actual cierra las conexiones de listeners limpiamente al recibir SIGINT/SIGTERM.
9. **Buffer limitado:** `MAX_BUFFER_MB=50` en `.env` evita que el servidor consuma RAM infinita.

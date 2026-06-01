# Guía de Migración a SRT (Secure Reliable Transport) y Restreaming

Este documento está diseñado para que una futura IA entienda el contexto y pueda implementar un sistema de **Restreaming Automático** utilizando SRT desde OBS Studio hacia el VPS, y desde el VPS hacia Facebook Live + la Radio Web Node.js.

## Objetivo
Reemplazar BUTT por OBS Studio utilizando el protocolo SRT para lograr una transmisión de bajísima latencia y altísima estabilidad frente a caídas de red local. 
Además, el VPS actuará como un "restreamer", ahorrando ancho de banda en la conexión local del usuario.

## Arquitectura Planeada

1. **Emisor (OBS Studio en PC local):** 
   Transmite Audio + Video a través del protocolo SRT hacia la IP del VPS.
2. **Receptor/Restreamer (VPS):**
   Un proceso (usando FFMPEG en modo `listener`) recibe el stream de OBS.
3. **Distribución (VPS):**
   - **Video+Audio:** Se envía vía RTMP hacia los servidores de Facebook Live.
   - **Solo Audio:** Se convierte a MP3 y se envía vía HTTP PUT al servidor de la radio (`http://127.0.0.1:3000/source`).

## Pasos para la IA que implemente esto en el futuro:

### 1. Preparar el Firewall en el VPS
Es necesario abrir un puerto UDP para recibir el tráfico SRT. Por convención, usaremos el `8890`.
```bash
ufw allow 8890/udp
```

### 2. Crear el Script de Re-transmisión
Deberás crear un archivo llamado `restream.sh` en `/var/www/radio/` (o la ruta correspondiente):

```bash
#!/bin/bash
# --- Variables a rellenar por la IA basándose en el .env ---
FACEBOOK_URL="rtmps://live-api-s.facebook.com:443/rtmp/"
FACEBOOK_KEY="TU_CLAVE_DE_TRANSMISION_DE_FACEBOOK"
RADIO_URL="http://127.0.0.1:3000/source"
RADIO_USER="COMPLETAR_DESDE_ENV"
RADIO_PASS="COMPLETAR_DESDE_ENV"

echo "Esperando conexión SRT desde OBS en el puerto 8890..."

# FFMPEG escucha en el puerto 8890 UDP (SRT)
# - Output 1 (Facebook): Copia exacta (-c copy) a RTMP
# - Output 2 (Radio Web): Extrae solo audio (-vn), convierte a MP3 y lo envía con curl
ffmpeg -mode listener -i "srt://0.0.0.0:8890" \
  -c copy -f flv "${FACEBOOK_URL}${FACEBOOK_KEY}" \
  -vn -c:a mp3 -f mp3 - | curl -s -X PUT -H 'Content-Type: application/octet-stream' -H 'Transfer-Encoding: chunked' -u "${RADIO_USER}:${RADIO_PASS}" -T - "$RADIO_URL"
```

### 3. Gestionar el Proceso con PM2
Para que el receptor SRT esté siempre listo, se debe añadir a PM2, al igual que el Auto-DJ actual:
```bash
chmod +x restream.sh
pm2 start restream.sh --name srt-listener
pm2 save
```

### 4. Flujo de Trabajo en el Dashboard
La futura IA deberá actualizar el **Dashboard de Administración (index.html)** para tener botones que controlen PM2.
El flujo sería:
1. El usuario detiene el `radio-loop` (Auto-DJ) desde la web.
2. El usuario inicia el `srt-listener` desde la web.
3. El usuario le da a "Iniciar Transmisión" en su OBS.

### 5. Configuración en el OBS Studio del Usuario
Para conectarse a este nuevo sistema, el usuario deberá ir a **Ajustes > Emisión** en OBS:
- **Servicio:** Personalizado (Custom)
- **Servidor:** `srt://radio.cdelu.io:8890?mode=caller`
- **Clave de transmisión:** *(Dejar en blanco)*

---

### Notas técnicas para la próxima IA:
*   Asegúrate de extraer las credenciales reales del archivo `.env` del servidor antes de generar el script.
*   Facebook actualmente requiere `rtmps://` (RTMP seguro). FFMPEG compila con soporte de TLS, pero si hay problemas, sugiere usar `stunnel` o verifica la versión de ffmpeg instalada en Ubuntu.
*   El comando `ffmpeg` propuesto usa una sola entrada (`-i`) y la mapea a dos salidas sin necesidad de hardware adicional de codificación de video (ya que usamos `-c copy` para Facebook).
*   Si hay latencia al conectar OBS, puedes ajustar el buffer de SRT añadiendo `&latency=300` al enlace del servidor SRT.

# Guía Rápida: Configuración de OBS Studio (SRT + Facebook Live)

Esta guía explica cómo configurar OBS Studio para transmitir hacia el servidor VPS usando el protocolo de baja latencia SRT. El VPS luego actuará como intermediario (Restreamer), enviando la transmisión de video hacia **Facebook Live** (como principal) y extrayendo el audio en alta calidad para la **Radio Web**.

---

## 1. Configuración de Conexión (SRT)
OBS Studio cuenta con soporte nativo para SRT, por lo que **no requieres instalar plugins**.

1. Abre OBS Studio y ve a **Ajustes** -> **Emisión**.
2. **Servicio:** Selecciona `Personalizado`.
3. **Servidor:** Escribe exactamente `srt://radio.cdelu.io:8890?mode=caller`
4. **Clave de transmisión:** *(Déjalo completamente en blanco)*

---

## 2. Calidad de Transmisión (Pestaña "Salida")
Ve a **Ajustes** -> **Salida** (Asegúrate de poner el Modo de Salida en "Avanzado").

### Emisión (Video para Facebook)
* **Codificador de video:** `x264` (Procesador) o `NVENC H.264` (Si tienes placa de video NVIDIA).
* **Control de frecuencia:** `CBR`.
* **Tasa de bits (Bitrate):** Entre `2500 Kbps` y `4000 Kbps` (Recomendado para una buena calidad en Facebook sin saturar tu internet).
* **Intervalo de fotogramas clave:** `2 s` (Requisito fundamental de Facebook Live).

### Audio (Para la Radio Web)
Ve a la subpestaña **Audio**.
* **Bitrate de audio (Pista 1):** Configúralo en `128` o `192`. (Esta calidad es la que llegará a los oyentes de la página web).

---

## 3. Resolución (Pestaña "Video")
Ve a **Ajustes** -> **Video**.
* **Resolución de la base (Lienzo):** `1920x1080` (O la resolución nativa de tu pantalla).
* **Resolución de salida (Escalada):** `1280x720` (Ideal para Facebook Live, ahorra recursos y se ve excelente).
* **Valores comunes de FPS:** `30`

---

## 4. El Flujo de Trabajo (Para Salir al Aire)
Cada vez que quieras comenzar tu programa en vivo, el orden a seguir es muy sencillo:

1. Ingresa a tu **Dashboard Web** (`https://radio.cdelu.io`).
2. **Apaga** el interruptor de "Auto-DJ" (Música 24/7).
3. **Enciende** el interruptor "SRT Restreamer".
4. Ve a OBS Studio y presiona **Iniciar Transmisión**.

Al terminar tu programa:
1. Detén la transmisión en OBS.
2. En el Dashboard, **apaga** el SRT Restreamer.
3. **Enciende** el Auto-DJ para retomar la música 24/7.

> ⚠️ **Nota importante sobre Facebook:** Para que el VPS sepa hacia dónde transmitir, asegúrate de haber colocado tu clave de transmisión de Facebook en el archivo `.env` de tu servidor (`FACEBOOK_KEY=TU_CLAVE_DE_FACEBOOK`). De esta forma, transmites UNA sola vez desde tu PC, y el servidor se encarga de repartirlo a todas partes.

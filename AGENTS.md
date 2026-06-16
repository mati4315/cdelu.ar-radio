# AGENTS.md — Radio Web Node.js

Instrucciones para agentes de IA que trabajen en este proyecto.
No modifiques el comportamiento de `restream.sh` ni elimines protecciones sin confirmar.

---

## Arquitectura (VPS: 212.147.255.37)

```
OBS → SRT(8890/udp) → restream.sh (ffmpeg listener)
                         ├→ MP3 → curl PUT /source → Node → oyentes HTTP
                         ├→ MKV grabación local
                         └→ Facebook Live (opcional, FACEBOOK_ENABLE=1)
               loop.sh → ffmpeg -re → curl PUT /source (Auto-DJ)
```

- **Node app:** `radio-envivo` (PM2), puerto 3000.
- **Auto-DJ:** `radio-loop` (PM2), ejecuta `loop.sh`.
- **SRT relay:** `srt-listener` (PM2), ejecuta `restream.sh`.
- **`/source`:** endpoint PUT que recibe audio MP3. Solo puede haber UNA fuente activa.
- **Clave SRT:** `SRT_PASSPHRASE` en `.env`, debe coincidir en OBS y restream.sh.
- **Facebook:** requiere `FACEBOOK_KEY` + `FACEBOOK_ENABLE=1` en `.env`.

---

## Problema 1 — "existing source replaced by a new one" en cascada (más crítico)

**Síntoma:**
El log `/var/log/radio/output.log` muestra `source disconnected` y `existing source replaced` cada 1-2 segundos.
FFmpeg se cae con `Broken pipe` (-32).

**Causa:**
`radio-loop` (Auto-DJ) y `srt-listener` estaban activos **al mismo tiempo**.
Ambos escriben a `/source` por HTTP. El servidor Fastify reemplaza la fuente anterior, corta la conexión del otro proceso y el pipeline entero se rompe.

**Solución aplicada:**
En `src/server.js`, los endpoints `/api/autodj` y `/api/srt` ahora se excluyen mutuamente:

```js
// POST /api/srt {action:"start"} → apaga radio-loop + mata ffmpeg/curl hijos
// POST /api/autodj {action:"start"} → apaga srt-listener + mata ffmpeg hijos
```

Además `pm2 stop radio-loop` se ejecuta automáticamente al iniciar SRT.

**Regla:** NUNCA dejes `radio-loop` y `srt-listener` online al mismo tiempo.
Si alguien reporta cortes, verificá `pm2 status` primero.

---

## Problema 2 — TLS fatal alert tumba todo el pipeline

**Síntoma:**
En `/tmp/ffmpeg-restream.log` aparece `A TLS fatal alert has been received` desde Facebook,
y FFmpeg entero se cae. Al caer ffmpeg, también se corta la radio.

**Causa:**
Facebook rechaza la conexión RTMPS (clave inválida/expirada, rate limit, etc.) y ffmpeg
propaga el error a todas las salidas del tee muxer.

**Solución aplicada:**
La salida Facebook usa `onfail=ignore` en el tee muxer:

```sh
TEE_OUTPUTS="[onfail=ignore:use_fifo=1:f=flv]${FACEBOOK_URL}${FACEBOOK_KEY}|$TEE_OUTPUTS"
```

Esto hace que si Facebook falla, ffmpeg **siga** con la grabación MKV y el audio MP3.

Además Facebook se deshabilitó por defecto con `FACEBOOK_ENABLE=0` en `restream.sh`.
Para activarlo: `FACEBOOK_ENABLE=1` en `.env`.

---

## Problema 3 — CRLF en scripts Bash

**Síntoma:**
`/var/www/radio/restream.sh: line N: $'\r': command not found`

**Causa:**
Windows (CRLF) vs Linux (LF). El `.bat` de sync o SCP sube archivos con `\r\n`.

**Solución:**
Siempre ejecutar en el VPS después de subir scripts:

```bash
sed -i 's/\r$//' /var/www/radio/restream.sh /var/www/radio/deploy/restream.sh
bash -n /var/www/radio/restream.sh
```

El `deploy/sync-vps-env.bat` ahora NO sube scripts, solo `.env`.

---

## Problema 4 — Credenciales en logs

**Síntoma:**
`/tmp/curl-restream.log` contenía `Authorization: Basic <base64>` por usar `curl -v`.
`/tmp/ffmpeg-restream.log` contenía la URL completa de Facebook con la clave.

**Solución:**
- `curl` usa `--silent --show-error` en vez de `-v`.
- `ffmpeg` redirige stderr a través de `sed` que reemplaza la clave antes de escribir el log.

```sh
ffmpeg ... 2> >(sed -e "s#${FACEBOOK_KEY}#***REDACTED***#g" >>/tmp/ffmpeg-restream.log) | \
curl --silent --show-error ...
```

---

## Problema 5 — srt-listener no se reiniciaba solo

**Síntoma:**
Si el pipeline SRT se caía (por timeout, OBS desconectado, etc.), PM2 no lo levantaba.

**Causa:**
`deploy/ecosystem.config.cjs` tenía `autorestart: false`.

**Solución:**
```js
{
  name: 'srt-listener',
  script: 'restream.sh',
  autorestart: true,      // ← cambiado de false
  restart_delay: 5000,    // ← agregado
  max_restarts: 10,
  ...
}
```

---

## Problema 6 — sync-vps-env.bat inseguro

**Síntoma:**
El `.bat` subía `.env` y reiniciaba `srt-listener` sin verificar `FACEBOOK_ENABLE`
ni apagar `radio-loop`.

**Solución:**
El `.bat` ahora:
- Agrega `FACEBOOK_ENABLE=0` al `.env` remoto si falta.
- Apaga `radio-loop` antes de reiniciar `srt-listener`.
- Hace `pm2 save`.

---

## Problema 7 — Dos versiones de restream.sh

**Síntoma:**
`restream.sh` (raíz) y `deploy/restream.sh` estaban desincronizados.
PM2 ejecuta `restream.sh` desde el raíz (`cwd: /var/www/radio`).

**Solución:**
Ambos scripts ahora comparten:
- `onfail=ignore` en Facebook.
- `FACEBOOK_ENABLE` como flag de activación.
- Redacción de logs.
- `curl --silent --show-error -H 'Expect:'`.

---

## Comandos de diagnóstico rápido

```bash
# Estado general
ssh -i upcloud_key root@212.147.255.37 'pm2 status'

# ¿Hay más de una fuente?
ssh -i upcloud_key root@212.147.255.37 \
  "grep -nE 'source connected|existing source' /var/log/radio/output.log | tail -n 30"

# ¿FFmpeg tiene errores?
ssh -i upcloud_key root@212.147.255.37 'tail -n 80 /tmp/ffmpeg-restream.log'

# ¿Puertos activos?
ssh -i upcloud_key root@212.147.255.37 "ss -lunpt | grep -E ':8890|:3000'"

# Reinicio seguro por HTTP (si SSH no funciona)
curl -sS -u "user:pass" -H "Content-Type: application/json" \
  -d '{"action":"start"}' http://212.147.255.37:3000/api/srt
```

---

## Reglas de oro

1. **Nunca** `radio-loop` y `srt-listener` online al mismo tiempo.
2. **Facebook** siempre con `onfail=ignore` y `FACEBOOK_ENABLE` explícito.
3. **Nunca** `curl -v` en producción.
4. **Siempre** `sed -i 's/\r$//'` después de subir scripts desde Windows.
5. **Nunca** comitear `.env` ni `upcloud_key`.
6. Si SSH no responde, usar los endpoints HTTP `/api/srt` y `/api/autodj` para control remoto.

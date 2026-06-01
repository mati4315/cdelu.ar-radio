# Fastify Radio Relay

Relay MP3 liviano para radio online:

- `POST/PUT /source` (privado, Basic Auth): ingesta desde BUTT
- `GET /live.mp3` (público): reproducción continua
- `GET /status` (público): estado `live/offline`
- `GET /healthz` (público): health check

## 1) Desarrollo local

```bash
npm install
cp .env.example .env
npm run dev
```

Abrir: `http://localhost:3000`

## 2) Deploy en VPS Ubuntu 26.04 (Hostinger)

### 2.1 Seguridad inicial (importante)

1. Revocar la clave SSH que quedó expuesta anteriormente.
2. Crear una nueva clave en tu PC:

```bash
ssh-keygen -t ed25519 -C "radio-vps"
```

3. Cargar nueva clave al VPS (desde panel Hostinger o consola VNC).
4. Confirmar acceso SSH y luego desactivar login por password (después de validar key).

### 2.2 Instalar dependencias base

```bash
apt update && apt upgrade -y
apt install -y curl git ufw nginx certbot python3-certbot-nginx
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable
```

### 2.3 Instalar Node 20 + PM2

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
npm install -g pm2
node -v
npm -v
```

### 2.4 Subir proyecto e instalar

```bash
mkdir -p /opt/radio-relay
cd /opt/radio-relay
# sube aquí los archivos del proyecto
npm install --omit=dev
cp .env.example .env
nano .env
```

Configura `.env` con valores reales fuertes:

```env
PORT=3000
HOST=0.0.0.0
SOURCE_USER=tu_usuario_source
SOURCE_PASS=tu_password_source_muy_fuerte
STREAM_NAME=Tu Radio
OFFLINE_TIMEOUT_MS=12000
BUFFER_CHUNKS=64
```

### 2.5 Levantar app 24/7

```bash
cd /opt/radio-relay
pm2 start deploy/ecosystem.config.cjs
pm2 save
pm2 startup systemd
# Ejecuta el comando que PM2 te muestre al final
pm2 status
```

### 2.6 Nginx reverse proxy

1. Edita `deploy/nginx-radio.conf` y cambia `server_name radio.example.com;` por tu subdominio real.
2. Instala config:

```bash
cp deploy/nginx-radio.conf /etc/nginx/sites-available/radio-relay
ln -sf /etc/nginx/sites-available/radio-relay /etc/nginx/sites-enabled/radio-relay
nginx -t
systemctl reload nginx
```

### 2.7 SSL Let's Encrypt

Asegúrate que el DNS A del subdominio apunte a `212.147.255.26`.

```bash
certbot --nginx -d radio.tudominio.com
```

Renovación (automática normalmente):

```bash
systemctl status certbot.timer
```

## 3) Configurar BUTT

- Server type: Icecast / HTTP source compatible
- Address: `radio.tudominio.com`
- Port: `443`
- Mountpoint/path: `/source`
- Username: `SOURCE_USER`
- Password: `SOURCE_PASS`
- Codec: `MP3`
- Bitrate: `128 kbps`
- Channels: `Stereo`
- Auto reconnect: habilitado

## 4) Verificaciones

1. Estado:

```bash
curl -s https://radio.tudominio.com/status
```

2. Escucha:
- Web: `https://radio.tudominio.com/`
- Stream directo: `https://radio.tudominio.com/live.mp3`
- VLC: abrir URL directa

3. Logs:

```bash
pm2 logs radio-relay --lines 200
```

## 5) Operación y mantenimiento

- Reiniciar app:

```bash
pm2 restart radio-relay
```

- Ver estado:

```bash
pm2 status
```

- Actualizar deploy:

```bash
cd /opt/radio-relay
# subir cambios
npm install --omit=dev
pm2 restart radio-relay
```

## 6) Notas

- Para 1-2 oyentes, este relay en 1 vCPU/2GB es suficiente.
- Si luego crecen oyentes, conviene separar ingesta y distribución con Icecast dedicado o CDN audio.

# Guía de Deploy para VPS (Ubuntu 24.04+)

_Actualizado: Junio 2026 — Incluye deploy automatizado y mejoras de seguridad._

---

## 📋 Índice

1. [Requisitos Previos](#1-requisitos-previos)
2. [Auto-Deploy con un Solo Script (Recomendado)](#2-auto-deploy-recomendado)
3. [Deploy Manual Paso a Paso](#3-deploy-manual)
4. [Nginx + SSL](#4-nginx--ssl)
5. [Verificación](#5-verificación)
6. [Operación y Troubleshooting](#6-operación)
7. [Anexo: Mejores Prácticas de Seguridad](#7-seguridad)

---

## 1. Requisitos Previos

- **IP del VPS** (ej: `123.123.123.123`)
- **Clave SSH** — la tenés en `upcloud_key` o generá una nueva (recomendado)
- **Dominio** configurado: `radio.cdelu.io` → apuntá un **Registro A** a la IP del VPS
- **Puertos abiertos** en tu router/firewall para conectarte por SSH

### 1.1 Generar nueva clave SSH (si la anterior quedó expuesta)

```bash
ssh-keygen -t ed25519 -C "radio-vps" -f "$HOME/.ssh/radio-vps"
cat ~/.ssh/radio-vps.pub
# Copiá la pubkey al VPS (panel Hostinger → SSH keys, o VNC)
```

Probá la conexión:
```bash
ssh -i ~/.ssh/radio-vps root@TU_NUEVA_IP
```

---

## 2. Auto-Deploy 🚀 (Recomendado)

Copiá esto, ajustá las variables, y ejecutalo **en tu PC local (PowerShell)**.
Hace TODO en uno: instala deps, sube archivos, configura Nginx, SSL, firewall, PM2.

### 2.1 Configurar variables

```powershell
# ===== CONFIGURÁ ESTO =====
$VPS_IP="123.123.123.123"
$DOMAIN="radio.cdelu.io"
$SSH_KEY="D:\RADIO\Radio web Nodejs\upcloud_key"
$ADMIN_EMAIL="admin@cdelu.io"
$PROJECT_DIR="D:\RADIO\Radio web Nodejs"
```

### 2.2 Ejecutar el auto-deploy

```powershell
# 1) Preparar carpetas en el VPS
ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$VPS_IP @"
mkdir -p /var/www/radio
mkdir -p /opt/radio-relay/music
mkdir -p /var/log/radio
apt-get update -qq && apt-get install -y -qq curl git
"@

# 2) Instalar Node.js 20 + FFMPEG (si no están)
ssh -i $SSH_KEY root@$VPS_IP @'
if ! command -v node &> /dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
if ! command -v ffmpeg &> /dev/null; then
  apt-get install -y ffmpeg
fi
if ! command -v pm2 &> /dev/null; then
  npm install -g pm2
fi
'@

# 3) Subir archivos del proyecto (sin node_modules, sin música)
scp -i $SSH_KEY -r "$PROJECT_DIR\src" "$PROJECT_DIR\public" "$PROJECT_DIR\package.json" "$PROJECT_DIR\package-lock.json" "$PROJECT_DIR\.env" "$PROJECT_DIR\loop.sh" root@$VPS_IP:/var/www/radio/
scp -i $SSH_KEY -r "$PROJECT_DIR\deploy" root@$VPS_IP:/var/www/radio/

# 4) Subir música (opcional)
scp -i $SSH_KEY "$PROJECT_DIR\musica.mp3" root@$VPS_IP:/opt/radio-relay/music/

# 5) Instalar dependencias y configurar PM2 en el VPS
ssh -i $SSH_KEY root@$VPS_IP @'
cd /var/www/radio
npm install --omit=dev
chmod +x loop.sh

# Configurar PM2
pm2 start deploy/ecosystem.config.cjs
pm2 save
# El siguiente comando MUESTRA qué ejecutar para startup automático
pm2 startup systemd -u root --hp /root
eval "$(pm2 startup systemd -u root --hp /root 2>&1 | tail -1)"

# Configurar firewall
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 8890/udp
ufw --force enable

echo "=== PM2 STATUS ==="
pm2 status
'@

# 6) Instalar y configurar Nginx
ssh -i $SSH_KEY root@$VPS_IP @"
apt-get install -y nginx certbot python3-certbot-nginx

cat > /etc/nginx/sites-available/radio << 'NGINX_EOF'
server {
    listen 80;
    server_name $DOMAIN;

    # Seguridad: ocultar version de Nginx
    server_tokens off;

    # Proxy universal
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding on;
        proxy_read_timeout 1h;
        proxy_send_timeout 1h;
    }

    # Ruta específica de stream
    location = /live.mp3 {
        proxy_pass http://127.0.0.1:3000/live.mp3;
        proxy_http_version 1.1;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        add_header Cache-Control 'no-cache, no-store, must-revalidate, private' always;
        add_header X-Accel-Buffering 'no' always;
        proxy_read_timeout 1h;
        proxy_send_timeout 1h;
    }
}
NGINX_EOF

ln -sf /etc/nginx/sites-available/radio /etc/nginx/sites-enabled/radio
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

echo '=== LISTO! ==='
echo 'Ahora ejecutá Certbot manualmente:'
echo "certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $ADMIN_EMAIL"
"@

Write-Output "============================================"
Write-Output "✅ Deploy completado en VPS: $VPS_IP"
Write-Output "📡 Dashboard: http://$DOMAIN"
Write-Output "🌍 Stream:    http://$DOMAIN/live.mp3"
Write-Output "📊 Status:    http://$DOMAIN/status"
Write-Output "============================================"
Write-Output ""
Write-Output "⚠️  AHORA ejecutá el Certbot manualmente:"
Write-Output "ssh -i $SSH_KEY root@$VPS_IP 'certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $ADMIN_EMAIL'"
```

### 2.3 Configurar SSL (después de que el DNS haya propagado)

```bash
ssh -i "D:\RADIO\Radio web Nodejs\upcloud_key" root@TU_NUEVA_IP "certbot --nginx -d radio.cdelu.io --non-interactive --agree-tos -m admin@cdelu.io"
```

---

## 3. Deploy Manual

Si preferís hacerlo paso a paso:

### 3.1 SSH al servidor

```bash
ssh -i "D:\RADIO\Radio web Nodejs\upcloud_key" root@TU_NUEVA_IP
```

### 3.2 Instalar Node.js, FFMPEG, PM2

```bash
apt-get update && apt-get upgrade -y
apt-get install -y curl git ffmpeg ufw nginx certbot python3-certbot-nginx

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
npm install -g pm2

node --version    # v20.x
ffmpeg -version
```

### 3.3 Crear carpetas y subir archivos

**En el VPS:**
```bash
mkdir -p /var/www/radio
mkdir -p /opt/radio-relay/music
mkdir -p /var/log/radio
```

**Desde tu PC (PowerShell):**
```powershell
# Subir proyecto (NUNCA subir node_modules)
scp -i upcloud_key -r "D:\RADIO\Radio web Nodejs\src" "D:\RADIO\Radio web Nodejs\public" "D:\RADIO\Radio web Nodejs\package.json" "D:\RADIO\Radio web Nodejs\package-lock.json" "D:\RADIO\Radio web Nodejs\.env" "D:\RADIO\Radio web Nodejs\loop.sh" "D:\RADIO\Radio web Nodejs\deploy" root@TU_NUEVA_IP:/var/www/radio/

# Subir música (opcional)
scp -i upcloud_key "D:\RADIO\Radio web Nodejs\musica.mp3" root@TU_NUEVA_IP:/opt/radio-relay/music/
```

### 3.4 Instalar dependencias y arrancar

```bash
cd /var/www/radio
npm install --omit=dev
chmod +x loop.sh

# Iniciar con PM2 (usa el ecosystem.config)
pm2 start deploy/ecosystem.config.cjs
pm2 save
pm2 startup systemd -u root --hp /root
# Ejecutá el comando que PM2 te muestre al final
```

### 3.5 Firewall

```bash
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 8890/udp
ufw --force enable
```

---

## 4. Nginx + SSL

### 4.1 Configurar Nginx

**En el VPS:**
```bash
cat > /etc/nginx/sites-available/radio << 'EOF'
server {
    listen 80;
    server_name radio.cdelu.io;

    server_tokens off;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding on;
        proxy_read_timeout 1h;
        proxy_send_timeout 1h;
    }

    location = /live.mp3 {
        proxy_pass http://127.0.0.1:3000/live.mp3;
        proxy_http_version 1.1;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        add_header Cache-Control 'no-cache, no-store, must-revalidate, private' always;
        add_header X-Accel-Buffering 'no' always;
        proxy_read_timeout 1h;
        proxy_send_timeout 1h;
    }
}
EOF

ln -sf /etc/nginx/sites-available/radio /etc/nginx/sites-enabled/radio
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx
```

### 4.2 SSL con Certbot

```bash
certbot --nginx -d radio.cdelu.io --non-interactive --agree-tos -m admin@cdelu.io

# Verificar renovación automática
systemctl status certbot.timer
```

---

## 5. Verificación

```bash
# Health check básico
curl -s http://127.0.0.1:3000/healthz

# Status de la radio
curl -s http://127.0.0.1:3000/status | python3 -m json.tool

# Status de PM2
pm2 status

# Ver logs
pm2 logs radio-envivo --lines 50
```

**Acceder desde el navegador:**
- Dashboard: `https://radio.cdelu.io`
- Stream directo: `https://radio.cdelu.io/live.mp3`
- Status API: `https://radio.cdelu.io/status`

---

## 6. Operación

### Comandos Útiles

```bash
# Logs
pm2 logs                     # Todos los logs
pm2 logs radio-envivo        # Solo servidor
pm2 logs radio-loop          # Solo auto-DJ

# Gestión
pm2 status                   # Estado de todos los procesos
pm2 restart radio-envivo     # Reiniciar servidor
pm2 restart radio-loop       # Reiniciar música
pm2 stop radio-loop          # Detener auto-DJ
pm2 start radio-loop         # Iniciar auto-DJ
pm2 delete radio-loop && pm2 start radio-loop  # Forzar reinicio completo

# Si detenés radio-loop manualmente, matá los procesos zombies:
pm2 stop radio-loop && pkill -f "ffmpeg -re -i" && pkill -f "curl.*source" 2>/dev/null
```

### Transmitir en Vivo desde PC (OBS Studio con SRT)

> ⚠️ **Importante:** Antes de transmitir, **apagá el Auto-DJ** desde el Dashboard o con `pm2 stop radio-loop`. Luego **encendé el SRT Restreamer**.

Configuración en **OBS Studio**:
1. Entrar a Ajustes > **Emisión**.
2. **Servicio:** Personalizado.
3. **Servidor:** `srt://radio.cdelu.io:8890?mode=caller`
4. **Clave de retransmisión:** *(dejar vacío, no hace falta).*
5. Dale a **Iniciar Transmisión**. El servidor (FFMPEG) detectará la conexión automáticamente y retransmitirá a la web (y Facebook si configuraste la key).

*(Ya no se utiliza BUTT. OBS captura el audio del sistema y lo transmite directo).*

---

## 7. Troubleshooting de SRT (Problemas Frecuentes)

Si al intentar transmitir con SRT (OBS) la conexión falla o el switch se apaga:

1. **Revisar puertos UDP en el VPS:**
   Asegurate de que el puerto `8890/udp` esté abierto en el firewall del servidor (`ufw allow 8890/udp`) y también en el **panel de control de tu proveedor VPS** (Hostinger, UpCloud, etc). SRT utiliza UDP obligatoriamente.
   
2. **Timeouts en el servidor Node.js (Broken pipe):**
   Si Node.js corta la conexión por inactividad antes de que OBS envíe audio, verificá que en `src/server.js`, la función `isLive()` ignore el timeout inicial para `totalBytesIn === 0`.
   
3. **El switch se apaga solo (ffmpeg muere):**
   Verificá que en `deploy/ecosystem.config.cjs`, el proceso `srt-listener` tenga configurado `autorestart: true`. Si estaba en `false`, FFMPEG se apagaba por timeout al no recibir conexión de OBS inmediatamente y el dashboard lo reflejaba.

4. **Permisos de SSH Key (Windows):**
   Si no te podés conectar al VPS porque "Permissions are too open" en el archivo `upcloud_key`:
   ```powershell
   icacls upcloud_key /inheritance:r
   icacls upcloud_key /grant:r "$($env:USERNAME):(R)"
   ```

## 7. Seguridad

### ✅ Mejoras aplicadas en esta guía

| Aspecto | Mejora |
|---------|--------|
| **Credenciales en loop.sh** | Ya no están hardcodeadas; las lee del `.env` |
| **Grabación de .env** | En `.gitignore` — si hacés git push, no se sube |
| **Logs rotativos** | El ecosystem.config escribe logs en `/var/log/radio/` |
| **Buffer de memoria** | Limitado por `MAX_BUFFER_MB=50` para evitar OOM |
| **Graceful shutdown** | El servidor cierra conexiones limpiamente al reiniciar |
| **Server tokens off** | Nginx no revela su versión |
| **upcloud_key** | En `.gitignore` — pero mejor movela fuera del repo |

### 🔒 Checklist de seguridad VPS

- [ ] **Cambiar password root** — `passwd`
- [ ] **SSH key only** — deshabilitar login por password:
  ```bash
  sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
  systemctl restart sshd
  ```
- [ ] **UFW activo** — solo puertos 22, 80, 443
- [ ] **Actualizaciones automáticas** — `apt install unattended-upgrades -y`
- [ ] **Certificado SSL vigente** — Certbot renueva automático
- [ ] **Firewall en el VPS** (Hostinger/UpCloud panel) — mismo: solo 22, 80, 443
- [ ] **Clave SSH** — guardala en `~/.ssh/` NO en el proyecto
- [ ] **Source user/pass FUERTES** — cambiá los defaults de `.env`

---

## 🛠 Troubleshooting

### ❌ Oyentes no reciben audio
```bash
# Verificar que hay source conectado
curl -s http://127.0.0.1:3000/status | python3 -m json.tool
# Si "live: false" — el Auto-DJ está caído o no hay source
pm2 status
```

### ❌ Auto-DJ no arranca
```bash
# Verificar permisos
chmod +x /var/www/radio/loop.sh
# Probar manualmente
bash /var/www/radio/loop.sh
# Ver errores de ffmpeg/curl
pm2 logs radio-loop
```

### ❌ Certbot falla ("no A record")
```bash
dig A radio.cdelu.io
# Si no resuelve, esperá propagación DNS (hasta 24h)
# Probá con: host radio.cdelu.io
```

### ❌ 502 Bad Gateway (Nginx)
```bash
# La app de Node no está corriendo
pm2 status
pm2 logs radio-envivo --lines 20
```

---

## 📦 ¿Qué hay en el proyecto?

```
Radio web Nodejs/
├── src/server.js          ← Servidor Fastify (el relay)
├── public/index.html      ← Dashboard web
├── loop.sh                ← Auto-DJ (música 24/7)
├── package.json           ← Dependencias
├── .env                   ← Config (¡no subir a git!)
├── .env.example           ← Template de config
├── deploy/
│   ├── ecosystem.config.cjs  ← Config PM2
│   └── nginx-radio.conf      ← Template Nginx
├── upcloud_key            ← Clave SSH (¡sensible!)
└── musica.mp3             ← Música default (opcional)
```

---

*Hecho para deploy rápido en cualquier VPS Ubuntu. Si tenés que migrar, seguí la sección [Auto-Deploy](#2-auto-deploy-recomendado).*

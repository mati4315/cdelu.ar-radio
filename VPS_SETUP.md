# Guía de Deploy para VPS (Ubuntu)

Dado que cambiarás de VPS frecuentemente, aquí tienes el paso a paso exacto para configurar un nuevo servidor Ubuntu desde cero y poner a correr la radio web. Esta guía está diseñada para que cualquier asistente de IA entienda rápidamente el contexto y pueda replicar el entorno sin problemas.

## 1. Requisitos Previos
- Acceso SSH al servidor (con la clave `upcloud_key` o la que generes, ubicada en `d:\RADIO\Radio web Nodejs\upcloud_key`).
- IP del nuevo servidor.
- Dominio configurado (`radio.cdelu.io`) apuntando a la IP del nuevo servidor (Registro A). Esperar propagación DNS antes del paso de Certbot.

---

## 2. Instalación de Node.js (v20) y FFMPEG
Una vez conectado por SSH al nuevo servidor (`ssh -i "d:\RADIO\Radio web Nodejs\upcloud_key" root@TU_NUEVA_IP`), ejecuta lo siguiente para instalar Node.js y FFMPEG (necesario para transmitir música automática si la usas):

```bash
# Descargar e instalar Node.js v20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs ffmpeg

# Verificar instalación
node --version
npm --version
ffmpeg -version
```

---

## 3. Subir los Archivos del Proyecto
Desde tu PC local (PowerShell), sube los archivos de la radio y la música. **No subas la carpeta `node_modules`.**

Primero, crea las carpetas en el servidor:
```bash
ssh -i "d:\RADIO\Radio web Nodejs\upcloud_key" root@TU_NUEVA_IP "mkdir -p /var/www/radio && mkdir -p /opt/radio-relay/music"
```

Luego, desde tu PC local, copia los archivos y la música:
```powershell
# Subir la música (Opcional, si usarás la música en loop)
scp -i "d:\RADIO\Radio web Nodejs\upcloud_key" -o StrictHostKeyChecking=no "d:\RADIO\Radio web Nodejs\musica.mp3" root@TU_NUEVA_IP:/opt/radio-relay/music/

# Subir el proyecto
scp -i "d:\RADIO\Radio web Nodejs\upcloud_key" -o StrictHostKeyChecking=no -r "d:\RADIO\Radio web Nodejs\src" "d:\RADIO\Radio web Nodejs\public" "d:\RADIO\Radio web Nodejs\package.json" "d:\RADIO\Radio web Nodejs\package-lock.json" "d:\RADIO\Radio web Nodejs\.env" "d:\RADIO\Radio web Nodejs\loop.sh" root@TU_NUEVA_IP:/var/www/radio/
```

---

## 4. Instalar Dependencias y PM2
Conéctate por SSH al servidor y ejecuta:

```bash
cd /var/www/radio
npm install --production

# Instalar PM2 globalmente para mantener la app corriendo 24/7
npm install -g pm2

# Hacer el script de música ejecutable
chmod +x loop.sh

# Iniciar la aplicación de streaming
pm2 start src/server.js --name radio-envivo

# Si deseas la música de fondo en loop:
pm2 start loop.sh --name radio-loop

# Guardar la configuración para que arranque automáticamente si se reinicia el servidor
pm2 save
pm2 startup systemd -u root --hp /root
```

---

## 5. Configuración del Firewall (UFW)
Abre los puertos necesarios (SSH, HTTP, HTTPS y el puerto de tu app de Node si lo necesitas directo, ej. 3000):

```bash
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 3000/tcp
ufw --force enable
```

---

## 6. Nginx (Proxy Inverso) y HTTPS (Certbot)
Instala Nginx y Certbot para manejar el dominio (`radio.cdelu.io`) y el certificado SSL:

```bash
# Instalar Nginx y Certbot
apt-get install -y nginx certbot python3-certbot-nginx

# Crear configuración de Nginx
cat > /etc/nginx/sites-available/radio << 'EOF'
server {
    listen 80;
    server_name radio.cdelu.io;

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
    }
}
EOF

# Habilitar el sitio y reiniciar Nginx
ln -sf /etc/nginx/sites-available/radio /etc/nginx/sites-enabled/radio
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx
```

### Configurar el Certificado SSL
Una vez que el dominio (`radio.cdelu.io`) apunte correctamente a la IP y haya propagado, ejecuta:

```bash
certbot --nginx -d radio.cdelu.io --non-interactive --agree-tos -m admin@cdelu.io
```
Esto configurará automáticamente Nginx para servir HTTPS y generará los certificados.

## 7. Dashboard de Administración y Control

La aplicación ahora incluye un **Dashboard de Administración** en la ruta principal (p.ej. `https://radio.cdelu.io/`). Este panel permite interactuar con el servidor mediante una interfaz moderna:

1. **Estado en vivo:** Muestra oyentes, datos transmitidos y estado de conexión actual.
2. **Control de Auto-DJ:** Permite encender o apagar el script `radio-loop` para alternar entre música automática y transmisión en vivo desde una PC.

**Autenticación:**
Los botones del panel (como el interruptor del Auto-DJ) requieren credenciales de administrador, que deben coincidir exactamente con los valores configurados en tu archivo `.env` (`SOURCE_USER` y `SOURCE_PASS`).

**Nota sobre Procesos Huérfanos (¡IMPORTANTE!):**
Cuando se detiene `radio-loop` desde PM2, el script `loop.sh` se apaga, pero los procesos hijos (`ffmpeg` y `curl`) de Linux no mueren automáticamente (se vuelven procesos zombies). 
El Dashboard ya está modificado internamente para forzar su cierre (usando `pkill`), pero si necesitas detener el Auto-DJ **manualmente desde la consola SSH**, SIEMPRE debes ejecutar:
```bash
pm2 stop radio-loop
pkill -f "ffmpeg -re -i"
pkill -f curl
```

---

## 8. FUTURO: Transmitir en Vivo desde PC (Icecast) -> VPS
**Nota para la próxima IA:**
Actualmente el servidor transmite música mediante un script local (`loop.sh`). El usuario planea transmitir en vivo desde su PC (usando BUTT, OBS, Mixxx, etc.).

Para hacerlo, el usuario debe:
1. Entrar al Dashboard web y **apagar el Auto-DJ** (lo cual libera el origen y detiene los procesos `ffmpeg`).
2. Conectar su software desde su PC hacia la IP/URL de este VPS (actualmente el servidor acepta conexiones PUT/POST en el endpoint `/source` con Basic Auth).
3. Asegurarse de abrir en el firewall (`ufw`) el puerto necesario si a futuro se instala Icecast.

## Comandos Útiles de PM2
Si necesitas gestionar la aplicación después:
```bash
pm2 logs                    # Ver todos los logs
pm2 restart radio-envivo    # Reiniciar la radio
pm2 restart radio-loop      # Reiniciar la música
pm2 status                  # Ver estado
```

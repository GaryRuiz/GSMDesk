#!/usr/bin/env bash
# Instala el servidor GSMDesk en un VPS Ubuntu/Debian limpio.
# Uso (como root, dentro de esta carpeta):  bash instalar-ubuntu.sh
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

if command -v ufw >/dev/null 2>&1; then
  ufw allow 22/tcp
  ufw allow 21115:21119/tcp
  ufw allow 21116/udp
fi

docker compose up -d

echo "Esperando a que se genere la clave del servidor..."
for _ in $(seq 1 30); do
  [ -s data/id_ed25519.pub ] && break
  sleep 1
done

echo
echo "Servidor GSMDesk en marcha."
echo "GSMDESK_SERVER = $(curl -fsS https://api.ipify.org || echo '<IP o dominio de este VPS>')"
echo "GSMDESK_KEY    = $(cat data/id_ed25519.pub)"
echo
echo "Guarda una copia de seguridad de la carpeta data/: si pierdes id_ed25519,"
echo "todos los GSMDesk ya instalados dejarán de conectar."

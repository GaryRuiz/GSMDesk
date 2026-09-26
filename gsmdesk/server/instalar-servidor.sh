#!/usr/bin/env bash
# Instala el servidor GSMDesk (hbbs + hbbr de rustdesk-server) como servicios
# systemd, sin Docker. Sirve para un VPS limpio o para uno que ya ejecuta otros
# servicios: solo usa los puertos TCP 21115-21119 y UDP 21116, y no toca nada más
# (por ejemplo, el relay de GSM Redirector en 5580-5582 sigue igual).
#
# Uso, como root en un Ubuntu/Debian:  bash instalar-servidor.sh
set -euo pipefail

VERSION=1.1.16
ARCH=$(dpkg --print-architecture)
BASE="https://github.com/rustdesk/rustdesk-server/releases/download/${VERSION}"
DATA=/var/lib/rustdesk-server

echo "== Recursos del VPS"
echo "CPU: $(nproc) núcleos | RAM: $(free -h | awk '/^Mem:/ {print $2 " total, " $7 " libre"}') | Disco libre: $(df -h / | awk 'NR==2 {print $4}')"

echo "== Comprobando que los puertos de GSMDesk estén libres"
if systemctl is-active --quiet rustdesk-hbbs 2>/dev/null; then
  echo "GSMDesk (rustdesk-hbbs) ya está instalado; se actualizará."
elif ss -Htlnu | awk '{print $5}' | grep -Eq ':(2111[5-9])$'; then
  echo "ERROR: algún puerto entre 21115 y 21119 ya está en uso:"
  ss -tlnup | grep -E ':2111[5-9]\b' || true
  exit 1
fi

echo "== Descargando rustdesk-server ${VERSION} (${ARCH})"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for pkg in hbbr hbbs; do
  curl -fsSL -o "$tmp/${pkg}.deb" "${BASE}/rustdesk-server-${pkg}_${VERSION}_${ARCH}.deb"
done
apt-get install -y "$tmp/hbbr.deb" "$tmp/hbbs.deb"
systemctl enable --now rustdesk-hbbr rustdesk-hbbs

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  echo "== Abriendo puertos en ufw"
  ufw allow 21115:21119/tcp
  ufw allow 21116/udp
else
  echo "== ufw no está activo: abre TCP 21115-21119 y UDP 21116 en el panel del proveedor si tiene firewall."
fi

echo "== Esperando la clave del servidor"
for _ in $(seq 1 30); do
  [ -s "${DATA}/id_ed25519.pub" ] && break
  sleep 1
done
[ -s "${DATA}/id_ed25519.pub" ] || { echo "ERROR: no se generó ${DATA}/id_ed25519.pub; revisa: journalctl -u rustdesk-hbbs"; exit 1; }

echo
echo "Servidor GSMDesk en marcha."
echo "  IP pública     : $(curl -fsS https://api.ipify.org || echo '<IP de este VPS>')"
echo "  GSMDESK_KEY    : $(cat "${DATA}/id_ed25519.pub")"
echo
echo "Haz una copia de seguridad de ${DATA}/id_ed25519 y id_ed25519.pub:"
echo "si se pierden, todos los GSMDesk ya instalados dejarán de conectar."

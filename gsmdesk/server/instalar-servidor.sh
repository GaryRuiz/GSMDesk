#!/usr/bin/env bash
# Instala o actualiza el servidor GSMDesk (hbbs y hbbr parcheados) como servicios
# systemd, sin Docker ni apt. Sirve para un VPS limpio o para uno con otros servicios:
# solo usa TCP 21115-21119 y UDP 21116 y no reinicia nada más. Los dos programas
# corren con su propio usuario y con límites de memoria y de ancho de banda, para que
# un problema aquí no afecte a lo demás (por ejemplo, al relay de GSM Redirector).
#
# Uso, como root, dentro de la carpeta del artefacto "gsmdesk-server" de GitHub Actions:
#   bash instalar-servidor.sh
#
# Para conservar la llave de otro servidor GSMDesk, deja id_ed25519 e id_ed25519.pub
# en esa misma carpeta antes de ejecutarlo. Si no hay llave, se crea una nueva.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN=/opt/gsmdesk-server
DATA=/var/lib/rustdesk-server
SVC_USER=gsmdesk
# Mb/s que puede usar el relé en total y por cada sesión.
TOTAL_BANDWIDTH=200
SINGLE_BANDWIDTH=40

echo "== Recursos del VPS"
echo "CPU: $(nproc) núcleos | RAM: $(free -h | awk '/^Mem:/ {print $2 " total, " $7 " libre"}') | Disco libre: $(df -h / | awk 'NR==2 {print $4}')"

echo "== Comprobando los programas"
for prog in hbbs hbbr; do
  [ -f "$HERE/$prog" ] || { echo "ERROR: falta $HERE/$prog (artefacto gsmdesk-server)"; exit 1; }
  chmod +x "$HERE/$prog"
  "$HERE/$prog" --help >/dev/null 2>&1 || { echo "ERROR: $prog no arranca en este sistema"; exit 1; }
done

echo "== Comprobando que los puertos de GSMDesk estén libres"
if systemctl is-active --quiet rustdesk-hbbs 2>/dev/null; then
  echo "GSMDesk ya está instalado; se actualizará."
elif ss -Htlnu | awk '{print $5}' | grep -E ':2111[5-9]$' >/dev/null; then
  echo "ERROR: algún puerto entre 21115 y 21119 ya está en uso:"
  ss -tlnup | grep -E ':2111[5-9]\b' || true
  exit 1
fi

echo "== Instalando"
id "$SVC_USER" >/dev/null 2>&1 || useradd --system --home-dir "$DATA" --shell /usr/sbin/nologin "$SVC_USER"
mkdir -p "$BIN" "$DATA"
for prog in hbbs hbbr; do
  [ -f "$BIN/$prog" ] && cp -a "$BIN/$prog" "$BIN/$prog.anterior"
  install -m 755 "$HERE/$prog" "$BIN/$prog"
done

if [ -s "$HERE/id_ed25519" ] && [ -s "$HERE/id_ed25519.pub" ]; then
  if [ -s "$DATA/id_ed25519" ] && ! cmp -s "$HERE/id_ed25519" "$DATA/id_ed25519"; then
    echo "ERROR: $DATA ya tiene otra llave y reemplazarla dejaría sin conexión a los GSMDesk instalados."
    exit 1
  fi
  install -m 600 "$HERE/id_ed25519" "$DATA/id_ed25519"
  install -m 644 "$HERE/id_ed25519.pub" "$DATA/id_ed25519.pub"
fi
chown -R "$SVC_USER:$SVC_USER" "$DATA"
chmod 700 "$DATA"

write_unit() { # nombre, descripción, memoria máxima, entorno extra
  cat > "/etc/systemd/system/rustdesk-$1.service" <<EOF
[Unit]
Description=$2
After=network-online.target
Wants=network-online.target

[Service]
User=$SVC_USER
Group=$SVC_USER
ExecStart=$BIN/$1 -k _
WorkingDirectory=$DATA
LimitNOFILE=1000000
Restart=always
RestartSec=5
MemoryMax=$3
$4
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$DATA

[Install]
WantedBy=multi-user.target
EOF
}
write_unit hbbs "GSMDesk: servidor de ID" 512M ""
write_unit hbbr "GSMDesk: relé" 1G "Environment=TOTAL_BANDWIDTH=$TOTAL_BANDWIDTH SINGLE_BANDWIDTH=$SINGLE_BANDWIDTH"
systemctl daemon-reload
systemctl enable rustdesk-hbbs rustdesk-hbbr >/dev/null 2>&1
systemctl restart rustdesk-hbbs rustdesk-hbbr

if command -v ufw >/dev/null 2>&1 && ufw status | grep "Status: active" >/dev/null; then
  echo "== Abriendo puertos en ufw"
  ufw allow 21115:21117/tcp comment 'GSMDesk'
  ufw allow 21116/udp comment 'GSMDesk'
elif iptables -S INPUT 2>/dev/null | grep -- "-j REJECT" >/dev/null; then
  # Las imágenes Ubuntu de Oracle Cloud traen iptables que rechaza todo salvo SSH.
  echo "== Abriendo puertos en iptables"
  iptables -C INPUT -p tcp -m multiport --dports 21115:21119 -j ACCEPT 2>/dev/null \
    || iptables -I INPUT 1 -p tcp -m multiport --dports 21115:21119 -j ACCEPT
  iptables -C INPUT -p udp --dport 21116 -j ACCEPT 2>/dev/null \
    || iptables -I INPUT 1 -p udp --dport 21116 -j ACCEPT
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
  else
    echo "AVISO: no hay netfilter-persistent; las reglas se perderán al reiniciar."
  fi
fi
echo "== Si el proveedor tiene firewall en su panel, abre ahí también TCP 21115-21117 y UDP 21116."

echo "== Esperando la clave del servidor"
for _ in $(seq 1 30); do
  [ -s "$DATA/id_ed25519.pub" ] && break
  sleep 1
done
[ -s "$DATA/id_ed25519.pub" ] || { echo "ERROR: no se generó $DATA/id_ed25519.pub; revisa: journalctl -u rustdesk-hbbs"; exit 1; }
sleep 2
systemctl is-active rustdesk-hbbs rustdesk-hbbr

echo
echo "Servidor GSMDesk en marcha."
echo "  GSMDESK_KEY : $(cat "$DATA/id_ed25519.pub")"
echo "  Registros   : journalctl -u rustdesk-hbbs -u rustdesk-hbbr"
echo
echo "Haz una copia de seguridad de $DATA/id_ed25519 y id_ed25519.pub:"
echo "si se pierden, todos los GSMDesk ya instalados dejarán de conectar."

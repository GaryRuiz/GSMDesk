#!/usr/bin/env bash
# Publica una versión nueva para que los GSMDesk instalados se actualicen solos.
#
# Firma con la llave privada guardada en esta PC, nunca en GitHub, y crea una
# Release en GitHub con los archivos y el manifiesto firmado. Los equipos solo
# instalan lo que coincide con esa firma.
#
# Antes de publicar, sube el número en estos dos sitios y compila con ese código:
#   BUILD en src/gsmdesk_update.rs y el +N de version en flutter/pubspec.yaml
#
# Uso: gsmdesk/publicar-actualizacion.sh BUILD VERSION CARPETA_EXE CARPETA_APK "NOTAS"
set -euo pipefail

[ $# -eq 5 ] || { sed -n 2,11p "$0"; exit 1; }
BUILD=$1; VERSION=$2; EXE_DIR=$3; APK_DIR=$4; NOTES=$5
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KEY=${GSMDESK_UPDATE_KEY:-$ROOT/../firma-actualizaciones/privada.pem}
PUB=${KEY%privada.pem}publica.pem
REPO=GaryRuiz/GSMDesk
TAG=gsm-$BUILD

[ -f "$KEY" ] || { echo "ERROR: no encuentro la llave $KEY"; exit 1; }
grep -q "pub const BUILD: u64 = $BUILD;" "$ROOT/src/gsmdesk_update.rs" ||
  { echo "ERROR: BUILD en src/gsmdesk_update.rs no es $BUILD"; exit 1; }
grep -q "^version: .*+$BUILD\$" "$ROOT/flutter/pubspec.yaml" ||
  { echo "ERROR: el +N de flutter/pubspec.yaml no es $BUILD"; exit 1; }

EXE=$EXE_DIR/GSMDesk.exe
ARM64=$(ls "$APK_DIR"/GSMDesk-*-arm64.apk)
ARMV7=$(ls "$APK_DIR"/GSMDesk-*-armv7.apk)
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

python - "$OUT/manifest.json" "$BUILD" "$VERSION" "$NOTES" "$REPO" "$TAG" \
  windows-x64 "$EXE" android-arm64 "$ARM64" android-armv7 "$ARMV7" <<'PY'
import hashlib, json, os, sys
out, build, version, notes, repo, tag, *pairs = sys.argv[1:]
files = {}
for key, path in zip(pairs[::2], pairs[1::2]):
    data = open(path, 'rb').read()
    files[key] = {
        'url': f'https://github.com/{repo}/releases/download/{tag}/{os.path.basename(path)}',
        'sha256': hashlib.sha256(data).hexdigest(),
        'size': len(data),
    }
manifest = {'build': int(build), 'version': version, 'notes': notes, 'files': files}
open(out, 'w', encoding='utf-8', newline='').write(json.dumps(manifest, ensure_ascii=False))
PY

# Formato de libsodium: firma de 64 bytes seguida del mensaje.
openssl pkeyutl -sign -inkey "$KEY" -rawin -in "$OUT/manifest.json" -out "$OUT/manifest.sig"
openssl pkeyutl -verify -pubin -inkey "$PUB" -rawin -in "$OUT/manifest.json" -sigfile "$OUT/manifest.sig"
cat "$OUT/manifest.sig" "$OUT/manifest.json" > "$OUT/gsmdesk-update.bin"

cat "$OUT/manifest.json"; echo
gh release create "$TAG" -R "$REPO" --target main --latest \
  --title "GSMDesk $VERSION" --notes "$NOTES" \
  "$OUT/gsmdesk-update.bin" "$EXE" "$ARM64" "$ARMV7"
echo "Publicada: los equipos la verán la próxima vez que abran GSMDesk."

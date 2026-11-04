# GSMDesk

Programa de soporte remoto (tipo AnyDesk) para técnicos GSM, basado en
[RustDesk](https://github.com/rustdesk/rustdesk) 1.4.9.

Incluye todo lo de RustDesk: control de ratón y teclado, portapapeles en ambos
sentidos, transferencia de archivos, acceso desatendido (instalado como servicio
de Windows) y visibilidad de las ventanas de administrador (UAC).

## Qué se cambió respecto a RustDesk

Los cambios son mínimos a propósito, para poder traer las actualizaciones de
RustDesk sin conflictos.

| Archivo | Cambio |
|---|---|
| `src/gsmdesk.rs` | Nombre "GSMDesk", servidor propio fijado al compilar y valores por defecto: aceptar conexiones con clic o con contraseña fija opcional (sin contraseña de un solo uso), pantalla ajustada a la ventana y centrada, una ventana por conexión |
| `flutter/lib/desktop/pages/desktop_home_page.dart` | Ventana principal al estilo GSM Redirector: ID en letra monoespaciada, títulos de sección, tarjeta de acceso (crear/quitar contraseña fija), botón "Copiar ID", aviso de instalación, botón de modo claro/oscuro; ventana del cliente más ancha |
| `flutter/lib/common.dart` | Paleta de GSM Redirector (azul marino, rojo metálico, azul señal) en modo claro y oscuro, y sus tipografías |
| `flutter/pubspec.yaml`, `flutter/assets/fonts/` | Tipografías de la web de GSM Redirector: Chakra Petch, IBM Plex Sans e IBM Plex Mono (licencia SIL OFL, incluida) |
| `src/lang/es.rs`, `src/lang/en.rs` | Textos nuevos de GSMDesk y dos textos reescritos (`desk_tip`, `install_tip`) |
| `src/common.rs`, `src/lib.rs` | Llaman a `gsmdesk::apply()` al arrancar |
| `build.rs` | Recompila si cambian las variables `GSMDESK_*` |
| `flutter/windows/runner/Runner.rc`, `Cargo.toml`, `libs/portable/Cargo.toml` | Nombre y copyright en las propiedades del `.exe` |
| `libs/portable/src/main.rs` | Carpeta temporal `gsmdesk` en vez de `rustdesk` |
| `res/*`, `flutter/assets/*`, `flutter/windows/runner/resources/*` | Iconos y logos |
| `.github/workflows/gsmdesk-windows.yml` | Compilación de Windows en GitHub |
| `.github/workflows/gsmdesk-server.yml`, `gsmdesk/server/p2p-*.patch` | Servidor `hbbs` parcheado para P2P por UDP/IPv6 |
| `gsmdesk/` | Esta carpeta: marca, servidor y documentación |

Al llamarse "GSMDesk", RustDesk activa solo su modo de "cliente personalizado":

- Todos los textos dicen GSMDesk.
- Se instala en `C:\Program Files\GSMDesk` y el servicio de Windows se llama "GSMDesk".
- No busca actualizaciones en rustdesk.com.

## 1. Cambiar el logo

1. Pon tus imágenes en `gsmdesk/branding/source/`:
   - `icon.png`: cuadrado, mínimo 512×512, fondo transparente (**obligatorio**).
   - `logo_light.png` y `logo_dark.png`: logo horizontal para tema claro y oscuro (opcional).
2. Ejecuta `python gsmdesk/branding/apply_branding.py`.
3. Haz commit de los archivos que cambien.

El ícono actual lo dibuja `make_icon.py` (cuadro rojo metálico como GSM Redirector, monitor y teléfono con cursor). Para regenerarlo: `python gsmdesk/branding/make_icon.py` y luego `apply_branding.py`.

## 2. Montar el servidor

Necesitas un VPS con Ubuntu/Debian y los puertos **TCP 21115-21117** y **UDP 21116**
abiertos. Puede ser el mismo VPS del relay de GSM Redirector: el instalador no usa
apt ni reinicia nada más, y los servicios corren con su propio usuario y con límites
de memoria y ancho de banda.

El servidor es `rustdesk-server` con unos parches (`gsmdesk/server/*.patch`) que compila
`.github/workflows/gsmdesk-server.yml` (*Actions → GSMDesk server*):

- `p2p-hbbs.patch` y `p2p-proto.patch`: el original no reenvía los datos que hacen falta
  para el P2P por UDP/IPv6, y casi todo terminaba pasando por el relé.
- `limit-packet.patch`: limita el tamaño de los paquetes. Sin esto, un solo paquete de
  los robots que rastrean internet podía tumbar el servidor.

Descarga el artefacto `gsmdesk-server`, cópialo al VPS y ejecuta el instalador:

```bash
scp -r gsmdesk-server root@IP_DEL_VPS:/root/
ssh root@IP_DEL_VPS "cd /root/gsmdesk-server && bash instalar-servidor.sh"
```

Crea los servicios `rustdesk-hbbs` y `rustdesk-hbbr` en `/opt/gsmdesk-server` (los
registros se ven con `journalctl -u rustdesk-hbbr`). El relé solo acepta clientes con la
llave. Al final muestra `GSMDESK_KEY` (la clave pública). **Guarda una copia de
`/var/lib/rustdesk-server/id_ed25519*`**: si pierdes la clave privada, todos los GSMDesk
ya instalados dejan de conectar. Para conservar la llave de otro servidor, deja
`id_ed25519` e `id_ed25519.pub` en la carpeta antes de ejecutar el instalador.

Para comprobar el servidor desde cualquier PC:

```bash
python probar-servidor.py IP_DEL_VPS LLAVE_PUBLICA
```

Para `GSMDESK_SERVER` usa un **subdominio** (`desk.gsmvyx.com`, un registro A que apunte
al VPS, con la nube gris en Cloudflare) en vez de la IP. Así, si algún día cambias de
VPS, basta con mover el subdominio y copiar la clave; los GSMDesk ya instalados siguen
funcionando sin recompilar.

Para quitarlo: `systemctl disable --now rustdesk-hbbs rustdesk-hbbr`, borrar sus dos
archivos en `/etc/systemd/system`, y `ufw delete allow 21115:21117/tcp` y
`ufw delete allow 21116/udp`.

### Conexión directa (P2P)

GSMDesk intenta primero una conexión directa entre los dos PCs (P2P por UDP y por
IPv6) y solo usa el relé del VPS si no se puede, igual que GSM Redirector. En los
registros de `rustdesk-hbbr` se ven las conexiones que siguen usando el relé.

### Licencia (gratis y con licencia)

- **Sin licencia:** GSMDesk es gratis para atender **1 PC a la vez**. Recibir
  conexiones siempre es gratis.
- **Con licencia activa:** varias PCs a la vez (varias ventanas de control).
- La licencia es **la misma de GSM Redirector**: misma clave, misma API
  (`check_license` en `mundogsm.net/api/mundogsm-login.php`) y el mismo
  identificador de PC, calculado igual que `HardwareId.cs` del Redirector
  (`hardware_id()` en `src/gsmdesk.rs`). Así, una licencia vinculada a un PC sirve
  para los dos programas en ese PC.
- **Se activa sola** si el PC tiene GSM Redirector: GSMDesk lee la clave que guarda
  el Redirector para ese usuario de Windows (`config.dat` en `%APPDATA%\GSMRedirectorTechnician`
  o, en la v2.2, `gsmredirector.dat` junto al `.exe`), la comprueba con el servidor
  y la activa (`redirector_license_key()` en `src/gsmdesk.rs`). Si el técnico quita
  la licencia a mano, no se vuelve a activar sola.
- Código: `flutter/lib/common/gsmdesk_license.dart` (activar, comprobar cada 6 h,
  3 días de margen sin conexión) y el límite en `connectMainDesktop` (`common.dart`).
- Como GSMDesk es de código abierto (AGPL), este límite está en la app; quien
  recompile el código podría quitarlo.

## 3. Compilar para Windows (GitHub Actions)

1. El repositorio es <https://github.com/GaryRuiz/GSMDesk> (rama `main`).
2. En *Settings → Secrets and variables → Actions → Variables* crea:
   - `GSMDESK_SERVER`: IP o dominio del VPS.
   - `GSMDESK_KEY`: el contenido de `data/id_ed25519.pub`.
3. En *Actions → GSMDesk Windows → Run workflow*. Tarda unos 45-60 minutos.
4. Descarga los archivos desde la ejecución:
   - `GSMDesk.exe`: la app, como AnyDesk. El mismo archivo sirve para el técnico y
     para el cliente: recibe conexiones, conecta a otros y funciona sin instalar.
     Desde la ventana principal se puede instalar para que arranque con Windows.
   - `GSMDesk-<versión>-x86_64.msi`: instalador para desplegar en muchos PCs.

Si subes una etiqueta `v1.4.9-gsm1` (por ejemplo), se crea además una *Release* con esos archivos.

Sin `GSMDESK_SERVER`/`GSMDESK_KEY`, la compilación usa los servidores públicos de
RustDesk. Sirve solo para pruebas.

## 3b. Compilar para Android (GitHub Actions)

1. Usa las mismas variables `GSMDESK_SERVER` y `GSMDESK_KEY` del paso anterior.
2. En *Actions → GSMDesk Android → Run workflow*. Tarda unos 45-60 minutos.
3. Descarga la APK desde la ejecución:
   - `GSMDesk-<versión>-arm64.apk`: casi todos los celulares actuales.
   - `GSMDesk-<versión>-armv7.apk`: celulares antiguos de 32 bits.

### Firma de la APK

Android solo actualiza una app si la nueva APK trae la misma firma. Para eso, el
repositorio necesita estos secretos (*Settings → Secrets and variables → Actions →
Secrets*):

- `ANDROID_SIGNING_KEY`: la llave `.p12` en base64.
- `ANDROID_ALIAS`: el alias de la llave.
- `ANDROID_KEY_STORE_PASSWORD`: su contraseña.

Sin ellos la APK sale con una firma de prueba que cambia en cada compilación, así
que para instalar una versión nueva hay que desinstalar la anterior.

La llave se guarda fuera del repositorio, porque el código es público. Si se pierde,
cada celular tendrá que desinstalar GSMDesk e instalarlo de nuevo.

### Qué hace la app en el celular

- Conecta y controla PCs con GSMDesk, usando el mismo servidor.
- Recibe conexiones: un PC puede ver el celular y controlarlo. Para esto la persona
  activa el servicio en la app y da los permisos de captura de pantalla y de
  accesibilidad.
- En Android 13 o superior, las apps instaladas desde una APK tienen bloqueada la
  accesibilidad al principio. Se habilita en *Ajustes → Aplicaciones → GSMDesk →
  ⋮ → Permitir ajustes restringidos*.
- El límite de la licencia no se aplica en el celular, que abre una sesión a la vez.
- iPhone no está incluido: necesita una cuenta de desarrollador de Apple, y iOS no
  permite que otro equipo controle el teléfono.

El paquete de Android es `com.gsmdesk.app`. El código Kotlin sigue en
`com.carriez.flutter_hbb` a propósito, para que las actualizaciones de RustDesk
sigan entrando sin conflictos. El usuario no lo ve.

## 3c. Publicar una actualización

GSMDesk busca versiones nuevas al abrirse y cada 6 horas, y las descarga solo. Al
terminar aparece el botón **Actualizar** arriba, para que nunca se corte una sesión por
sorpresa. En Android el sistema pide confirmar. Una copia sin instalar en Windows no se
actualiza.

Nada llega a los equipos hasta que lo publicas:

1. Sube el número en `BUILD` de `src/gsmdesk_update.rs` y en el `+N` de `version` de
   `flutter/pubspec.yaml`. Tienen que ser iguales.
2. Compila el exe y la APK con ese código y descárgalos.
3. Pruébalos, y publica:

```bash
gsmdesk/publicar-actualizacion.sh 69 "1.4.9 (69)" CARPETA_EXE CARPETA_APK "Qué cambió"
```

El script firma un manifiesto con las sumas SHA-256 de cada archivo y crea una Release
`gsm-69` en GitHub. La app solo instala lo que coincide con esa firma, comprobada con la
clave pública de `src/gsmdesk_update.rs`.

La llave privada está en `firma-actualizaciones\privada.pem`, fuera del repositorio.
Quien la tenga puede instalar programas en todos los equipos con GSMDesk: nunca la subas
a GitHub ni la compartas. Si se pierde, los equipos dejan de actualizarse solos y hay que
instalarles a mano una versión con otra clave pública.

## 4. Traer actualizaciones de RustDesk

El remoto `upstream` ya apunta a RustDesk y `origin` a GaryRuiz/GSMDesk.

```bash
git fetch upstream --tags
git merge 1.5.0            # la etiqueta estable nueva
git submodule update --init
```

Actualiza también `VCPKG_COMMIT_ID` y las versiones del principio de
`.github/workflows/gsmdesk-windows.yml` con las de `flutter-build.yml`.

Se borraron `flutter-nightly.yml`, `flutter-tag.yml` y `fdroid.yml` (publicaban
versiones con el nombre de RustDesk cada noche o con cada etiqueta), además de
`dependabot.yml` y `FUNDING.yml`. Si un merge los vuelve a traer, bórralos otra vez
con `git rm`.

## Obligaciones de la licencia (AGPL-3.0)

- El código de GSMDesk tiene que ser público para quien reciba el programa.
  Tener este repositorio público en GitHub cumple con eso.
- No se puede quitar el crédito a RustDesk. La app muestra "Powered by RustDesk"
  y el copyright original está en las propiedades del `.exe`.
- No se puede usar el nombre ni el logo de RustDesk como marca propia.

## Pendiente

- Certificado de firma de código, para que SmartScreen y los antivirus no lo bloqueen.
- macOS y Linux: ids de paquete, iconos y compilación.
- La librería interna sigue llamándose `librustdesk.dll`. El usuario no la ve;
  el ejecutable ya sale como `GSMDesk.exe`.

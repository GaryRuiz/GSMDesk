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

Ahora mismo hay un logo provisional generado con `make_placeholder.py`.

## 2. Montar el servidor

Necesitas un VPS con Ubuntu/Debian y los puertos **TCP 21115-21119** y
**UDP 21116** abiertos. Puede ser el mismo VPS del relay de GSM Redirector:
no comparten puertos y el instalador no toca nada más.

```bash
# en el VPS, como root, copiando la carpeta gsmdesk/server
bash instalar-servidor.sh
```

Instala `rustdesk-server` como servicios systemd (`rustdesk-hbbs` y
`rustdesk-hbbr`), sin Docker. Al final muestra la IP y `GSMDESK_KEY` (la clave pública).
**Guarda una copia de `/var/lib/rustdesk-server/id_ed25519*`**: si pierdes la
clave privada, todos los GSMDesk ya instalados dejan de conectar.

Para `GSMDESK_SERVER` es mejor usar un **subdominio** (por ejemplo
`desk.mundogsm.net`, un registro A que apunte al VPS) que la IP directa. Así, si
algún día cambias de VPS, basta con mover el subdominio y copiar la clave; los
GSMDesk ya instalados siguen funcionando sin recompilar.

`docker-compose.yml` queda como alternativa para un VPS dedicado con Docker.

## 3. Compilar para Windows (GitHub Actions)

1. El repositorio es <https://github.com/GaryRuiz/GSMDesk> (rama `main`).
2. En *Settings → Secrets and variables → Actions → Variables* crea:
   - `GSMDESK_SERVER`: IP o dominio del VPS.
   - `GSMDESK_KEY`: el contenido de `data/id_ed25519.pub`.
3. En *Actions → GSMDesk Windows → Run workflow*. Tarda unos 45-60 minutos.
4. Descarga los archivos desde la ejecución:
   - `GSMDesk-<versión>-x86_64.exe`: la app completa (técnico, o para instalar en el PC del cliente).
   - `GSMDesk-<versión>-x86_64.msi`: instalador para desplegar en muchos PCs.
   - `GSMDesk-Cliente-qs-<versión>.exe`: versión para el cliente. Solo recibe
     conexiones y al abrirse pide permisos de administrador una vez, para que el
     técnico vea y acepte las ventanas de UAC sin tener que instalar nada.

Si subes una etiqueta `v1.4.9-gsm1` (por ejemplo), se crea además una *Release* con esos archivos.

Sin `GSMDESK_SERVER`/`GSMDESK_KEY`, la compilación usa los servidores públicos de
RustDesk. Sirve solo para pruebas.

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
- Android, macOS y Linux: ids de paquete (`com.carriez.*`), iconos y compilación.
- La librería interna sigue llamándose `librustdesk.dll`. El usuario no la ve;
  el ejecutable ya sale como `GSMDesk.exe`.

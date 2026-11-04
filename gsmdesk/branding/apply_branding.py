"""Generates every GSMDesk icon/logo file the build uses from ./source/.

Inputs (in ./source/):
  icon.png        required, square, at least 512x512, transparent background
  logo_light.png  optional, wide logo for light theme (shown at max 300x60)
  logo_dark.png   optional, wide logo for dark theme

Run from anywhere:  python gsmdesk/branding/apply_branding.py
Then commit the changed files.
"""

import base64
import io
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SOURCE = HERE / "source"

ICO_APP = [16, 20, 24, 32, 40, 48, 64, 128, 256]
ICO_TRAY = [16, 20, 24, 32, 48]
# density, launcher icon, adaptive foreground, notification icon (pixels)
ANDROID_DENSITIES = [
    ("mdpi", 48, 108, 24),
    ("hdpi", 72, 162, 36),
    ("xhdpi", 96, 216, 48),
    ("xxhdpi", 144, 324, 72),
    ("xxxhdpi", 192, 432, 96),
]


def fail(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def resized(im, size):
    return im.resize((size, size), Image.LANCZOS)


def save_png(im, rel, size=None):
    out = resized(im, size) if size else im
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path, optimize=True)
    print(f"  {rel}")


def save_ico(im, rel, sizes):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    resized(im, max(sizes)).save(path, format="ICO", sizes=[(s, s) for s in sizes])
    print(f"  {rel}")


def save_svg(im, rel, size=256):
    buf = io.BytesIO()
    resized(im, size).save(buf, format="PNG", optimize=True)
    data = base64.b64encode(buf.getvalue()).decode("ascii")
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
        f'width="{size}" height="{size}" viewBox="0 0 {size} {size}">'
        f'<image width="{size}" height="{size}" xlink:href="data:image/png;base64,{data}"/></svg>\n'
    )
    (ROOT / rel).write_text(svg, encoding="utf-8")
    print(f"  {rel}")


def fit_logo(im, max_w=600, max_h=120):
    """2x the on-screen 300x60 limit so it stays sharp on HiDPI screens."""
    ratio = min(max_w / im.width, max_h / im.height, 1.0)
    if ratio < 1.0:
        im = im.resize((round(im.width * ratio), round(im.height * ratio)), Image.LANCZOS)
    return im


def main():
    icon_path = SOURCE / "icon.png"
    if not icon_path.is_file():
        fail(f"missing {icon_path} (run make_placeholder.py or add your own)")
    icon = Image.open(icon_path).convert("RGBA")
    if icon.width != icon.height:
        fail(f"icon.png must be square, got {icon.width}x{icon.height}")
    if icon.width < 512:
        fail(f"icon.png must be at least 512x512, got {icon.width}x{icon.height}")

    print("Icons:")
    # Windows: exe, installer, tray, shortcuts.
    save_ico(icon, "res/icon.ico", ICO_APP)
    save_ico(icon, "res/tray-icon.ico", ICO_TRAY)
    save_ico(icon, "flutter/windows/runner/resources/app_icon.ico", ICO_APP)
    # Used for shortcut/registry icons when the app name is not "RustDesk".
    save_ico(icon, "flutter/assets/icon.ico", ICO_APP)
    # In-app icon (loadIcon prefers the PNG, SVG is the fallback).
    save_png(icon, "flutter/assets/icon.png", 512)
    save_svg(icon, "flutter/assets/icon.svg")
    # Linux / macOS packaging and docs.
    save_png(icon, "res/icon.png", 1024)
    save_png(icon, "res/mac-icon.png", 1024)
    save_png(icon, "res/32x32.png", 32)
    save_png(icon, "res/64x64.png", 64)
    save_png(icon, "res/128x128.png", 128)
    save_png(icon, "res/128x128@2x.png", 256)
    save_svg(icon, "res/scalable.svg")
    save_svg(icon, "res/logo.svg")

    print("Android:")
    res = "flutter/android/app/src/main/res/mipmap-"
    round_mask = Image.new("L", icon.size, 0)
    ImageDraw.Draw(round_mask).ellipse((0, 0, icon.width - 1, icon.height - 1), fill=255)
    tile_box = tuple(round(icon.width * v) for v in (0.04, 0.04, 0.96, 0.948))
    round_icon = icon.crop(tile_box).resize(icon.size, Image.LANCZOS)
    round_icon.putalpha(ImageChops.multiply(round_icon.getchannel("A"), round_mask))
    foreground = Image.open(SOURCE / "android_foreground.png").convert("RGBA")
    status = Image.open(SOURCE / "android_status.png").convert("RGBA")
    for dpi, launcher, fg, stat in ANDROID_DENSITIES:
        save_png(icon, f"{res}{dpi}/ic_launcher.png", launcher)
        save_png(round_icon, f"{res}{dpi}/ic_launcher_round.png", launcher)
        save_png(foreground, f"{res}{dpi}/ic_launcher_foreground.png", fg)
        save_png(status, f"{res}{dpi}/ic_stat_logo.png", stat)

    logos = {
        "logo_light.png": "flutter/assets/logo_light.png",
        "logo_dark.png": "flutter/assets/logo_dark.png",
    }
    found = [name for name in logos if (SOURCE / name).is_file()]
    if found:
        print("Logos:")
    for name in found:
        save_png(fit_logo(Image.open(SOURCE / name).convert("RGBA")), logos[name])
    # Fallback when only one variant exists.
    if found:
        save_png(
            fit_logo(Image.open(SOURCE / found[0]).convert("RGBA")), "flutter/assets/logo.png"
        )
    print("Done. Review with `git status` and commit the result.")


if __name__ == "__main__":
    main()

"""Draws the GSMDesk icon and logos into ./source/.

Same family as GSM Redirector: brushed red metal tile, white glyph and the
electric-blue "signal" colour. The glyph is a monitor with a phone in front
of it, and the phone screen shows a remote-control cursor.

Run, then apply_branding.py to spread the result to every icon file:
  python gsmdesk/branding/make_icon.py
  python gsmdesk/branding/apply_branding.py
"""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "source"
FONT = str(HERE.parents[1] / "flutter/assets/fonts/ChakraPetch-Bold.ttf")

# Brushed red metal, lit from the top (GSM Redirector's RedMetalBrush).
RED_METAL = [(0.0, (255, 112, 120)), (0.10, (222, 54, 65)), (0.55, (182, 38, 49)), (1.0, (118, 24, 32))]
SIGNAL_TOP = (92, 205, 255)
SIGNAL_BOTTOM = (14, 120, 214)
NAVY = (8, 16, 28)
WHITE = (255, 255, 255, 255)
DARK_TEXT = (11, 21, 32)
LIGHT_TEXT = (238, 244, 251)


def vertical_gradient(w, h, stops):
    col = Image.new("RGB", (1, h))
    px = col.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                k = (t - t0) / (t1 - t0)
                px[0, y] = tuple(round(a + (b - a) * k) for a, b in zip(c0, c1))
                break
    return col.resize((w, h))


def rounded_mask(size, box, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def draw_icon(size=1024):
    s = size * 4  # supersample
    icon = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    # Tile with a soft drop shadow.
    pad = int(s * 0.04)
    tile_box = (pad, pad, s - pad, s - pad - int(s * 0.012))
    radius = int(s * 0.21)
    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (tile_box[0], tile_box[1] + int(s * 0.02), tile_box[2], tile_box[3] + int(s * 0.02)),
        radius=radius, fill=(40, 0, 6, 150))
    icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(s * 0.015)))

    tw, th = tile_box[2] - tile_box[0], tile_box[3] - tile_box[1]
    tile = vertical_gradient(tw, th, RED_METAL).convert("RGBA")
    # Gloss on the upper half.
    gloss = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gloss)
    gd.ellipse((-tw * 0.35, -th * 0.95, tw * 1.35, th * 0.48), fill=(255, 255, 255, 34))
    tile.alpha_composite(gloss.filter(ImageFilter.GaussianBlur(s * 0.035)))
    # Bevel: light rim on top, dark rim at the bottom.
    rim = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle(
        (0, 0, tw - 1, th - 1), radius=radius, outline=(255, 190, 195, 120), width=int(s * 0.008))
    rim_mask = vertical_gradient(1, th, [(0, (255,)), (0.5, (0,)), (1, (0,))]).convert("L").resize((tw, th))
    tile.paste(rim, (0, 0), Image.composite(rim, Image.new("RGBA", (tw, th)), rim_mask).getchannel("A"))
    icon.paste(tile, tile_box[:2], rounded_mask((tw, th), (0, 0, tw - 1, th - 1), radius))

    icon.alpha_composite(draw_glyph(s))
    return icon.resize((size, size), Image.LANCZOS)


def draw_glyph(s):
    """Monitor and phone with a remote cursor, on a transparent s x s canvas."""
    glyph = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(glyph)
    stroke = int(s * 0.052)

    # Monitor (outline) with stand.
    mx0, my0, mx1, my1 = s * 0.19, s * 0.25, s * 0.73, s * 0.62
    d.rounded_rectangle((mx0, my0, mx1, my1), radius=s * 0.05, outline=WHITE, width=stroke)
    neck_w = s * 0.07
    cx = (mx0 + mx1) / 2
    d.rectangle((cx - neck_w / 2, my1, cx + neck_w / 2, s * 0.70), fill=WHITE)
    d.rounded_rectangle((cx - s * 0.13, s * 0.69, cx + s * 0.13, s * 0.735), radius=s * 0.02, fill=WHITE)

    # Phone in front, bottom right, with a shadow that separates it from the monitor.
    px0, py0, px1, py1 = s * 0.56, s * 0.38, s * 0.82, s * 0.83
    pr = s * 0.055
    # Cut the monitor outline around the phone so the overlap reads cleanly.
    cut = Image.new("L", (s, s), 0)
    ImageDraw.Draw(cut).rounded_rectangle(
        (px0 - s * 0.025, py0 - s * 0.025, px1 + s * 0.025, py1 + s * 0.025), radius=pr * 1.3, fill=255)
    glyph.putalpha(Image.composite(Image.new("L", (s, s), 0), glyph.getchannel("A"), cut))
    ph_shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(ph_shadow).rounded_rectangle(
        (px0 - s * 0.01, py0 + s * 0.012, px1 + s * 0.02, py1 + s * 0.03), radius=pr, fill=(30, 0, 5, 170))
    glyph.alpha_composite(ph_shadow.filter(ImageFilter.GaussianBlur(s * 0.018)))
    d = ImageDraw.Draw(glyph)
    d.rounded_rectangle((px0, py0, px1, py1), radius=pr, fill=WHITE)
    # Phone screen: signal-blue gradient.
    sx0, sy0, sx1, sy1 = px0 + s * 0.022, py0 + s * 0.06, px1 - s * 0.022, py1 - s * 0.065
    screen = vertical_gradient(int(sx1 - sx0), int(sy1 - sy0), [(0, SIGNAL_TOP), (1, SIGNAL_BOTTOM)]).convert("RGBA")
    glyph.paste(screen, (int(sx0), int(sy0)),
                rounded_mask(screen.size, (0, 0, screen.size[0] - 1, screen.size[1] - 1), s * 0.02))
    d.rounded_rectangle((px0 + (px1 - px0) * 0.38, py0 + s * 0.022, px1 - (px1 - px0) * 0.38, py0 + s * 0.036),
                        radius=s * 0.01, fill=NAVY + (255,))
    pcx = (px0 + px1) / 2
    d.ellipse((pcx - s * 0.018, py1 - s * 0.05, pcx + s * 0.018, py1 - s * 0.014), fill=NAVY + (255,))
    # Remote cursor on the phone screen.
    ax, ay, k = sx0 + (sx1 - sx0) * 0.30, sy0 + (sy1 - sy0) * 0.22, s * 0.0019
    arrow = [(0, 0), (0, 70), (17, 54), (29, 80), (41, 75), (29, 49), (51, 49)]
    d.polygon([(ax + x * k, ay + y * k) for x, y in arrow], fill=WHITE, outline=NAVY + (255,))

    return glyph


def draw_android_foreground(size=432):
    """Adaptive icon foreground: the glyph inside Android's safe zone (66/108)."""
    s = size * 4
    glyph = draw_glyph(s)
    glyph = glyph.crop(glyph.getbbox())
    # 0.50 keeps the glyph's corners inside the safe circle of 0.61.
    k = 0.50 * s / max(glyph.size)
    glyph = glyph.resize((round(glyph.width * k), round(glyph.height * k)), Image.LANCZOS)
    canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    canvas.alpha_composite(glyph, ((s - glyph.width) // 2, (s - glyph.height) // 2))
    return canvas.resize((size, size), Image.LANCZOS)


def draw_android_status_icon(size=96):
    """Notification icon: Android only uses its alpha, so white parts of the glyph."""
    glyph = draw_glyph(size * 4)
    r, g, b, a = glyph.split()
    whitish = ImageChops.darker(ImageChops.darker(r, g), b).point(lambda v: 255 if v > 200 else 0)
    white = Image.new("RGBA", glyph.size, (255, 255, 255, 0))
    white.putalpha(ImageChops.multiply(a, whitish))
    white = white.crop(white.getbbox())
    k = 0.86 * size * 4 / max(white.size)
    white = white.resize((round(white.width * k), round(white.height * k)), Image.LANCZOS)
    canvas = Image.new("RGBA", (size * 4, size * 4), (255, 255, 255, 0))
    canvas.alpha_composite(white, ((canvas.width - white.width) // 2, (canvas.height - white.height) // 2))
    return canvas.resize((size, size), Image.LANCZOS)


def draw_logo(icon, text_color, height=120):
    font = ImageFont.truetype(FONT, int(height * 0.62))
    text = "GSMDesk"
    left, top, right, bottom = font.getbbox(text)
    gap = int(height * 0.16)
    width = height + gap + (right - left) + 4
    logo = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    logo.alpha_composite(icon.resize((height, height), Image.LANCZOS))
    ImageDraw.Draw(logo).text(
        (height + gap - left, (height - (bottom - top)) / 2 - top), text, font=font, fill=text_color)
    return logo


def main():
    SOURCE.mkdir(exist_ok=True)
    icon = draw_icon()
    icon.save(SOURCE / "icon.png")
    draw_logo(icon, DARK_TEXT).save(SOURCE / "logo_light.png")
    draw_logo(icon, LIGHT_TEXT).save(SOURCE / "logo_dark.png")
    draw_android_foreground().save(SOURCE / "android_foreground.png")
    draw_android_status_icon().save(SOURCE / "android_status.png")
    print(f"Icon and logos written to {SOURCE}")


if __name__ == "__main__":
    main()

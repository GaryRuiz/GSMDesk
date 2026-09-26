"""Draws a placeholder GSMDesk icon and logo into ./source/.

Only needed until the real artwork exists: put the real files in ./source/
(same names) and run apply_branding.py instead.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "source"
FONT = "C:/Windows/Fonts/segoeuib.ttf"

TOP = (11, 61, 145)  # deep blue
BOTTOM = (0, 168, 132)  # teal green
DARK_TEXT = (17, 24, 39)
LIGHT_TEXT = (243, 244, 246)


def gradient(size):
    im = Image.new("RGB", (size, size))
    px = im.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))
    return im


def draw_icon(size=1024):
    scale = 4  # supersample for smooth edges
    s = size * scale
    bg = gradient(size).resize((s, s), Image.BILINEAR)
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, s - 1, s - 1), radius=s // 5, fill=255)
    icon = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    icon.paste(bg, (0, 0), mask)

    d = ImageDraw.Draw(icon)
    white = (255, 255, 255, 255)
    # Phone outline.
    pw, ph = s * 0.34, s * 0.60
    px0, py0 = s * 0.16, (s - ph) / 2
    d.rounded_rectangle(
        (px0, py0, px0 + pw, py0 + ph), radius=s * 0.06, outline=white, width=int(s * 0.045)
    )
    d.rounded_rectangle(
        (px0 + pw * 0.35, py0 + ph * 0.88, px0 + pw * 0.65, py0 + ph * 0.92),
        radius=s * 0.01,
        fill=white,
    )
    # Remote-signal arcs to the right of the phone.
    cx, cy = px0 + pw + s * 0.02, s / 2
    for i, r in enumerate((0.16, 0.27, 0.38)):
        rr = s * r
        d.arc(
            (cx - rr, cy - rr, cx + rr, cy + rr),
            start=-50,
            end=50,
            fill=(255, 255, 255, 255 - i * 50),
            width=int(s * 0.05),
        )
    return icon.resize((size, size), Image.LANCZOS)


def draw_logo(icon, text_color, height=120):
    font = ImageFont.truetype(FONT, int(height * 0.62))
    text = "GSMDesk"
    left, top, right, bottom = font.getbbox(text)
    gap = int(height * 0.18)
    width = height + gap + (right - left) + 4
    logo = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    logo.paste(icon.resize((height, height), Image.LANCZOS), (0, 0))
    d = ImageDraw.Draw(logo)
    d.text((height + gap - left, (height - (bottom - top)) / 2 - top), text, font=font, fill=text_color)
    return logo


def main():
    SOURCE.mkdir(exist_ok=True)
    icon = draw_icon()
    icon.save(SOURCE / "icon.png")
    draw_logo(icon, DARK_TEXT).save(SOURCE / "logo_light.png")
    draw_logo(icon, LIGHT_TEXT).save(SOURCE / "logo_dark.png")
    print(f"Placeholder artwork written to {SOURCE}")


if __name__ == "__main__":
    main()

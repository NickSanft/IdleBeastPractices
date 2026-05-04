"""Generate 64x64 placeholder PNGs for currency icons.

These are intentionally simple (flat color disc + letter glyph) so that
the *shape* of an icon exists in the build while final art is being
commissioned. Replace the .png files in `assets/sprites/icons/` directly
with hand-drawn art keeping the same dimensions and the same filenames.

Re-running this script overwrites the placeholders in place.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


SIZE = 64
OUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "sprites" / "icons"

# (filename, fill_color, ring_color, glyph_color, glyph)
ICONS = [
    ("coin.png",          (212, 175,  55, 255), (110,  80,  20, 255), ( 50,  35,   8, 255), "G"),
    ("rancher_point.png", (180, 200, 230, 255), ( 60,  90, 140, 255), ( 25,  40,  80, 255), "R"),
    ("prestige.png",      (170,  60,  90, 255), ( 90,  20,  40, 255), (250, 230, 220, 255), "P"),
]


def _try_font() -> ImageFont.ImageFont | ImageFont.FreeTypeFont:
    candidates = [
        "C:/Windows/Fonts/georgiab.ttf",
        "C:/Windows/Fonts/timesbd.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, 38)
    return ImageFont.load_default()


def _draw_icon(filename: str, fill, ring, glyph_color, glyph: str) -> Path:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse((2, 2, SIZE - 2, SIZE - 2), fill=fill, outline=ring, width=3)
    font = _try_font()
    bbox = draw.textbbox((0, 0), glyph, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(
        ((SIZE - tw) / 2 - bbox[0], (SIZE - th) / 2 - bbox[1] - 1),
        glyph,
        fill=glyph_color,
        font=font,
    )
    out = OUT_DIR / filename
    img.save(out, "PNG")
    return out


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for filename, fill, ring, glyph_color, glyph in ICONS:
        out = _draw_icon(filename, fill, ring, glyph_color, glyph)
        print(f"wrote {out}")


if __name__ == "__main__":
    main()

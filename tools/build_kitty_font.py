#!/usr/bin/env python3
"""Rasterize the configured Geist Mono font for the FPGA's 8x16 cell ROM."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT = Path.home() / ".local/share/fonts/GeistMono/GeistMonoNerdFontMono-Regular.otf"
OUTPUT = ROOT / "software/baremetal/kitty_ui/kitty_font.hex"


def main():
    font = ImageFont.truetype(str(FONT), 13)
    rows = []
    for code in range(256):
        glyph = Image.new("L", (8, 16), 0)
        if 32 <= code <= 126:
            draw = ImageDraw.Draw(glyph)
            bbox = draw.textbbox((0, 0), chr(code), font=font)
            width = bbox[2] - bbox[0]
            x = (8 - width) // 2 - bbox[0]
            y = (16 - (bbox[3] - bbox[1])) // 2 - bbox[1]
            draw.text((x, y), chr(code), font=font, fill=255)
        for y in range(16):
            word = 0
            for x in range(8):
                word = (word << 4) | ((glyph.getpixel((x, y)) + 8) // 17)
            rows.append(f"{word:08x}")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(rows) + "\n")
    print(OUTPUT)


if __name__ == "__main__":
    main()

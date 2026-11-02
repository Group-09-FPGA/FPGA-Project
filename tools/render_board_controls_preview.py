#!/usr/bin/env python3
"""Render control-page fixtures with the actual RTL character selection/font."""
import argparse
import subprocess
from pathlib import Path

from PIL import Image


def main():
    repo = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=repo / "build/ui_preview")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    program = output / "preview.vvp"
    subprocess.run([
        "iverilog", "-g2001", "-s", "tb_board_ui_text", "-o", str(program),
        str(repo / "rtl/ui/board_ui_text.v"),
        str(repo / "rtl/display/vga_top.v"),
        str(repo / "sim/unit/tb_board_ui_text.v"),
    ], check=True)
    subprocess.run(["vvp", "-N", str(program)], cwd=output, check=True)
    for page in range(1, 8):
        glyphs = [int(word, 16) for word in
                  (output / f"ui_page{page}.glyph").read_text().splitlines()]
        picture = Image.new("RGB", (640, 480), (0, 17, 34))
        pixels = picture.load()
        for cell in range(40 * 30):
            x, y = (cell % 40) * 16, (cell // 40) * 16
            color = ((102, 255, 187) if page == 7 and cell // 40 in (5, 18)
                     else (221, 221, 221))
            for gy in range(8):
                bits = glyphs[cell * 8 + gy]
                for gx in range(8):
                    if bits & (128 >> gx):
                        for dy in range(2):
                            for dx in range(2):
                                pixels[x + gx * 2 + dx, y + gy * 2 + dy] = color
        picture.save(output / f"ui_page{page}.png")
    print(f"VGA control-page previews: {output}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Builds Tests/Fixtures/sample.djvu: three pages with a hidden text layer,
a nested outline and a page title. Needs Pillow and the DjVuLibre command
line tools (cjb2, c44, djvm, djvused), e.g. `brew install djvulibre` or
`apt install djvulibre-bin`.

Page 1 - bitonal text page (JB2), Ukrainian text
Page 2 - color page (IW44) with a gradient and text
Page 3 - bitonal text page, Russian and English text, title "iii"
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

DPI = 200
W, H = 1166, 1654  # A5 at 200 dpi
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "sample.djvu")

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/Library/Fonts/Arial Unicode.ttf",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
]


def font(size):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    sys.exit("No Cyrillic font found; edit FONT_CANDIDATES.")


def draw_page(lines, color=False):
    """Draws lines of text and returns (image, text-layer s-expression)."""
    if color:
        img = Image.new("RGB", (W, H))
        px = img.load()
        for y in range(H):
            for x in range(0, W, 2):
                c = (235 - y * 60 // H, 225 - x * 40 // W, 200 + y * 40 // H)
                px[x, y] = c
                if x + 1 < W:
                    px[x + 1, y] = c
    else:
        img = Image.new("1", (W, H), 1)
    d = ImageDraw.Draw(img)
    ink = (20, 20, 40) if color else 0

    sx_lines = []
    y = 120
    for text, size in lines:
        f = font(size)
        x = 100
        words = []
        line_top, line_bottom = None, None
        for word in text.split(" "):
            l, t, r, b = d.textbbox((x, y), word, font=f)
            d.text((x, y), word, font=f, fill=ink)
            words.append((l, t, r, b, word))
            line_top = t if line_top is None else min(line_top, t)
            line_bottom = b if line_bottom is None else max(line_bottom, b)
            x = r + int(size * 0.35)
        # DjVu text boxes: xmin ymin xmax ymax with y growing upwards.
        def box(l, t, r, b):
            return f"{l} {H - b} {r} {H - t}"
        words_sx = " ".join(
            f'(word {box(l, t, r, b)} "{w}")' for (l, t, r, b, w) in words
        )
        lx0, lx1 = words[0][0], words[-1][2]
        sx_lines.append(f"(line {box(lx0, line_top, lx1, line_bottom)} {words_sx})")
        y = line_bottom + int(size * 0.8)
    sexpr = f"(page 0 0 {W} {H} " + " ".join(sx_lines) + ")"
    return img, sexpr


PAGES = [
    (
        [
            ("Розділ 1. Вступ", 64),
            ("Це тестова сторінка DjVu", 40),
            ("з прихованим текстовим шаром.", 40),
            ("Пошук: ґанок, їжак, єнот", 40),
        ],
        False,
    ),
    (
        [
            ("Розділ 2. Кольорова сторінка", 56),
            ("Фон закодовано IW44", 40),
        ],
        True,
    ),
    (
        [
            ("Глава 3. Русский текст", 56),
            ("English words on the same page", 40),
        ],
        False,
    ),
]

OUTLINE = (
    '(bookmarks ("Розділ 1. Вступ" "#1") '
    '("Розділ 2. Кольорова сторінка" "#2" ("Підрозділ 2.1" "#2")) '
    '("Глава 3" "#3"))'
)


def run(*cmd):
    subprocess.run(cmd, check=True)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        page_files = []
        script = []
        for i, (lines, color) in enumerate(PAGES, start=1):
            img, sexpr = draw_page(lines, color)
            txt = os.path.join(tmp, f"p{i}.txt")
            with open(txt, "w", encoding="utf-8") as fh:
                fh.write(sexpr + "\n")
            out = os.path.join(tmp, f"p{i}.djvu")
            if color:
                src = os.path.join(tmp, f"p{i}.ppm")
                img.save(src)
                run("c44", "-dpi", str(DPI), src, out)
            else:
                src = os.path.join(tmp, f"p{i}.pbm")
                img.save(src)
                run("cjb2", "-dpi", str(DPI), src, out)
            page_files.append(out)
            script.append(f"select {i}; set-txt {txt}")
        run("djvm", "-c", OUT, *page_files)
        outline_file = os.path.join(tmp, "outline.txt")
        with open(outline_file, "w", encoding="utf-8") as fh:
            fh.write(OUTLINE + "\n")
        script.append(f"set-outline {outline_file}")
        script.append('select 3; set-page-title "iii"')
        run("djvused", OUT, "-e", "; ".join(script) + "; save")
    print("wrote", OUT, os.path.getsize(OUT), "bytes")


if __name__ == "__main__":
    main()

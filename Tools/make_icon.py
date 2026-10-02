#!/usr/bin/env python3
"""Draws the app icon (placeholder until a designed one exists) into
Resources/Assets.xcassets/AppIcon.appiconset. Needs Pillow."""
import json
import os

from PIL import Image, ImageDraw, ImageFilter

S = 2048  # drawn large, then scaled down for clean edges
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Resources", "Assets.xcassets", "AppIcon.appiconset")


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def squircle_mask(size, inset, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (inset, inset, size - inset, size - inset), radius=radius, fill=255)
    return mask


def draw():
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    inset, radius = 200, 370  # macOS grid: 824/1024 body, ~22.5 % corner radius

    # Soft drop shadow under the body.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (inset, inset + 24, S - inset, S - inset + 24), radius=radius, fill=(0, 0, 0, 120))
    icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)))

    # Graphite body with a gentle vertical gradient.
    body = Image.new("RGBA", (S, S))
    top, bottom = (52, 56, 64), (26, 28, 33)
    px = body.load()
    for y in range(S):
        c = lerp(top, bottom, y / S) + (255,)
        for x in range(S):
            px[x, y] = c
    icon.paste(body, (0, 0), squircle_mask(S, inset, radius))

    d = ImageDraw.Draw(icon)
    cx, cy = S // 2, S // 2 + 40
    paper = (240, 233, 218, 255)
    ink = (128, 120, 106, 255)

    # Open book: two pages meeting at the spine with a slight V.
    left = [(cx - 560, cy - 330), (cx - 18, cy - 270), (cx - 18, cy + 400), (cx - 560, cy + 340)]
    right = [(cx + 18, cy - 270), (cx + 560, cy - 330), (cx + 560, cy + 340), (cx + 18, cy + 400)]
    book_shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(book_shadow).polygon(
        [(cx - 570, cy - 300), (cx + 570, cy - 300), (cx + 570, cy + 380), (cx, cy + 440), (cx - 570, cy + 380)],
        fill=(0, 0, 0, 140))
    icon.alpha_composite(book_shadow.filter(ImageFilter.GaussianBlur(30)))
    d = ImageDraw.Draw(icon)
    d.polygon(left, fill=paper)
    d.polygon(right, fill=paper)
    # Shade along the spine, blended on its own layer.
    shade = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for i in range(70):
        alpha = int(90 * (1 - i / 70) ** 2)
        for side in (-1, 1):
            x = cx + side * (18 + i)
            sd.line([(x, cy - 270 - i * 60 // 540), (x, cy + 400 - i * 60 // 540)],
                    fill=(150, 138, 116, alpha), width=1)
    icon.alpha_composite(shade)
    d = ImageDraw.Draw(icon)

    # Lines of text on both pages; every third line is shorter, like a paragraph end.
    for row in range(9):
        y0 = cy - 200 + row * 62
        for side in (-1, 1):
            xa, xb = sorted((cx + side * 470, cx + side * 110))
            if row % 3 == 2:
                xb -= 90 + (row * 37) % 120  # text runs left to right on both pages
            d.rounded_rectangle((xa, y0 - 9, xb, y0 + 9), radius=9, fill=ink)

    # Amber ribbon bookmark hanging over the right page.
    rx = cx + 300
    ribbon = [(rx - 46, cy - 312), (rx + 46, cy - 318), (rx + 46, cy + 470), (rx, cy + 420), (rx - 46, cy + 476)]
    d.polygon(ribbon, fill=(222, 164, 58, 255))
    d.line([(rx + 46, cy - 318), (rx + 46, cy + 470)], fill=(176, 122, 34, 255), width=10)
    return icon


def main():
    os.makedirs(OUT, exist_ok=True)
    master = draw()
    slots = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
    images = []
    for size, scale in slots:
        px = size * scale
        name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{size}x{size}"})
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
    with open(os.path.join(OUT, "..", "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
    print("icons written to", os.path.normpath(OUT))


if __name__ == "__main__":
    main()

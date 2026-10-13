"""Add titles to the raw launch renders and write the upload-ready files.

Run after shots.py: python blender/launch/finish.py [out_dir]
Writes thumbnail_*.png (1920x1080, titled), thumbnail_*_clean.png (no text), icon_512.png and
loading_screen.png into renders/final/ (or out_dir).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "renders", "raw")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "renders", "final")

FONT_DIRS = ["/usr/share/fonts/opentype/inter", "/Library/Fonts", "/System/Library/Fonts/Supplemental"]
INK = (40, 34, 28)
WHITE = (255, 255, 255)
HAY = (236, 214, 150)


def font(names, size):
    for d in FONT_DIRS:
        for n in names:
            p = os.path.join(d, n)
            if os.path.exists(p):
                return ImageFont.truetype(p, size)
    return ImageFont.load_default(size)


TITLE = ["Inter-Black.otf", "InterDisplay-Black.otf", "Inter-ExtraBold.otf"]
SUB = ["Inter-ExtraBold.otf", "Inter-Bold.otf"]

# shot: (title, subtitle, anchor x 0..1, anchor y 0..1, align)
TEXT = {
    "haul": ("NEEDLEWOOD", "HAUL HAY. FIND THE NEEDLES.", 0.70, 0.15, "mm"),
    "factory": ("BUILD YOUR BALE LINE", "BELTS, SORTERS AND SILOS ON YOUR OWN LAND", 0.30, 0.13, "mm"),
    "field": ("SMASH. RAKE. SORT.", "EVERY BALE HIDES NEEDLES", 0.5, 0.12, "mm"),
    "needles": ("FIND RARE NEEDLES", "COSMIC, CLOUD AND OBSIDIAN GLOW IN THE HAY", 0.5, 0.86, "mm"),
}


def shadowed_text(img, xy, text, f, fill, stroke=8, anchor="mm"):
    """White text with a dark ink stroke and a soft drop shadow (STYLE.md UI text)."""
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(shadow)
    d.text((xy[0] + 6, xy[1] + 8), text, font=f, fill=(0, 0, 0, 150), anchor=anchor,
           stroke_width=stroke, stroke_fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(8))
    img.alpha_composite(shadow)
    d = ImageDraw.Draw(img)
    d.text(xy, text, font=f, fill=fill, anchor=anchor, stroke_width=stroke, stroke_fill=INK)


def fit_font(names, text, max_w, size):
    while size > 20:
        f = font(names, size)
        if f.getbbox(text)[2] <= max_w:
            return f
        size -= 4
    return font(names, size)


def grade(img):
    """Gentle warm vignette so the eye lands in the middle."""
    w, h = img.size
    v = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(v)
    d.ellipse((-w * 0.25, -h * 0.35, w * 1.25, h * 1.35), fill=255)
    v = v.filter(ImageFilter.GaussianBlur(w // 10))
    dark = Image.new("RGBA", (w, h), (30, 22, 14, 255))
    return Image.composite(img, Image.blend(img, dark, 0.35), v)


def main():
    os.makedirs(OUT, exist_ok=True)
    for i, (name, (title, sub, ax, ay, _)) in enumerate(TEXT.items(), 1):
        img = grade(Image.open(os.path.join(RAW, name + ".png")).convert("RGBA"))
        img.convert("RGB").save(os.path.join(OUT, f"thumbnail_{i}_{name}_clean.png"))
        w, h = img.size
        tf = fit_font(TITLE, title, w * 0.52, int(h * 0.13))
        sf = fit_font(SUB, sub, w * 0.6, int(h * 0.04))
        x, y = w * ax, h * ay
        shadowed_text(img, (x, y), title, tf, WHITE, stroke=max(6, tf.size // 14))
        shadowed_text(img, (x, y + tf.size * 0.78), sub, sf, HAY, stroke=5)
        img.convert("RGB").save(os.path.join(OUT, f"thumbnail_{i}_{name}.png"))
        print("wrote", name)

    icon = Image.open(os.path.join(RAW, "icon.png")).convert("RGBA")
    icon = grade(icon).resize((512, 512), Image.LANCZOS)
    icon.convert("RGB").save(os.path.join(OUT, "icon_512.png"))

    load = Image.open(os.path.join(RAW, "loading.png")).convert("RGB")
    load.save(os.path.join(OUT, "loading_screen.png"))
    print("done", OUT)


if __name__ == "__main__":
    main()

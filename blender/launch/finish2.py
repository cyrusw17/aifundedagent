"""Title and package the second batch (shots2.py): world and event thumbnails, the regions collage,
icon A/B/C variants and Robux store art. Run after shots2.py: python blender/launch/finish2.py [out_dir]
"""
import os
import sys

from PIL import Image, ImageDraw

import finish as F

RAW = F.RAW
OUT = sys.argv[1] if len(sys.argv) > 1 else F.OUT

TEXT = {
    "ferry": ("SAIL THE STITCHED ISLES", "FERRY YOUR TRUCK TO NEW REGIONS", 0.5, 0.12),
    "rich": ("RICH FIELD!", "2X NEEDLES WHERE THE GOLD BEAM FALLS", 0.5, 0.12),
    "burst": ("BREAK THE BALE", "A GLINT IN THE HAY MEANS A NEEDLE", 0.68, 0.14),
    "worldmap": ("HAUL ACROSS THE ISLES", "MEADOW TO VOLCANO, SNOW PEAK TO SKY ISLAND", 0.5, 0.88),
    "winter": ("WINTER HARVEST", "SNOWY BALES AND FESTIVE LIGHTS", 0.70, 0.15),
    "harvest": ("HARVEST FESTIVAL", "PUMPKINS, GOLD LEAVES AND BUMPER BALES", 0.70, 0.15),
    "halloween": ("HAUNTED HAYRIDE", "GHOST NEEDLES GLOW AFTER DARK", 0.70, 0.15),
}
REGIONS = [("meadow", "MEADOW"), ("pine", "PINE FOREST"), ("desert", "DESERT DUNES"), ("snow", "SNOW PEAK"),
           ("swamp", "SWAMP"), ("volcano", "VOLCANO"), ("haunted", "HAUNTED GROVE"), ("sky", "SKY ISLAND")]
STORE = ["homestead_classic", "timber_wolf", "midnight_express", "prairie_schooner", "founders_semi"]
PASSES = ["vip", "auto_dock", "big_silo", "paint_studio", "plot_themes", "truck_radio", "hay_fever", "meteor_shower",
          "harvest_pass"]


def titled(name, title, sub, ax, ay, out_name):
    img = F.grade(Image.open(os.path.join(RAW, name + ".png")).convert("RGBA"))
    img.convert("RGB").save(os.path.join(OUT, out_name + "_clean.png"))
    w, h = img.size
    tf = F.fit_font(F.TITLE, title, w * (0.52 if ax != 0.5 else 0.8), int(h * 0.12))
    sf = F.fit_font(F.SUB, sub, w * (0.52 if ax != 0.5 else 0.7), int(h * 0.04))
    F.shadowed_text(img, (w * ax, h * ay), title, tf, F.WHITE, stroke=max(6, tf.size // 14))
    F.shadowed_text(img, (w * ax, h * ay + tf.size * 0.78), sub, sf, F.HAY, stroke=5)
    img.convert("RGB").save(os.path.join(OUT, out_name + ".png"))


def regions_collage():
    W, H = 1920, 1080
    out = Image.new("RGBA", (W, H), F.INK + (255,))
    cw, ch = W // 4, H // 2
    for i, (rid, label) in enumerate(REGIONS):
        p = os.path.join(RAW, "region_" + rid + ".png")
        im = Image.open(p).convert("RGBA")
        scale = max(cw / im.width, ch / im.height)
        im = im.resize((int(im.width * scale) + 1, int(im.height * scale) + 1), Image.LANCZOS)
        left, top = (im.width - cw) // 2, (im.height - ch) // 2
        im = im.crop((left, top, left + cw, top + ch))
        x, y = (i % 4) * cw, (i // 4) * ch
        out.paste(im, (x, y))
        f = F.fit_font(F.SUB, label, cw * 0.86, 40)
        ly = y + 44 if i < 4 else y + ch - 40  # top row labels at the top, clear of the centre title
        F.shadowed_text(out, (x + cw / 2, ly), label, f, F.WHITE, stroke=5)
    d = ImageDraw.Draw(out)
    for k in range(1, 4):
        d.line([(k * cw, 0), (k * cw, H)], fill=F.INK, width=6)
    d.line([(0, ch), (W, ch)], fill=F.INK, width=6)
    out = out.convert("RGBA")
    tf = F.fit_font(F.TITLE, "EVERY REGION, ITS OWN HAY", W * 0.7, 110)
    F.shadowed_text(out, (W / 2, ch), "EVERY REGION, ITS OWN HAY", tf, F.WHITE, stroke=10)
    out.convert("RGB").save(os.path.join(OUT, "thumbnail_9_regions.png"))


def square(name, out_name, size=512):
    im = F.grade(Image.open(os.path.join(RAW, name + ".png")).convert("RGBA"))
    s = min(im.size)
    im = im.crop(((im.width - s) // 2, (im.height - s) // 2, (im.width + s) // 2, (im.height + s) // 2))
    im.resize((size, size), Image.LANCZOS).convert("RGB").save(os.path.join(OUT, out_name))


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.join(OUT, "store"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "events"), exist_ok=True)
    order = {"burst": 5, "ferry": 6, "rich": 7, "worldmap": 8}
    for name, (t, s, ax, ay) in TEXT.items():
        if not os.path.exists(os.path.join(RAW, name + ".png")):
            continue
        out = f"thumbnail_{order[name]}_{name}" if name in order else f"events/event_{name}"
        titled(name, t, s, ax, ay, out)
        print("wrote", out)
    if all(os.path.exists(os.path.join(RAW, "region_" + r + ".png")) for r, _ in REGIONS):
        regions_collage()
        print("wrote regions")
    for src, out in [("icon", "icon_A_bale.png"), ("icon_truck", "icon_B_truck.png"), ("icon_farmer", "icon_C_farmer.png")]:
        if os.path.exists(os.path.join(RAW, src + ".png")):
            square(src, out)
    for k in STORE:
        if os.path.exists(os.path.join(RAW, "store_" + k + ".png")):
            square("store_" + k, os.path.join("store", "truck_" + k + ".png"))
    for k in PASSES:
        if os.path.exists(os.path.join(RAW, "pass_" + k + ".png")):
            square("pass_" + k, os.path.join("store", "pass_" + k + ".png"))
    print("done", OUT)


if __name__ == "__main__":
    main()

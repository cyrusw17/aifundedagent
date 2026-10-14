"""Title and package the R15 character batch (shots4.py), which replaces the scenery-only thumbnails as the
main set. Run after shots4.py: python blender/launch/finish4.py [out_dir]"""
import os
import shutil
import sys

import finish as F
import finish2 as F2

OUT = sys.argv[1] if len(sys.argv) > 1 else F.OUT
F2.OUT = OUT

# raw name -> (out name, title, subtitle, title anchor x, y)
TEXT = {
    "hero_haul": ("hero_1_haul", "NEEDLEWOOD", "HAUL HAY. FIND THE NEEDLES.", 0.68, 0.13),
    "hero_needle": ("hero_2_needle", "FIND THE NEEDLE!", "12 KINDS HIDDEN IN THE HAY", 0.5, 0.87),
    "hero_golden": ("hero_3_golden", "GOLDEN BALES", "3X THE NEEDLES. GRAB IT FIRST!", 0.66, 0.13),
    "hero_smash": ("hero_4_smash", "SMASH THE BALES", "EVERY BALE COULD HIDE A NEEDLE", 0.66, 0.87),
    "hero_factory": ("hero_5_factory", "BUILD YOUR HAY EMPIRE", "CONVEYORS, SORTERS AND SILOS", 0.64, 0.87),
    "hero_spindle": ("hero_6_spindle", "OPEN THE SPINDLE", "TWELVE SHARDS OF THE MASTER NEEDLE", 0.5, 0.88),
    "hero_wagon": ("hero_7_haywagon", "RIDE THE HAY WAGON", "A FREE TOUR OF 14 REGIONS", 0.5, 0.88),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (out, t, s, ax, ay) in TEXT.items():
        if os.path.exists(os.path.join(F.RAW, name + ".png")):
            F2.titled(name, t, s, ax, ay, out)
            print("wrote", out)
    for src, out in [("icon_hero", "icon_hero_needle.png"), ("icon_hero_golden", "icon_hero_golden.png")]:
        if os.path.exists(os.path.join(F.RAW, src + ".png")):
            F2.square(src, out)
            print("wrote", out)
    # the loading screen is the haul shot without text (Loading.client.luau draws its own title)
    clean = os.path.join(OUT, "hero_1_haul_clean.png")
    if os.path.exists(clean):
        shutil.copy(clean, os.path.join(OUT, "loading_screen.png"))
        print("wrote loading_screen.png")


if __name__ == "__main__":
    main()

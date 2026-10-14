"""Title and package the third batch (shots3.py). Run after shots3.py: python blender/launch/finish3.py [out_dir]"""
import os
import sys

import finish as F
import finish2 as F2

OUT = sys.argv[1] if len(sys.argv) > 1 else F.OUT
F2.OUT = OUT

TEXT = {
    "golden": ("thumbnail_10_golden", "GOLDEN BALES", "3X THE NEEDLES. GRAB IT FIRST!", 0.66, 0.14),
    "spindle": ("thumbnail_11_spindle", "OPEN THE SPINDLE", "TWELVE SHARDS OF THE MASTER NEEDLE", 0.5, 0.86),
    "haywagon": ("thumbnail_12_haywagon", "RIDE THE HAY WAGON", "A FREE TOUR OF 14 REGIONS", 0.66, 0.14),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (out, t, s, ax, ay) in TEXT.items():
        if os.path.exists(os.path.join(F.RAW, name + ".png")):
            F2.titled(name, t, s, ax, ay, out)
            print("wrote", out)
    for src, out in [("icon_golden", "icon_D_golden.png"), ("icon_spindle", "icon_E_spindle.png")]:
        if os.path.exists(os.path.join(F.RAW, src + ".png")):
            F2.square(src, out)
            print("wrote", out)


if __name__ == "__main__":
    main()

"""Hay-handling gloves, the player's upgrade path (the only hand tools are the shovel and the rake).

Five tiers, each a single right glove standing on its cuff, back of the hand facing -y (toward
the shop customer), fingers up, about
1.7 studs tall so it reads on a shop shelf; the game scales it onto the character's hand.

  1 work_gloves        worn cream cloth, frayed cuff, patched palm
  2 leather_gloves     brown leather, turned-down cuff, twine stitching
  3 reinforced_gloves  leather with a padded palm, riveted knuckle plate and a buckled wrist strap
  4 iron_gauntlets     leather under segmented steel finger plates and a flared steel cuff
  5 starlight_gloves   rare: night-blue with glowing seams, fingertips and a knuckle gem

Run:
  python blender/props/rustic_props.py --out <dir> --category gloves
"""
import math
import os
import sys

import bpy  # noqa: F401  (must be imported before mathutils with the pip bpy module)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
from mathutils import Matrix  # noqa: E402
from style import box, cyl  # noqa: E402

STUD = 0.28

# Hand layout in studs: palm block, then fingers (x offset, length) left to right seen from the front.
PALM = (1.0, 0.46, 0.78)       # width, thickness, height
CUFF_H = 0.55
FINGERS = ((-0.36, 0.46), (-0.12, 0.58), (0.12, 0.54), (0.36, 0.42))
FW, FD = 0.22, 0.36            # finger width and thickness


def s(*v):
    return tuple(x * STUD for x in v)


def B(f, kind, size, loc, rot=(0, 0, 0), along="z", rounded=True):
    return f.apply(f.shape(box(s(*size), s(*loc), rot=rot), round_edges=rounded), kind, along=along)


def C(f, kind, r, depth, loc, axis="z", verts=10, rounded=False):
    rot = {"x": (0, math.pi / 2, 0), "y": (math.pi / 2, 0, 0), "z": (0, 0, 0)}[axis]
    return f.apply(f.shape(cyl(r * STUD, depth * STUD, s(*loc), verts=verts, rot=rot), round_edges=rounded),
                   kind, along=axis)


def hand(f, kind, cuff_kind=None, cuff_w=1.08, cuff_d=0.56, cuff_h=CUFF_H, finger_kind=None, thumb_kind=None):
    """Cuff, palm, four fingers and a thumb. Returns (parts, z of the palm top)."""
    parts = [B(f, cuff_kind or kind, (cuff_w, cuff_d, cuff_h), (0, 0, cuff_h / 2))]
    z0 = cuff_h - 0.02
    parts.append(B(f, kind, PALM, (0, 0, z0 + PALM[2] / 2)))
    top = z0 + PALM[2]
    for x, ln in FINGERS:
        parts.append(B(f, finger_kind or kind, (FW, FD, ln), (x, 0, top + ln / 2 - 0.04)))
    # Thumb out of the left side of the palm, angled up and out.
    parts.append(B(f, thumb_kind or kind, (0.24, 0.34, 0.5), (-PALM[0] / 2 - 0.1, -0.03, z0 + 0.42),
                   rot=(0, math.radians(-35), 0)))
    return parts, top


def knuckle_band(f, kind, top, z_off=-0.08, h=0.14, d=0.5):
    return B(f, kind, (PALM[0] + 0.04, d, h), (0, 0, top + z_off), rounded=False)


def work_gloves(f):
    """Tier 1: worn cream cloth work glove with a frayed dirt-stained cuff and a patched palm."""
    parts, top = hand(f, "cloth", cuff_kind="cloth")
    parts.append(B(f, "dirt", (1.1, 0.58, 0.12), (0, 0, CUFF_H - 0.04), rounded=False))   # cuff hem
    parts.append(B(f, "paint_cream", (0.42, 0.06, 0.34), (0.15, -0.25, CUFF_H + 0.35), rounded=False))  # patch
    for x, ln in FINGERS[1:3]:
        parts.append(B(f, "dirt", (FW + 0.02, FD + 0.02, 0.1), (x, 0, top + ln - 0.1), rounded=False))
    return parts


def leather_gloves(f):
    """Tier 2: brown leather glove with a turned-down cuff and twine stitching on the back."""
    parts, top = hand(f, "leather", cuff_w=1.16, cuff_d=0.62)
    parts.append(B(f, "dirt", (1.2, 0.66, 0.16), (0, 0, CUFF_H - 0.06), rounded=False))     # cuff fold
    for x in (-0.24, 0.0, 0.24):
        parts.append(B(f, "twine", (0.04, 0.05, PALM[2] * 0.7), (x, 0.24, CUFF_H + PALM[2] * 0.45),
                       rounded=False))
    return parts


def reinforced_gloves(f):
    """Tier 3: leather with a padded cloth palm, riveted iron knuckle plate and a buckled wrist strap."""
    parts, top = hand(f, "leather", cuff_kind="handle")
    parts.append(B(f, "cloth", (0.86, 0.08, 0.6), (0, -0.25, CUFF_H + 0.36)))                # palm pad
    parts.append(B(f, "metal", (PALM[0] + 0.06, 0.12, 0.26), (0, 0.26, top - 0.14), rounded=False))
    for x in (-0.36, -0.12, 0.12, 0.36):
        parts.append(C(f, "steel", 0.05, 0.06, (x, 0.33, top - 0.14), axis="y", verts=8))
    parts.append(B(f, "leather", (1.14, 0.62, 0.16), (0, 0, CUFF_H + 0.08), rounded=False))  # wrist strap
    parts.append(B(f, "metal", (0.22, 0.06, 0.22), (0.32, 0.33, CUFF_H + 0.08), rounded=False))  # buckle
    return parts


def iron_gauntlets(f):
    """Tier 4: leather glove under a flared steel cuff, a back plate and segmented finger plates."""
    parts, top = hand(f, "leather", cuff_kind="steel", cuff_w=1.3, cuff_d=0.7, cuff_h=0.7)
    parts.append(B(f, "steel", (PALM[0] + 0.06, 0.1, PALM[2] * 0.8), (0, 0.27, 0.7 + PALM[2] * 0.42)))
    parts.append(knuckle_band(f, "steel", top, z_off=-0.04, h=0.2, d=0.56))
    for x, ln in FINGERS:
        for n in range(2):
            z = top + 0.1 + n * (ln * 0.48)
            parts.append(B(f, "steel", (FW + 0.04, 0.08, ln * 0.4), (x, 0.2, z + ln * 0.2), rounded=False))
    parts.append(B(f, "metal", (1.34, 0.74, 0.1), (0, 0, 0.66), rounded=False))              # cuff rim
    return parts


def starlight_gloves(f):
    """Tier 5 (rare): night-blue glove with glowing seams, fingertips and a gem on the knuckles."""
    parts, top = hand(f, "tire", cuff_kind="paint_blue", cuff_w=1.2, cuff_d=0.64)
    parts.append(B(f, "glow", (1.24, 0.68, 0.08), (0, 0, CUFF_H - 0.08), rounded=False))     # cuff band
    parts.append(B(f, "glow", (0.06, 0.06, PALM[2] * 0.8), (0, 0.25, CUFF_H + PALM[2] * 0.45), rounded=False))
    for x, ln in FINGERS:
        parts.append(B(f, "glow", (FW + 0.02, FD + 0.02, 0.08), (x, 0, top + ln - 0.08), rounded=False))
    parts.append(knuckle_band(f, "steel", top))
    parts.append(C(f, "glow", 0.16, 0.12, (0, 0.3, top - 0.32), axis="y", verts=6))           # gem
    parts.append(C(f, "steel", 0.21, 0.08, (0, 0.27, top - 0.32), axis="y", verts=6))         # gem setting
    return parts


def back_to_front(build):
    """The builders put the back of the hand on +y; turn the glove so it faces -y like other props."""
    turn = Matrix.Rotation(math.pi, 4, "Z")

    def wrapped(f):
        parts = build(f)
        for o in parts:
            o.data.transform(turn @ Matrix.Translation(o.location))
            o.location = (0, 0, 0)
        return parts
    wrapped.__doc__ = build.__doc__
    return wrapped


PROPS = {k: back_to_front(b) for k, b in (
    ("work_gloves", work_gloves),
    ("leather_gloves", leather_gloves),
    ("reinforced_gloves", reinforced_gloves),
    ("iron_gauntlets", iron_gauntlets),
    ("starlight_gloves", starlight_gloves),
)}

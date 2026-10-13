"""Hay-handling gloves, the player's upgrade path (the only hand tools are the shovel and the rake).

Each is a single right glove standing on its cuff, back of the hand facing -y (toward
the shop customer), fingers up, about
1.7 studs tall so it reads on a shop shelf; the game scales it onto the character's hand.

  cotton_gloves      free starter: off-white cotton, short knit cuff
  work_gloves        cream cloth, blue cuff with a red stripe, patched palm
  leather_gloves     dark brown long gauntlet cuff, cream stitching
  reinforced_gloves  leather, short cuff, iron knuckle plate, black buckled strap
  iron_gauntlets     leather under segmented iron finger plates and a flared iron cuff
  insulated_gloves   heat: padded quilted red, cream lining
  starlight_gloves   rare: night-blue with glowing seams, fingertips and a knuckle gem
  starweave_gloves   crafted from Cosmic needles: black with a glowing woven lattice
Quest gloves: scarecrow_gloves, frostbite_mitts, magma_grips, kraken_gauntlets.

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
    """Tier 1 (bought): worn cream cloth work glove with a blue cuff striped red, a patched palm and
    dirt-stained fingertips."""
    parts, top = hand(f, "cloth", cuff_kind="paint_blue", cuff_w=1.12, cuff_d=0.6)
    parts.append(B(f, "paint_red", (1.16, 0.64, 0.14), (0, 0, CUFF_H * 0.5), rounded=False))  # cuff stripe
    parts.append(B(f, "paint_cream", (0.42, 0.06, 0.34), (0.15, -0.25, CUFF_H + 0.35), rounded=False))  # patch
    for x, ln in FINGERS[1:3]:
        parts.append(B(f, "dirt", (FW + 0.02, FD + 0.02, 0.1), (x, 0, top + ln - 0.1), rounded=False))
    return parts

def leather_gloves(f):
    """Tier 2: dark brown leather with a long flared gauntlet cuff and cream stitching."""
    ch = 0.95
    parts, top = hand(f, "leather", cuff_kind="twine", cuff_w=1.34, cuff_d=0.74, cuff_h=ch)
    parts.append(B(f, "twine", (1.42, 0.82, 0.12), (0, 0, 0.06), rounded=False))           # flared hem
    for x in (-0.6, 0.6):                                                                  # cuff side seams
        parts.append(B(f, "paint_cream", (0.04, 0.78, 0.04), (x, 0, ch * 0.5), rot=(math.pi / 2, 0, 0),
                       rounded=False))
    for z in (0.22, 0.5, 0.78):                                                            # cuff stitch row
        parts.append(B(f, "paint_cream", (1.0, 0.03, 0.03), (0, 0.38, z), rounded=False))
    for x in (-0.24, 0.0, 0.24):                                                           # back stitching
        parts.append(B(f, "paint_cream", (0.04, 0.05, PALM[2] * 0.7), (x, 0.24, ch + PALM[2] * 0.45),
                       rounded=False))
    return parts

def reinforced_gloves(f):
    """Tier 3: leather with a padded cloth palm, a big riveted iron knuckle plate and a black
    wrist strap with an iron buckle over a short leather cuff."""
    parts, top = hand(f, "leather", cuff_kind="leather", cuff_w=1.1, cuff_d=0.6, cuff_h=0.45)
    z0 = 0.45
    parts.append(B(f, "cloth", (0.86, 0.08, 0.6), (0, -0.25, z0 + 0.36)))                    # palm pad
    parts.append(B(f, "metal", (PALM[0] + 0.1, 0.14, 0.34), (0, 0.27, top - 0.14), rounded=False))
    for x in (-0.36, -0.12, 0.12, 0.36):
        parts.append(C(f, "steel", 0.06, 0.06, (x, 0.35, top - 0.14), axis="y", verts=8))
    parts.append(B(f, "tire", (1.14, 0.64, 0.2), (0, 0, z0 + 0.1), rounded=False))           # wrist strap
    parts.append(B(f, "metal", (0.26, 0.08, 0.26), (0.3, 0.33, z0 + 0.1), rounded=False))     # buckle
    parts.append(B(f, "tire", (0.12, 0.09, 0.12), (0.3, 0.35, z0 + 0.1), rounded=False))      # buckle hole
    return parts

def iron_gauntlets(f):
    """Tier 4: leather glove under a flared iron cuff, a back plate and segmented finger plates."""
    parts, top = hand(f, "leather", cuff_kind="metal", cuff_w=1.3, cuff_d=0.7, cuff_h=0.7)
    parts.append(B(f, "metal", (PALM[0] + 0.06, 0.1, PALM[2] * 0.8), (0, 0.27, 0.7 + PALM[2] * 0.42)))
    parts.append(knuckle_band(f, "metal", top, z_off=-0.04, h=0.2, d=0.56))
    for x, ln in FINGERS:
        for n in range(2):
            z = top + 0.1 + n * (ln * 0.48)
            parts.append(B(f, "metal", (FW + 0.04, 0.08, ln * 0.4), (x, 0.2, z + ln * 0.2), rounded=False))
    parts.append(B(f, "steel", (1.34, 0.74, 0.1), (0, 0, 0.66), rounded=False))              # cuff rim
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


# ---------------------------------------------------------------- V8 ladder and quest gloves

def cotton_gloves(f):
    """Tier 1 (free starter): thin off-white cotton glove with a short ribbed knit cuff and grip dots."""
    ch = 0.36
    parts, top = hand(f, "paint_cream", cuff_kind="paint_cream", cuff_w=0.98, cuff_d=0.5, cuff_h=ch)
    for i in range(9):                                                  # knit ribs round the cuff
        x = -0.44 + i * 0.11
        for y in (-0.26, 0.26):
            parts.append(B(f, "cloth", (0.05, 0.04, ch - 0.06), (x, y, ch / 2), rounded=False))
    for x in (-0.26, 0.0, 0.26):                                        # rubber grip dots on the palm
        for z in (0.25, 0.5):
            parts.append(C(f, "tire", 0.05, 0.04, (x, -0.24, ch + z), axis="y", verts=6))
    return parts

def insulated_gloves(f):
    """Tier 4 (heat): thick padded red glove, quilted with ridges, cream fleece lining at the cuff."""
    parts, top = hand(f, "paint_red", cuff_w=1.26, cuff_d=0.74, cuff_h=0.62)
    parts.append(B(f, "paint_red", (1.1, 0.58, PALM[2] * 0.9), (0, 0, 0.6 + PALM[2] * 0.45)))  # padding
    for i in range(4):                                                  # quilting ridges across the back
        parts.append(B(f, "paint_red", (1.14, 0.1, 0.07), (0, 0.29, 0.66 + i * 0.18), rounded=False))
    for x, ln in FINGERS:                                               # puffy finger segments
        for n in range(2):
            parts.append(B(f, "paint_red", (FW + 0.08, FD + 0.08, ln * 0.36),
                           (x, 0, top + 0.08 + n * ln * 0.46 + ln * 0.18)))
    parts.append(B(f, "paint_cream", (1.32, 0.8, 0.14), (0, 0, 0.07), rounded=False))       # lining roll
    parts.append(B(f, "paint_cream", (1.3, 0.78, 0.1), (0, 0, 0.62), rounded=False))        # wrist band
    return parts


def starweave_gloves(f):
    """Tier 6 (crafted from Cosmic needles): near-black glove woven with glowing crossing threads."""
    parts, top = hand(f, "tire", cuff_kind="tire", cuff_w=1.16, cuff_d=0.62)
    zc = CUFF_H + PALM[2] / 2
    for sgn in (-1, 1):                                                 # woven lattice on the back
        for off in (-0.3, 0.0, 0.3):
            parts.append(B(f, "glow", (0.05, 0.05, 0.92), (off, 0.25, zc),
                           rot=(0, sgn * math.radians(40), 0), rounded=False))
    for sgn in (-1, 1):                                                 # zigzag weave round the cuff
        for off in (-0.36, -0.12, 0.12, 0.36):
            parts.append(B(f, "glow", (0.04, 0.04, 0.5), (off, 0.32, CUFF_H / 2),
                           rot=(0, sgn * math.radians(25), 0), rounded=False))
    for x, ln in FINGERS:                                               # threads up each finger
        parts.append(B(f, "glow", (0.05, 0.05, ln), (x, FD / 2, top + ln / 2 - 0.04), rounded=False))
    parts.append(B(f, "metal", (PALM[0] + 0.04, 0.64, 0.08), (0, 0, CUFF_H), rounded=False))
    return parts


def scarecrow_gloves(f):
    """Quest: patched burlap glove stuffed with straw, tufts poking out of the cuff and fingertips."""
    parts, top = hand(f, "dirt", cuff_w=1.12, cuff_d=0.6)
    parts.append(B(f, "cloth", (0.38, 0.06, 0.32), (-0.18, 0.26, CUFF_H + 0.3), rounded=False))  # patches
    parts.append(B(f, "paint_red", (0.3, 0.06, 0.26), (0.24, 0.26, CUFF_H + 0.62), rounded=False))
    for x0, z0 in ((-0.18, CUFF_H + 0.3), (0.24, CUFF_H + 0.62)):       # big cross stitches
        parts.append(B(f, "twine", (0.03, 0.03, 0.2), (x0 + 0.12, 0.3, z0), rot=(0, 0.6, 0), rounded=False))
    parts.append(B(f, "twine", (1.16, 0.64, 0.06), (0, 0, CUFF_H - 0.06), rounded=False))     # tie string
    for i in range(9):                                                  # straw fanning out of the cuff
        a = math.radians(-80 + i * 20)
        parts.append(B(f, "hay", (0.05, 0.05, 0.42), (0.5 * math.sin(a), 0.3 + 0.08 * math.cos(a), 0.18),
                       rot=(math.radians(-60) * math.cos(a), math.radians(60) * math.sin(a), 0), rounded=False))
    for side in (-1, 1):
        for dz in (0.1, 0.3):
            parts.append(B(f, "hay", (0.05, 0.05, 0.36), (side * 0.66, 0.0, dz),
                           rot=(0, side * math.radians(65), 0), rounded=False))
    for x, ln in FINGERS[::2]:                                          # tufts out of two fingertips
        for dx in (-0.06, 0.06):
            parts.append(B(f, "hay", (0.04, 0.04, 0.26), (x + dx, 0, top + ln + 0.06),
                           rot=(0, dx * 4, 0), rounded=False))
    return parts


def frostbite_mitts(f):
    """Quest: pale blue mitten (thumb and one fused finger block) with a thick fluffy cream cuff."""
    parts = [B(f, "paint_cream", (1.24, 0.72, 0.6), (0, 0, 0.3))]       # fur cuff
    for i in range(10):                                                 # fur tufts round the cuff
        a = i / 10 * 2 * math.pi
        parts.append(B(f, "paint_cream", (0.22, 0.22, 0.2), (0.6 * math.cos(a), 0.34 * math.sin(a), 0.5 + (i % 2) * 0.06),
                       rot=(0.3, 0.2, a)))
    z0 = 0.58
    body_h = PALM[2] + 0.5
    parts.append(B(f, "paint_blue", (1.06, 0.54, body_h), (0, 0, z0 + body_h / 2)))          # palm + fingers
    parts.append(C(f, "paint_blue", 0.53, 0.54, (0, 0, z0 + body_h), axis="y", verts=14))   # rounded tip
    parts.append(B(f, "paint_blue", (0.3, 0.42, 0.62), (-0.6, -0.02, z0 + 0.42),
                   rot=(0, math.radians(-30), 0)))                                          # thumb
    parts.append(B(f, "paint_cream", (0.7, 0.06, 0.08), (0, 0.28, z0 + body_h * 0.62), rounded=False))  # stitch
    for x in (-0.18, 0.18):                                             # snowflake stitch on the back
        parts.append(B(f, "paint_cream", (0.05, 0.05, 0.36), (x * 0.0, 0.29, z0 + 0.4),
                       rot=(0, math.radians(60 if x > 0 else -60), 0), rounded=False))
    parts.append(B(f, "paint_cream", (0.05, 0.05, 0.36), (0, 0.29, z0 + 0.4), rounded=False))
    return parts


def magma_grips(f):
    """Quest: black glove armoured with dark basalt-like plates, glowing cracks between them."""
    parts, top = hand(f, "tire", cuff_kind="bark", cuff_w=1.24, cuff_d=0.7, cuff_h=0.62)
    parts.append(B(f, "lava", (1.0, 0.04, PALM[2] * 0.9), (0, 0.25, 0.62 + PALM[2] * 0.45), rounded=False))
    plates = ((-0.27, 0.8, 0.4, 0.3), (0.2, 0.84, 0.5, 0.36), (-0.18, 1.18, 0.56, 0.3), (0.3, 1.2, 0.34, 0.32))
    for x, z, w, h in plates:                                           # stone plates, glow shows between
        parts.append(B(f, "bark", (w, 0.1, h), (x, 0.3, z), rot=(0, 0.08 * (1 if x > 0 else -1), 0)))
    for x, ln in FINGERS:                                               # stone knuckles, glowing joints
        parts.append(B(f, "bark", (FW + 0.06, FD + 0.06, ln * 0.42), (x, 0, top + ln * 0.22)))
        parts.append(B(f, "lava", (FW + 0.03, FD + 0.03, 0.05), (x, 0, top + ln * 0.48), rounded=False))
        parts.append(B(f, "bark", (FW + 0.05, FD + 0.05, ln * 0.36), (x, 0, top + ln * 0.72)))
    parts.append(B(f, "lava", (1.28, 0.74, 0.05), (0, 0, 0.3), rounded=False))               # cuff crack
    parts.append(B(f, "lava", (0.05, 0.74, 0.3), (0.2, 0, 0.42), rot=(0, 0.5, 0), rounded=False))
    return parts


def kraken_gauntlets(f):
    """Quest: sea-green plated gauntlet with suction-cup rivets and a tentacle curling round the cuff."""
    parts, top = hand(f, "leather", cuff_kind="leather", cuff_w=1.24, cuff_d=0.7, cuff_h=0.66)
    parts.append(B(f, "paint_green", (PALM[0] + 0.06, 0.1, PALM[2] * 0.82), (0, 0.27, 0.66 + PALM[2] * 0.42)))
    for x, ln in FINGERS:
        parts.append(B(f, "paint_green", (FW + 0.04, 0.08, ln * 0.8), (x, 0.2, top + ln * 0.44), rounded=False))
    for x in (-0.3, 0.0, 0.3):                                          # suction-cup rivets
        for z in (0.88, 1.18):
            parts.append(C(f, "paint_cream", 0.08, 0.06, (x, 0.34, z), axis="y", verts=10))
            parts.append(C(f, "leather", 0.04, 0.03, (x, 0.37, z), axis="y", verts=8))
    # Tentacle: one tapering tube wrapping round the cuff from the palm side, across the back of
    # the hand (the side the shop shows) and curling up over the thumb side, with cream suckers.
    from tools import catmull, tube  # props/ is on sys.path when run through rustic_props
    ctrl = ((0.45, -0.46, 0.12), (0.76, -0.12, 0.2), (0.74, 0.3, 0.3), (0.38, 0.52, 0.38), (-0.1, 0.56, 0.46),
            (-0.55, 0.48, 0.56), (-0.84, 0.2, 0.72), (-0.9, 0.12, 0.98), (-0.74, 0.14, 1.14),
            (-0.6, 0.18, 1.02), (-0.68, 0.2, 0.92))
    pts = catmull(ctrl, 4)
    def rad(t):
        return 0.19 - 0.15 * t
    ctr = [tuple(c * STUD for c in p) for p in pts]
    parts.append(f.apply(f.shape(tube(ctr, lambda t: rad(t) * STUD, sides=8), round_edges=False),
                         "paint_green", along="z"))
    for i in range(3, 26, 4):                                           # suckers on the outer side
        x, y, z = pts[i]
        t = i / (len(pts) - 1)
        out = (x * x + y * y) ** 0.5
        k = (out + rad(t) * 0.85) / out
        parts.append(C(f, "paint_cream", rad(t) * 0.5, 0.08, (x * k, y * k, z),
                       axis="y" if abs(y) > abs(x) else "x", verts=8))
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
    ("cotton_gloves", cotton_gloves),
    ("work_gloves", work_gloves),
    ("leather_gloves", leather_gloves),
    ("reinforced_gloves", reinforced_gloves),
    ("iron_gauntlets", iron_gauntlets),
    ("insulated_gloves", insulated_gloves),
    ("starlight_gloves", starlight_gloves),
    ("starweave_gloves", starweave_gloves),
    ("scarecrow_gloves", scarecrow_gloves),
    ("frostbite_mitts", frostbite_mitts),
    ("magma_grips", magma_grips),
    ("kraken_gauntlets", kraken_gauntlets),
)}

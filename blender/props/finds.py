"""Small things players find inside hay bales (foreign objects for the collection book).

Each lies on the ground (z=0) as it would after spilling out of a broken bale, sized next to a
4.6-stud bale. Common finds are plain Rustic; the rarer ones get a little shine or glow.

  old_boot     common    worn leather work boot, flapping sole, twine laces
  horseshoe    common    grey iron horseshoe with nail holes
  rusty_key    uncommon  old grey iron barrel key with a ring bow
  old_radio    rare      wooden cabinet radio with a cloth grille, dials and antenna
  lost_ring    rare      gold band with a little blue stone (the only shiny find)
  fossil       epic      stone slab with a raised spiral ammonite

Run:
  python blender/props/rustic_props.py --out <dir> --category finds
"""
import math
import os
import sys

import bpy  # noqa: F401  (must be imported before mathutils with the pip bpy module)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
from style import box, cyl  # noqa: E402

STUD = 0.28


def s(*v):
    return tuple(x * STUD for x in v)


def B(f, kind, size, loc, rot=(0, 0, 0), along="x", rounded=True):
    return f.apply(f.shape(box(s(*size), s(*loc), rot=rot), round_edges=rounded), kind, along=along)


def C(f, kind, r, depth, loc, axis="z", verts=10, rot=None):
    rot = rot or {"x": (0, math.pi / 2, 0), "y": (math.pi / 2, 0, 0), "z": (0, 0, 0)}[axis]
    return f.apply(f.shape(cyl(r * STUD, depth * STUD, s(*loc), verts=verts, rot=rot), round_edges=False),
                   kind, along=axis)


def ring_of(f, kind, r, thick, z, n=12, gap=0.0, h=None):
    """A flat ring of n short boxes around the z axis (gap = radians left open at +y)."""
    parts = []
    h = h or thick
    span = 2 * math.pi - gap
    for i in range(n):
        a = math.pi / 2 + gap / 2 + span * (i + 0.5) / n
        seg = 2 * r * math.sin(span / n / 2) + 0.04
        parts.append(B(f, kind, (seg, thick, h), (r * math.cos(a), r * math.sin(a), z),
                       rot=(0, 0, a + math.pi / 2), rounded=False))
    return parts


def old_boot(f):
    """Worn leather work boot lying on its side, about 1.4 long x 0.9 tall, sole peeling at the toe."""
    p = [B(f, "leather", (1.3, 0.55, 0.4), (0.05, 0, 0.3)),                    # foot
         B(f, "leather", (0.5, 0.55, 0.75), (-0.4, 0, 0.65), rounded=False),   # shaft
         B(f, "handle", (0.55, 0.6, 0.1), (-0.4, 0, 1.05), rounded=False),     # turned-down collar
         B(f, "tire", (1.4, 0.6, 0.12), (0.05, 0, 0.06), rounded=False),       # sole
         B(f, "tire", (0.4, 0.58, 0.08), (0.62, 0, 0.14), rot=(0, -0.35, 0), rounded=False),  # flapping toe
         B(f, "tire", (0.32, 0.6, 0.12), (-0.45, 0, 0.18), rounded=False)]     # heel
    for i in range(3):
        p.append(B(f, "twine", (0.06, 0.6, 0.05), (-0.05 - i * 0.16, 0, 0.52 + i * 0.1), rounded=False))
    p.append(B(f, "twine", (0.05, 0.05, 0.35), (0.05, -0.32, 0.4), rot=(0.6, 0, 0), rounded=False))
    return p


def horseshoe(f):
    """Grey iron horseshoe lying flat, about 0.9 across, with nail holes and calkins."""
    p = ring_of(f, "metal", 0.36, 0.16, 0.05, n=8, gap=1.2, h=0.1)
    for a in (math.pi / 2 + 0.75, math.pi / 2 - 0.75 + 2 * math.pi):
        x, y = 0.36 * math.cos(a), 0.36 * math.sin(a)
        p.append(B(f, "metal", (0.18, 0.18, 0.08), (x, y + 0.04, 0.09), rounded=False))
    for i in range(2):
        a = math.pi / 2 + 1.6 + i * (2 * math.pi - 3.2)
        p.append(B(f, "tire", (0.05, 0.05, 0.02), (0.36 * math.cos(a), 0.36 * math.sin(a), 0.105),
                   rounded=False))
    return p


def rusty_key(f):
    """Old grey iron barrel key lying flat, about 0.9 long: ring bow, collar, bit with two teeth."""
    p = ring_of(f, "metal", 0.14, 0.05, 0.03, n=8, h=0.06)
    p.append(C(f, "metal", 0.035, 0.6, (0.45, 0, 0.035), axis="x", verts=6))
    p.append(C(f, "metal", 0.05, 0.06, (0.2, 0, 0.05), axis="x", verts=6))
    p.append(B(f, "metal", (0.16, 0.05, 0.18), (0.66, 0, 0.12), rounded=False))
    p.append(B(f, "metal", (0.05, 0.05, 0.08), (0.62, 0, 0.24), rounded=False))
    p.append(B(f, "dirt", (0.12, 0.06, 0.07), (0.5, 0, 0.06), rounded=False))  # a crust of old dirt
    return p


def old_radio(f):
    """Rare: 1940s wooden cabinet radio, about 1.4 wide x 1.1 tall x 0.7 deep, arched top, cloth
    speaker grille, two dials, a glass tuning window and a bent wire antenna."""
    p = [B(f, "handle", (1.4, 0.7, 0.9), (0, 0, 0.45)),
         C(f, "handle", 0.7, 0.7, (0, 0, 0.75), axis="y", verts=16)]
    p[-1].scale = (1.0, 1.0, 0.45)
    p.append(B(f, "cloth", (0.8, 0.06, 0.55), (0, -0.36, 0.62), rounded=False))
    for x in (-0.2, 0, 0.2):
        p.append(B(f, "handle", (0.05, 0.08, 0.5), (x, -0.38, 0.62), rounded=False))
    p.append(B(f, "glass", (0.5, 0.06, 0.12), (0, -0.36, 0.22), rounded=False))
    for x in (-0.48, 0.48):
        p.append(C(f, "paint_cream", 0.09, 0.1, (x, -0.38, 0.22), axis="y", verts=8))
    p.append(C(f, "steel", 0.02, 0.9, (0.45, 0.2, 1.3), verts=4, rot=(0.25, 0.3, 0)))
    for x in (-0.55, 0.55):
        p.append(B(f, "tire", (0.18, 0.6, 0.06), (x, 0, 0.03), rounded=False))
    return p


def lost_ring(f):
    """Rare: a gold band standing on its edge with a little blue stone on top, about 0.45 across.
    The only shiny find (gold, no glow). Shown a little larger than life so it reads in the hay."""
    p = []
    n = 9
    r = 0.2
    for i in range(n):
        a = 2 * math.pi * (i + 0.5) / n
        p.append(B(f, "gold", (0.1, 2 * r * math.sin(math.pi / n) + 0.03, 0.07),
                   (0, r * math.cos(a), r + r * math.sin(a)), rot=(a, 0, 0), rounded=False))
    p.append(C(f, "paint_blue", 0.07, 0.1, (0, 0, 2 * r + 0.06), verts=6))
    return p


def fossil(f):
    """Epic: a flat split stone slab, about 1.4 x 1.0, with a raised spiral ammonite shell on it."""
    p = [B(f, "stone", (1.4, 1.0, 0.2), (0, 0, 0.1), rounded=False)]
    # Ammonite: a widening spiral of short ridged segments, the ribs a shade paler than the slab.
    n = 14
    for i in range(n):
        t0 = i / n
        a = t0 * 3.2 * math.pi
        rad = 0.05 + 0.38 * t0
        w = 0.07 + 0.11 * t0
        p.append(B(f, "paint_cream", (w, 0.08 + 0.14 * t0, 0.12 + 0.08 * t0),
                   (rad * math.cos(a), rad * math.sin(a), 0.24 + 0.04 * t0), rot=(0, 0, a), rounded=False))
    return p


PROPS = {
    "old_boot": old_boot,
    "horseshoe": horseshoe,
    "rusty_key": rusty_key,
    "old_radio": old_radio,
    "lost_ring": lost_ring,
    "fossil": fossil,
}

"""Lumber Tycoon 2 style mockups: simple part-built props in several finishes.

Every variant uses the same LT2-like shapes (blocks and cylinders); only the
finish changes:

  plain     flat colors, like Roblox SmoothPlastic parts
  textured  straw / bark / wood-grain textures, like Roblox Wood and Grass
  painted   textured, but brighter and more saturated with bolder grain
  rustic    textured, muted and weathered, with slightly lumpy, uneven shapes
  faceted   low-poly: fewer sides, flat-shaded faces each a slightly different tone
  soft      flat pastel-warm colors with big rounded bevels, smooth shading

Each scene shows a stack of square hay bales, a round hay bale, a small
shovel and a log.

Run:
  blender --background --python blender/styles/lt2_mockups.py -- --out blender/exports/styles [--only painted,rustic]
Writes lt2_<variant>.glb and lt2_<variant>.png.
"""
import math
import os
import random
import sys

import bpy  # must be imported before bmesh/mathutils with the pip bpy module

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, os.path.join(HERE, "..", "props"))
import common  # noqa: E402
import hay_bale  # noqa: E402
from style import Finish, VARIANTS, box, cap_uv, cyl  # noqa: E402,F401

GRASS = (0.42, 0.60, 0.28)


# ---------------------------------------------------------------- props

def square_bale(f, loc, yaw=0.0):
    hay_bale.BEVEL = max(f.bevel, 0.001)
    hay = hay_bale.build_hay()
    f.shape(hay, round_edges=False)  # build_hay already bevels
    bands = hay_bale.build_twine()
    parts = [f.apply(hay, "hay")] + [f.apply(b, "twine") for b in bands]
    obj = common.join(parts, "SquareBale")
    obj.rotation_euler = (0, 0, yaw)
    obj.location = loc
    return obj


def round_bale(f, loc):
    r, width = 0.5, 0.95
    sides = max(f.sides + 8, 12)
    body = f.shape(cyl(r, width, (0, 0, r), verts=sides, rot=(math.pi / 2, 0, 0)))
    f.apply(body, "hay", along="x")
    parts = [body]
    if f.textured:
        # Ends show the rolled-up hay as rings.
        for side in (-1, 1):
            cap = cyl(r * 0.96 - f.lumpy, 0.01, (0, side * (width / 2 + 0.002 + f.lumpy), r), verts=sides, rot=(math.pi / 2, 0, 0))
            cap_uv(cap, 1, r)
            parts.append(f.apply(cap, "hay", uv="rolled"))
    for y in (-0.25, 0.0, 0.25):
        band = cyl(r + 0.006 + f.lumpy, 0.025, (0, y, r), verts=sides, rot=(math.pi / 2, 0, 0))
        parts.append(f.apply(band, "twine"))
    obj = common.join(parts, "RoundBale")
    obj.location = loc
    return obj


def small_shovel(f, loc):
    """A short spade, about 2.7 studs tall: hand-tool size."""
    s = max(6, f.sides // 2 + 2)
    parts = []
    handle = cyl(0.018, 0.48, (0, 0, 0.47), verts=s)
    parts.append(f.apply(handle, "handle", along="z"))
    grip = f.shape(cyl(0.016, 0.12, (0, 0, 0.73), verts=s, rot=(0, math.pi / 2, 0)))
    parts.append(f.apply(grip, "handle", along="x"))
    for x in (-0.055, 0.055):
        post = box((0.02, 0.02, 0.06), (x * 0.9, 0, 0.70), rot=(0, x * 4, 0))
        parts.append(f.apply(post, "handle", along="z"))
    neck = f.shape(box((0.05, 0.03, 0.06), (0, 0, 0.22)))
    parts.append(f.apply(neck, "metal"))
    blade = box((0.17, 0.02, 0.2), (0, 0, 0.1))
    for v in blade.data.vertices:
        if v.co.z < 0:
            v.co.x *= 0.8
    f.shape(blade)
    parts.append(f.apply(blade, "metal"))
    obj = common.join(parts, "SmallShovel")
    obj.location = loc
    return obj


def log(f, loc):
    r, length = 0.24, 1.4
    body = f.shape(cyl(r, length, (0, 0, r), verts=f.sides, rot=(0, math.pi / 2, 0)))
    f.apply(body, "bark", along="x")
    parts = [body]
    for side in (-1, 1):
        cap = cyl(r - f.bevel * 0.9 if f.bevel > 0.05 else r * 0.99, 0.01, (side * (length / 2 + 0.003), 0, r),
                  verts=f.sides, rot=(0, math.pi / 2, 0))
        cap_uv(cap, 0, r)
        parts.append(f.apply(cap, "wood", uv="cap"))
    obj = common.join(parts, "Log")
    obj.location = loc
    return obj


def build_scene(variant):
    f = Finish(variant)
    L, W, H = hay_bale.SIZE
    return [
        # Two bales side by side, one across the top: they stack because 2 x width = length.
        square_bale(f, (0, -W / 2, 0)),
        square_bale(f, (0, W / 2, 0)),
        square_bale(f, (0, 0, H), yaw=math.pi / 2),
        round_bale(f, (1.45, 0, 0)),
        small_shovel(f, (2.35, -0.1, 0)),
        log(f, (3.45, 0, 0)),
    ]


def main():
    args = common.parse_args("lt2")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else list(VARIANTS)
    args.formats = "glb"
    base, out = args.name, args.out
    for name in only:
        common.reset_scene()
        objs = build_scene(name)
        args.name = f"{base}_{name}"
        common.export(objs, args)
        common.render_preview(os.path.join(out, f"{args.name}.png"), 1400, ground=GRASS)


if __name__ == "__main__":
    main()

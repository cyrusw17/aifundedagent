"""Region style sheet: one vignette per region (Meadow, Pine Forest, Desert Dunes, Snow Peak,
Swamp) showing its ground, hay, trees, a fence, a signpost in the accent color and palette chips.
Palettes come from mockups/regions.py; everything else is the Rustic house finish.

Run:
  python blender/mockups/region_sheet.py [out_folder]
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mock  # noqa: E402
from mock import rgb  # noqa: E402
from regions import ORDER, REGIONS  # noqa: E402

bpy.ops.wm.read_factory_settings(use_empty=True)

INK = mock.mat("ink", rgb(40, 34, 28), 0.9)
SUB = mock.mat("sub", rgb(80, 72, 62), 0.9)
BLANK = mock.mat("tmp", (1, 1, 1))
SPACING = 23.0
TILE = 19.0


def lin(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def flat(name, col, rough=0.9, emit=0.0):
    return mock.mat(name, lin(col), rough, emit=emit)


def part(o, kind, f, along="x"):
    return mock.finish_part(o, kind, f, along=along)


def cone(r, depth, loc, verts=6, r2=0.0):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=depth, location=loc)
    return bpy.context.active_object


def oak(x, y, f, rng):
    part(mock.cylinder("trunk", 0.6, 6, (x, y, 3), BLANK, verts=8), "bark", f, along="z")
    for k in range(3):
        s = rng.uniform(3.4, 4.6)
        part(mock.box("crown", (s, s * 0.8, s), (x + rng.uniform(-1.2, 1.2), y + rng.uniform(-1, 1), 6.6 + k * 0.8),
                      BLANK, rot=(0, 0, rng.uniform(0, 1.5))), "paint_green", f)


def pine(x, y, f, rng, snow=False, scale=1.0):
    part(mock.cylinder("trunk", 0.45 * scale, 3 * scale, (x, y, 1.5 * scale), BLANK, verts=8), "bark", f, along="z")
    white = flat("snowcap", (0.95, 0.96, 0.97), 0.7)
    for k, (r, z) in enumerate(((2.8, 3.6), (2.2, 5.6), (1.5, 7.4))):
        c = cone(r * scale, 2.8 * scale, (x, y, z * scale), verts=7)
        part(c, "paint_green", f)
        if snow:
            cap = cone(r * scale * 0.75, 1.0 * scale, (x, y, (z + 0.9) * scale), verts=7)
            cap.data.materials.append(white)


def cactus(x, y, f, rng):
    part(mock.box("cactus", (1.3, 5.5, 1.3), (x, y, 2.75), BLANK), "paint_green", f, along="z")
    for side in (-1, 1):
        h = rng.uniform(2.0, 3.4)
        part(mock.box("arm", (1.4, 0.9, 0.9), (x + side * 1.0, y, h), BLANK), "paint_green", f)
        part(mock.box("arm_up", (0.9, 1.8, 0.9), (x + side * 1.5, y, h + 1.2), BLANK), "paint_green", f, along="z")


def dead_tree(x, y, f, rng):
    trunk = mock.cylinder("trunk", 0.55, 6.5, (x, y, 3.2), BLANK, verts=7, rot=(0.12, 0.08, 0))
    part(trunk, "bark", f, along="z")
    for k in range(4):
        a = rng.uniform(0, math.tau)
        b = mock.box("branch", (2.6, 0.35, 0.35), (x + math.cos(a) * 1.2, y + math.sin(a) * 1.2, 4.5 + k * 0.6), BLANK,
                     rot=(0, rng.uniform(-0.6, -0.2), a))
        part(b, "bark", f)


def rock(x, y, f, rng, s=1.0):
    o = mock.sphere("rock", s, (x, y, s * 0.4), BLANK, scale=(1.2, 1, 0.7), subdiv=1)
    o.rotation_euler[2] = rng.uniform(0, 3)
    part(o, "stone", f)


for i, key in enumerate(ORDER):
    r = REGIONS[key]
    cx, cy = (i - 2) * SPACING, 0.0
    rng = random.Random(i + 3)
    kinds = {"dirt": r["ground"], "paint_green": r["leaves"], "paint_red": r["accent"]}
    if r["hay"]:
        kinds["hay"] = r["hay"]
    if r["bark"]:
        kinds["bark"] = r["bark"]
    f = mock.rustic_finish("region_" + key, **kinds)

    # Ground tile and a few patches.
    part(mock.box("ground", (TILE, 0.6, TILE), (cx, cy, -0.3), BLANK), "dirt", f)
    for k in range(7):
        col = r["ground"][0] if k % 2 else r["ground"][2]
        o = mock.cylinder("patch", rng.uniform(1.0, 2.2), 0.04, (cx + rng.uniform(-7, 7), cy + rng.uniform(-7, 7), 0.02 + k * 0.003),
                          flat(f"patch_{key}_{k % 2}", col), verts=8)
        o.scale = (1, rng.uniform(0.5, 1), 1)
    if key == "swamp":
        water = flat("water", (0.20, 0.27, 0.24), 0.08)
        for wx, wy, wr in ((cx + 4.5, cy - 4, 2.8), (cx - 6, cy - 6.5, 1.8)):
            mock.cylinder("water", wr, 0.06, (wx, wy, 0.04), water, verts=12)
        reed = flat("reed", r["leaves"][0])
        for k in range(14):
            mock.box("reed", (0.15, rng.uniform(1.2, 2.4), 0.15), (cx + 4.5 + rng.uniform(-3, 3), cy - 4 + rng.uniform(-3, 3), 0.8), reed,
                     rot=(rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), 0))
        fly = flat("firefly", r["accent"][0], 0.5, emit=6.0)
        for k in range(8):
            mock.sphere("fly", 0.12, (cx + rng.uniform(-7, 7), cy + rng.uniform(-6, 6), rng.uniform(2, 6)), fly, subdiv=1)
    if key == "desert":
        for k in range(3):
            o = mock.sphere("dune", rng.uniform(3, 4), (cx + rng.uniform(-6, 6), cy + 6.5, -1.6), BLANK, scale=(1.8, 1, 0.6), subdiv=2)
            part(o, "dirt", f)

    # Hay: two bales with one across on top.
    mock.bale_stack(cx - 3.5, cy + 0.5, 0.0, f, layers=2)

    # Region trees and props along the back.
    if r["props"] == "oak":
        oak(cx + 4.5, cy + 5.5, f, rng)
        oak(cx - 6.5, cy + 6.5, f, rng)
    elif r["props"] == "pine":
        pine(cx + 4.5, cy + 5, f, rng, scale=1.25)
        pine(cx - 6.5, cy + 6.5, f, rng)
        pine(cx + 7, cy + 7.5, f, rng, scale=0.8)
    elif r["props"] == "cactus":
        cactus(cx + 5, cy + 4.5, f, rng)
        rock(cx - 7, cy + 6, f, rng, 1.4)
        rock(cx + 7.5, cy - 1, f, rng, 0.8)
    elif r["props"] == "snowpine":
        pine(cx + 4.5, cy + 5, f, rng, snow=True, scale=1.25)
        pine(cx - 6.5, cy + 6.5, f, rng, snow=True)
        rock(cx + 7.5, cy - 1.5, f, rng, 1.0)
    elif r["props"] == "deadtree":
        dead_tree(cx + 4, cy + 6, f, rng)
        dead_tree(cx - 6.5, cy + 6.5, f, rng)

    # Fence along the front right, and a signpost in the accent color.
    for k in range(3):
        part(mock.box("post", (0.45, 2.6, 0.45), (cx + 2.5 + k * 2.6, cy - 7.5, 1.3), BLANK), "handle", f, along="z")
    for z in (1.0, 2.0):
        part(mock.box("rail", (5.6, 0.3, 0.2), (cx + 5.1, cy - 7.5, z), BLANK), "handle", f)
    part(mock.box("signpost", (0.45, 4.2, 0.45), (cx - 6.5, cy - 4.5, 2.1), BLANK), "handle", f, along="z")
    part(mock.box("signboard", (3.8, 1.5, 0.3), (cx - 6.5, cy - 4.75, 3.7), BLANK), "paint_red", f)

    # Palette chips: ground, hay, bark, leaves, accent, sky.
    hay = r["hay"] or ((0.86, 0.80, 0.60), (0.74, 0.66, 0.44), (0.52, 0.45, 0.28))
    bark = r["bark"] or ((0.38, 0.33, 0.27), (0.30, 0.25, 0.20), (0.16, 0.13, 0.10))
    chips = [r["ground"][1], hay[1], bark[1], r["leaves"][1], r["accent"][1], r["sky"]]
    for k, col in enumerate(chips):
        mock.box("chip", (2.2, 0.3, 1.6), (cx - 6.25 + k * 2.5, cy - TILE / 2 - 1.6, 0.15), flat(f"chip_{key}_{k}", col, 0.8))

    mock.label(r["name"].upper(), (cx, cy - TILE / 2 - 4.0, 0.2), 1.5, INK)
    mock.label(f"{r['tier']}  ·  {r['needle']} needles", (cx, cy - TILE / 2 - 5.6, 0.2), 0.7, SUB)
    mock.label(f"accent: {r['accent_name']}", (cx, cy - TILE / 2 - 6.7, 0.2), 0.7, SUB)

mock.label("REGION STYLE SHEET  (Rustic LT2)", (0, -TILE / 2 - 11.0, 0.2), 2.0, INK)
mock.label("chips: ground · hay · bark · leaves · accent · sky", (0, -TILE / 2 - 13.4, 0.2), 1.0, SUB)

mock.box("floor", (200, 1, 80), (0, 0, -1.2), flat("floor", (0.78, 0.76, 0.70)))
mock.scene_setup(world_color=(0.76, 0.77, 0.75), res=(2600, 1100), samples=48)
mock.sun(rotation=(0.65, 0.15, 0.45), energy=3.0)
mock.camera((0, -118, 96), look_at=(0, -4.5, 0), lens=42)
mock.render(mock.out_path("region_style_sheet.png"))

"""Needle rarity sheet: every needle type grouped by rarity tier, at dusk so the glows read,
using the tier looks in mockups/rarity.py. Needles are drawn 4x their game size (1.2 x 0.15 studs).

Run:
  python blender/mockups/needle_sheet.py [out_folder]
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mock  # noqa: E402
from mock import rgb  # noqa: E402
from rarity import MUTATED, NEEDLES, TIERS  # noqa: E402

bpy.ops.wm.read_factory_settings(use_empty=True)
F = mock.rustic_finish()
BLANK = mock.mat("tmp", (1, 1, 1))
INK = mock.mat("ink", rgb(236, 228, 210), 0.9)
SUB = mock.mat("sub", rgb(190, 182, 166), 0.9)
SCALE = 4.0


def needle(x, y, color, emit, size=1.0, name="needle"):
    m = mock.mat(f"{name}_{color}_{emit}", rgb(*color), 0.35, 0.0 if emit else 0.8, emit=emit)
    L, r = 1.2 * SCALE * size, 0.075 * SCALE * size
    mock.cylinder("shaft", r, L * 0.82, (x, y, r + 0.05), m, verts=8, rot=(0, math.pi / 2, 0))
    bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=r, depth=L * 0.18, location=(x + L * 0.5, y, r + 0.05),
                                    rotation=(0, math.pi / 2, 0))
    bpy.context.active_object.data.materials.append(m)
    bpy.ops.mesh.primitive_torus_add(major_radius=r * 1.5, minor_radius=r * 0.45, location=(x - L * 0.46, y, r + 0.05),
                                     rotation=(math.pi / 2, 0, 0))
    bpy.context.active_object.data.materials.append(m)


def point_light(x, y, color, rng_studs, brightness):
    if not brightness:
        return
    light = bpy.data.lights.new("glow", "POINT")
    light.color = rgb(*color)
    light.energy = 60 * brightness * rng_studs / 5
    light.shadow_soft_size = 0.4
    o = bpy.data.objects.new("glow", light)
    o.location = (x, y, 1.2)
    bpy.context.collection.objects.link(o)


tiers = [t for t in TIERS]
col_w = 9.5
for ti, (key, label, material, rng_studs, bright, pulse, extras, emit) in enumerate(tiers):
    cx = (ti - (len(tiers) - 1) / 2) * col_w
    members = [n for n in NEEDLES if n[2] == key] if key != "mythic" else [("steel", "Any type", "mythic", MUTATED)]
    mock.finish_part(mock.box("plank", (8.4, 0.4, 13), (cx, 0, -0.2), BLANK), "handle", F)
    for k, (nid, name, _, color) in enumerate(members):
        y = 3.5 - k * 3.6
        size = 1.6 if key == "mythic" else 1.0
        needle(cx, y, color, emit, size, nid)
        point_light(cx, y, color, rng_studs, bright)
        mock.label(name, (cx, y - 1.4, 0.05), 0.55, SUB)
        if key == "legendary" or key == "mythic":
            star = mock.mat(f"mote_{key}", rgb(*(MUTATED if key == "mythic" else (255, 240, 180))), 0.5, emit=10)
            for s in range(10):
                a = s * 2.4
                mock.box("mote", (0.12, 0.12, 0.12), (cx + math.cos(a) * (1.2 + s * 0.15), y + math.sin(a) * 0.9, 0.6 + (s % 4) * 0.4), star,
                         rot=(0.6, 0.6, 0))
    mock.label(label.upper(), (cx, -7.6, 0.05), 0.8, INK)
    line2 = f"{material}" + (f", light {rng_studs}/{bright:g}" if bright else ", no light")
    mock.label(line2, (cx, -8.6, 0.05), 0.42, SUB)
    mock.label(extras, (cx, -9.3, 0.05), 0.38, SUB)

mock.label("NEEDLE RARITY GLOW", (0, 9.2, 0.05), 1.3, INK)
mock.label("drawn 4x game size  ·  shown at dusk", (0, 7.9, 0.05), 0.5, SUB)

mock.box("floor", (120, 1, 60), (0, 0, -0.9), mock.mat("floor", rgb(52, 56, 58), 0.95))
mock.scene_setup(world_color=(0.10, 0.12, 0.16), world_strength=0.6, res=(2400, 1100), samples=64)
mock.sun(rotation=(0.9, 0.2, 0.6), energy=0.8)
mock.camera((0, -46, 58), look_at=(0, -0.8, 0), lens=40)
mock.render(mock.out_path("needle_rarity.png"))

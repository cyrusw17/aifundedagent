"""Design mockups for the Robux truck skins (V8). Each skin is the cash truck's own model with only its paint
and trim swapped, so size and stats are identical (monetization rule: Robux trucks are never stronger).
Glow stays off: glow means rarity.

Run:
  python blender/mockups/truck_skins.py [out_folder]
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mock  # noqa: E402
from mock import rgb  # noqa: E402

bpy.ops.wm.read_factory_settings(use_empty=True)
BLANK = mock.mat("tmp", (1, 1, 1))
INK = mock.mat("ink", rgb(40, 34, 28), 0.9)
SUB = mock.mat("sub", rgb(80, 72, 62), 0.9)
BASE = mock.rustic_finish()


def shades(r, g, b):
    """(light, mid, dark) sRGB 0-1 from a 0-255 mid color."""
    mid = (r / 255, g / 255, b / 255)
    return tuple(min(1, c * 1.2) for c in mid), mid, tuple(c * 0.68 for c in mid)


FOREST = shades(66, 92, 64)
NAVY = shades(40, 50, 74)
GOLD = shades(196, 166, 98)
DEEP_GREEN = shades(46, 72, 54)
CREAM = BASE.pal["paint_cream"]
CANVAS = shades(214, 204, 178)

# key, label, cash truck, the paint kind that truck uses for its body, new body palette, trim
SKINS = [
    ("homestead_classic", "Homestead Classic", "rusty_pickup", "paint_red", None, "two_tone"),
    ("timber_wolf_4x4", "Timber Wolf 4x4", "rusty_pickup", "paint_red", FOREST, "light_bar"),
    ("midnight_express", "Midnight Express", "box_truck", "paint_cream", NAVY, "stripe"),
    ("prairie_schooner", "Prairie Schooner", "farm_flatbed", "paint_green", None, "canvas"),
    ("founders_semi", "Founders' Semi", "semi_rig", "paint_blue", DEEP_GREEN, "pinstripe"),
]


TRIM = {"paint_yellow": mock.mat("trim_gold", rgb(214, 190, 120), 0.5, 0.0),
        "paint_cream": mock.mat("trim_cream", rgb(222, 210, 180), 0.7),
        "lamp": mock.mat("trim_lamp", rgb(236, 230, 210), 0.3)}


def B(f, kind, size, loc, rot=(0, 0, 0)):
    if kind in TRIM:
        return mock.box("trim", (size[0], size[2], size[1]), loc, TRIM[kind], rot)
    return mock.finish_part(mock.box("p", (size[0], size[2], size[1]), loc, BLANK, rot), kind, f, studs=True)


def trim(f, kind, lo, hi):
    L, W, H = hi.x - lo.x, hi.y - lo.y, hi.z - lo.z
    cx, cy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2
    front = hi.x  # trucks are turned to face +X
    if kind == "two_tone":  # cream upper band down the side, barn red below
        B(f, "paint_cream", (L * 0.97, W + 0.3, 1.1), (cx, cy, lo.z + H * 0.5))
        return "barn red with a cream belt line, grey bumper"
    if kind == "light_bar":
        B(f, "metal", (1.0, W * 0.8, 0.5), (front - L * 0.33, cy, hi.z + 0.25))
        for k in range(4):
            B(f, "lamp", (0.2, 0.9, 0.35), (front - L * 0.33 - 0.55, cy + (k - 1.5) * 1.6, hi.z + 0.3))
        return "forest green, roof light bar (lamps off), same tires"
    if kind == "stripe":
        B(f, "paint_yellow", (L * 0.95, W + 0.3, 0.5), (cx, cy, lo.z + H * 0.45))
        return "deep navy, one thin pale-gold stripe, no glow"
    if kind == "canvas":  # hoops and a canvas cover over the rear 60%
        hz = hi.z + 0.3
        bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=W * 0.5, depth=L * 0.55,
                                            location=(lo.x + L * 0.3, cy, hz - W * 0.18), rotation=(0, math.pi / 2, 0))
        cover = bpy.context.active_object
        cover.scale = (1, 1, 0.75)
        mock.finish_part(cover, "cloth", f, studs=True)
        return "weathered wood sides, canvas hoop cover (own Cover mesh)"
    if kind == "pinstripe":
        for dz in (0.0, 0.6):
            B(f, "paint_yellow", (L * 0.36, W + 0.3, 0.15), (front - L * 0.2, cy, lo.z + H * 0.36 + dz))
        B(f, "paint_yellow", (0.9, W + 0.35, 0.9), (front - L * 0.22, cy, lo.z + H * 0.52))  # door crest
        return "deep green, gold pinstripes, gold door crest"
    return ""


x = -70.0
first = x
for key, label, truck, body, pal, kind in SKINS:
    kinds = {}
    if pal:
        kinds[body] = pal
    if kind == "two_tone":
        kinds["tire"] = BASE.pal["tire"]
    if kind == "canvas":
        kinds[body] = BASE.pal["wood"]
        kinds["cloth"] = CANVAS
    f = mock.rustic_finish(name=key, **kinds) if kinds else mock.rustic_finish(name=key, paint_red=BASE.pal["paint_red"])
    root = mock.prop_any("vehicles", truck, (0, 0, 0), rot_z=math.pi / 2, f=f)
    bpy.context.view_layer.update()
    lo, hi = mock.bounds(root)
    L = hi.x - lo.x
    root.location = (x - (lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, 0)
    bpy.context.view_layer.update()
    lo, hi = mock.bounds(root)
    note = trim(f, kind, lo, hi)
    mock.label(label, (x, -11, 0.05), 1.9, INK)
    mock.label(f"skin of {truck}  ·  same size and stats", (x, -13.8, 0.05), 0.95, SUB)
    mock.label(note, (x, -15.8, 0.05), 0.85, SUB)
    x += max(L, 26) + 8

mid = (first + x - max(L, 26) - 8) / 2
mock.box("ground", (400, 0.6, 120), (mid, 10, -0.3), mock.mat("ground", rgb(150, 132, 104), 0.95))
mock.label("ROBUX TRUCK SKINS  ·  paint and trim only", (mid, -20.5, 0.05), 2.4, INK)
mock.scene_setup(world_color=(0.78, 0.82, 0.86), res=(2800, 1100), samples=48)
mock.sun(rotation=(0.75, 0.2, -0.5), energy=3.6)
mock.camera((mid, -235, 60), look_at=(mid, -4, 4), lens=40)
mock.render(mock.out_path("truck_skins.png"))

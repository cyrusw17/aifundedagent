"""Design mockups for the six sorter tier roofs (Machines.luau dressTier). Each sorter is the game's two-cell
box (6 wide, 12 long, walls 7 tall on the belt), with the tier's painted band down both sides and its own
silhouette on the downstream half of the roof, so a tier reads from across a plot. Rustic block-outs in studs.

Run:
  python blender/mockups/sorter_roofs.py [out_folder]
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mock  # noqa: E402
from mock import rgb  # noqa: E402

bpy.ops.wm.read_factory_settings(use_empty=True)
F = mock.rustic_finish()
BLANK = mock.mat("tmp", (1, 1, 1))
INK = mock.mat("ink", rgb(40, 34, 28), 0.9)
SUB = mock.mat("sub", rgb(80, 72, 62), 0.9)
T, TOP, HEIGHT = 6, 3.5, 7  # tile, belt top, side wall height (Machines.sorter)
ROOT = None  # every part made goes under this empty, so a whole sorter can be turned


def own(o):
    o.parent = ROOT
    return o


def B(kind, size, loc, rot=(0, 0, 0), along="x"):
    """size and loc in Blender axes (x, y depth, z up)."""
    o = mock.box("p", (size[0], size[2], size[1]), loc, BLANK, rot)
    if isinstance(kind, str):
        return own(mock.finish_part(o, kind, F, along, studs=True))
    o.data.materials.clear()
    o.data.materials.append(kind)
    return own(o)


def C(kind, r, depth, loc, rot=(0, 0, 0), verts=16, along="z"):
    o = mock.cylinder("c", r, depth, loc, BLANK, verts=verts, rot=rot)
    if isinstance(kind, str):
        return own(mock.finish_part(o, kind, F, along, studs=True))
    o.data.materials.clear()
    o.data.materials.append(kind)
    return own(o)


def torus(kind, R, r, loc, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, location=loc, rotation=rot, major_segments=28,
                                     minor_segments=8)
    o = bpy.context.active_object
    if isinstance(kind, str):
        return own(mock.finish_part(o, kind, F, studs=True))
    o.data.materials.append(kind)
    return own(o)


AX = (0, math.pi / 2, 0)  # turns a cylinder to lie along X
TIERS = [
    ("hand_sieve", "Hand Sieve", 1, (160, 132, 96), "riddle sieve on the roof, shakes"),
    ("shaker_table", "Shaker Table", 2, (122, 138, 104), "slatted deck on four springs, shakes"),
    ("conveyor_sorter", "Conveyor Sorter", 3, (104, 124, 140), "hooded belt and motor, motor spins"),
    ("magnet_drum", "Magnet Drum", 4, (150, 72, 58), "big drum between bearings, spins"),
    ("optical_sorter", "Optical Sorter", 5, (196, 160, 84), "brass-trimmed cabinet, camera lamp lit while running"),
    ("alien_collector", "Alien Collector", 6, (96, 196, 180), "glass dome, glowing ring spins (quest tier)"),
]


def sorter(tier_id, color):
    paint = mock.mat(f"band_{tier_id}", rgb(*color), 0.7, 0.3 if tier_id == "optical_sorter" else 0.0)
    # Belt tile under it, for scale.
    B("metal", (T, T * 2, TOP - 0.4), (0, 0, (TOP - 0.4) / 2))
    B("tire", (T - 1, T * 2, 0.4), (0, 0, TOP - 0.2))
    for sx in (-1, 1):
        B("handle", (0.6, T * 2, HEIGHT), (sx * (T / 2 - 0.3), 0, TOP + HEIGHT / 2), along="y")
        B(paint, (0.7, T * 2 + 0.1, 0.9), (sx * (T / 2 - 0.3), 0, TOP + HEIGHT - 1))
        for y in (-T + 0.4, 0, T - 0.4):
            B("metal", (0.75, 0.35, HEIGHT), (sx * (T / 2 - 0.3), y, TOP + HEIGHT / 2))  # iron straps
    B("metal", (T + 0.4, T * 2 + 0.4, 1), (0, 0, TOP + HEIGHT + 0.5))  # roof
    B("metal", (T - 1.4, 3, 1.4), (0, -1, TOP + HEIGHT + 1.7))  # hopper on the upstream half
    B("tire", (T - 1.2, 0.4, HEIGHT - 0.6), (0, -(T - 0.2), TOP + (HEIGHT - 0.6) / 2 + 0.3))  # rubber flap
    B("metal", (3, 2, 0.3), (-T / 2 - 1.4, 0, TOP + 2.5), rot=(0, math.radians(20), 0))  # needle chute
    # Downstream half of the roof: the tier silhouette (game: top = center * (0, TOP + h + 1, -T/2 - 0.2)).
    tx, ty, tz = 0, T / 2 + 0.2, TOP + HEIGHT + 1
    if tier_id == "hand_sieve":
        torus("handle", 2.15, 0.32, (tx, ty, tz + 0.35))
        C("metal", 2.0, 0.1, (tx, ty, tz + 0.3), verts=28)
        for k in range(-3, 4):
            B("metal", (0.06, 3.8 - abs(k) * 0.35, 0.12), (tx + k * 0.5, ty, tz + 0.4))  # mesh wires
            B("metal", (3.8 - abs(k) * 0.35, 0.06, 0.12), (tx, ty + k * 0.5, tz + 0.4))
    elif tier_id == "shaker_table":
        for x in (-1.8, 1.8):
            for y in (-1.8, 1.8):
                for k in range(4):
                    torus("metal", 0.35, 0.08, (tx + x, ty + y, tz + 0.15 + k * 0.2))  # coil spring
        tilt = (0, math.radians(8), 0)
        B(paint, (5, 5.2, 0.3), (tx, ty, tz + 1), rot=tilt)
        for k in range(-2, 3):
            B("handle", (5.1, 0.5, 0.18), (tx, ty + k * 1.0, tz + 1.2), rot=tilt)  # slats
        B("handle", (0.3, 5.2, 0.6), (tx - 2.5, ty, tz + 1.5), rot=tilt)  # lip on the high side
    elif tier_id == "conveyor_sorter":
        hood_rot = (math.radians(-12), 0, 0)
        B(paint, (3.6, 5.4, 1.4), (tx, ty, tz + 1), rot=hood_rot)
        for k in range(-2, 3):
            B("metal", (3.7, 0.2, 1.5), (tx, ty + k * 1.0, tz + 1 + k * 0.21), rot=hood_rot)  # ribs
        C("metal", 0.7, 1.6, (tx + 2.2, ty + 2.2, tz + 0.8), rot=AX, verts=14)  # motor
        C("handle", 0.35, 0.4, (tx + 3.1, ty + 2.2, tz + 0.8), rot=AX, verts=10)  # pulley
    elif tier_id == "magnet_drum":
        for sx in (-1, 1):
            B("metal", (0.8, 1.4, 2.4), (tx + sx * (T / 2 - 0.6), ty, tz + 1.2))
        C(paint, 2.0, T - 2, (tx, ty, tz + 2.4), rot=AX, verts=24)
        for sx in (-1, 1):
            C("metal", 2.08, 0.25, (tx + sx * (T / 2 - 1.15), ty, tz + 2.4), rot=AX, verts=24)  # iron end bands
        C("metal", 0.3, T - 0.6, (tx, ty, tz + 2.4), rot=AX, verts=10)  # axle
    elif tier_id == "optical_sorter":
        B("metal", (4.4, 4.4, 4.5), (tx, ty, tz + 2.25))
        B(paint, (4.6, 4.6, 0.4), (tx, ty, tz + 4.5))
        B(paint, (4.6, 4.6, 0.3), (tx, ty, tz + 0.15))
        B(paint, (2, 1.4, 1.6), (tx, ty - 1.2, tz + 5.5))  # camera hood, looking upstream
        lens = mock.mat("lens", rgb(255, 226, 160), 0.1, emit=2.0)
        B(lens, (1.2, 0.2, 0.8), (tx, ty - 1.95, tz + 5.5))
        for k in range(3):
            B("glass", (0.9, 0.1, 0.9), (tx - 1.2 + k * 1.2, ty - 2.25, tz + 2.6))  # inspection windows
    elif tier_id == "alien_collector":
        glass = mock.mat("dome_glass", rgb(170, 230, 220), 0.05, alpha=0.45)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=2.4, location=(tx, ty, tz + 1))
        own(bpy.context.active_object).data.materials.append(glass)
        ring = mock.mat("dome_ring", rgb(*color), 0.3, emit=3.0)
        torus(ring, 2.7, 0.22, (tx, ty, tz + 0.3))
        core = mock.mat("dome_core", rgb(200, 255, 240), 0.2, emit=4.0)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.6, location=(tx, ty, tz + 1.6))
        own(bpy.context.active_object).data.materials.append(core)


SPACING = 17
for i, (tier_id, name, stars, color, note) in enumerate(TIERS):
    x = (i - (len(TIERS) - 1) / 2) * SPACING
    ROOT = bpy.data.objects.new(tier_id, None)
    bpy.context.collection.objects.link(ROOT)
    sorter(tier_id, color)
    ROOT.rotation_euler = (0, 0, -math.pi / 2)  # length across the sheet, downstream end to the right
    ROOT.location = (x, 0, 0)
    mock.label(name, (x, -7.5, 0.05), 1.15, INK)
    mock.label("*" * stars, (x, -9.0, 0.05), 1.0, mock.mat(f"star_{tier_id}", rgb(*color), 0.6))
    mock.label(note, (x, -10.3, 0.05), 0.5, SUB)
mock.label("SORTER TIER ROOFS  ·  Rustic block-outs from Machines.luau", (0, -13.2, 0.05), 1.6, INK)

mock.box("ground", (200, 0.6, 120), (0, 20, -0.3), mock.mat("ground", rgb(150, 132, 104), 0.95))
mock.scene_setup(world_color=(0.78, 0.82, 0.86), res=(2800, 1100), samples=48)
mock.sun(rotation=(0.75, 0.2, -0.5), energy=3.6)
mock.camera((0, -112, 40), look_at=(0, -2, 5), lens=40)
mock.render(mock.out_path("sorter_roofs.png"))

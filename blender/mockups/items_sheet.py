"""Design mockups for the new backlog items: the loaded wheelbarrow, the needle display wall, the needle
bundle and the six foreign-object finds (Config/Finds.luau). Sizes follow the game code where it exists
(Wheelbarrow.luau, Display.luau, Factory bundle size); the finds are drawn 2.5x so they read next to the wall.

Run:
  python blender/mockups/items_sheet.py [out_folder]
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mock  # noqa: E402
from mock import rgb  # noqa: E402
from rarity import NEEDLES, TIERS  # noqa: E402

bpy.ops.wm.read_factory_settings(use_empty=True)
F = mock.rustic_finish()
BLANK = mock.mat("tmp", (1, 1, 1))
INK = mock.mat("ink", rgb(40, 34, 28), 0.9)
SUB = mock.mat("sub", rgb(80, 72, 62), 0.9)
GOLD = mock.mat("gold", rgb(212, 175, 85), 0.25, 1.0)
GEM = mock.mat("gem", rgb(70, 120, 200), 0.05, 0.0, emit=0.4)
UP = (math.pi / 2, 0, 0)
FIND = 2.5  # finds are drawn this many times their game size


def B(kind, size, loc, rot=(0, 0, 0), along="x"):
    return mock.finish_part(mock.box("p", (size[0], size[2], size[1]), loc, BLANK, rot), kind, F, along, studs=True)


def C(kind, r, depth, loc, rot=(0, 0, 0), verts=12, along="z"):
    return mock.finish_part(mock.cylinder("c", r, depth, loc, BLANK, verts=verts, rot=rot), kind, F, along, studs=True)


def torus(kind_or_mat, R, r, loc, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, location=loc, rotation=rot,
                                     major_segments=24, minor_segments=8)
    o = bpy.context.active_object
    if isinstance(kind_or_mat, str):
        return mock.finish_part(o, kind_or_mat, F, studs=True)
    o.data.materials.append(kind_or_mat)
    return o


def needle_mesh(x, y, z, color, emit, s=1.0, rot_z=0.0):
    """A game needle (1.2 x 0.15) at scale s, lying along X."""
    m = mock.mat(f"n_{color}_{emit}", rgb(*color), 0.35, 0.0 if emit else 0.8, emit=emit)
    L, r = 1.2 * s, 0.06 * s
    c, sn = math.cos(rot_z), math.sin(rot_z)
    mock.cylinder("shaft", r, L * 0.82, (x, y, z), m, verts=6, rot=(0, math.pi / 2, rot_z))
    bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=r, depth=L * 0.18, location=(x + c * L * 0.5, y + sn * L * 0.5, z),
                                    rotation=(0, math.pi / 2, rot_z))
    bpy.context.active_object.data.materials.append(m)
    bpy.ops.mesh.primitive_torus_add(major_radius=r * 1.6, minor_radius=r * 0.5, location=(x - c * L * 0.46, y - sn * L * 0.46, z),
                                     rotation=(math.pi / 2, 0, rot_z + math.pi / 2))
    bpy.context.active_object.data.materials.append(m)


# ---------------------------------------------------------------- loaded wheelbarrow (game: tray 5 x 3.6, 3 bales)
def wheelbarrow(cx, cy):
    tz = 1.4  # tray floor
    B("handle", (5, 3.6, 0.25), (cx, cy, tz), along="x")
    for sx in (-1, 1):
        B("handle", (0.2, 3.6, 0.8), (cx + sx * 2.5, cy, tz + 0.4))
        B("handle", (5.2, 0.2, 0.8), (cx, cy + sx * 1.8, tz + 0.4))
        B("metal", (5.3, 0.25, 0.15), (cx, cy + sx * 1.85, tz + 0.82))  # iron rim
    # Wheel at the front (-X), handles out the back (+X), two legs.
    C("tire", 0.7, 0.4, (cx - 3.4, cy, 0.7), rot=UP, verts=16)  # Wheel_L1
    C("metal", 0.3, 0.5, (cx - 3.4, cy, 0.7), rot=UP, verts=8)
    for sy in (-1, 1):
        B("handle", (7.4, 0.25, 0.25), (cx + 0.6, cy + sy * 1.2, 1.15), rot=(0, -0.12, 0))
        B("handle", (0.25, 0.25, 1.1), (cx + 1.6, cy + sy * 1.2, 0.55))
        B("leather", (0.9, 0.32, 0.32), (cx + 4.0, cy + sy * 1.2, 0.72), rot=(0, -0.12, 0))
    for n in range(3):
        mock.bale((cx, cy, tz + 0.13 + n * mock.BALE[2]), 0.0, F)
    return "wheelbarrow_loaded", "tray 5 x 3.6, holds 3 bales", "wheel is its own mesh; bales ride loose"


# ---------------------------------------------------------------- needle display wall (game: 6 wide, 7 tall, 6 pegs)
def display_wall(cx, cy):
    T, H = 6, 7
    B("handle", (T - 0.4, 0.4, H), (cx, cy, H / 2), along="z")
    for sx in (-1, 1):
        B("bark", (0.5, 0.6, H + 0.6), (cx + sx * (T / 2 - 0.25), cy - 0.1, (H + 0.6) / 2), along="z")
    B("metal", (T + 0.2, 1.0, 0.4), (cx, cy - 0.1, H + 0.6))
    B("paint_red", (3.8, 0.3, 0.8), (cx, cy - 0.45, H + 1.25))  # accent name board on the cap
    mock.label("NEEDLE DISPLAY", (cx, cy - 0.62, H + 1.2), 0.38, mock.mat("cream", rgb(236, 226, 204)), rot=UP)
    show = [n for n in NEEDLES if n[2] in ("rare", "epic", "legendary")][:5]
    emits = {t[0]: t[7] for t in TIERS}
    for i in range(6):
        col, row = i % 3, i // 3
        x, z = cx + (col - 1) * 1.8, H - 2 - row * 3
        B("cloth", (1.6, 0.1, 2.2), (x, cy - 0.25, z + 0.2))  # velvet backing
        B("metal", (0.9, 0.3, 0.3), (x, cy - 0.4, z))  # peg
        B("paint_yellow", (0.9, 0.08, 0.35), (x, cy - 0.3, z - 0.75))  # brass plaque
        if i < len(show):
            nid, name, tier, color = show[i]
            needle_mesh(x, cy - 0.65, z + 0.5, color, emits[tier])
    return "needle_display_wall", "6 x 1 x 7.6 (one tile)", "6 pegs, velvet backs, brass plaques"


# ---------------------------------------------------------------- needle bundle (game: 1.3 x 0.55 x 0.55)
def bundle(cx, cy, s, z0=0.0):
    steel = NEEDLES[0][3]
    k = 0
    for row, count in ((0, 4), (1, 3), (2, 3)):
        for j in range(count):
            y = cy + (j - (count - 1) / 2) * 0.15 * s
            needle_mesh(cx, y, z0 + (0.09 + row * 0.13) * s, steel, 0.0, s=1.05 * s)
            k += 1
    for dx in (-0.3, 0.3):
        C("twine", 0.32 * s, 0.1 * s, (cx + dx * s, cy, z0 + 0.22 * s), rot=(0, math.pi / 2, 0), verts=10, along="y")


# ---------------------------------------------------------------- finds (Config/Finds.luau), drawn at FIND x
def boot(x, y, s):
    B("handle", (1.6 * s, 0.85 * s, 0.18 * s), (x, y, 0.09 * s))  # sole
    B("leather", (1.5 * s, 0.8 * s, 0.45 * s), (x + 0.02 * s, y, 0.4 * s))
    B("leather", (0.62 * s, 0.75 * s, 0.9 * s), (x + 0.42 * s, y, 0.72 * s))
    B("leather", (0.6 * s, 0.72 * s, 0.25 * s), (x + 0.12 * s, y, 1.08 * s), rot=(0, 0.9, 0))  # flopped shaft
    C("twine", 0.05 * s, 0.6 * s, (x - 0.1 * s, y - 0.3 * s, 0.55 * s), rot=UP, verts=6)
    return "old_boot", "1 in 50"


def horseshoe(x, y, s):
    for k in range(11):
        a = math.radians(-30 + k * 24)
        B("metal", (0.24 * s, 0.32 * s, 0.15 * s), (x + math.cos(a) * 0.42 * s, y + math.sin(a) * 0.42 * s, 0.08 * s),
          rot=(0, 0, a))
        if k in (2, 4, 6, 8):
            B("handle", (0.07 * s, 0.07 * s, 0.17 * s), (x + math.cos(a) * 0.42 * s, y + math.sin(a) * 0.42 * s, 0.09 * s))
    return "horseshoe", "1 in 150"


def key(x, y, s):
    torus("metal", 0.16 * s, 0.04 * s, (x - 0.3 * s, y, 0.05 * s))
    B("metal", (0.55 * s, 0.07 * s, 0.07 * s), (x, y, 0.05 * s))
    B("metal", (0.08 * s, 0.18 * s, 0.07 * s), (x + 0.22 * s, y - 0.1 * s, 0.05 * s))
    B("metal", (0.06 * s, 0.13 * s, 0.07 * s), (x + 0.12 * s, y - 0.08 * s, 0.05 * s))
    return "rusty_key", "1 in 300"


def radio(x, y, s):
    B("handle", (1.4 * s, 0.7 * s, 0.75 * s), (x, y, 0.375 * s))
    C("handle", 0.7 * s, 0.7 * s, (x, y, 0.75 * s), rot=UP, verts=20, along="y")
    B("cloth", (0.8 * s, 0.05 * s, 0.75 * s), (x - 0.18 * s, y - 0.36 * s, 0.7 * s))  # grille
    for k in range(4):
        B("handle", (0.04 * s, 0.07 * s, 0.7 * s), (x - 0.42 * s + k * 0.16 * s, y - 0.39 * s, 0.7 * s))
    C("paint_cream", 0.18 * s, 0.05 * s, (x + 0.42 * s, y - 0.36 * s, 0.75 * s), rot=UP, verts=16)  # dial
    for dx in (0.3, 0.55):
        C("handle", 0.07 * s, 0.12 * s, (x + dx * s, y - 0.4 * s, 0.3 * s), rot=UP, verts=8)
    return "old_radio", "1 in 600"


def ring(x, y, s):
    torus(GOLD, 0.16 * s, 0.04 * s, (x, y, 0.2 * s), rot=UP)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.06 * s, location=(x, y, 0.4 * s))
    bpy.context.active_object.data.materials.append(GEM)
    return "lost_ring", "1 in 1,000"


def fossil(x, y, s):
    B("stone", (1.2 * s, 1.0 * s, 0.3 * s), (x, y, 0.15 * s), rot=(0, 0, 0.15))
    for k in range(26):
        a = k * 0.55
        r = 0.05 * s + k * 0.013 * s
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=5, radius=0.05 * s + k * 0.003 * s,
                                             location=(x + math.cos(a) * r, y + math.sin(a) * r, 0.31 * s))
        mock.finish_part(bpy.context.active_object, "paint_cream", F, studs=True)
    return "fossil", "1 in 2,000"


ground = mock.box("ground", (140, 0.6, 90), (0, 6, -0.3), mock.mat("ground", rgb(150, 132, 104), 0.95))
for cx, cy, build in ((-24, 0, wheelbarrow), (-8, 1.5, display_wall)):
    name, size, note = build(cx, cy)
    mock.label(name, (cx, -5, 0.05), 1.0, INK)
    mock.label(size, (cx, -6.4, 0.05), 0.6, SUB)
    mock.label(note, (cx, -7.5, 0.05), 0.5, SUB)

# Bundle: game size on a plank, and 4x beside it.
B("handle", (7, 3.4, 0.3), (5, 0, 0.15))
bundle(3.0, 0, 1.0, z0=0.3)
bundle(6.6, 0, 4.0, z0=0.3)
mock.label("needle_bundle", (5, -5, 0.05), 1.0, INK)
mock.label("1.3 x 0.55 x 0.55, 10 needles", (5, -6.4, 0.05), 0.6, SUB)
mock.label("game size and 4x; eyes all one end", (5, -7.5, 0.05), 0.5, SUB)

finds = (boot, horseshoe, key, radio, ring, fossil)
for k, build in enumerate(finds):
    fx = 14 + (k % 3) * 5.2
    fy = 2.5 - (k // 3) * 6.2
    name, odds = build(fx, fy, FIND)
    mock.label(name, (fx, fy - 2.4, 0.05), 0.6, INK)
    mock.label(odds, (fx, fy - 3.3, 0.05), 0.45, SUB)
mock.label(f"foreign objects (drawn {FIND:g}x)", (19.2, -10.2, 0.05), 0.75, INK)
mock.label("NEW ITEMS  ·  Rustic block-outs", (1, -12.5, 0.05), 1.5, INK)

mock.scene_setup(world_color=(0.78, 0.82, 0.86), res=(2600, 1300), samples=48)
mock.sun(rotation=(0.75, 0.2, -0.5), energy=3.6)
mock.camera((1, -76, 28), look_at=(1, -2, 3), lens=42)
mock.render(mock.out_path("items_sheet.png"))

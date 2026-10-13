"""Design mockups for the new hub buildings in the backlog: the Homestead bank, the trading post, a field
bale chute with the starter pickup backed under it, and the bounty board. Block-outs in the Rustic house
finish, in studs, sized to MODEL_SPECS.md (art-review) and the game code. Each building carries the region
accent (barn red for Homestead) on one sign only.

Run:
  python blender/mockups/buildings_sheet.py [out_folder]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mock  # noqa: E402
from mock import rgb  # noqa: E402

bpy.ops.wm.read_factory_settings(use_empty=True)
F = mock.rustic_finish()
BLANK = mock.mat("tmp", (1, 1, 1))
INK = mock.mat("ink", rgb(40, 34, 28), 0.9)
SUB = mock.mat("sub", rgb(80, 72, 62), 0.9)
CREAM = mock.mat("signtext", rgb(236, 226, 204), 0.8)
UP = (math.pi / 2, 0, 0)  # stands a label up, facing the camera (-Y)


def B(kind, size, loc, rot=(0, 0, 0), along="x"):
    return mock.finish_part(mock.box("p", (size[0], size[2], size[1]), loc, BLANK, rot), kind, F, along, studs=True)


def C(kind, r, depth, loc, rot=(0, 0, 0), verts=12, along="z"):
    return mock.finish_part(mock.cylinder("c", r, depth, loc, BLANK, verts=verts, rot=rot), kind, F, along, studs=True)


def sign_text(text, loc, size, mat=CREAM):
    return mock.label(text, loc, size, mat, rot=UP)


def gable(kind, cx, cy, z, width, depth, rise, overhang=1.0):
    """Two roof slabs meeting at a ridge along X."""
    half = depth / 2 + overhang
    slope = math.atan2(rise, depth / 2)
    run = half / math.cos(slope)
    drop = overhang * math.tan(slope)
    for s in (-1, 1):
        B(kind, (width + overhang * 2, run, 0.5), (cx, cy + s * half / 2, z + rise / 2 - drop / 2), rot=(-s * slope, 0, 0))


def crate(x, y, s=2.0, z=0.0):
    B("handle", (s, s, s), (x, y, z + s / 2))
    for d in (-1, 1):
        B("handle", (s + 0.05, 0.25, 0.3), (x, y - s / 2, z + s / 2 + d * s * 0.32))


def barrel(x, y, r=1.0, h=2.6):
    C("handle", r, h, (x, y, h / 2), verts=14)
    for z in (0.35, 0.8):
        C("metal", r + 0.05, 0.18, (x, y, h * z), verts=14)


# ---------------------------------------------------------------- Homestead bank (26 x 20 x 22)
def bank(cx):
    W, D = 26, 20
    fy = -D / 2
    B("stone", (W + 3, D + 6, 0.8), (cx, -2, 0.4))  # plinth and steps
    B("stone", (12, 2, 0.4), (cx, fy - 3.4, 0.2))
    B("stone", (W, D, 10.6), (cx, 0, 0.8 + 5.3))  # ground floor: dressed stone
    B("handle", (W, D, 8.4), (cx, 0, 11.4 + 4.2), along="z")  # upper floor: planks
    B("paint_cream", (W + 0.8, D + 0.8, 0.8), (cx, 0, 11.6))  # floor band
    B("paint_cream", (W + 1.2, D + 1.2, 1.0), (cx, 0, 20.3))  # cornice
    gable("paint_green", cx, 0, 20.8, W, D, 2.4, overhang=0.6)
    # Portico: four columns, an entablature and the sign.
    for k in range(4):
        C("paint_cream", 0.75, 10.6, (cx - 7.5 + k * 5, fy - 2.4, 6.1), verts=16)
    B("paint_cream", (19, 4, 1.4), (cx, fy - 1.6, 12.1))
    B("paint_red", (13, 0.5, 3.4), (cx, fy - 3.8, 15.2))
    sign_text("BANK", (cx, fy - 4.1, 14.9), 2.6)
    # Door and windows.
    B("handle", (4.4, 0.4, 7.2), (cx, fy - 0.1, 4.4))
    B("metal", (0.25, 0.5, 0.6), (cx + 1.6, fy - 0.35, 4.2))
    for sx in (-1, 1):
        x = cx + sx * 9.2
        B("paint_cream", (5.4, 0.5, 5.8), (x, fy - 0.05, 6.2))
        B("glass", (4.6, 0.5, 5.0), (x, fy - 0.15, 6.2))
        for wx in (-1.2, 0, 1.2):
            B("metal", (0.15, 0.6, 5.0), (x + wx, fy - 0.3, 6.2))  # teller bars
    # The vault, seen through the left window.
    C("metal", 2.0, 0.6, (cx - 9.2, fy + 1.4, 6.0), rot=UP, verts=24)
    C("paint_yellow", 0.4, 0.8, (cx - 9.2, fy + 1.0, 6.0), rot=UP, verts=12)
    for k in range(5):
        x = cx - 10 + k * 5
        B("paint_cream", (3, 0.5, 4.2), (x, fy - 0.05, 16.0))
        B("glass", (2.3, 0.5, 3.5), (x, fy - 0.15, 16.0))
    B("metal", (0.2, 0.2, 5), (cx + 11.5, fy - 2.5, 3.3))  # lamp post
    C("glow", 0.5, 0.9, (cx + 11.5, fy - 2.5, 6.0), verts=8)
    return "homestead_bank", "26 x 20 x 22", "stone below, planks above, columns, vault in the window"


# ---------------------------------------------------------------- trading post (24 x 18 x 16)
def trading_post(cx):
    W, D, H = 24, 18, 10.5
    fy = -D / 2
    B("handle", (W + 1, D + 5, 0.6), (cx, -2.4, 0.3), along="x")  # deck, runs out under the awning
    r = 0.62
    n = int(H / (r * 1.9))
    for k in range(n):
        z = 0.6 + r + k * r * 1.9
        C("bark", r, W + 1.6, (cx, D / 2 - r, z), rot=(0, math.pi / 2, 0), verts=10, along="x")
        for sx in (-1, 1):
            C("bark", r, D + 1.6, (cx + sx * (W / 2 - r), 0, z), rot=UP, verts=10, along="y")
    # Front: corner log stacks either side of the open shop front, and a counter.
    for sx in (-1, 1):
        for k in range(n):
            z = 0.6 + r + k * r * 1.9
            C("bark", r, 4.5, (cx + sx * (W / 2 - 2.6), fy + r, z), rot=(0, math.pi / 2, 0), verts=10, along="x")
    B("bark", (W - 9, 1.6, 1.6), (cx, fy + 0.8, H + 0.1), along="x")  # header log over the opening
    B("handle", (W - 10, 1.4, 3.6), (cx, fy + 2.4, 2.4))
    B("handle", (W - 9.6, 1.9, 0.3), (cx, fy + 2.4, 4.35))
    # Scale on the counter.
    B("metal", (0.25, 0.25, 1.8), (cx + 3, fy + 2.4, 5.4))
    B("metal", (2.6, 0.15, 0.15), (cx + 3, fy + 2.4, 6.3))
    for sx in (-1, 1):
        C("metal", 0.6, 0.15, (cx + 3 + sx * 1.2, fy + 2.4, 5.6), verts=12)
    # Shelves with goods at the back wall.
    for z in (3, 5.5, 8):
        B("handle", (W - 6, 1.2, 0.25), (cx, D / 2 - 2, z))
        for k in range(6):
            B("cloth" if k % 2 else "handle", (1.1, 0.9, 1.1), (cx - 8 + k * 3.2, D / 2 - 2, z + 0.7))
    gable("handle", cx, 0, H + 0.6, W + 1, D, 4.6, overhang=1.2)
    # Awning on posts, and the accent sign.
    for sx in (-1, 1):
        C("bark", 0.4, 8.2, (cx + sx * 10.5, fy - 4.6, 4.4), verts=8)
    B("handle", (W + 1, 5.4, 0.35), (cx, fy - 2.3, 8.3), rot=(-0.2, 0, 0))
    B("paint_red", (14, 0.5, 2.6), (cx, fy - 0.2, H + 2.4))
    sign_text("TRADING POST", (cx, fy - 0.5, H + 2.2), 1.45)
    for x, y in ((-10.5, -14.5), (-8.2, -15.2), (-9.4, -13.0)):
        crate(cx + x, y, 2.0)
    crate(cx - 9.4, -14.3, 1.6, z=2.0)
    for x in (8.5, 10.8):
        barrel(cx + x, -14.4)
    return "trading_post", "24 x 18 x 16", "open log front, awning, counter scale, crates and barrels"


# ---------------------------------------------------------------- field bale chute (12 x 16 x 14)
def bale_chute(cx):
    truck = mock.prop_any("vehicles", "rusty_pickup", (0, 0, 0), rot_z=math.pi / 2, f=F)
    bpy.context.view_layer.update()
    lo, hi = mock.bounds(truck)
    length, width = hi.x - lo.x, hi.y - lo.y
    # Back the truck in from the right so its bed sits under the hopper at cx.
    bed_x = lo.x + length * 0.27
    truck.location = (cx - bed_x + 1.0, -(lo.y + hi.y) / 2 - 1.0, 0)
    bpy.context.view_layer.update()
    clear_w = width + 1.6
    leg_y = clear_w / 2 + 0.4
    leg_h = 10.0
    for lx in (-4.6, 4.6):
        for ly in (-leg_y, leg_y):
            B("bark", (0.9, 0.9, leg_h + 3.6), (cx + lx, ly, (leg_h + 3.6) / 2), along="z")
        B("handle", (0.4, leg_y * 2, 0.5), (cx + lx, 0, 7.2), rot=(0.55, 0, 0))  # cross brace
    for ly in (-leg_y, leg_y):
        B("handle", (10.2, 0.9, 0.9), (cx, ly, leg_h + 0.45))  # head beams
    # Hopper: an upside-down square funnel of planks, hay heaped in it.
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=2.4, radius2=8.4, depth=4.2, location=(cx, 0, leg_h + 3.0),
                                    rotation=(0, 0, math.pi / 4), end_fill_type="NOTHING")
    hop = bpy.context.active_object
    m = hop.modifiers.new("solid", "SOLIDIFY")
    m.thickness = 0.3
    mock.finish_part(hop, "handle", F, along="z", studs=True)
    B("hay", (10.4, 10.4, 1.0), (cx, 0, leg_h + 4.4))  # HayFill
    # Gate at the throat and a short spout dropping into the bed.
    B("handle", (3.6, 3.6, 0.25), (cx, 0, leg_h + 0.8))
    B("handle", (3.6, 0.3, 1.4), (cx, -1.8, leg_h + 0.1))
    B("handle", (3.6, 0.3, 1.4), (cx, 1.8, leg_h + 0.1))
    # Lever on the front left leg (the one the driver walks to), the accent goes on its grip.
    lever_x, lever_y = cx - 4.6, -leg_y - 0.6
    B("metal", (0.3, 0.3, 3.2), (lever_x, lever_y, 4.8), rot=(0, 0.45, 0))
    B("paint_red", (0.55, 0.55, 0.9), (lever_x + 0.75, lever_y, 6.4), rot=(0, 0.45, 0))
    B("metal", (0.8, 0.5, 0.8), (lever_x, lever_y + 0.1, 3.4))
    sign_text("PULL", (lever_x, lever_y - 0.35, 2.4), 0.6, INK)
    return "field_bale_chute", f"12 x 16 x 14  (clear {clear_w:.1f} wide, {leg_h:.1f} tall)", \
        "hopper on legs, gate drops a bed's worth; lever at the driver's side"


# ---------------------------------------------------------------- bounty board (8 x 1.5 x 9)
def bounty_board(cx):
    for sx in (-1, 1):
        B("bark", (0.7, 0.7, 9), (cx + sx * 3.7, 0, 4.5), along="z")
    B("handle", (8, 0.35, 5.2), (cx, 0, 5.2), along="x")
    B("handle", (8.4, 0.5, 0.4), (cx, -0.1, 7.95))
    B("handle", (8.4, 0.5, 0.4), (cx, -0.1, 2.45))
    for s in (-1, 1):
        B("handle", (9.2, 1.0, 0.25), (cx, s * 0.45, 9.1 - 0.2), rot=(s * 0.45, 0, 0))
    B("paint_red", (5.2, 0.3, 0.9), (cx, -0.28, 7.15))
    sign_text("BOUNTIES", (cx, -0.48, 7.1), 0.62)
    for k, (dx, dz, rz) in enumerate(((-2.5, 5.0, 0.06), (0.1, 4.6, -0.04), (2.6, 5.2, 0.08))):
        B("cloth", (2.0, 0.1, 2.6), (cx + dx, -0.25, dz), rot=(0, rz, 0))  # Notice1-3
        for line in range(4):
            B("handle", (1.4, 0.05, 0.12), (cx + dx, -0.33, dz + 0.8 - line * 0.45), rot=(0, rz, 0))
        C("metal", 0.12, 0.2, (cx + dx, -0.36, dz + 1.15), rot=UP, verts=6)
    B("handle", (2.4, 2.4, 0.3), (cx, -2.4, 0.15))  # a stepping plank
    return "bounty_board", "8 x 1.5 x 9", "Notice1-3 are their own meshes so the game can recolor them"


ground = mock.box("ground", (260, 0.6, 160), (0, 15, -0.3), mock.mat("ground", rgb(150, 132, 104), 0.95))
items = [(-64, bank), (-26, trading_post), (16, bale_chute), (50, bounty_board)]
for x, build in items:
    key, size, note = build(x)
    mock.label(key, (x, -30, 0.05), 1.7, INK)
    mock.label(size, (x, -33.2, 0.05), 1.05, SUB)
    mock.label(note, (x, -35.6, 0.05), 0.8, SUB)
mock.label("NEW HUB BUILDINGS  ·  Rustic block-outs", (-8, -40.5, 0.05), 2.3, INK)

mock.scene_setup(world_color=(0.78, 0.82, 0.86), res=(2600, 1300), samples=48)
mock.sun(rotation=(0.75, 0.2, -0.5), energy=3.6)
mock.camera((-8, -190, 48), look_at=(-8, -8, 7), lens=40)
mock.render(mock.out_path("buildings_sheet.png"))

"""Homestead hub and base structures in the house style (LT2 shapes, Rustic finish).

Simple shells with no interiors. Built facing -y (RIG_FLIP turns them to face -Z in the .glb), ground at z = 0, sizes in studs (1 stud = 0.28 m).
Player doors are at least 4 x 7, vehicle openings at least 12 x 11. Truck beds and belts sit at 3.5.
The exporter keeps 4 materials per mesh (1 per moving part), so each builder sticks to 4 kinds.

  homestead_motors   truck dealer: glass showroom, garage door ("Door"), western false front sign
  land_office        clapboard office with a porch and a plot map board out front
  hay_sell_shop      public HAY SELL SHOP: open barn shed, loading dock at 3.5, conveyor into it
  field_bale_chute   hopper on legs over a truck lane, chute to 6.5; "Lever", "Gate", "HayFill"
  loading_dock       plot dock 11 wide at 3.5 with bumpers and a funnel ramp onto a belt
  hay_buyer          one 6 x 6 tile: belt, hopper over it, cash box
  bounty_board       notice board with "Notice1-3"
  trading_post       open-front log store with awning, scale, crates and barrels
  scarecrow          the moving scarecrow quest NPC, 7 tall; "Head", "ArmL", "ArmR"
  plot_fence_sign    plot boundary post with a blank owner board and fence stubs
  ferry_dock         wooden pier 40 x 30 with a "Ramp" at the sea end (-y) and bollards
  display_stand      needle display pedestal
  homestead_bank     stone and plank two storey bank with columns, vault and a "Door"
  region_sign        two posts with a "Board" for the region name
  road_sign          post with "Arrow1-3"

Run:
  python blender/props/rustic_props.py --out <dir> --category hub
"""
import math
import os
import sys

import bpy  # noqa: F401  (must be imported before bmesh/mathutils with the pip bpy module)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, HERE)
from mathutils import Matrix, Vector  # noqa: E402
from rig import tag  # noqa: E402
from buildings import (B, C, WALL, brace, door_frame, frustum, gable_roof, open_door, plate,  # noqa: E402
                       prism, to3, wall, window)
import buildings  # noqa: E402
import machines  # noqa: E402

RIG_FLIP = True  # export facing -Z like the vehicles (art spec: every model faces -Z in the .glb)
BED = 3.5        # truck bed floor / belt top
BELT_W = 5.4


# ---------------------------------------------------------------- helpers (studs)

GLYPHS = {
    "A": [".#.", "#.#", "###", "#.#", "#.#"],
    "B": ["##.", "#.#", "##.", "#.#", "##."],
    "C": ["###", "#..", "#..", "#..", "###"],
    "D": ["##.", "#.#", "#.#", "#.#", "##."],
    "E": ["###", "#..", "##.", "#..", "###"],
    "F": ["###", "#..", "##.", "#..", "#.."],
    "H": ["#.#", "#.#", "###", "#.#", "#.#"],
    "I": ["###", ".#.", ".#.", ".#.", "###"],
    "K": ["#.#", "#.#", "##.", "#.#", "#.#"],
    "L": ["#..", "#..", "#..", "#..", "###"],
    "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
    "N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
    "O": ["###", "#.#", "#.#", "#.#", "###"],
    "P": ["##.", "#.#", "##.", "#..", "#.."],
    "R": ["##.", "#.#", "##.", "#.#", "#.#"],
    "S": ["###", "#..", "###", "..#", "###"],
    "T": ["###", ".#.", ".#.", ".#.", ".#."],
    "U": ["#.#", "#.#", "#.#", "#.#", "###"],
    "Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
    "$": [".##", "##.", ".#.", ".##", "##."],
    " ": ["..", "..", "..", "..", ".."],
}


def text(f, kind, s, x, y, z, h, depth=0.2):
    """Block letters on a board facing -y, centered at (x, z), letter height h; y is the board's front face."""
    p = h / 5
    widths = [len(GLYPHS[c][0]) for c in s]
    total = (sum(widths) + len(s) - 1) * p
    u = x - total / 2
    parts = []
    for c, w in zip(s, widths):
        for r, row in enumerate(GLYPHS[c]):
            zc = z + h / 2 - (r + 0.5) * p
            i = 0
            while i < w:
                if row[i] == "#":
                    j = i
                    while j < w and row[j] == "#":
                        j += 1
                    parts.append(B(f, kind, ((j - i) * p, depth, p), (u + (i + j) / 2 * p, y - depth / 2, zc),
                                   rnd=False))
                    i = j
                else:
                    i += 1
        u += (w + 1) * p
    return parts


def win(f, axis, at, out, u, zc, w, h, trim, pane):
    """window() with a chosen pane kind (buildings.window always uses glass)."""
    parts = window(f, axis, at, out, u, zc, w, h, trim=trim)
    old = parts[0]
    bpy.data.objects.remove(old, do_unlink=True)
    gsize = (w, 0.1, h) if axis == "x" else (0.1, w, h)
    parts[0] = B(f, pane, gsize, to3(axis, at + out * 0.05, u, zc), rnd=False)
    return parts


def post(f, kind, x, y, z0, z1, s=1.0, rnd=True):
    return B(f, kind, (s, s, z1 - z0), (x, y, (z0 + z1) / 2), along="z", rnd=rnd)


def belt_y(f, y0, y1, x=0.0, **kw):
    """A machines.belt_run turned to run along y from y0 to y1."""
    parts = machines.belt_run(f, y0, y1, **kw)
    return machines.xform(parts, Matrix.Translation(Vector((x * buildings.S, 0, 0))) @ Matrix.Rotation(math.pi / 2, 4, "Z"))


def shift(objs, d):
    """Move already-built parts by d studs."""
    return machines.xform(objs, Matrix.Translation(Vector(d) * buildings.S))


def bale(f, x, y, z, rot=0.0):
    return buildings.bale(f, x, y, z, rot)


def stairs(f, kind, x, y0, top, w, run=1.0, axis="y", sign=-1):
    """Steps from ground up to top, stepping out in sign*axis from y0 (or x0 when axis is x)."""
    n = max(2, int(round(top / 0.9)))
    parts = []
    for i in range(n):
        h = top * (n - i) / n
        c = y0 + sign * (i + 0.5) * run
        size, loc = ((w, run, h), (x, c, h / 2)) if axis == "y" else ((run, w, h), (c, x, h / 2))
        parts.append(B(f, kind, size, loc, along="x" if axis == "y" else "y"))
    return parts


def railing(f, x0, x1, y, z0, h=3.0, step=4.0, axis="x", kind="handle", post_kind="bark"):
    """Post-and-two-rail fence along x (or y) at z0."""
    parts = []
    L = x1 - x0
    n = max(1, int(round(L / step)))
    for i in range(n + 1):
        u = x0 + L * i / n
        loc = (u, y) if axis == "x" else (y, u)
        parts.append(post(f, post_kind, loc[0], loc[1], z0, z0 + h, 0.6, rnd=False))
    for zz in (z0 + h * 0.45, z0 + h - 0.3):
        size = (L, 0.3, 0.4) if axis == "x" else (0.3, L, 0.4)
        loc = ((x0 + x1) / 2, y, zz) if axis == "x" else (y, (x0 + x1) / 2, zz)
        parts.append(B(f, kind, size, loc, along=axis, rnd=False))
    return parts


# ---------------------------------------------------------------- hub buildings

def homestead_motors(f):
    """Truck dealer, 52 wide x 26 tall x 60 deep (registry footprint 60 x 52: the 52 side is the
    front and faces the lot). Left half is a glass showroom with a player door; right half is the
    garage whose 16 x 13 door (tagged "Door", closed; slide it up) lets a truck drive out. Cream
    clapboard, green trim, low tin roof behind a western false front carrying HOMESTEAD MOTORS."""
    hw, hd, slab, eave, rise = 26.0, 30.0, 0.3, 18.0, 4.0
    p = [B(f, "metal", (2 * hw + 1, 2 * hd + 1, slab), (0, 0, slab / 2), rnd=False)]
    fy = -hd + WALL / 2
    a = hw - WALL / 2
    door = (-15.0, -10.0, slab, slab + 8.0)            # player door in the showroom glass
    glass = [(-23.5, -16.5, 2.0, 14.0), (-8.5, -1.0, 2.0, 14.0)]
    garage = (5.0, 21.0, slab, slab + 13.0)            # vehicle door
    p += wall(f, "paint_cream", "x", fy, -a, a, slab, eave + 7.0, holes=[door, garage] + glass)
    for u0, u1, z0, z1 in glass:
        p.append(B(f, "glass", (u1 - u0, 0.2, z1 - z0), ((u0 + u1) / 2, -hd + 0.4, (z0 + z1) / 2), rnd=False))
        n = int(round((u1 - u0) / 3.5))
        for i in range(n + 1):
            u = u0 + (u1 - u0) * i / n
            p.append(B(f, "paint_green", (0.4, 0.5, z1 - z0), (u, -hd + 0.2, (z0 + z1) / 2), along="z", rnd=False))
        for z in (z0, z1, 9.0):
            p.append(B(f, "paint_green", (u1 - u0 + 0.4, 0.5, 0.4), ((u0 + u1) / 2, -hd + 0.2, z), rnd=False))
    p += door_frame(f, "x", -hd, -1, *door, trim="paint_green")
    p += open_door(f, "glass", door[0] - 0.2, -hd, 2.5, 8.0, slab)
    p += open_door(f, "glass", door[1] + 0.2, -hd, 2.5, 8.0, slab)
    p += door_frame(f, "x", -hd, -1, *garage, trim="paint_green")
    # Garage door: horizontal slats in one tagged panel, closed.
    gd = []
    gw, gh = garage[1] - garage[0], garage[3] - garage[2]
    for i in range(6):
        z = garage[2] + gh * (i + 0.5) / 6
        gd.append(B(f, "paint_cream", (gw, 0.4 if i % 2 else 0.6, gh / 6 - 0.1), ((garage[0] + garage[1]) / 2, fy, z)))
    gd.append(B(f, "paint_cream", (2.0, 0.8, 0.4), ((garage[0] + garage[1]) / 2, fy - 0.3, garage[2] + 1.2), rnd=False))
    p += tag(gd, "Door")
    # Apron ramp so wheels roll off the slab.
    p.append(B(f, "metal", (gw + 2, 2.0, slab), ((garage[0] + garage[1]) / 2, -hd - 1.0, slab / 2 - 0.1), rnd=False))
    # Back and sides.
    p += wall(f, "paint_cream", "x", hd - WALL / 2, -a, a, slab, eave, holes=[(-2, 2.5, slab, slab + 7.5)])
    for s in (-1, 1):
        p += wall(f, "paint_cream", "y", s * (hw - WALL / 2), -hd, hd, slab, eave)
        for y in (-12, 2, 16):
            p += window(f, "y", s * hw, s, y, 9.0, 4.0, 4.0, trim="paint_green")
    p.append(prism(f, "paint_cream", "x", hd - WALL / 2, WALL, [(-hw, eave), (hw, eave), (0, eave + rise)]))
    roof = gable_roof(f, "metal", hw, eave, rise, 2 * hd - 3.0, ridge="y", over=1.0, t=0.5)
    p += shift(roof, (0, 1.5, 0))     # front edge tucked behind the false front
    # Stone base course and green corner boards.
    for s in (-1, 1):
        p.append(B(f, "paint_green", (0.4, 2 * hd, 1.6), (s * (hw + 0.1), 0, slab + 0.8), along="y", rnd=False))
        p.append(post(f, "paint_green", s * (hw - 0.1), -hd + 0.1, slab, eave + 7.0, 0.9, rnd=False))
        p.append(post(f, "paint_green", s * (hw - 0.1), hd - 0.1, slab, eave, 0.9, rnd=False))
    # False front: stepped top, cornice and the sign.
    p.append(B(f, "paint_cream", (16, WALL, 3.0), (0, fy, eave + 8.5), rnd=False))
    p.append(B(f, "paint_green", (2 * hw + 1.2, 1.4, 0.8), (0, -hd - 0.3, eave + 7.2), rnd=False))
    p.append(B(f, "paint_green", (17, 1.4, 0.8), (0, -hd - 0.3, eave + 10.2), rnd=False))
    p.append(B(f, "paint_green", (40, 0.5, 6.8), (0, -hd - 0.15, eave + 3.0)))
    p += text(f, "paint_cream", "HOMESTEAD", 0, -hd - 0.4, eave + 4.6, 2.4)
    p += text(f, "paint_cream", "MOTORS", 0, -hd - 0.4, eave + 1.3, 2.0)
    p += text(f, "paint_green", "$", 0, -hd - 0.2, eave + 8.6, 2.0)
    # Porch awning over the showroom front.
    ax0, ax1 = -hw + 0.5, 1.5
    for x in (ax0 + 0.5, (ax0 + ax1) / 2, ax1 - 0.5):
        p.append(post(f, "paint_green", x, -hd - 5.5, slab, 15.0, 0.7))
    p.append(B(f, "paint_green", (ax1 - ax0, 0.8, 0.8), ((ax0 + ax1) / 2, -hd - 5.5, 15.0), rnd=False))
    p.append(plate(f, "metal", (-hd - 6.5, 15.2), (-hd, 16.6), 0.4, "x", ax1 - ax0, mid=(ax0 + ax1) / 2))
    # Hanging lamps.
    for x in (-19, -5):
        p.append(C(f, "metal", 0.6, 0.6, (x, -hd - 3, 14.2), verts=8))
    return p


def land_office(f):
    """Small clapboard land office, about 20 wide x 15 tall x 25 deep with its yard: plank walls with
    cream trim, a porch with steps, LAND OFFICE board, and a plot map board on posts out front
    (six green fields along a lane, two brown ones sold)."""
    hw, hd, base, eave, rise = 9.0, 7.0, 1.2, 10.0, 4.5
    cy = 4.0
    p = [B(f, "bark", (2 * hw + 1, 2 * hd + 1, base), (0, cy, base / 2))]
    a = hw - WALL / 2
    door = (-2.2, 2.2, base, base + 7.6)
    fy = cy - hd + WALL / 2
    p += wall(f, "handle", "x", fy, -a, a, base, eave, holes=[door, (-7.5, -4.5, 4, 7.5), (4.5, 7.5, 4, 7.5)])
    p += wall(f, "handle", "x", cy + hd - WALL / 2, -a, a, base, eave)
    for s in (-1, 1):
        p += wall(f, "handle", "y", s * (hw - WALL / 2), cy - hd, cy + hd, base, eave)
        p += win(f, "y", s * hw, s, cy, 6.5, 3.0, 3.2, "paint_cream", "bark")
    for x in (-6, 6):
        p += win(f, "x", cy - hd, -1, x, 5.75, 3.0, 3.5, "paint_cream", "bark")
    p += door_frame(f, "x", cy - hd, -1, *door)
    p += open_door(f, "paint_green", door[0] - 0.1, cy - hd, 4.2, 7.6, base)
    # Clapboard lap lines on the front.
    for z in (2.6, 3.8, 8.4, 9.4):
        p.append(B(f, "bark", (2 * hw - 0.4, 0.2, 0.18), (0, cy - hd - 0.05, z), rnd=False))
    for x in (-hw, hw):
        for y in (cy - hd, cy + hd):
            p.append(post(f, "paint_cream", x, y, base, eave, 0.8, rnd=False))
    for y in (cy - hd + WALL / 2, cy + hd - WALL / 2):
        p.append(prism(f, "handle", "x", y, WALL, [(-hw, eave), (hw, eave), (0, eave + rise)]))
    p += gable_roof(f, "bark", hw, eave, rise, 2 * hd, ridge="y", over=1.0, cap="bark")
    # Porch: deck, posts, shed roof, steps, sign.
    py = cy - hd - 2.5
    p.append(B(f, "handle", (2 * hw, 5.0, 0.4), (0, py, base - 0.2)))
    for x in (-hw + 0.5, -3.0, 3.0, hw - 0.5):
        p.append(post(f, "paint_cream", x, py - 2.2, 0.0, 8.6, 0.6))
    p.append(B(f, "paint_cream", (2 * hw, 0.6, 0.6), (0, py - 2.2, 8.6), rnd=False))
    p.append(plate(f, "bark", (py - 3.2, 8.7), (cy - hd, 9.9), 0.4, "x", 2 * hw + 1))
    p += stairs(f, "handle", 0, py - 2.5, base, 4.4, run=0.9)
    p.append(B(f, "paint_cream", (11, 0.4, 2.4), (0, cy - hd - 0.4, eave + 1.6), rnd=False))
    p += text(f, "paint_green", "LAND OFFICE", 0, cy - hd - 0.6, eave + 1.6, 1.5)
    # Plot map board out front.
    my = -11.0
    for x in (-4.6, 4.6):
        p.append(post(f, "bark", x, my, 0.0, 7.6, 0.6))
    p.append(B(f, "handle", (9.0, 0.4, 5.6), (0, my, 4.6)))
    p.append(B(f, "paint_cream", (8.2, 0.3, 4.8), (0, my - 0.2, 4.6), rnd=False))
    p.append(B(f, "bark", (8.0, 0.2, 0.6), (0, my - 0.4, 4.6), rnd=False))       # the lane
    for i, x in enumerate((-2.7, 0.0, 2.7)):
        for j, z in enumerate((6.0, 3.2)):
            kind = "handle" if (i, j) in ((0, 0), (2, 1)) else "paint_green"
            p.append(B(f, kind, (2.3, 0.2, 1.8), (x, my - 0.4, z), rnd=False))
    p.append(B(f, "bark", (9.6, 0.8, 0.5), (0, my, 7.7)))
    return p


def hay_sell_shop(f):
    """Public HAY SELL SHOP, about 32 wide x 22 tall x 30 deep: open-front red barn shed (y 0..20)
    with a loading dock across the front at bed height 3.5 (y -8..0, bumpers on its face) and a
    3-tile conveyor down the middle from the dock edge into a hay bin at the back. Price board on a
    post at the front right: hay pays well, needles in the hay are underpaid."""
    hw, d0, d1, eave, rise = 15.0, 0.0, 20.0, 13.0, 6.0
    p = [B(f, "handle", (2 * hw + 1, d1 - d0 + 0.5, 0.3), (0, (d0 + d1) / 2, 0.15), rnd=False)]
    a = hw - WALL / 2
    p += wall(f, "paint_red", "x", d1 - WALL / 2, -a, a, 0.3, eave)
    for s in (-1, 1):
        p += wall(f, "paint_red", "y", s * (hw - WALL / 2), d0 + 1, d1, 0.3, eave)
        p += win(f, "y", s * hw, s, 12, 7.5, 3.0, 3.0, "handle", "metal")
        p.append(post(f, "handle", s * (hw - 0.4), d0 + 0.5, 0, eave + 0.6, 1.2))
    p.append(B(f, "handle", (2 * hw, 1.2, 1.4), (0, d0 + 0.5, eave + 0.1)))          # header beam
    for s in (-1, 1):
        p.append(brace(f, "handle", (s * (hw - 0.6), d0 + 0.5, eave - 3.5), (s * (hw - 4.0), d0 + 0.5, eave - 0.6)))
    for y in (d0 + WALL / 2, d1 - WALL / 2):
        p.append(prism(f, "paint_red", "x", y, WALL, [(-hw, eave + 0.8), (hw, eave + 0.8), (0, eave + 0.8 + rise)]))
    p += shift(gable_roof(f, "metal", hw, eave + 0.8, rise, d1 - d0, ridge="y", over=1.2, t=0.5),
               (0, (d0 + d1) / 2, 0))
    # Sign hung under the header beam.
    sz = eave - 2.2
    p.append(B(f, "handle", (14.6, 0.3, 5.0), (0, d0 - 0.15, sz), rnd=False))
    p.append(B(f, "paint_red", (14, 0.4, 4.4), (0, d0 - 0.3, sz), rnd=False))
    p += text(f, "hay", "HAY SELL", 0, d0 - 0.5, sz + 0.9, 1.8)
    p += text(f, "hay", "SHOP", 0, d0 - 0.5, sz - 1.2, 1.2)
    # Loading dock at bed height on both sides of the belt.
    for s in (-1, 1):
        cx = s * (3.0 + (hw - 3.0) / 2)
        p.append(B(f, "paint_red", (hw - 3.0, 8.0, BED - 0.4), (cx, -4.0, (BED - 0.4) / 2)))
        p.append(B(f, "handle", (hw - 3.0, 8.0, 0.4), (cx, -4.0, BED - 0.2)))
        for x in (cx - 4, cx + 4):
            p.append(B(f, "metal", (1.6, 0.8, 1.6), (x, -8.4, BED - 1.2)))
    p.append(B(f, "metal", (2 * hw, 0.3, 0.3), (0, -8.0, BED - 0.1), rnd=False))     # steel edge
    p += stairs(f, "handle", -4.0, -hw, BED, 3.0, axis="x", sign=-1)
    # Conveyor from the dock edge into the bin at the back.
    p += belt_y(f, -8.0, 10.0)
    p.append(frustum(f, "handle", 4.2, 3.4, 0.3, 6.0, 0, 13.6))
    p += tag([box_hay(f, 0, 13.6, 6.0)], "HayFill")
    for b in ((-9.0, 15.0, 0.3), (-9.0, 15.0, 2.9), (9.0, 15.0, 0.3)):
        p += bale(f, *b)
    # Price board: hay row with a long bar (good pay), needle row with a short bar (poor pay).
    bx = hw - 1.5
    p.append(post(f, "handle", bx, -10.0, 0, 9.0, 0.6))
    p.append(B(f, "paint_red", (5.6, 0.4, 4.6), (bx - 2.4, -10.0, 7.0)))
    p.append(B(f, "handle", (5.0, 0.3, 4.0), (bx - 2.4, -10.2, 7.0), rnd=False))
    p.append(B(f, "hay", (1.2, 0.3, 1.0), (bx - 4.2, -10.4, 8.0), rnd=False))
    p.append(B(f, "hay", (2.8, 0.3, 0.6), (bx - 1.8, -10.4, 8.0), rnd=False))
    p.append(B(f, "metal", (1.4, 0.3, 0.2), (bx - 4.2, -10.4, 6.0), rot=(0, 0.5, 0), rnd=False))
    p.append(B(f, "paint_red", (0.9, 0.3, 0.6), (bx - 2.85, -10.4, 6.0), rnd=False))
    return p


def box_hay(f, x, y, z):
    """Heaped loose hay filling a 7 x 7 bin top at z."""
    o = buildings.box((7.6 * buildings.S, 7.6 * buildings.S, 1.6 * buildings.S),
                      (x * buildings.S, y * buildings.S, (z + 0.6) * buildings.S))
    for v in o.data.vertices:
        if v.co.z > 0:
            v.co.x *= 0.6
            v.co.y *= 0.6
    return f.apply(f.shape(o), "hay")


def loading_dock(f):
    """Plot loading dock, 12 wide x 4.7 tall x 18 long (three 6 x 6 tiles deep). A plank deck 11
    wide with its top at 3.5 (bed height) where the truck backs up from -y, rubber bumpers on its
    face, then a funnel ramp whose guide walls narrow 11 down to the belt lane, then one belt tile."""
    hw, y0, y1 = 6.0, -9.0, -3.0
    p = [B(f, "stone", (2 * hw, y1 - y0, BED - 0.4), (0, (y0 + y1) / 2, (BED - 0.4) / 2)),
         B(f, "handle", (2 * hw, y1 - y0, 0.4), (0, (y0 + y1) / 2, BED - 0.2))]
    p.append(B(f, "metal", (2 * hw, 0.3, 0.3), (0, y0, BED - 0.1), rnd=False))
    for x in (-4.0, 4.0):
        p.append(B(f, "tire", (1.6, 0.8, 1.8), (x, y0 - 0.4, BED - 1.4)))
    for x in (-hw + 0.3, hw - 0.3):
        p.append(post(f, "metal", x, y0 + 0.3, BED, BED + 1.2, 0.6))
    # Funnel ramp (y -3..3): floor and angled guide walls from 11 to the 6-wide belt frame.
    p.append(B(f, "stone", (2 * hw, 6.0, BED - 0.4), (0, 0, (BED - 0.4) / 2)))
    p.append(B(f, "metal", (2 * hw, 6.0, 0.4), (0, 0, BED - 0.2)))
    for s in (-1, 1):
        p.append(brace(f, "handle", (s * (hw - 0.3), y1, BED + 0.6), (s * (BELT_W / 2 + 0.15), 3.0, BED + 0.6), 0.3))
        p.append(brace(f, "handle", (s * (hw - 0.3), y1, BED + 1.2), (s * (BELT_W / 2 + 0.15), 3.0, BED + 1.2), 0.3))
        for y in (y1, 3.0):
            x = s * (hw - 0.3) if y == y1 else s * (BELT_W / 2 + 0.15)
            p.append(post(f, "handle", x, y, BED, BED + 1.4, 0.4, rnd=False))
    p += belt_y(f, 3.0, 9.0)
    return p


def hay_buyer(f):
    """Plot hay buyer on one 6 x 6 tile, about 11 tall: a belt across the tile at 3.5, a plank hopper
    over it on four posts, and a green cash box with a coin slot and a stack of gold coins on the
    front beam. Hay rides in along x and the box pays out."""
    p = machines.belt_run(f, -3.0, 3.0)
    for x in (-2.7, 2.7):
        for y in (-2.7, 2.7):
            p.append(post(f, "handle", x, y, 0, 9.0, 0.5))
    for y in (-2.7, 2.7):
        p.append(B(f, "handle", (6.0, 0.5, 0.5), (0, y, 8.0), rnd=False))
    p.append(frustum(f, "handle", 2.6, 1.6, 6.0, 9.6))
    for s in (-1, 1):
        p.append(B(f, "metal", (5.6, 0.3, 0.3), (0, s * 2.65, 9.7), rnd=False))
        p.append(B(f, "metal", (0.3, 5.6, 0.3), (s * 2.65, 0, 9.7), rnd=False))
    p += tag([box_hay_small(f)], "HayFill")
    # Cash box on the front beam.
    p.append(B(f, "paint_green", (2.2, 1.2, 1.6), (0, -3.0, 9.0)))
    p.append(B(f, "metal", (0.9, 0.2, 0.15), (0, -3.6, 9.4), rnd=False))
    p.append(B(f, "metal", (0.4, 0.3, 0.4), (0.6, -3.65, 8.6), rnd=False))
    for i in range(3):
        p.append(C(f, "hay", 0.35, 0.12, (-0.6, -3.0, 9.86 + i * 0.13), verts=10, rnd=False))
    p += text(f, "hay", "$", 0, -3.6, 8.65, 0.6, depth=0.08)
    return p


def box_hay_small(f):
    o = buildings.box((4.4 * buildings.S, 4.4 * buildings.S, 1.0 * buildings.S), (0, 0, 9.6 * buildings.S))
    for v in o.data.vertices:
        if v.co.z > 0:
            v.co.x *= 0.5
            v.co.y *= 0.5
    return f.apply(f.shape(o), "hay")


def field_bale_chute(f):
    """Field bale chute, 12 wide x 14 tall x 16 deep: a wooden hopper on four legs over a truck lane
    11 clear wide x 9.5 clear tall (legs at x +-5.75, every beam at or above 9.5). A slanted chute
    runs from the hopper mouth forward (-y) and ends at 6.5 (bed 3.5 + 3), so the bed slides under it
    as the truck backs in. Gate (a flap on the chute end), Lever (on the left front leg) and HayFill
    (the loose hay heaped in the hopper) are separate meshes."""
    lx, ly, clear = 5.75, 4.5, 9.5
    p = []
    for x in (-lx, lx):
        for y in (-ly, ly):
            p.append(post(f, "bark", x, y, 0, 11.0, 0.5, rnd=False))
        p.append(brace(f, "handle", (x, -ly, 1.0), (x, ly, 8.5), 0.35))              # side brace, outside the lane
        p.append(B(f, "handle", (0.4, 2 * ly, 0.4), (x, 0, 1.2), along="y", rnd=False))
    for y in (-ly, ly):
        p.append(B(f, "bark", (2 * lx + 0.6, 0.6, 0.6), (0, y, clear + 0.3), rnd=False))
    # Hopper: plank funnel 11.6 square at the top, 3.6 at the mouth, rim boards.
    p.append(frustum(f, "handle", 5.8, 1.8, clear + 0.6, 13.6))
    for s in (-1, 1):
        p.append(B(f, "bark", (11.9, 0.4, 0.4), (0, s * 5.8, 13.8), rnd=False))
        p.append(B(f, "bark", (0.4, 11.9, 0.4), (s * 5.8, 0, 13.8), along="y", rnd=False))
    hay = buildings.box((11.2 * buildings.S, 11.2 * buildings.S, 0.9 * buildings.S), (0, 0, 13.55 * buildings.S))
    for v in hay.data.vertices:
        if v.co.z > 0:
            v.co.x *= 0.7
            v.co.y *= 0.7
    p += tag([f.apply(f.shape(hay, round_edges=False), "hay")], "HayFill")
    # Chute: trough from the hopper mouth (z 10.1, y -1) to the end at 6.5, y -7.5.
    a, b = (-1.0, clear + 0.6), (-7.5, 6.5)
    p.append(plate(f, "handle", a, b, 0.3, "x", 3.4, rnd=False))
    for s in (-1, 1):
        size, loc, rot = buildings.slope((a[0], a[1] + 0.6), (b[0], b[1] + 0.6), 0.3, "x", 0.3, mid=s * 1.85)
        p.append(B(f, "handle", (0.3, size[1], 1.2), loc, rot=rot, rnd=False))
    p += tag([B(f, "handle", (3.4, 0.3, 1.6), (0, b[0] - 0.2, b[1] + 0.6), rnd=False)], "Gate")
    # Lever on the left front leg, pivot at its base.
    p.append(B(f, "bark", (0.8, 0.8, 0.8), (-lx - 0.65, -ly, 3.6), rnd=False))
    p += tag([B(f, "metal", (0.25, 0.25, 2.4), (-lx - 0.65, -ly - 0.35, 5.1), rot=(0.3, 0, 0), rnd=False),
              B(f, "metal", (0.5, 0.5, 0.6), (-lx - 0.65, -ly - 0.7, 6.3), rnd=False)], "Lever")
    return p


def bounty_board(f):
    """Bounty board, 8 wide x 9 tall x 1.5 deep: plank board on two posts under a little shingle
    roof, with 3 paper notices (Notice1-3, own meshes so the game can swap their color)."""
    p = []
    for x in (-3.6, 3.6):
        p.append(post(f, "bark", x, 0, 0, 8.0, 0.5, rnd=False))
    p.append(B(f, "handle", (7.0, 0.3, 4.6), (0, 0, 5.3), rnd=False))
    p.append(B(f, "bark", (7.4, 0.4, 0.3), (0, 0, 3.0), rnd=False))
    p.append(B(f, "bark", (7.4, 0.4, 0.3), (0, 0, 7.6), rnd=False))
    for s in (-1, 1):
        p.append(plate(f, "bark", (s * 0.75, 8.0), (0, 8.75), 0.2, "x", 8.0, rnd=False))
    for i, x in enumerate((-2.2, 0.0, 2.2)):
        rot = (0, (-0.06, 0.04, -0.03)[i], 0)
        p += tag([B(f, "paint_cream", (1.8, 0.1, 2.4), (x, -0.2, 5.3), rot=rot, rnd=False),
                  B(f, "paint_cream", (0.2, 0.2, 0.2), (x, -0.3, 6.25), rnd=False)], f"Notice{i + 1}")
    return p


def trading_post(f):
    """Trading post, 24 wide x 16 tall x 18 deep: an open-front log store (round log back and side
    walls, plank floor, counter across the front with a balance scale), gable plank roof, a red
    awning over the front, a TRADE board, and crates and barrels outside on the -y side."""
    hw, y0, y1, eave = 11.0, -2.5, 9.0, 10.0
    p = [B(f, "handle", (2 * hw, y1 - y0, 0.6), (0, (y0 + y1) / 2, 0.3), rnd=False)]
    r = 0.55
    n = int(eave / (2 * r * 0.95))
    for i in range(n):
        z = 0.6 + r + i * 2 * r * 0.95
        p.append(C(f, "bark", r, 2 * hw + 1.0, (0, y1 - r, z), verts=8, rot=(0, math.pi / 2, 0), along="x", rnd=False))
        for s in (-1, 1):
            p.append(C(f, "bark", r, y1 - y0 + 1.0, (s * (hw - r), (y0 + y1) / 2, z + r * 0.95), verts=8,
                       rot=(math.pi / 2, 0, 0), along="y", rnd=False))
    for s in (-1, 1):
        p.append(post(f, "bark", s * (hw - 0.5), y0, 0, eave + 0.5, 0.9, rnd=False))
    p.append(B(f, "bark", (2 * hw + 0.6, 0.9, 0.9), (0, y0, eave + 0.6), rnd=False))
    p.append(prism(f, "bark", "x", y1 - r, 1.0, [(-hw, eave + 0.6), (hw, eave + 0.6), (0, eave + 4.6)], rnd=False))
    p.append(prism(f, "bark", "x", y0, 0.6, [(-hw, eave + 1.0), (hw, eave + 1.0), (0, eave + 4.6)], rnd=False))
    p += shift(gable_roof(f, "handle", hw, eave + 1.0, 3.6, y1 - y0, ridge="y", over=1.0, t=0.4, cap="bark"),
               (0, (y0 + y1) / 2, 0))
    # Awning over the open front and the counter.
    p.append(plate(f, "paint_red", (y0 - 4.5, 7.6), (y0, 9.4), 0.25, "x", 2 * hw - 1.0, rnd=False))
    for x in (-hw + 1.0, 0.0, hw - 1.0):
        p.append(post(f, "bark", x, y0 - 4.3, 0, 7.6, 0.4, rnd=False))
    p.append(B(f, "handle", (2 * hw - 3.0, 1.6, 3.2), (0, y0 + 1.6, 1.6 + 0.3), rnd=False))
    p.append(B(f, "handle", (2 * hw - 2.6, 2.0, 0.3), (0, y0 + 1.6, BED + 0.2), rnd=False))
    # Balance scale on the counter.
    sx, sy, sz = -4.0, y0 + 1.6, BED + 0.35
    p.append(B(f, "metal", (0.25, 0.25, 1.8), (sx, sy, sz + 0.9), rnd=False))
    p.append(B(f, "metal", (2.6, 0.2, 0.2), (sx, sy, sz + 1.8), rnd=False))
    for dx in (-1.2, 1.2):
        p.append(C(f, "metal", 0.55, 0.12, (sx + dx, sy, sz + 1.0), verts=8, rnd=False))
        p.append(B(f, "metal", (0.06, 0.06, 0.8), (sx + dx, sy, sz + 1.45), rnd=False))
    # TRADE board on the front gable.
    p.append(B(f, "handle", (7.0, 0.3, 2.0), (0, y0 - 0.4, eave + 2.4), rnd=False))
    p += text(f, "paint_red", "TRADE", 0, y0 - 0.55, eave + 2.4, 1.2, depth=0.12)
    # Crates and barrels out front.
    for x, y, z in ((-9.0, y0 - 3.6, 0), (-7.0, y0 - 3.9, 0), (-8.0, y0 - 3.7, 1.8)):
        p.append(B(f, "handle", (1.8, 1.8, 1.8), (x, y, z + 0.9), rnd=False))
        p.append(B(f, "bark", (1.9, 0.2, 0.3), (x, y - 0.9, z + 0.9), rnd=False))
    for x, y in ((7.5, y0 - 3.8), (9.6, y0 - 3.4)):
        p.append(C(f, "handle", 0.9, 2.4, (x, y, 1.2), verts=10, rnd=False))
        for z in (0.5, 1.9):
            p.append(C(f, "metal", 0.95, 0.2, (x, y, z), verts=10, rnd=False))
    return p


def homestead_bank(f):
    """Homestead Bank, 26 wide x 22 tall x 20 deep, the most solid building in town: a stone (brick)
    ground storey with quoins, a plank upper storey, a flat roof behind a stone cornice, two stone
    columns and a pediment at the door, and a barn-red BANK board. The Door (one plank door, 5 x 8.5,
    hinged on its left edge) is its own mesh; a round iron vault door is visible through the left
    ground window."""
    hw, hd, base, mid, top = 13.0, 10.0, 0.8, 11.0, 20.0
    p = [B(f, "stone", (2 * hw + 1, 2 * hd + 1, base), (0, 0, base / 2), rnd=False)]
    a = hw - WALL / 2
    fy = -hd + WALL / 2
    door = (-2.5, 2.5, base, base + 8.5)
    wins_low = [(-10.0, -5.0, 3.5, 8.5), (5.0, 10.0, 3.5, 8.5)]
    wins_up = [(-10.0, -6.0, 13.5, 18.0), (-2.0, 2.0, 13.5, 18.0), (6.0, 10.0, 13.5, 18.0)]
    p += wall(f, "stone", "x", fy, -a, a, base, mid, holes=[door] + wins_low, rnd=False)
    p += wall(f, "handle", "x", fy, -a, a, mid, top, holes=wins_up, rnd=False)
    p += wall(f, "stone", "x", hd - WALL / 2, -a, a, base, mid, rnd=False)
    p += wall(f, "handle", "x", hd - WALL / 2, -a, a, mid, top, rnd=False)
    for s in (-1, 1):
        p += wall(f, "stone", "y", s * (hw - WALL / 2), -hd, hd, base, mid, holes=[(-4, 2, 3.5, 8.5)], rnd=False)
        p += wall(f, "handle", "y", s * (hw - WALL / 2), -hd, hd, mid, top, holes=[(-4, 2, 13.5, 18.0)], rnd=False)
    # Window panes (iron-dark) and stone sills; the vault sits behind the left ground window.
    for u0, u1, z0, z1 in wins_low + wins_up:
        p.append(B(f, "stone", (u1 - u0 + 0.8, 0.8, 0.4), ((u0 + u1) / 2, -hd - 0.2, z0 - 0.2), rnd=False))
        if (u0, u1, z0, z1) != wins_low[0]:
            p.append(B(f, "metal", (u1 - u0, 0.1, z1 - z0), ((u0 + u1) / 2, -hd + 0.5, (z0 + z1) / 2), rnd=False))
        p.append(B(f, "handle", (0.2, 0.3, z1 - z0), ((u0 + u1) / 2, -hd + 0.4, (z0 + z1) / 2), rnd=False))
    for s in (-1, 1):
        for y in (-1.0,):
            p.append(B(f, "metal", (0.1, 6.0, 5.0), (s * (hw - 0.5), y, 6.0), rnd=False))
            p.append(B(f, "metal", (0.1, 6.0, 4.5), (s * (hw - 0.5), y, 15.75), rnd=False))
    vx, vy = -7.5, -hd + 3.0
    p.append(B(f, "stone", (7.0, 0.6, 7.5), (vx, vy + 0.4, base + 3.75), rnd=False))     # vault wall inside
    p.append(C(f, "metal", 2.2, 0.6, (vx, vy, 6.0), verts=12, rot=(math.pi / 2, 0, 0), rnd=False))
    for ang in (0, math.pi / 3, 2 * math.pi / 3):
        p.append(B(f, "metal", (2.4, 0.3, 0.2), (vx, vy - 0.45, 6.0), rot=(0, ang, 0), rnd=False))
    # Quoins, storey band, cornice, flat roof.
    for x in (-hw, hw):
        for i in range(5):
            w = 1.6 if i % 2 else 1.1
            p.append(B(f, "stone", (1.0, w, 1.6), (x, -hd + w / 2 - 0.2, base + 1.0 + i * 2.0), rnd=False))
    p.append(B(f, "stone", (2 * hw + 0.8, 2 * hd + 0.8, 0.6), (0, 0, mid), rnd=False))
    p.append(B(f, "stone", (2 * hw + 1.4, 2 * hd + 1.4, 1.0), (0, 0, top + 0.5), rnd=False))
    p.append(B(f, "metal", (2 * hw - 0.6, 2 * hd - 0.6, 0.3), (0, 0, top + 0.6), rnd=False))
    p.append(B(f, "stone", (12.0, 1.0, 2.0), (0, -hd - 0.2, top + 2.0), rnd=False))     # parapet centre
    # Porch: steps, two columns, pediment, BANK board.
    p += stairs(f, "stone", 0, -hd - 0.4, base, 8.0, run=0.8)
    for x in (-3.8, 3.8):
        p.append(C(f, "stone", 0.6, 9.0, (x, -hd - 2.0, base + 4.5), verts=10, rnd=False))
        p.append(B(f, "stone", (1.6, 1.6, 0.4), (x, -hd - 2.0, base + 0.2), rnd=False))
    p.append(B(f, "stone", (9.6, 3.0, 0.8), (0, -hd - 1.4, base + 9.4), rnd=False))
    p.append(prism(f, "stone", "x", -hd - 2.4, 1.0, [(-4.8, base + 9.8), (4.8, base + 9.8), (0, base + 12.0)], rnd=False))
    p.append(B(f, "paint_red", (9.0, 0.4, 2.4), (0, -hd - 0.9, top + 2.0), rnd=False))
    p += text(f, "stone", "BANK", 0, -hd - 1.1, top + 2.0, 1.5, depth=0.15)
    p += door_frame(f, "x", -hd, -1, *door, trim="stone")
    p += tag([B(f, "handle", (door[1] - door[0], 0.4, door[3] - door[2]), (0, fy, (door[2] + door[3]) / 2), rnd=False),
              B(f, "handle", (0.3, 0.6, 0.6), (door[1] - 0.8, fy - 0.3, base + 4.2), rnd=False)], "Door")
    return p


def region_sign(f):
    """Region welcome sign, 6 wide x 5 tall x 0.5 deep: two posts and a plank board. The Board is its
    own mesh (painted in the region accent in game; text goes on as a SurfaceGui)."""
    p = [post(f, "bark", x, 0, 0, 5.0, 0.4, rnd=False) for x in (-2.7, 2.7)]
    p += tag([B(f, "paint_green", (5.6, 0.25, 2.6), (0, -0.12, 3.4), rnd=False)], "Board")
    p.append(B(f, "bark", (6.0, 0.5, 0.25), (0, 0, 4.85), rnd=False))
    return p


def road_sign(f):
    """Road sign, 6 tall on a 0.3 post: three plank arrow boards (Arrow1-3, top to bottom) pointing
    right, left, right; each is its own mesh so the game can turn or hide them. Arrows are 2.6 long."""
    p = [post(f, "bark", 0, 0, 0, 6.0, 0.3, rnd=False)]
    for i, (z, d) in enumerate(((5.3, 1), (4.3, -1), (3.3, 1))):
        pts = [(0, -0.35), (2.0, -0.35), (2.6, 0.0), (2.0, 0.35), (0, 0.35)]
        pts = [(d * (u - 1.0), z + v) for u, v in pts]
        if d < 0:
            pts = pts[::-1]
        p += tag([prism(f, "handle", "x", -0.25, 0.15, pts, rnd=False)], f"Arrow{i + 1}")
    return p


def scarecrow(f):
    """The moving scarecrow quest NPC, 3 wide x 7 tall x 1.5 deep: a cross post, burlap trousers and
    a muted patched plaid shirt with straw tufts. Head (burlap sack with button eyes and a stitched
    grin, plus its floppy hat) and ArmL / ArmR (the scarecrow's own left and right) are separate
    meshes for the quest; each gets one material."""
    p = [B(f, "hay", (1.4, 1.2, 0.3), (0, 0.2, 0.15), rnd=False)]                   # straw tuft at the foot
    p.append(post(f, "bark", 0, 0.35, 0, 5.4, 0.3, rnd=False))
    p.append(B(f, "bark", (3.0, 0.25, 0.25), (0, 0.35, 4.6), rnd=False))
    p.append(B(f, "cloth", (1.2, 0.7, 0.9), (0, 0, 2.95), rnd=False))
    for x in (-0.3, 0.3):
        p.append(B(f, "cloth", (0.5, 0.55, 1.8), (x, 0, 1.6), rot=(0, x * 0.2, 0), rnd=False))
        p.append(B(f, "hay", (0.55, 0.45, 0.35), (x * 1.2, 0, 0.6), rnd=False))
    p.append(B(f, "paint_red", (1.3, 0.8, 1.4), (0, 0, 4.05), rnd=False))
    for z in (3.6, 4.2):
        p.append(B(f, "bark", (1.32, 0.82, 0.1), (0, 0, z), rnd=False))                 # plaid bands
    p.append(B(f, "cloth", (0.4, 0.1, 0.4), (-0.3, -0.42, 3.9), rnd=False))            # patch
    p.append(B(f, "hay", (0.7, 0.55, 0.3), (0, 0, 4.85), rnd=False))                    # straw at the neck
    for s, name in ((1, "ArmL"), (-1, "ArmR")):
        p += tag([B(f, "paint_red", (0.7, 0.5, 0.5), (s * 1.0, 0.15, 4.6), rnd=False),
                  B(f, "paint_red", (0.25, 0.45, 0.45), (s * 1.22, 0.15, 4.6), rnd=False)], name)
        p.append(B(f, "hay", (0.2, 0.4, 0.4), (s * 1.42, 0.15, 4.6), rnd=False))       # straw hand tuft
    head = [B(f, "cloth", (1.0, 0.85, 1.0), (0, 0, 5.5), rot=(0, 0.05, 0), rnd=False),
            B(f, "cloth", (1.05, 0.9, 0.12), (0, 0, 5.1), rnd=False)]
    for x in (-0.22, 0.22):
        head.append(C(f, "cloth", 0.1, 0.1, (x, -0.47, 5.65), verts=6, rot=(math.pi / 2, 0, 0), rnd=False))
    head.append(B(f, "cloth", (0.5, 0.08, 0.06), (0, -0.46, 5.25), rnd=False))
    head.append(C(f, "cloth", 0.95, 0.1, (0, 0, 6.05), verts=10, rot=(0.08, 0.05, 0), rnd=False))
    head.append(C(f, "cloth", 0.48, 0.9, (0, 0.03, 6.5), verts=8, rot=(0.12, 0, 0), rnd=False))
    p += tag(head, "Head")
    return p


def plot_fence_sign(f):
    """Plot boundary sign, about 14 wide x 7.6 tall x 1 deep: a blank cream owner board under a
    little plank cap on two posts, with a short two-rail fence stub on each side."""
    p = []
    for x in (-2.8, 2.8):
        p.append(post(f, "bark", x, 0, 0, 7.0, 0.6))
    p.append(B(f, "handle", (5.4, 0.35, 2.8), (0, -0.1, 5.2)))
    p.append(B(f, "paint_cream", (4.8, 0.2, 2.2), (0, -0.3, 5.2), rnd=False))
    p.append(B(f, "bark", (6.4, 0.9, 0.3), (0, 0, 7.1)))
    for x in (-2.0, 2.0):
        p.append(C(f, "metal", 0.12, 0.2, (x, -0.42, 6.05), verts=6, rot=(math.pi / 2, 0, 0), rnd=False))
    for s in (-1, 1):
        p += railing(f, s * 2.8, s * 7.0, 0, 0, h=3.2, step=4.2)
    return p


def ferry_dock(f):
    """Ferry pier, 40 wide x 4.7 tall x 30 long (plus an 8-long ramp): land approach ramp at +y
    (ground to the deck over 8), plank deck at 4 on pilings, rails along the sides, metal bollards
    and hanging fenders at the sea end (-y), lamp posts, and a FERRY arch over the approach
    (15 tall inside). The vehicle ramp (tagged "Ramp", hinge along y = -15 at deck height) lies
    flat out to y = -23; tilt it up to stow it."""
    hw, deck, y0, y1 = 20.0, 4.0, -15.0, 7.0
    p = [B(f, "handle", (2 * hw, y1 - y0, 0.6), (0, (y0 + y1) / 2, deck - 0.3), along="y")]
    for y in range(-14, 8, 7):
        p.append(B(f, "bark", (2 * hw, 0.9, 0.9), (0, y, deck - 1.0), rnd=False))
    for x in (-18.5, -9.25, 0.0, 9.25, 18.5):
        for y in (-14.0, -7.0, 0.0, 6.5):
            p.append(C(f, "bark", 0.7, deck - 0.6, (x, y, (deck - 0.6) / 2), verts=8, rnd=False))
    # Approach from land.
    p.append(plate(f, "handle", (y1 + 8.0, 0.0), (y1, deck - 0.6), 0.6, "x", 18.0))
    p.append(B(f, "bark", (18.0, 1.0, deck - 0.6), (0, y1 + 0.5, (deck - 0.6) / 2), rnd=False))
    # Side rails (leave the sea end open).
    for s in (-1, 1):
        p += railing(f, y0 + 1.0, y1, s * (hw - 0.4), deck, h=3.0, step=5.5, axis="y")
    # Bollards and fenders at the sea end.
    for x in (-17.0, -12.0, 12.0, 17.0):
        p.append(C(f, "metal", 0.6, 1.6, (x, y0 + 0.9, deck + 0.8), verts=10))
        p.append(C(f, "metal", 0.85, 0.3, (x, y0 + 0.9, deck + 1.6), verts=10))
    for x in (-15.0, -10.0, 10.0, 15.0):
        p.append(C(f, "bark", 1.0, 0.6, (x, y0 - 0.35, deck - 1.5), verts=12, rot=(math.pi / 2, 0, 0)))
    # Lamp posts.
    for x in (-hw + 1.5, hw - 1.5):
        p.append(post(f, "bark", x, y0 + 2.5, deck, deck + 9.0, 0.6))
        p.append(B(f, "bark", (1.6, 0.4, 0.4), (x - math.copysign(0.6, x), y0 + 2.5, deck + 8.8), rnd=False))
        p.append(C(f, "metal", 0.5, 0.8, (x - math.copysign(1.2, x), y0 + 2.5, deck + 8.1), verts=8))
    # FERRY arch over the land end.
    for x in (-10.0, 10.0):
        p.append(post(f, "bark", x, y1 - 1.0, deck, deck + 17.0, 1.0))
    p.append(B(f, "bark", (21.0, 1.0, 1.0), (0, y1 - 1.0, deck + 15.5)))
    p.append(B(f, "handle", (10.0, 0.4, 2.6), (0, y1 - 1.6, deck + 17.4)))
    p += text(f, "paint_cream", "FERRY", 0, y1 - 1.8, deck + 17.4, 1.6)
    # The vehicle ramp.
    rl = 8.0
    ramp = [B(f, "handle", (16.0, rl, 0.5), (0, y0 - rl / 2, deck - 0.25), along="y")]
    for x in (-7.8, 7.8):
        ramp.append(B(f, "metal", (0.4, rl, 0.7), (x, y0 - rl / 2, deck + 0.1), along="y", rnd=False))
    for y in (y0 - 2.0, y0 - 4.0, y0 - 6.0):
        ramp.append(B(f, "metal", (15.0, 0.25, 0.15), (0, y, deck + 0.05), rnd=False))
    p += tag(ramp, "Ramp")
    for x in (-8.5, 8.5):
        p.append(C(f, "metal", 0.4, 1.2, (x, y0, deck), verts=8, rot=(0, math.pi / 2, 0)))
    return p


def display_stand(f):
    """Needle display pedestal, about 3 wide x 4.9 tall x 3 deep: plank base, stone column with a
    metal plaque, wooden cap with a red velvet cushion and two small metal cradles that hold a
    needle level at about 4.8 (the needle is not part of the prop)."""
    p = [B(f, "handle", (3.0, 3.0, 0.6), (0, 0, 0.3)),
         B(f, "stone", (1.8, 1.8, 3.0), (0, 0, 2.1)),
         B(f, "handle", (2.6, 2.6, 0.4), (0, 0, 3.8)),
         B(f, "paint_red", (2.0, 2.0, 0.3), (0, 0, 4.15)),
         B(f, "metal", (1.0, 0.1, 0.5), (0, -0.92, 2.6), rnd=False)]
    for x in (-0.6, 0.6):
        p.append(B(f, "metal", (0.12, 0.12, 0.35), (x, 0, 4.47), rnd=False))
        for s in (-1, 1):
            p.append(B(f, "metal", (0.1, 0.1, 0.3), (x, s * 0.15, 4.72), rot=(s * 0.5, 0, 0), rnd=False))
    return p


PROPS = {
    "homestead_motors": homestead_motors,
    "land_office": land_office,
    "hay_sell_shop": hay_sell_shop,
    "field_bale_chute": field_bale_chute,
    "loading_dock": loading_dock,
    "hay_buyer": hay_buyer,
    "bounty_board": bounty_board,
    "trading_post": trading_post,
    "scarecrow": scarecrow,
    "plot_fence_sign": plot_fence_sign,
    "ferry_dock": ferry_dock,
    "display_stand": display_stand,
    "homestead_bank": homestead_bank,
    "region_sign": region_sign,
    "road_sign": road_sign,
}

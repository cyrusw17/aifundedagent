"""Signature landmark buildings, one per region of the Stitched Isles (GAME_PLAN_V8 Part A).

Simple shells in the house style (LT2 shapes, Rustic finish), no interiors. Walk-in doors are at
least 4 x 7 studs, vehicle doors at least 12 x 11. Moving parts are tagged for the rig:
  snow_cabin             Door (hidden side door, Frostbite Mitts quest)
  buried_pyramid_garage  Door (roll-up garage door, 12 x 11 opening)
  the_spindle            Door (sealed slab), Socket..Socket12 (shard sockets)
  zeppelin_dock          Gangway
  bobbin_captain_shack   ShipWheel
  meadow_windmill        Blades
  corn_maze_gate         Door, Door2 (the two gate leaves)

Built and exported by rustic_props.py:
  python blender/props/rustic_props.py --out <dir> --category regions
"""
import math
import os
import random
import sys

import bpy  # noqa: F401  (must be imported before bmesh/mathutils with the pip bpy module)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, HERE)
from buildings import (B, C, WALL, bale, brace, corrugated, door_frame, floor, frustum,  # noqa: E402
                       gable_roof, plate, prism, ring_x, wall, window)
from rig import tag  # noqa: E402
from style import cyl  # noqa: E402

STUD = 0.28
S = STUD


# ---------------------------------------------------------------- helpers (studs)

def T(f, kind, r0, r1, z0, z1, x=0.0, y=0.0, verts=12, rnd=True, along="z"):
    """Tapered cylinder (cone frustum) standing on z0: radius r0 at the bottom, r1 at the top."""
    o = cyl(r0 * S, (z1 - z0) * S, (x * S, y * S, (z0 + z1) / 2 * S), verts=verts)
    k = r1 / r0
    for v in o.data.vertices:
        if v.co.z > (z0 + z1) / 2 * S:
            v.co.x = x * S + (v.co.x - x * S) * k
            v.co.y = y * S + (v.co.y - y * S) * k
    return f.apply(f.shape(o, round_edges=rnd), kind, along=along)


def shear(parts, kx=0.0, ky=0.0):
    """Lean parts sideways with height (x += kx * z) so the ground footprint stays put."""
    for o in parts:
        for v in o.data.vertices:
            v.co.x += kx * v.co.z
            v.co.y += ky * v.co.z
    return parts


def log_wall(f, axis, at, u0, u1, z0, z1, d=1.2, holes=(), over=1.0, kind="bark"):
    """Stacked round logs along a wall line, split around holes (ua, ub, za, zb). Ends stick out."""
    parts = []
    z, row = z0 + d / 2, 0
    while z - d / 2 < z1 - 0.1:
        off = d / 2 if row % 2 else 0.0          # alternate walls sit half a log up
        cuts = [(u0 - over, u1 + over)]
        for ua, ub, za, zb in holes:
            if za < z + d / 2 and zb > z - d / 2:
                new = []
                for a, b in cuts:
                    if ub <= a or ua >= b:
                        new.append((a, b))
                        continue
                    if ua > a:
                        new.append((a, ua))
                    if ub < b:
                        new.append((ub, b))
                cuts = new
        for a, b in cuts:
            if b - a < 0.3:
                continue
            mid = (a + b) / 2
            loc = (mid, at, z + off) if axis == "x" else (at, mid, z + off)
            rot = (0, math.pi / 2, 0) if axis == "x" else (math.pi / 2, 0, 0)
            parts.append(C(f, kind, d / 2, b - a, loc, verts=8, rot=rot, along=axis, rnd=False))
        z += d
        row += 1
    return parts


def rock(f, rng, x, y, z, sx, sy, sz, kind="stone"):
    """Lumpy boulder: a box with random tilt."""
    rot = (rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(0, math.pi))
    return B(f, kind, (sx, sy, sz), (x, y, z), rot=rot)


def railing(f, kind, x0, x1, y, z, h=3.0, step=3.0, along="x"):
    """Posts and a top rail along x (or along y when along='y', then x0/x1 are y and y is x)."""
    parts = []
    n = max(1, int(round(abs(x1 - x0) / step)))
    for i in range(n + 1):
        u = x0 + (x1 - x0) * i / n
        loc = (u, y, z + h / 2) if along == "x" else (y, u, z + h / 2)
        parts.append(B(f, kind, (0.4, 0.4, h), loc, along="z", rnd=False))
    size = (abs(x1 - x0), 0.4, 0.4) if along == "x" else (0.4, abs(x1 - x0), 0.4)
    loc = ((x0 + x1) / 2, y, z + h) if along == "x" else (y, (x0 + x1) / 2, z + h)
    parts.append(B(f, kind, size, loc, along=along, rnd=False))
    return parts


def lattice_mast(f, kind, half, z0, z1, bays):
    """Square lattice tower: four corner posts with X bracing on every face."""
    parts = [B(f, kind, (0.8, 0.8, z1 - z0), (x, y, (z0 + z1) / 2), along="z")
             for x in (-half, half) for y in (-half, half)]
    h = (z1 - z0) / bays
    for i in range(bays):
        za, zb = z0 + i * h, z0 + (i + 1) * h
        for s in (-1, 1):
            parts.append(brace(f, kind, (-half, s * half, za), (half, s * half, zb), 0.35))
            parts.append(brace(f, kind, (s * half, -half, za), (s * half, half, zb), 0.35))
        parts.append(B(f, kind, (2 * half, 0.4, 0.4), (0, -half, zb), rnd=False))
        parts.append(B(f, kind, (2 * half, 0.4, 0.4), (0, half, zb), rnd=False))
        parts.append(B(f, kind, (0.4, 2 * half, 0.4), (-half, 0, zb), rnd=False))
        parts.append(B(f, kind, (0.4, 2 * half, 0.4), (half, 0, zb), rnd=False))
    return parts


def lantern(f, x, y, z, lit="glass"):
    return [B(f, "metal", (0.8, 0.8, 0.2), (x, y, z + 1.1), rnd=False),
            B(f, lit, (0.6, 0.6, 0.9), (x, y, z + 0.55), rnd=False),
            B(f, "metal", (0.8, 0.8, 0.15), (x, y, z), rnd=False)]


def barrel(f, x, y, kind="handle", r=1.0, h=2.6):
    p = [C(f, kind, r, h, (x, y, h / 2), verts=10)]
    for z in (0.5, h - 0.5):
        p.append(C(f, "metal", r + 0.05, 0.2, (x, y, z), verts=10, rnd=False))
    return p


def net(f, x0, x1, z0, z1, y, cells=6):
    """Twine fishing net hung flat on a wall plane (along x at depth y)."""
    p = []
    for i in range(cells + 1):
        x = x0 + (x1 - x0) * i / cells
        p.append(B(f, "twine", (0.12, 0.12, z1 - z0), (x, y, (z0 + z1) / 2), along="z", rnd=False))
    rows = max(2, int((z1 - z0) / ((x1 - x0) / cells)))
    for j in range(rows + 1):
        z = z0 + (z1 - z0) * j / rows
        p.append(B(f, "twine", (x1 - x0, 0.12, 0.12), ((x0 + x1) / 2, y, z), rnd=False))
    return p


def kind_of(o):
    return o.material_slots[0].material.name.split(".")[0].replace("rustic_", "") if o.material_slots else None


def palette(f, parts, sub, rigs=None):
    """Hold a prop to its 4 chosen materials (Roblox makes one MeshPart per material): repaint parts
    whose kind is in sub with sub[kind]. rigs maps a rig tag to the single kind its parts all get."""
    rigs = rigs or {}
    for o in parts:
        k = kind_of(o)
        want = rigs.get(o.get("rig")) if "rig" in o else sub.get(k)
        if want and want != k:
            f.apply(o, want, along="z")
    return parts


# ---------------------------------------------------------------- Pine Forest

def pine_lodge(f):
    """Pine Forest log lodge, about 30 x 25 x 22 studs: round bark-log walls with crossed corner ends,
    a steep plank roof, stone chimney, covered front porch and a 5 x 8 open doorway."""
    hw, hd, base, eave, rise = 12.0, 9.0, 0.8, 11.0, 7.5
    p = [floor(f, "stone", 2 * hw + 2, 2 * hd + 2, base)]
    door = (-2.5, 2.5, base, base + 8)
    wins = [(-9, -5.5, base + 3.5, base + 7), (5.5, 9, base + 3.5, base + 7)]
    p += log_wall(f, "x", -hd, -hw, hw, base, eave, holes=[door] + wins)
    p += log_wall(f, "x", hd, -hw, hw, base, eave, holes=[(-2, 2, base + 3.5, base + 7)])
    for s in (-1, 1):
        p += log_wall(f, "y", s * hw, -hd, hd, base + 0.6, eave, holes=[(-2, 2, base + 3.5, base + 7)])
    for (u0, u1, z0, z1) in wins:
        p += window(f, "x", -hd, -1, (u0 + u1) / 2, (z0 + z1) / 2, u1 - u0, z1 - z0, trim="handle")
    p += window(f, "x", hd, 1, 0, base + 5.25, 4, 3.5, trim="handle")
    for s in (-1, 1):
        p += window(f, "y", s * hw, s, 0, base + 5.25, 4, 3.5, trim="handle")
    p += door_frame(f, "x", -hd - 0.4, -1, *door, trim="handle")
    p.append(B(f, "handle", (0.4, 5, 8), (-2.5, -hd - 3.0, base + 4), along="z"))   # door swung open
    # Log gables and a steep plank roof.
    for y in (-hd, hd):
        p.append(prism(f, "bark", "x", y, 1.2, [(-hw, eave), (hw, eave), (0, eave + rise)]))
    p += gable_roof(f, "handle", hw + 0.6, eave, rise, 2 * hd + 2, ridge="y", t=0.7, over=1.6, cap="bark")
    # Covered porch on the front with log posts and a lean-to roof.
    p.append(B(f, "handle", (2 * hw, 6, 0.6), (0, -hd - 3.6, base - 0.1), along="x"))
    for x in (-hw + 0.8, -4, 4, hw - 0.8):
        p.append(C(f, "bark", 0.5, 8.5, (x, -hd - 6.0, base + 4.25), verts=8, rnd=False))
    p.append(plate(f, "handle", (-hd - 7.4, base + 8.0), (-hd - 0.6, base + 10.2), 0.5, "x", 2 * hw + 1))
    p.append(C(f, "bark", 0.45, 2 * hw, (0, -hd - 6.0, base + 8.6), verts=8, rot=(0, math.pi / 2, 0), along="x", rnd=False))
    # Stone chimney on the right gable end.
    p.append(B(f, "stone", (3, 4, eave + rise + 3), (hw + 1.8, 2, (eave + rise + 3) / 2), along="z"))
    p.append(B(f, "stone", (3.6, 4.6, 0.8), (hw + 1.8, 2, eave + rise + 3), rnd=False))
    # Woodpile and a chopping stump by the porch.
    for i in range(3):
        for j in range(3 - i):
            p.append(C(f, "bark", 0.6, 3.0, (-hw - 2.5, -4 + j * 1.25 + i * 0.6, 0.6 + i * 1.05), verts=8,
                       rot=(math.pi / 2, 0, 0), along="y", rnd=False))
    p.append(C(f, "bark", 1.0, 1.4, (-hw - 3.0, -9, 0.7), verts=10))
    p.append(C(f, "wood", 1.0, 0.05, (-hw - 3.0, -9, 1.43), verts=10, rnd=False))
    return palette(f, p, {"wood": "bark"})


# ---------------------------------------------------------------- Snow Peak

def snow_cabin(f):
    """Snow Peak cabin, about 20 x 20 x 19 studs: plank walls under a steep roof capped with thick
    snow (paint_cream), drifts and icicles. A plain 4 x 7 hidden door on the right side wall sits half
    behind a snow drift (tagged Door, the Frostbite Mitts quest)."""
    hw, hd, base, eave, rise = 8.0, 7.0, 0.6, 9.0, 7.0
    p = [floor(f, "stone", 2 * hw + 1, 2 * hd + 1, base)]
    a = hw - WALL / 2
    front = (-2, 2, base, base + 7)
    hidden = (1.0, 5.0, base, base + 7)                         # y range on the right wall
    p += wall(f, "handle", "x", -hd + WALL / 2, -a, a, base, eave, holes=[front, (3.5, 6.5, base + 3, base + 6)])
    p += wall(f, "handle", "x", hd - WALL / 2, -a, a, base, eave)
    p += wall(f, "handle", "y", -hw + WALL / 2, -hd, hd, base, eave, holes=[(-2, 2, base + 3, base + 6)])
    p += wall(f, "handle", "y", hw - WALL / 2, -hd, hd, base, eave, holes=[hidden])
    p += door_frame(f, "x", -hd, -1, *front, trim="bark")
    p.append(B(f, "bark", (4, 0.4, 7), (0, -hd + 0.4, base + 3.5), along="z"))              # front door, shut
    p += window(f, "x", -hd, -1, 5, base + 4.5, 3, 3, trim="bark")
    p += window(f, "y", -hw, -1, 0, base + 4.5, 4, 3, trim="bark")
    # Hidden door: flush planks, no trim, so it reads as more wall until the drift is dug away.
    door = [B(f, "handle", (0.5, 4, 7), (hw - WALL / 2, 3.0, base + 3.5), along="z")]
    door.append(B(f, "metal", (0.6, 0.3, 0.6), (hw - 0.1, 1.5, base + 3.5), rnd=False))
    p += tag(door, "Door")
    for x in (-hw, hw):
        for y in (-hd, hd):
            p.append(B(f, "bark", (0.9, 0.9, eave - base), (x, y, (eave + base) / 2), along="z", rnd=False))
    for y in (-hd + WALL / 2, hd - WALL / 2):
        p.append(prism(f, "handle", "x", y, WALL, [(-hw, eave), (hw, eave), (0, eave + rise)]))
    p += gable_roof(f, "bark", hw, eave, rise, 2 * hd, ridge="y", t=0.6, over=1.4, cap="paint_cream")
    # Snow cap: thick cream slabs on both roof slopes, drooping over the eaves.
    for s in (-1, 1):
        p.append(plate(f, "paint_cream", (s * (hw + 1.6), eave - 1.0), (0, eave + rise + 0.6), 1.0, "y", 2 * hd + 3.2))
        p.append(B(f, "paint_cream", (1.2, 2 * hd + 3.2, 0.9), (s * (hw + 1.4), 0, eave - 1.3), along="y"))
        for i in range(7):
            y = -hd + 1 + i * 2.1
            ln = 0.8 + (i * 7 % 5) * 0.25
            p.append(T(f, "glass", 0.18, 0.04, eave - 1.75 - ln, eave - 1.75, x=s * (hw + 1.6), y=y, verts=5, rnd=False))
    p.append(B(f, "paint_cream", (1.4, 2 * hd + 3.4, 1.0), (0, 0, eave + rise + 1.1), along="y"))
    # Chimney with snow on top.
    p.append(B(f, "stone", (2.2, 2.2, 6), (-3.5, 3, eave + rise - 1)))
    p.append(B(f, "paint_cream", (2.6, 2.6, 0.6), (-3.5, 3, eave + rise + 2.2)))
    # Snow drifts, the big one hiding the lower half of the side door.
    rng = random.Random(7)
    for x, y, sx, sy, sz in ((hw + 1.6, 3.0, 3.2, 7.0, 4.0), (hw + 1.2, -4.0, 2.4, 4.0, 2.0),
                             (-hw - 1.5, 2.0, 3.0, 8.0, 2.4), (-4, -hd - 1.6, 5.0, 2.6, 1.6),
                             (5, hd + 1.4, 7.0, 2.6, 2.2)):
        p.append(B(f, "paint_cream", (sx, sy, sz), (x, y, sz / 2 - 0.3), rot=(0, rng.uniform(-0.15, 0.15), 0)))
    return palette(f, p, {"glass": "bark", "paint_green": "bark", "metal": "bark"}, {"Door": "handle"})


# ---------------------------------------------------------------- Haunted Grove

def haunted_barn(f):
    """Haunted Grove barn, about 24 x 30 x 24 studs: weathered dark-grey boards, the whole frame leaning
    a few degrees, holes of missing boards, loose boards hanging, a sagging roof with gaps, a crooked
    door leaf and a softly glowing loft window. 12 x 11 doorway for the Ghost Hauler."""
    hw, hd, base, eave, rise = 11.0, 14.0, 0.5, 12.0, 9.0
    p = [floor(f, "stone", 2 * hw + 1, 2 * hd + 1, base)]
    a = hw - WALL / 2
    door = (-6, 6, base, base + 11)
    holes_f = [door, (7.5, 9.5, base + 7, base + 9.5)]
    shell = []
    shell += wall(f, "greywood", "x", -hd + WALL / 2, -a, a, base, eave, holes=holes_f)
    shell += wall(f, "greywood", "x", hd - WALL / 2, -a, a, base, eave, holes=[(-3, 0, base + 4, base + 6)])
    shell += wall(f, "greywood", "y", -hw + WALL / 2, -hd, hd, base, eave, holes=[(-8, -6, base + 2, base + 8),
                                                                              (4, 7, base + 5, base + 7)])
    shell += wall(f, "greywood", "y", hw - WALL / 2, -hd, hd, base, eave, holes=[(-2, 1, base + 6, base + 10)])
    # Vertical batten strips (grey stone-ish weathering) make it read as boards.
    for s in (-1, 1):
        for y in range(-12, 13, 4):
            if s < 0 and -8 <= y <= -6:
                continue
            shell.append(B(f, "stone", (0.3, 0.5, eave - base - 1), (s * (hw + 0.1), y, (eave + base) / 2), along="z", rnd=False))
    for x in (-hw, hw):
        for y in (-hd, hd):
            shell.append(B(f, "stone", (0.9, 0.9, eave - base), (x, y, (eave + base) / 2), along="z", rnd=False))
    gable = [(-hw, eave), (hw, eave), (0, eave + rise)]
    for y in (-hd + WALL / 2, hd - WALL / 2):
        shell.append(prism(f, "greywood", "x", y, WALL, gable))
    shell += door_frame(f, "x", -hd, -1, *door, trim="stone")
    # Loft window glowing in the front gable.
    shell.append(B(f, "glow", (3, 0.3, 3), (0, -hd + 0.2, eave + 3.0), rnd=False))
    shell += window(f, "x", -hd, -1, 0, eave + 3.0, 3, 3, trim="stone")
    # Sagging, gappy roof: plates broken into strips with a missing one.
    L = 2 * hd + 2.4
    for s in (-1, 1):
        n = 5
        for i in range(n):
            if s > 0 and i == 3:
                continue
            ln = L / n - 0.3
            y = -L / 2 + (i + 0.5) * L / n
            sag = 0.4 if i in (1, 2) else 0.0
            shell.append(plate(f, "handle", (s * (hw + 1.2), eave - 0.9 - sag), (0, eave + rise - sag), 0.5, "y", ln, mid=y))
    shell.append(B(f, "greywood", (0.8, L, 0.8), (0, 0, eave + rise + 0.5), along="y"))
    p += shear(shell, kx=0.06)
    # Crooked door leaf hanging from one hinge, and loose boards.
    p.append(B(f, "greywood", (6, 0.4, 10), (-8.6, -hd - 1.4, base + 5.3), rot=(0, math.radians(8), math.radians(-20))))
    for x, y, z, ang in ((8.5, -hd - 0.6, 6, 30), (-hw - 0.6, -7, 5, -25), (hw + 0.6, -0.5, 9, 40)):
        rot = (0, math.radians(ang), 0) if abs(y) > hd - 1 else (math.radians(ang), 0, 0)
        size = (0.9, 0.25, 4.5) if abs(y) > hd - 1 else (0.25, 0.9, 4.5)
        p.append(B(f, "handle", size, (x, y, z), rot=rot, rnd=False))
    for x, y, rz in ((-5, -hd - 4, 0.3), (6, -hd - 5, -0.5), (-hw - 3, 4, 1.2)):
        p.append(B(f, "handle", (4.0, 0.9, 0.25), (x, y, 0.15), rot=(0, 0, rz), rnd=False))
    # Dead tree and a lantern on a post.
    p.append(T(f, "greywood", 1.0, 0.5, 0, 12, x=hw + 5, y=-hd + 3, verts=8, rnd=False))
    p.append(brace(f, "greywood", (hw + 5, -hd + 3, 9), (hw + 9, -hd + 1, 14), 0.6))
    p.append(brace(f, "greywood", (hw + 5, -hd + 3, 7), (hw + 2, -hd, 11), 0.5))
    p.append(B(f, "greywood", (0.5, 0.5, 6), (-hw - 2, -hd - 2, 3), along="z", rnd=False))
    p += lantern(f, -hw - 2, -hd - 2.6, 4.2, lit="glow")
    return palette(f, p, {"glass": "greywood", "metal": "stone", "bark": "greywood"})


# ---------------------------------------------------------------- Volcano

def volcano_forge(f):
    """Volcano stone forge, about 26 x 26 x 30 studs: heavy dark stone walls, a tall tapering chimney
    stack, an 8 x 9 open archway, an anvil out front and a long stone lava trough with a molten
    surface running across the yard."""
    hw, hd, base, eave = 9.0, 8.0, 0.8, 11.0
    p = [floor(f, "stone", 2 * hw + 4, 2 * hd + 12, base, y=-4)]
    a = hw - 1.0
    arch = (-4, 4, base, base + 9)
    p += wall(f, "stone", "x", -hd + 1.0, -a, a, base, eave, t=2.0, holes=[arch])
    p += wall(f, "stone", "x", hd - 1.0, -a, a, base, eave, t=2.0)
    for s in (-1, 1):
        p += wall(f, "stone", "y", s * (hw - 1.0), -hd, hd, base, eave, t=2.0, holes=[(-2, 2, base + 4, base + 7)])
        p += window(f, "y", s * hw, s, 0, base + 5.5, 4, 3, trim="metal", cross=False)
    p += door_frame(f, "x", -hd, -1, *arch, trim="metal", t=0.8)
    p.append(B(f, "stone", (2 * hw + 1, 2 * hd + 1, 1.4), (0, 0, eave + 0.7)))
    p.append(B(f, "stone", (2 * hw - 3, 2 * hd - 3, 1.2), (0, 0, eave + 2.0)))
    # Chimney stack with iron bands.
    p.append(frustum(f, "stone", 2.0, 3.2, eave + 2.6, eave + 18, x=-3, y=3))
    for z in (eave + 7, eave + 13):
        p.append(B(f, "metal", (6.0 - (z - eave) * 0.12, 6.0 - (z - eave) * 0.12, 0.5), (-3, 3, z), rnd=False))
    p.append(B(f, "metal", (4.6, 4.6, 0.6), (-3, 3, eave + 18.2), rnd=False))
    # Forge fire seen through the arch.
    p.append(B(f, "stone", (7, 3, 3.5), (0, hd - 3.5, base + 1.75)))
    p.append(B(f, "lava", (5, 2, 0.4), (0, hd - 3.5, base + 3.6), rnd=False))
    p.append(B(f, "lava", (4, 1.5, 0.6), (0, hd - 3.5, base + 3.9), rnd=False))
    # Lava trough out front: stone channel, molten fill, a sluice gate box at one end.
    ty = -hd - 6
    p.append(B(f, "stone", (2 * hw + 2, 4, 2.2), (0, ty, base + 1.1)))
    p.append(B(f, "lava", (2 * hw, 2.6, 0.3), (0, ty, base + 2.15), rnd=False))
    for x in (-7, -2.5, 3, 7.5):
        p.append(B(f, "lava", (2.4, 1.6, 0.2), (x, ty + 0.2 * (x % 2), base + 2.35), rnd=False))
    p.append(B(f, "stone", (3, 5, 4.5), (hw + 2.0, ty, base + 2.25)))
    p.append(B(f, "metal", (0.5, 3.0, 3.0), (hw + 0.4, ty, base + 2.9), rnd=False))
    # Anvil and quench barrel.
    p.append(B(f, "stone", (2.2, 1.6, 1.8), (-5, -hd - 2.5, base + 0.9)))
    p.append(B(f, "metal", (3.0, 1.2, 0.9), (-5, -hd - 2.5, base + 2.25)))
    p.append(T(f, "metal", 0.6, 0.1, base + 2.0, base + 2.6, x=-7.0, y=-hd - 2.5, verts=6, rnd=False))
    p += barrel(f, 5, -hd - 2.5, kind="handle")
    # Scattered volcanic rocks.
    rng = random.Random(11)
    for x, y in ((-hw - 4, -hd), (hw + 4, hd - 2), (-hw - 3, hd + 2), (hw + 5, -hd - 1)):
        p.append(rock(f, rng, x, y, 1.0, 3, 2.5, 2.2))
    return palette(f, p, {"glass": "metal", "paint_red": "lava", "paint_yellow": "lava"})


# ---------------------------------------------------------------- Desert Dunes

def buried_pyramid_garage(f):
    """Desert Dunes buried pyramid, about 52 x 52 x 24 studs: a stepped sandstone pyramid sunk into
    the sand with a pillared portal and a 12 wide x 11 tall roll-up garage door (tagged Door) on the
    front, big enough to drive a pickup in. Sand dunes heap up against its sides."""
    steps, step_h, half0 = 11, 2.0, 25.0
    door = (-6.0, 6.0, 0.0, 11.0)
    back = 10.0                                    # tunnel runs from the front face to y=back
    p = [B(f, "paint_cream", (12, back + half0, 0.2), (0, (back - half0) / 2, 0.1), rnd=False)]   # tunnel floor
    for i in range(steps):
        z0, z1 = i * step_h, (i + 1) * step_h
        h = half0 - i * 2.0
        zc, hz = (z0 + z1) / 2, z1 - z0
        if z0 >= door[3]:
            p.append(B(f, "paint_yellow", (2 * h, 2 * h, hz), (0, 0, zc)))
            continue
        for s in (-1, 1):                          # left and right of the tunnel
            p.append(B(f, "paint_yellow", (h - 6.0, 2 * h, hz), (s * (6.0 + h) / 2, 0, zc)))
        if z1 > door[3]:                           # roof over the tunnel
            p.append(B(f, "paint_yellow", (12.0, 2 * h, z1 - door[3]), (0, 0, (door[3] + z1) / 2)))
        if back < h:                               # behind the tunnel end
            lo = z0
            hi = min(z1, door[3])
            p.append(B(f, "paint_yellow", (12.0, h - back, hi - lo), (0, (back + h) / 2, (lo + hi) / 2)))
    # Capstone.
    p.append(frustum(f, "paint_yellow", 0.4, 3.0, steps * step_h, steps * step_h + 3))
    # Portal: two square pillars and a heavy lintel with carved glyph blocks.
    fy = -half0
    for s in (-1, 1):
        p.append(B(f, "paint_cream", (2.4, 2.4, 13.4), (s * 7.4, fy - 1.0, 6.7), along="z"))
    p.append(B(f, "paint_cream", (17.2, 3.0, 2.6), (0, fy - 1.0, 12.4)))
    for x in (-5, -2.5, 0, 2.5, 5):
        p.append(B(f, "bark", (1.0, 0.3, 1.2), (x, fy - 2.55, 12.4), rnd=False))
    p.append(B(f, "paint_cream", (4, 1.0, 4), (0, fy - 1.6, 15.2)))
    p.append(B(f, "glass", (1.6, 0.3, 1.6), (0, fy - 2.15, 15.2), rnd=False))
    # Roll-up garage door, closed, in the portal: tagged Door so the quest can roll it up.
    gd = [B(f, "metal", (12.0, 0.4, 11.0), (0, fy - 0.5, 5.5), rnd=False)]
    for z in [0.9 * k + 0.6 for k in range(12)]:
        gd.append(B(f, "metal", (12.0, 0.5, 0.25), (0, fy - 0.75, z), rnd=False))
    gd.append(B(f, "metal", (1.8, 0.5, 0.5), (0, fy - 0.95, 1.4), rnd=False))
    p += tag(gd, "Door")
    p.append(B(f, "metal", (13.0, 1.8, 1.4), (0, fy - 0.4, 11.7), rnd=False))     # roll drum housing
    # Sand dunes banked against the sides and corners (kept clear of the door).
    rng = random.Random(5)
    for x, y, sx, sy, sz in ((-18, -24, 14, 7, 5), (19, -23, 12, 8, 6), (-27, 0, 7, 30, 8),
                             (27, 4, 8, 26, 7), (0, 27, 34, 7, 7), (-24, 20, 10, 10, 6), (22, 22, 12, 9, 5),
                             (-12, -30, 6, 4, 1.6), (12, -31, 7, 4, 1.4)):
        p.append(B(f, "paint_cream", (sx, sy, sz), (x, y, sz / 2 - 1.2),
                   rot=(rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), rng.uniform(-0.2, 0.2))))
    return palette(f, p, {"glass": "bark"}, {"Door": "metal"})


# ---------------------------------------------------------------- Swamp

def swamp_stilt_house(f):
    """Swamp house on stilts, about 22 x 34 x 19 studs: a green plank shack with a tin roof on a deck
    6 studs up, log stilts, a ladder, and a low plank dock running out the front with mooring posts."""
    hw, hd, deck = 8.0, 7.0, 6.0
    p = []
    for x in (-hw, 0, hw):
        for y in (-hd, 0, hd):
            p.append(C(f, "bark", 0.55, deck, (x, y, deck / 2), verts=8, rnd=False))
    for s in (-1, 1):
        p.append(brace(f, "bark", (-hw, s * hd, 0.5), (hw, s * hd, deck - 0.5), 0.4))
    p.append(B(f, "handle", (2 * hw + 2, 2 * hd + 2, 0.6), (0, 0, deck + 0.3)))
    base = deck + 0.6
    cw, cd, eave, rise = 6.0, 5.0, base + 8, 3.5
    a = cw - WALL / 2
    door = (-2, 2, base, base + 7)
    p += wall(f, "paint_green", "x", -cd + WALL / 2, -a, a, base, eave, holes=[door, (3, 5, base + 3.5, base + 5.5)])
    p += wall(f, "paint_green", "x", cd - WALL / 2, -a, a, base, eave)
    for s in (-1, 1):
        p += wall(f, "paint_green", "y", s * (cw - WALL / 2), -cd, cd, base, eave, holes=[(-1, 1, base + 3.5, base + 5.5)])
    p += window(f, "x", -cd, -1, 4, base + 4.5, 2, 2, trim="bark")
    p += door_frame(f, "x", -cd, -1, *door, trim="bark")
    p.append(B(f, "handle", (4, 0.4, 7), (-2.0 - 0.0, -cd - 2.0, base + 3.5), rot=(0, 0, math.pi / 2)))
    for y in (-cd + WALL / 2, cd - WALL / 2):
        p.append(prism(f, "paint_green", "x", y, WALL, [(-cw, eave), (cw, eave), (0, eave + rise)]))
    p += gable_roof(f, "metal", cw, eave, rise, 2 * cd, ridge="y", over=1.4, sheet=True)
    p.append(B(f, "metal", (0.8, 0.8, 4), (cw - 2, cd - 1.5, eave + 2)))      # stovepipe
    # Deck railing, ladder down to the dock.
    p += railing(f, "bark", -hw - 1, hw + 1, hd + 1, base, h=2.5)
    for s in (-1, 1):
        p += railing(f, "bark", -hd - 1, hd + 1, s * (hw + 1), base, h=2.5, along="y")
    p += railing(f, "bark", -hw - 1, -2.5, -hd - 1, base, h=2.5)
    p += railing(f, "bark", 2.5, hw + 1, -hd - 1, base, h=2.5)
    for s in (-1, 1):
        p.append(brace(f, "handle", (s * 1.6, -hd - 6.0, 1.0), (s * 1.6, -hd - 1.0, deck + 0.6), 0.4))
    for k in range(5):
        z = 1.6 + k * 1.1
        y = -hd - 6.0 + (z - 1.0) / (deck - 0.4) * 5.0
        p.append(B(f, "handle", (3.2, 0.9, 0.25), (0, y, z), rnd=False))
    # Dock: plank walkway out the front, low over the water, with mooring posts.
    dz = 1.6
    p.append(B(f, "handle", (5, 12, 0.4), (0, -hd - 12, dz)))
    for y in range(-int(hd) - 17, -int(hd) - 6, 2):
        p.append(B(f, "handle", (5.2, 0.15, 0.1), (0, y + 0.5, dz + 0.22), rnd=False))
    for x in (-2.8, 2.8):
        for y in (-hd - 7, -hd - 12, -hd - 17.5):
            p.append(C(f, "bark", 0.45, dz + 1.6, (x, y, (dz + 1.6) / 2), verts=8, rnd=False))
    p.append(C(f, "twine", 0.5, 0.4, (2.8, -hd - 17.5, dz + 1.0), verts=8, rnd=False))
    p.append(B(f, "handle", (3.2, 7.0, 0.8), (5.2, -hd - 14, 0.6), rot=(0, 0, 0.1)))      # skiff
    p.append(B(f, "handle", (2.6, 1.0, 1.0), (5.2, -hd - 17.2, 0.9), rot=(0, 0, 0.1)))
    p += lantern(f, -2.2, -cd - 0.6, base + 7.2)
    p += barrel(f, -hw + 1.2, -hd + 1.2, kind="paint_green")
    return palette(f, p, {"glass": "bark", "twine": "bark"})


# ---------------------------------------------------------------- The Spindle (center)

def the_spindle(f):
    """The Spindle, the giant tower at the center of the map, about 40 x 40 x 120 studs: a stone plinth
    with 12 shard sockets in a ring (tagged Socket..Socket12), a huge bobbin with flanges top and bottom
    wound with red thread, and a steel spindle shaft rising to a needle eye. A sealed stone slab door
    (tagged Door, 6 x 9) opens when all 12 shards are placed."""
    p = [C(f, "stone", 19.0, 1.2, (0, 0, 0.6), verts=24)]
    p.append(C(f, "stone", 14.0, 2.0, (0, 0, 2.2), verts=24))
    # Bobbin: bottom flange, wound core, top flange.
    p.append(C(f, "handle", 13.0, 3.0, (0, 0, 4.7), verts=24))
    p.append(C(f, "metal", 13.2, 0.4, (0, 0, 5.9), verts=24, rnd=False))
    p.append(C(f, "wood", 8.0, 34.0, (0, 0, 23.2), verts=20, rnd=False))
    for i in range(8):
        z = 8.4 + i * 4.0
        r = 10.0 + 0.6 * math.sin(i * 0.9)
        p.append(C(f, "paint_red", r, 3.6, (0, 0, z), verts=20, rnd=False))
        p.append(C(f, "twine", r + 0.1, 0.3, (0, 0, z + 1.9), verts=20, rnd=False))
    p.append(C(f, "metal", 11.2, 0.4, (0, 0, 40.4), verts=24, rnd=False))
    p.append(C(f, "handle", 11.0, 3.0, (0, 0, 42.1), verts=24))
    # A loose thread end drifting down the side.
    for k in range(5):
        p.append(brace(f, "paint_red", (10.2 + k * 0.4, -2 - k * 1.2, 30 - k * 5), (10.6 + k * 0.4, -3.2 - k * 1.2, 25 - k * 5), 0.6))
    # Spindle shaft: steel cone up to a needle eye.
    # The shaft tops every silo at about 120 studs so it works as the map's skyline compass (B2-3).
    p.append(T(f, "steel", 3.4, 1.3, 43.6, 112.0, verts=12))
    p.append(C(f, "steel", 1.0, 0.8, (0, 0, 44.0), verts=12, rnd=False))
    for s in (-1, 1):
        p.append(B(f, "steel", (0.9, 1.0, 7.0), (s * 1.4, 0, 115.5), along="z"))
    p.append(B(f, "steel", (3.7, 1.0, 0.8), (0, 0, 119.4)))
    p.append(B(f, "steel", (3.7, 1.0, 0.8), (0, 0, 112.0)))
    # Sealed door in the plinth front.
    p.append(B(f, "stone", (8.4, 1.0, 10.4), (0, -13.4, 5.2)))
    p += tag([B(f, "stone", (6.0, 0.8, 9.0), (0, -14.0, 1.2 + 4.5)),
              B(f, "metal", (5.0, 0.3, 0.5), (0, -14.5, 7.5), rnd=False),
              B(f, "metal", (0.5, 0.3, 5.0), (0, -14.5, 5.0), rnd=False)], "Door")
    # Steps up to the door.
    for k in range(2):
        p.append(B(f, "stone", (8, 2.0, 0.6 * (k + 1)), (0, -19.0 + k * 1.8, 0.3 * (k + 1))))
    # 12 shard sockets on short pillars around the plinth ring.
    for i in range(12):
        a = -math.pi / 2 + 2 * math.pi * (i + 0.5) / 12
        x, y = 17.0 * math.cos(a), 17.0 * math.sin(a)
        p.append(C(f, "stone", 0.9, 2.4, (x, y, 2.4), verts=8))
        p += tag([C(f, "metal", 0.75, 0.6, (x, y, 3.9), verts=8, rnd=False),
                  C(f, "tire", 0.45, 0.1, (x, y, 4.21), verts=8, rnd=False)], "Socket", str(i))
    return palette(f, p, {"twine": "handle", "wood": "handle", "metal": "steel", "tire": "steel"}, {"Door": "stone", "Socket": "steel"})


# ---------------------------------------------------------------- Cave

def cave_entrance(f):
    """Cave mine entrance, about 30 x 16 x 18 studs: a heap of boulders forming a rocky arch over a
    10 x 9 opening, timber supports framing it, mine-cart rails on sleepers running out, and a cart."""
    rng = random.Random(3)
    p = [B(f, "tire", (12, 0.6, 11), (0, 3.0, 5.5), rnd=False)]          # dark mouth
    # Rock mass: side piles and a lintel heap over the opening.
    for x, y, z, sx, sy, sz in ((-9, 0, 3.0, 8, 9, 7), (9, 0, 3.0, 8, 9, 7), (-11, 2, 8, 6, 8, 6),
                                (11, 2, 8, 6, 8, 6), (-6, 1, 11.5, 7, 8, 4), (6, 1, 11.5, 7, 8, 4),
                                (0, 1, 13.0, 10, 8, 4.0), (-3, 2, 16, 8, 7, 4), (3, 2, 16.5, 7, 6, 4),
                                (-14, -2, 1.5, 5, 5, 3), (14, -1, 1.5, 4, 5, 3), (0, 4, 18, 5, 5, 3)):
        p.append(rock(f, rng, x, y, z, sx, sy, sz))
    for x, y, z in ((-12, -5, 0.8), (13, -6, 0.6), (-6, -7, 0.5)):
        p.append(rock(f, rng, x, y, z, 2, 1.6, 1.4))
    # Timber supports: posts, header and knee braces.
    y0 = -3.6
    for s in (-1, 1):
        p.append(B(f, "handle", (1.0, 1.0, 10), (s * 5.4, y0, 5.0), along="z"))
        p.append(brace(f, "handle", (s * 5.4, y0, 7.2), (s * 3.4, y0, 9.4), 0.6))
    p.append(B(f, "handle", (12.4, 1.2, 1.2), (0, y0, 10.3)))
    p.append(B(f, "handle", (12.4, 1.2, 1.2), (0, 1.0, 10.3)))
    for s in (-1, 1):
        p.append(B(f, "handle", (1.0, 1.0, 10), (s * 5.4, 1.0, 5.0), along="z"))
    p.append(B(f, "handle", (5, 0.4, 1.4), (0, y0 - 0.7, 11.4)))     # name board
    # Rails out of the mouth.
    for k in range(9):
        p.append(B(f, "handle", (4.4, 0.8, 0.4), (0, 2.5 - k * 1.8, 0.2), rnd=False))
    for s in (-1, 1):
        p.append(B(f, "metal", (0.3, 17, 0.4), (s * 1.5, -4.5, 0.6), along="y", rnd=False))
    # Mine cart.
    cy = -9.0
    p.append(frustum(f, "metal", 1.0, 0.8, 1.2, 3.8, y=cy))
    p.append(B(f, "tire", (3.2, 3.2, 0.2), (0, cy, 3.75), rnd=False))
    for x in (-1.5, 1.5):
        for y in (cy - 1.0, cy + 1.0):
            p.append(C(f, "metal", 0.55, 0.3, (x, y, 0.95), verts=8, rot=(0, math.pi / 2, 0), along="x", rnd=False))
    p += lantern(f, -5.4, y0 - 0.8, 7.0)
    return palette(f, p, {"glass": "metal"})


# ---------------------------------------------------------------- Sky Island

def zeppelin_dock(f):
    """Sky Island zeppelin mooring mast, about 24 x 30 x 46 studs: a steel lattice tower on a stone
    footing, a railed platform up top with the mooring cone, a ladder, and a railed gangway reaching
    out 14 studs toward the airship (tagged Gangway)."""
    half, top = 4.0, 38.0
    p = [B(f, "stone", (12, 12, 1.2), (0, 0, 0.6))]
    p += lattice_mast(f, "steel", half, 1.2, top, 6)
    # Platform and railing.
    p.append(B(f, "handle", (13, 13, 0.6), (0, 0, top + 0.3)))
    for s in (-1, 1):
        p += railing(f, "steel", -6.5, 6.5, s * 6.5, top + 0.6, h=2.6, step=3.25)
    p += railing(f, "steel", -6.5, 6.5, 6.5, top + 0.6, h=2.6, step=3.25, along="y")
    p += railing(f, "steel", 1.5, 6.5, -6.5, top + 0.6, h=2.6, step=2.5, along="y")
    p += railing(f, "steel", -6.5, -1.5, -6.5, top + 0.6, h=2.6, step=2.5, along="y")
    # Mooring head: a short mast and a cone cup with a beacon.
    p.append(C(f, "steel", 0.8, 6.0, (0, 0, top + 3.6), verts=10))
    p.append(T(f, "metal", 0.9, 2.4, top + 6.6, top + 8.0, verts=12))
    p += lantern(f, 0, 0, top + 8.0)
    # Gangway out the -x side (toward the airship): deck, rails, and a hanging rope.
    gx = -6.5
    g = [B(f, "handle", (14, 3.2, 0.4), (gx - 7.0, 0, top + 0.4))]
    for y in (-1.6, 1.6):
        g += railing(f, "twine", gx - 14, gx, y, top + 0.6, h=2.4, step=3.5)
    g.append(B(f, "metal", (0.6, 3.6, 0.6), (gx - 14, 0, top + 0.3), rnd=False))
    p += tag(g, "Gangway")
    for s in (-1, 1):
        p.append(brace(f, "steel", (-half, s * half, top - 6), (gx - 6, s * 1.6, top), 0.4))
    # Ladder up the front face.
    for s in (-1, 1):
        p.append(B(f, "steel", (0.3, 0.3, top), (s * 1.0, -half - 0.8, top / 2), along="z", rnd=False))
    for k in range(int(top / 2)):
        p.append(B(f, "steel", (2.0, 0.25, 0.25), (0, -half - 0.8, 1.6 + k * 2.0), rnd=False))
    # Wind sock pole.
    p.append(B(f, "steel", (0.3, 0.3, 4.0), (5.8, 5.8, top + 2.6), along="z", rnd=False))
    p.append(brace(f, "paint_red", (5.9, 5.8, top + 4.3), (8.6, 5.8, top + 3.9), 0.9))
    return palette(f, p, {"metal": "steel", "glass": "steel", "twine": "handle"}, {"Gangway": "handle"})


# ---------------------------------------------------------------- Thimble Keys

def thimble(f, r0, r1, z0, z1, rows=3, dots=12):
    """A thimble: tapering steel body, a rolled rim at the bottom and a domed crown with dimple rows."""
    p = [T(f, "steel", r0, r1, z0, z1, verts=16)]
    p.append(C(f, "steel", r0 + 0.35, 0.8, (0, 0, z0 + 0.4), verts=16))
    p.append(T(f, "steel", r1, r1 * 0.55, z1, z1 + r1 * 0.35, verts=16))
    h = z1 - z0
    for j in range(rows):
        z = z0 + 2.0 + j * (h - 3.0) / max(1, rows - 1) * 0.85
        r = r0 + (r1 - r0) * (z - z0) / h
        for i in range(dots):
            a = 2 * math.pi * (i + 0.5 * (j % 2)) / dots
            p.append(B(f, "metal", (0.7, 0.2, 0.7), (r * math.cos(a), r * math.sin(a), z),
                       rot=(0, 0, a + math.pi / 2), rnd=False))
    return p


def thimble_lighthouse(f):
    """Thimble Keys lighthouse, about 18 x 18 x 46 studs: three galvanized thimbles stacked smaller and
    smaller, dimpled all over, on a stone base, with a red-and-cream lamp room, a glowing lamp and a
    walk-around gallery. 4 x 7 door at the base."""
    p = [C(f, "stone", 9.0, 1.4, (0, 0, 0.7), verts=16)]
    p += thimble(f, 7.0, 6.0, 1.4, 14.0)
    p += thimble(f, 5.2, 4.4, 14.0 + 6.0 * 0.35, 25.0, rows=3, dots=10)
    p += thimble(f, 3.8, 3.2, 25.0 + 4.4 * 0.35, 33.5, rows=2, dots=8)
    z = 33.5 + 3.2 * 0.35
    # Gallery and lamp room.
    p.append(C(f, "metal", 5.0, 0.5, (0, 0, z + 0.25), verts=16))
    for i in range(12):
        a = 2 * math.pi * i / 12
        p.append(B(f, "metal", (0.25, 0.25, 2.0), (4.7 * math.cos(a), 4.7 * math.sin(a), z + 1.5), along="z", rnd=False))
    p.append(C(f, "metal", 4.8, 0.25, (0, 0, z + 2.5), verts=16, rnd=False))
    p.append(C(f, "paint_red", 3.0, 1.0, (0, 0, z + 1.0), verts=12))
    p.append(C(f, "glow", 1.4, 2.4, (0, 0, z + 3.2), verts=10, rnd=False))
    for i in range(6):
        a = 2 * math.pi * i / 6
        p.append(B(f, "paint_cream", (0.3, 0.3, 3.4), (2.65 * math.cos(a), 2.65 * math.sin(a), z + 3.2), along="z", rnd=False))
    p.append(T(f, "paint_red", 3.2, 0.4, z + 4.9, z + 7.2, verts=12))
    p.append(C(f, "metal", 0.4, 1.4, (0, 0, z + 7.8), verts=6, rnd=False))
    # Door at the base and a little porch step.
    p.append(B(f, "handle", (4.0, 1.2, 7.0), (0, -7.0, 1.4 + 3.5)))
    p += door_frame(f, "x", -7.4, -1, -2.0, 2.0, 1.4, 8.4, trim="paint_red")
    p.append(B(f, "stone", (6, 2.4, 0.7), (0, -9.6, 0.35)))
    # Round window high up.
    p.append(C(f, "glass", 1.0, 0.4, (0, -4.9, 20.0), verts=10, rot=(math.pi / 2, 0, 0), along="y", rnd=False))
    return palette(f, p, {"metal": "stone", "glass": "stone", "handle": "paint_red", "paint_cream": "steel"})


# ---------------------------------------------------------------- Bobbin Rock

def bobbin_captain_shack(f):
    """Bobbin Rock captain's shack, about 26 x 22 x 18 studs: a blue-trimmed plank shack on a rocky
    ledge, a ship's wheel mounted beside the door (tagged ShipWheel), fishing nets drying on the wall
    and on a pole rack, barrels, a buoy and an anchor."""
    rng = random.Random(9)
    p = []
    p.append(B(f, "stone", (17, 15, 2.2), (0, 1, 1.1)))
    for x, y, sx, sy, sz in ((-9, -5, 4, 3.5, 3.0), (9, -3, 3.5, 4, 2.6), (-8.5, 7, 4.5, 4, 3.4),
                             (8, 8, 4, 3, 2.8), (2, 9, 3, 2.5, 2.2), (-3, -7.6, 2.4, 2, 1.6)):
        p.append(rock(f, rng, x, y, sz / 2 - 0.2, sx, sy, sz))
    p.append(B(f, "handle", (16, 14, 0.6), (0, 1, 2.5)))
    hw, hd, base, eave, rise = 6.0, 5.0, 2.8, 10.8, 4.0
    a = hw - WALL / 2
    door = (-4.5, -0.5, base, base + 7)
    p += wall(f, "handle", "x", -hd + WALL / 2, -a, a, base, eave, holes=[door, (2, 4.5, base + 3.5, base + 5.5)])
    p += wall(f, "handle", "x", hd - WALL / 2, -a, a, base, eave)
    for s in (-1, 1):
        p += wall(f, "handle", "y", s * (hw - WALL / 2), -hd, hd, base, eave, holes=[(-1, 1, base + 3.5, base + 5.5)])
        p += window(f, "y", s * hw, s, 0, base + 4.5, 2, 2, trim="paint_blue")
    p += window(f, "x", -hd, -1, 3.25, base + 4.5, 2.5, 2, trim="paint_blue")
    p += door_frame(f, "x", -hd, -1, *door, trim="paint_blue")
    p.append(B(f, "paint_blue", (0.4, 4, 7), (-4.5, -hd - 2.0, base + 3.5), along="z"))
    for x in (-hw, hw):
        for y in (-hd, hd):
            p.append(B(f, "paint_blue", (0.8, 0.8, eave - base), (x, y, (eave + base) / 2), along="z", rnd=False))
    for y in (-hd + WALL / 2, hd - WALL / 2):
        p.append(prism(f, "handle", "x", y, WALL, [(-hw, eave), (hw, eave), (0, eave + rise)]))
    p += gable_roof(f, "bark", hw, eave, rise, 2 * hd, ridge="y", t=0.5, over=1.2, cap="paint_blue")
    p.append(B(f, "stone", (1.6, 1.6, 5), (3, 2, eave + rise)))
    # Ship's wheel on the front wall between door and window.
    wx, wy, wz = 1.2, -hd - 0.6, base + 5.0
    sw = []
    o = cyl(1.7 * S, 0.3 * S, (wx * S, wy * S, wz * S), verts=12, rot=(math.pi / 2, 0, 0))
    hole = cyl(1.4 * S, 0.6 * S, (wx * S, wy * S, wz * S), verts=12, rot=(math.pi / 2, 0, 0))
    m = o.modifiers.new("ring", "BOOLEAN")
    m.object, m.operation = hole, "DIFFERENCE"
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.data.objects.remove(hole)
    sw.append(f.apply(f.shape(o, round_edges=False), "handle", along="y"))
    sw.append(C(f, "metal", 0.4, 0.6, (wx, wy, wz), verts=8, rot=(math.pi / 2, 0, 0), along="y", rnd=False))
    for i in range(8):
        ang = math.pi * i / 4
        sw.append(B(f, "handle", (0.22, 0.22, 2.0 if i % 2 else 4.6), (wx, wy, wz), rot=(0, ang, 0), rnd=False))
    p += tag(sw, "ShipWheel")
    # Net on the side wall and a pole drying rack with a net.
    for k in range(5):
        y = -hd + 1 + k * 2.0
        p.append(B(f, "twine", (0.12, 0.12, 5), (-hw - 0.3, y, base + 4.5), along="z", rnd=False))
    for k in range(4):
        p.append(B(f, "twine", (0.12, 8.4, 0.12), (-hw - 0.3, -1, base + 2.4 + k * 1.4), along="y", rnd=False))
    for x in (-8.5, 5.0):
        p.append(B(f, "bark", (0.5, 0.5, 7), (x, -hd - 4.5, base + 3.5), along="z", rnd=False))
    p.append(B(f, "bark", (14, 0.4, 0.4), (-1.75, -hd - 4.5, base + 6.8), rnd=False))
    p += net(f, -8.0, 4.5, base + 2.2, base + 6.6, -hd - 4.5, cells=10)
    # Barrels, buoy, anchor.
    for x, y in ((hw + 1.4, -hd + 1), (hw + 1.4, -hd + 3.2)):
        for o in barrel(f, x, y, kind="handle", r=0.9, h=2.2):
            for v in o.data.vertices:
                v.co.z += base * S
            p.append(o)
    p.append(C(f, "paint_red", 0.9, 1.4, (-hw - 1.5, -hd - 1, base + 0.7), verts=10))
    p.append(C(f, "paint_cream", 0.92, 0.5, (-hw - 1.5, -hd - 1, base + 0.7), verts=10, rnd=False))
    p.append(B(f, "metal", (0.4, 0.4, 4), (hw + 1.0, hd - 1, base + 2.0), along="z", rnd=False))
    p.append(B(f, "metal", (3.0, 0.4, 0.4), (hw + 1.0, hd - 1, base + 0.4), rnd=False))
    for sgn in (-1, 1):
        p.append(B(f, "metal", (0.4, 0.4, 1.2), (hw + 1.0 + sgn * 1.4, hd - 1, base + 0.9), rnd=False))
    p.append(C(f, "metal", 0.6, 0.3, (hw + 1.0, hd - 1, base + 4.2), verts=8, rot=(math.pi / 2, 0, 0), rnd=False))
    return palette(f, p, {"twine": "bark", "metal": "stone", "glass": "bark", "paint_red": "paint_blue", "paint_cream": "handle"}, {"ShipWheel": "handle"})


# ---------------------------------------------------------------- Meadow Farm

def meadow_windmill(f):
    """Meadow Farm windmill, about 30 x 16 x 38 studs: an eight-sided tapering cream tower with a dark
    boat-shaped cap, four lattice sails with cloth (the hub and sails tagged Blades, turning about y),
    a 4 x 7 door and a little balcony."""
    p = [C(f, "stone", 7.4, 1.0, (0, 0, 0.5), verts=8)]
    p.append(T(f, "paint_cream", 7.0, 4.6, 1.0, 26.0, verts=8))
    p.append(C(f, "bark", 5.2, 0.8, (0, 0, 26.4), verts=8, rnd=False))
    p.append(T(f, "bark", 5.0, 0.6, 26.8, 32.0, verts=8))
    for z in (9.0, 17.5):
        r = 7.0 - (z - 1.0) / 25.0 * 2.4
        p.append(B(f, "glass", (2.0, 0.3, 2.6), (0, -r + 0.05, z), rnd=False))
        p += door_frame(f, "x", -r - 0.05, -1, -1.0, 1.0, z - 1.3, z + 1.3, trim="bark")
    p.append(B(f, "bark", (4.0, 1.0, 7.0), (0, -6.6, 1.0 + 3.5)))
    p += door_frame(f, "x", -7.0, -1, -2.0, 2.0, 1.0, 8.0, trim="bark")
    # Balcony ring at the cap.
    p.append(C(f, "handle", 7.0, 0.5, (0, 0, 22.0), verts=8))
    for i in range(8):
        a = 2 * math.pi * (i + 0.5) / 8
        p.append(B(f, "handle", (0.3, 0.3, 2.0), (6.7 * math.cos(a), 6.7 * math.sin(a), 23.0), along="z", rnd=False))
    p.append(C(f, "handle", 6.8, 0.3, (0, 0, 24.0), verts=8, rnd=False))
    # Sails on the front (-y), hub at y = -6.
    hy, hz = -6.4, 27.5
    bl = [C(f, "metal", 1.2, 2.4, (0, hy, hz), verts=10, rot=(math.pi / 2, 0, 0), along="y")]
    for i in range(4):
        a = math.pi / 4 + math.pi / 2 * i
        ca, sa = math.cos(a), math.sin(a)
        # Stock (main arm) and a sail frame along it.
        bl.append(B(f, "handle", (0.6, 0.6, 15.0), (7.6 * ca, hy - 0.4, hz + 7.6 * sa), rot=(0, -a + math.pi / 2, 0), rnd=False))
        for k in range(5):
            r = 3.5 + k * 2.6
            bl.append(B(f, "handle", (3.6, 0.3, 0.25), (r * ca - 1.8 * sa, hy - 0.5, hz + r * sa + 1.8 * ca),
                        rot=(0, -a + math.pi / 2 + math.pi / 2, 0), rnd=False))
        rc = 3.5 + 2 * 2.6
        bl.append(B(f, "cloth", (3.2, 0.15, 10.4), (rc * ca - 1.8 * sa, hy - 0.2, hz + rc * sa + 1.8 * ca),
                    rot=(0, -a + math.pi / 2, 0), rnd=False))
    p += tag(bl, "Blades")
    p.append(C(f, "metal", 0.5, 3.0, (0, -5.0, hz), verts=8, rot=(math.pi / 2, 0, 0), along="y", rnd=False))
    # Sacks by the door.
    for x in (-4.5, 4.0):
        p.append(B(f, "cloth", (1.8, 1.4, 2.2), (x, -7.6, 1.1)))
    return palette(f, p, {"glass": "bark", "metal": "stone", "cloth": "paint_cream"}, {"Blades": "handle"})


# ---------------------------------------------------------------- Longstitch Highway

def longstitch_highway_sign(f):
    """Longstitch Highway sign gantry, about 40 x 5 x 24 studs: two steel lattice legs on concrete
    footings spanning a 30 stud road with 16 studs of clearance, a truss beam, and two big green signs
    with cream borders, arrows and the dashed stitch line that is the highway's mark."""
    span, clear = 16.0, 16.0
    p = []
    for s in (-1, 1):
        x = s * span
        p.append(B(f, "stone", (4, 4, 1.4), (x, 0, 0.7)))
        for dx in (-1.0, 1.0):
            for dy in (-1.0, 1.0):
                p.append(B(f, "steel", (0.5, 0.5, clear + 3.5 - 1.4), (x + dx, dy, (clear + 3.5 + 1.4) / 2), along="z", rnd=False))
        for k in range(5):
            z = 1.4 + k * 3.6
            p.append(brace(f, "steel", (x - 1, -1, z), (x + 1, -1, z + 3.6), 0.25))
            p.append(brace(f, "steel", (x - 1, 1, z), (x + 1, 1, z + 3.6), 0.25))
    # Truss beam over the road.
    for z in (clear, clear + 3.5):
        for dy in (-1.0, 1.0):
            p.append(B(f, "steel", (2 * span + 2.5, 0.5, 0.5), (0, dy, z), rnd=False))
    n = 16
    for i in range(n):
        x0 = -span + 2 * span * i / n
        x1 = -span + 2 * span * (i + 1) / n
        za, zb = (clear, clear + 3.5) if i % 2 else (clear + 3.5, clear)
        p.append(brace(f, "steel", (x0, -1, za), (x1, -1, zb), 0.25))
    # Signs hanging on the front face.
    for cx, w, arrow in ((-7.0, 14.0, "up"), (7.5, 13.0, "right")):
        cz, h, y = clear + 4.0, 7.0, -1.6
        p.append(B(f, "paint_green", (w, 0.4, h), (cx, y, cz)))
        for dz in (-1, 1):
            p.append(B(f, "paint_cream", (w - 0.6, 0.2, 0.3), (cx, y - 0.25, cz + dz * (h / 2 - 0.45)), rnd=False))
        for dx in (-1, 1):
            p.append(B(f, "paint_cream", (0.3, 0.2, h - 0.6), (cx + dx * (w / 2 - 0.45), y - 0.25, cz), along="z", rnd=False))
        # Stitch line: a row of short dashes across the top.
        for k in range(6):
            p.append(B(f, "paint_cream", (1.0, 0.2, 0.3), (cx - w / 2 + 1.6 + k * (w - 3.2) / 5, y - 0.25, cz + 2.2), rnd=False))
        # Placeholder lettering bars.
        for k, ln in enumerate((w * 0.55, w * 0.4)):
            p.append(B(f, "paint_cream", (ln, 0.2, 0.7), (cx - w * 0.12, y - 0.25, cz + 0.6 - k * 1.4), rnd=False))
        ax = cx + w / 2 - 2.4
        if arrow == "up":
            p.append(B(f, "paint_cream", (0.6, 0.2, 2.8), (ax, y - 0.25, cz - 0.6), along="z", rnd=False))
            p.append(prism(f, "paint_cream", "x", y - 0.25, 0.2, [(ax - 1.2, cz + 0.8), (ax + 1.2, cz + 0.8), (ax, cz + 2.0)]))
        else:
            p.append(B(f, "paint_cream", (2.0, 0.2, 0.6), (ax - 0.8, y - 0.25, cz - 0.3), rnd=False))
            p.append(prism(f, "paint_cream", "x", y - 0.25, 0.2, [(ax + 0.2, cz - 1.5), (ax + 1.4, cz - 0.3), (ax + 0.2, cz + 0.9)]))
        for dx in (-w / 3, w / 3):
            p.append(B(f, "steel", (0.3, 0.6, 1.2), (cx + dx, -1.3, clear + 3.3), rnd=False))
    return palette(f, p, {})


# ---------------------------------------------------------------- Mazes

def corn_maze_gate(f):
    """Corn Night Maze gate, about 26 x 6 x 17 studs: rough timber arch wrapped in corn stalk bundles
    with cobs, a hanging board and lanterns, and two plank gate leaves (tagged Door, Door2) closing an
    8 x 10 opening; they swing open at nightfall."""
    p = []
    for s in (-1, 1):
        x = s * 5.0
        p.append(B(f, "bark", (1.4, 1.4, 14), (x, 0, 7.0), along="z"))
        # Corn shock: bundle of stalks leaning in against the post.
        for k in range(9):
            a = 2 * math.pi * k / 9
            dx, dy = 1.4 * math.cos(a), 1.4 * math.sin(a)
            p.append(brace(f, "paint_green", (x + s * 2.0 + dx * 1.4, dy * 1.4, 0), (x + s * 1.0 + dx * 0.3, dy * 0.3, 11.0), 0.35))
        for k in range(3):
            a = 2 * math.pi * k / 3 + 0.4
            p.append(B(f, "paint_yellow", (0.5, 0.5, 1.4), (x + s * 1.8 + math.cos(a) * 1.2, math.sin(a) * 1.2, 4.0 + k),
                       rot=(0.3, 0.2 * s, a), rnd=False))
        p.append(B(f, "twine", (2.4, 2.4, 0.4), (x + s * 1.3, 0, 7.0), rnd=False))
        # Low corn row fence running off to the side.
        for k in range(4):
            xx = x + s * (4.0 + k * 1.6)
            p.append(brace(f, "paint_green", (xx, 0.4, 0), (xx + s * 0.4, 0.0, 8.0 + (k % 2)), 0.3))
            p.append(B(f, "paint_green", (0.15, 1.4, 1.6), (xx + s * 0.2, 0.2, 5.0 + k % 2), rot=(0.6, 0, 0), rnd=False))
    p.append(B(f, "bark", (13.0, 1.4, 1.4), (0, 0, 14.0)))
    p.append(B(f, "bark", (12.0, 1.0, 1.0), (0, 0, 11.4)))
    for s in (-1, 1):
        p.append(brace(f, "bark", (s * 5.0, 0, 9.4), (s * 3.0, 0, 11.4), 0.6))
    p.append(B(f, "handle", (9.0, 0.4, 2.6), (0, -0.9, 16.2)))
    for x in (-3.5, 0.0, 3.5):
        p.append(B(f, "paint_red", (2.2, 0.2, 1.0), (x, -1.15, 16.2), rnd=False))
    for s in (-1, 1):
        p.append(B(f, "twine", (0.15, 0.15, 1.4), (s * 4.0, -0.9, 15.2), along="z", rnd=False))
        p.append(B(f, "metal", (0.3, 1.2, 0.3), (s * 5.0, -1.2, 10.0), rnd=False))
        p += lantern(f, s * 5.0, -2.0, 8.6)
    # Gate leaves, closed, hinged on the posts.
    for s, uid in ((-1, "L"), (1, "R")):
        leaf = []
        cx = s * 2.1
        for k in range(4):
            leaf.append(B(f, "handle", (0.95, 0.4, 9.6), (cx + (k - 1.5) * 1.0, -0.2, 5.4), along="z", rnd=False))
        for z in (1.6, 8.6):
            leaf.append(B(f, "bark", (4.0, 0.3, 0.6), (cx, -0.5, z), rnd=False))
        leaf.append(brace(f, "bark", (cx - s * 1.8, -0.55, 1.8), (cx + s * 1.8, -0.55, 8.4), 0.4))
        p += tag(leaf, "Door", uid)
    return palette(f, p, {"twine": "bark", "metal": "bark", "glass": "paint_yellow", "paint_red": "handle"}, {"Door": "handle"})


def straw_labyrinth_gate(f):
    """Straw Labyrinth gate, about 28 x 10 x 21 studs: an arch built only of real-size hay bales
    (4.6 x 2.6 x 3.2 studs) stacked like bricks, a 9.2 wide x 10.4 tall opening, a stepped crest,
    buttress bales and a plank name board with pennants."""
    p = []
    BL, BH, BD = 4.6, 2.6, 3.2
    rng = random.Random(21)

    def jit():
        return rng.uniform(-0.05, 0.05)        # hand-stacked: a few degrees off square

    # Pillars: 4 courses, two bales deep, one bale long, outside the opening.
    for s in (-1, 1):
        for row in range(4):
            for y in (-BD / 2, BD / 2):
                p += bale(f, s * (BL + BL / 2), y, row * BH, rot=jit())
        # Buttress bales stepping down the outside.
        p += bale(f, s * (2 * BL + BL / 2), 0, 0, rot=jit())
        p += bale(f, s * (2 * BL + BL / 2), 0, BH, rot=jit())
        p += bale(f, s * (3 * BL + BL / 2), 0, 0, rot=jit())
    # Lintel course spanning the opening, then a stepped crest.
    zl = 4 * BH
    for x in (-1.5, -0.5, 0.5, 1.5):
        for y in (-BD / 2, BD / 2):
            p += bale(f, x * BL, y, zl, rot=jit())
    for x in (-1.0, 0.0, 1.0):
        p += bale(f, x * BL, 0, zl + BH, rot=jit())
    for x in (-0.5, 0.5):
        p += bale(f, x * BL, 0, zl + 2 * BH, rot=jit())
    # Name board on posts above the crest, and pennants on the pillar tops.
    zt = zl + 3 * BH
    for s in (-1, 1):
        p.append(B(f, "bark", (0.4, 0.4, 3.0), (s * 3.0, -BD / 2 - 0.3, zt - 1.0), along="z", rnd=False))
    p.append(B(f, "handle", (8.0, 0.4, 2.2), (0, -BD / 2 - 0.5, zt + 0.2)))
    for x in (-2.4, 0.0, 2.4):
        p.append(B(f, "paint_cream", (1.8, 0.2, 0.7), (x, -BD / 2 - 0.75, zt + 0.2), rnd=False))
    for s in (-1, 1):
        x = s * (2 * BL - 1.0)
        p.append(B(f, "bark", (0.3, 0.3, 4.0), (x, 0, zl + 2.0 + 2.0), along="z", rnd=False))
        p.append(prism(f, "paint_red", "x", 0, 0.15, [(x, zl + 5.6), (x, zl + 3.8), (x + s * 2.4, zl + 4.7)]))
    return palette(f, p, {"bark": "handle", "paint_cream": "twine"})


# ---------------------------------------------------------------- Art-review landmarks (MODEL_SPECS.md)

def windmill(f):
    """American farm windmill, 10 wide at the base and 30 tall: a tapering wooden lattice tower on stone
    footings, a small platform, an iron gearbox, a 4-blade wooden rotor facing front (tagged Rotor,
    one material, hub at the pivot, spins about the forward axis) and a tail vane with a barn-red fin.
    Materials: handle, metal, stone, paint_red."""
    half0, half1, ztop = 4.6, 1.1, 23.0
    p = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.append(B(f, "stone", (1.6, 1.6, 0.8), (sx * half0, sy * half0, 0.4), rnd=False))
            p.append(brace(f, "handle", (sx * half0, sy * half0, 0.6), (sx * half1, sy * half1, ztop), 0.6))
    # Girts and X braces in 4 bays on every face.
    levels = [0.8, 6.5, 12.0, 17.5, ztop]

    def hw(z):
        return half0 + (half1 - half0) * (z - 0.6) / (ztop - 0.6)
    for za, zb in zip(levels, levels[1:]):
        ha, hb = hw(za), hw(zb)
        for s in (-1, 1):
            p.append(brace(f, "handle", (-ha, s * ha, za), (hb, s * hb, zb), 0.3))
            p.append(brace(f, "handle", (s * ha, -ha, za), (s * hb, hb, zb), 0.3))
        for s in (-1, 1):
            p.append(B(f, "handle", (2 * hb, 0.3, 0.3), (0, s * hb, zb), rnd=False))
            p.append(B(f, "handle", (0.3, 2 * hb, 0.3), (s * hb, 0, zb), rnd=False))
    # Platform, gearbox and turntable.
    p.append(B(f, "handle", (4.2, 4.2, 0.35), (0, 0, ztop + 0.15), rnd=False))
    p.append(C(f, "metal", 0.9, 0.8, (0, 0, ztop + 0.7), verts=8, rnd=False))
    hz = ztop + 2.2
    p.append(B(f, "metal", (1.4, 3.0, 1.6), (0, 0.2, hz)))
    p.append(C(f, "metal", 0.35, 1.2, (0, -1.6, hz), verts=8, rot=(math.pi / 2, 0, 0), along="y", rnd=False))
    # Pump rod down the middle of the tower.
    p.append(B(f, "metal", (0.2, 0.2, ztop - 1.0), (0, 0, ztop / 2), along="z", rnd=False))
    # Tail vane: boom out the back and a barn-red fin.
    p.append(brace(f, "handle", (0, 1.6, hz), (0, 6.6, hz + 0.6), 0.3))
    p.append(B(f, "paint_red", (0.2, 3.4, 2.4), (0, 7.4, hz + 0.7), rnd=False))
    # Rotor: hub plus four pitched wooden blades, all one material, hub center = pivot.
    hy = -2.5
    rotor = [C(f, "handle", 0.7, 0.8, (0, hy, hz), verts=8, rot=(math.pi / 2, 0, 0), along="y", rnd=False)]
    for i in range(4):
        a = math.pi / 4 + math.pi / 2 * i
        r = 2.9
        rotor.append(B(f, "handle", (1.3, 0.2, 4.4), (r * math.cos(a), hy, hz + r * math.sin(a)),
                       rot=(0, math.pi / 2 - a, 0), rnd=False))
        rotor.append(B(f, "handle", (0.3, 0.3, 4.6), (r * 0.98 * math.cos(a), hy + 0.25, hz + r * 0.98 * math.sin(a)),
                       rot=(0, math.pi / 2 - a, 0), rnd=False))
    p += tag(rotor, "Rotor")
    return palette(f, p, {}, {"Rotor": "handle"})


def spindle_landmark(f):
    """The Spindle seen from any region: a giant grey iron needle, 120 tall, point down in a 12 wide
    stepped stone base, with a long eye at the top lined by a faint glow ring. Materials: metal, stone,
    glow."""
    p = [C(f, "stone", 6.0, 2.4, (0, 0, 1.2), verts=8)]
    p.append(C(f, "stone", 4.6, 2.0, (0, 0, 3.4), verts=8))
    p.append(C(f, "stone", 3.2, 1.0, (0, 0, 4.9), verts=8, rnd=False))
    # Shaft: the point disappears into the base, the body tapers very slightly up to the eye.
    p.append(T(f, "metal", 1.2, 2.3, 4.0, 14.0, verts=10, rnd=False))
    p.append(T(f, "metal", 2.3, 1.9, 14.0, 104.0, verts=10, rnd=False))
    for z in (14.0, 60.0):
        p.append(C(f, "metal", 2.45 - z * 0.003, 0.5, (0, 0, z), verts=10, rnd=False))
    # Eye: two flattened cheeks around a tall slot, closed by a rounded head.
    z0, z1 = 104.0, 116.5
    p.append(T(f, "metal", 1.9, 1.6, z0 - 0.01, z0 + 1.2, verts=10, rnd=False))
    for s in (-1, 1):
        p.append(B(f, "metal", (1.1, 2.6, z1 - z0 - 1.2), (s * 1.05, 0, (z0 + 1.2 + z1) / 2), along="z", rnd=False))
    p.append(B(f, "metal", (3.2, 2.6, 1.6), (0, 0, z1 + 0.6), rnd=False))
    p.append(T(f, "metal", 1.6, 0.6, z1 + 1.4, 120.0, verts=10, rnd=False))
    # Faint glow ring lining the eye (eye only).
    g = 0.15
    for s in (-1, 1):
        p.append(B(f, "glow", (g, 2.0, z1 - z0 - 1.4), (s * (0.5 - g / 2), 0, (z0 + 1.2 + z1 - 0.2) / 2), rnd=False))
    for z in (z0 + 1.2 + g / 2, z1 - 0.2 - g / 2):
        p.append(B(f, "glow", (1.0, 2.0, g), (0, 0, z), rnd=False))
    return palette(f, p, {})


RIG_FLIP = True  # builders face -y; turn to +y so the glTF faces -Z (MODEL_SPECS rules)

PROPS = {
    "pine_lodge": pine_lodge,
    "snow_cabin": snow_cabin,
    "haunted_barn": haunted_barn,
    "volcano_forge": volcano_forge,
    "buried_pyramid_garage": buried_pyramid_garage,
    "swamp_stilt_house": swamp_stilt_house,
    "the_spindle": the_spindle,
    "cave_entrance": cave_entrance,
    "zeppelin_dock": zeppelin_dock,
    "thimble_lighthouse": thimble_lighthouse,
    "bobbin_captain_shack": bobbin_captain_shack,
    "meadow_windmill": meadow_windmill,
    "longstitch_highway_sign": longstitch_highway_sign,
    "corn_maze_gate": corn_maze_gate,
    "straw_labyrinth_gate": straw_labyrinth_gate,
    "windmill": windmill,
    "spindle_landmark": spindle_landmark,
}

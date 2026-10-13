"""Quest gear for the V8 quest lines: reward tools, keys, quest items and markers.

Same house style as the other modules (LT2 block shapes, Rustic finish). Each prop sits on the
ground (z=0), centered on x=y=0, front facing -y. Sizes are given in studs (1 stud = 0.28 m).
Glow is only used on the alien, mythic and crop-circle pieces.

Run:
  python blender/props/rustic_props.py --out <dir> --category quest_gear
"""
import math
import os
import sys

import bpy  # noqa: F401  (must be imported before bmesh/mathutils with the pip bpy module)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, HERE)
import hay_bale  # noqa: E402
from style import box, cyl  # noqa: E402
from tools import arc_band, catmull, rod, tube  # noqa: E402

STUD = 0.28


def s(*v):
    return tuple(x * STUD for x in v)


def B(f, kind, size, loc, rot=(0, 0, 0), along="z", rounded=True):
    """Box in studs."""
    return f.apply(f.shape(box(s(*size), s(*loc), rot=rot), round_edges=rounded), kind, along=along)


def C(f, kind, r, depth, loc, axis="z", verts=10, rounded=False, rot=None):
    """Cylinder in studs along an axis."""
    rot = rot or {"x": (0, math.pi / 2, 0), "y": (math.pi / 2, 0, 0), "z": (0, 0, 0)}[axis]
    return f.apply(f.shape(cyl(r * STUD, depth * STUD, s(*loc), verts=verts, rot=rot), round_edges=rounded),
                   kind, along=axis)


def R(f, kind, p0, p1, r, sides=8, r1=None):
    """Rod between two points in studs."""
    return f.apply(f.shape(rod(s(*p0), s(*p1), r * STUD, sides=sides, r1=None if r1 is None else r1 * STUD),
                           round_edges=False), kind, along="z")


def ring(f, kind, center, r_in, r_out, depth, n=20, a0=0.0, a1=2 * math.pi):
    """Ring (or arc) in the xz plane, facing -y, in studs."""
    return f.apply(f.shape(arc_band(s(*center), r_in * STUD, r_out * STUD, a0, a1, n, depth * STUD),
                           round_edges=False), kind, along="x")


# ---------------------------------------------------------------- reward tools

def golden_shovel(f):
    """About 0.8 x 2.7 x 0.3 studs: the basic spade with a yellow-gold blade, a steel cutting edge,
    a gold collar band and a D grip."""
    parts = [C(f, "handle", 0.065, 1.72, (0, 0, 0.82 + 0.86), verts=6)]
    parts.append(B(f, "gold", (0.24, 0.24, 0.16), (0, 0, 1.38), rounded=False))      # gold band
    parts.append(C(f, "handle", 0.057, 0.43, (0, 0, 2.68), axis="x", verts=6))                # D grip
    for x in (-0.18, 0.18):
        parts.append(B(f, "handle", (0.07, 0.07, 0.22), (x, 0, 2.55)))
    parts.append(B(f, "steel", (0.2, 0.12, 0.22), (0, 0, 0.8)))                             # socket
    blade = box(s(0.62, 0.07, 0.62), s(0, 0, 0.42))
    for v in blade.data.vertices:
        if v.co.z < 0.42 * STUD:
            v.co.x *= 0.8
    parts.append(f.apply(f.shape(blade), "gold"))
    edge = box(s(0.52, 0.09, 0.1), s(0, 0, 0.13))
    for v in edge.data.vertices:
        if v.co.z < 0.13 * STUD:
            v.co.x *= 0.9
    parts.append(f.apply(f.shape(edge, round_edges=False), "steel", along="x"))
    for x in (-0.22, 0.22):                                                                 # rivets
        parts.append(C(f, "steel", 0.04, 0.1, (x, 0, 0.66), axis="y", verts=6))
    return parts


def thread_rake(f):
    """About 1.9 x 4.9 x 0.5 studs: the garden rake with a wooden head strung with stiff thread
    tines, a spool of twine mounted on the handle and loose thread wound up to it."""
    parts = [C(f, "handle", 0.065, 4.6, (0, 0, 0.22 + 2.3), verts=6)]
    parts.append(B(f, "handle", (1.8, 0.2, 0.2), (0, 0, 0.32), along="x"))                 # head
    for i in range(11):                                                                     # thread tines
        x = -0.78 + i * 0.156
        parts.append(B(f, "twine", (0.04, 0.04, 0.36), (x, 0, 0.16), rounded=False))
        parts.append(C(f, "paint_cream", 0.035, 0.04, (x, 0, 0.0 + 0.02), verts=6))       # waxed tips
    parts.append(B(f, "twine", (1.78, 0.06, 0.04), (0, -0.11, 0.24), rounded=False))      # binding thread
    # Spool on a short axle sticking out of the handle at about hand height.
    z = 2.3
    parts.append(C(f, "metal", 0.03, 0.4, (0, -0.2, z), axis="y", verts=6))
    parts.append(C(f, "twine", 0.2, 0.22, (0, -0.32, z), axis="y", verts=12))
    for y in (-0.2, -0.44):
        parts.append(C(f, "wood", 0.27, 0.04, (0, y, z), axis="y", verts=12))
    # Loose thread from the spool down to the head, wrapped round the handle twice.
    pts = [(0.0, -0.32, z - 0.2)]
    for k in range(10):
        a = k * 0.8
        pts.append((0.1 * math.cos(a), 0.1 * math.sin(a) - 0.02, z - 0.35 - k * 0.18))
    pts.append((0.3, -0.12, 0.36))
    parts.append(f.apply(tube([s(*p) for p in pts], 0.012 * STUD * 2, sides=4), "twine", along="z"))
    return parts


# ---------------------------------------------------------------- keys

def _corn_key(f, variant):
    """Iron key lying flat on the ground, about 1.2 studs long, with a corn-cob bow (husk leaves)
    on the -x end. variant 1..3 changes the bit teeth and the number of shaft bands."""
    parts = []
    t = 0.09                                                                              # iron thickness
    parts.append(B(f, "metal", (0.58, 0.09, t), (0.12, 0, t / 2), rounded=False))       # shaft
    parts.append(C(f, "paint_yellow", 0.13, 0.36, (-0.32, 0, 0.13), axis="x", verts=10))  # cob
    parts.append(C(f, "paint_yellow", 0.09, 0.08, (-0.53, 0, 0.13), axis="x", verts=10))  # cob tip
    for k in range(4):                                                                   # kernel rows
        parts.append(C(f, "dirt", 0.137, 0.02, (-0.44 + k * 0.08, 0, 0.13), axis="x", verts=10))
    for side in (-1, 1):                                                                 # husk leaves
        parts.append(B(f, "paint_green", (0.3, 0.16, 0.03), (-0.2, side * 0.12, 0.05),
                       rot=(side * 0.5, 0, side * -0.4), rounded=False))
    parts.append(C(f, "metal", 0.08, 0.1, (-0.1, 0, 0.1), axis="x", verts=8))             # collar
    for k in range(variant):                                                             # shaft bands
        parts.append(B(f, "steel", (0.03, 0.12, t + 0.03), (0.02 + k * 0.08, 0, t / 2), rounded=False))
    teeth = {1: ((0.5, 0.18),), 2: ((0.42, 0.14), (0.54, 0.2)), 3: ((0.36, 0.2), (0.46, 0.12), (0.56, 0.22))}
    for x, ln in teeth[variant]:                                                          # bit
        parts.append(B(f, "metal", (0.08, ln, t), (x, -0.045 - ln / 2, t / 2), rounded=False))
    return parts


def corn_maze_key_1(f):
    """1.2 x 0.3 x 0.5 studs (lying flat): corn-cob iron key, one tooth and one band."""
    return _corn_key(f, 1)


def corn_maze_key_2(f):
    """1.2 x 0.3 x 0.5 studs (lying flat): corn-cob iron key, two teeth and two bands."""
    return _corn_key(f, 2)


def corn_maze_key_3(f):
    """1.2 x 0.3 x 0.5 studs (lying flat): corn-cob iron key, three teeth and three bands."""
    return _corn_key(f, 3)


def barn_key(f):
    """1.4 x 0.2 x 0.6 studs (lying flat): big old iron barn key with a round ring bow, a collar,
    and a chunky two-step bit, tied to a twine tag loop."""
    t = 0.12
    parts = [B(f, "metal", (0.8, 0.12, t), (0.2, 0, t / 2), rounded=False)]                  # shaft
    bow = arc_band(s(0, 0, 0), 0.13 * STUD, 0.25 * STUD, 0, 2 * math.pi, 16, t * STUD)
    bow.rotation_euler = (math.pi / 2, 0, 0)
    bow.location = s(-0.4, 0, t / 2)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=False)
    parts.append(f.apply(f.shape(bow, round_edges=False), "metal", along="x"))
    for x in (-0.13, -0.08):                                                             # collar rings
        parts.append(C(f, "metal", 0.1, 0.03, (x, 0, t / 2), axis="x", verts=8))
    parts.append(B(f, "metal", (0.12, 0.26, t), (0.48, -0.17, t / 2), rounded=False))       # bit
    parts.append(B(f, "metal", (0.08, 0.14, t), (0.36, -0.11, t / 2), rounded=False))
    parts.append(B(f, "metal", (0.06, 0.12, t + 0.02), (0.6, 0, t / 2), rounded=False))     # tip
    loop = [(-0.5, 0, t * 0.5), (-0.62, 0.1, 0.03), (-0.7, 0.2, 0.03), (-0.62, 0.3, 0.03), (-0.5, 0.18, t * 0.5)]
    parts.append(f.apply(tube([s(*p) for p in catmull(loop, 3)], 0.02 * STUD, sides=5), "twine", along="x"))
    parts.append(B(f, "paint_cream", (0.18, 0.24, 0.02), (-0.7, 0.32, 0.01), rot=(0, 0, 0.4), rounded=False))
    return parts


# ---------------------------------------------------------------- bale

def golden_hay_bale(f):
    """Exactly the game bale (4.6 long x 2.6 high x 3.2 deep studs) in golden straw with twine bands."""
    hay_bale.BEVEL = max(f.bevel, 0.001)
    gold = f.apply(f.shape(hay_bale.build_hay(), round_edges=False), "paint_yellow")
    return [gold] + [f.apply(b, "twine") for b in hay_bale.build_twine()]


# ---------------------------------------------------------------- alien beacon

def beacon_part_1(f):
    """Antenna, about 1.0 x 2.0 x 1.0 studs: steel foot, mast with fins and a dish around a glowing tip."""
    parts = [C(f, "metal", 0.45, 0.16, (0, 0, 0.08), verts=8)]
    parts.append(C(f, "steel", 0.08, 1.4, (0, 0, 0.86), verts=8))
    for k in range(3):                                                                    # fins
        a = k * 2 * math.pi / 3
        parts.append(B(f, "steel", (0.36, 0.05, 0.5), (0.18 * math.cos(a), 0.18 * math.sin(a), 0.4),
                       rot=(0, 0, a), rounded=False))
    dish = arc_band(s(0, 0, 0), 0.12 * STUD, 0.48 * STUD, 0, 2 * math.pi, 14, 0.06 * STUD)
    dish.rotation_euler = (math.radians(-60), 0, 0)                                    # tipped up and forward
    dish.location = s(0, 0, 1.6)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=False)
    parts.append(f.apply(f.shape(dish, round_edges=False), "metal", along="x"))
    parts.append(C(f, "glow", 0.11, 0.3, (0, 0, 1.75), verts=8))
    parts.append(C(f, "glow", 0.05, 0.25, (0, -0.02, 1.98), verts=6))
    for z in (0.5, 0.95):                                                                 # light bands
        parts.append(C(f, "glow", 0.1, 0.05, (0, 0, z), verts=8))
    return parts


def beacon_part_2(f):
    """Power core, about 1.0 x 1.6 x 1.0 studs: glowing cylinder in a glass sleeve held by a
    steel cage with end caps."""
    parts = [C(f, "metal", 0.5, 0.2, (0, 0, 0.1), verts=8), C(f, "metal", 0.5, 0.2, (0, 0, 1.4), verts=8)]
    parts.append(C(f, "glow", 0.22, 1.1, (0, 0, 0.75), verts=10))
    parts.append(C(f, "glass", 0.32, 1.1, (0, 0, 0.75), verts=10))
    for k in range(4):                                                                    # cage bars
        a = math.pi / 4 + k * math.pi / 2
        parts.append(B(f, "steel", (0.08, 0.08, 1.12), (0.4 * math.cos(a), 0.4 * math.sin(a), 0.75), rounded=False))
    parts.append(C(f, "steel", 0.16, 0.12, (0, 0, 1.56), verts=8))                        # top plug
    parts.append(C(f, "glow", 0.08, 0.04, (0, 0, 1.63), verts=8))
    return parts


def beacon_part_3(f):
    """Base plate, about 1.8 x 0.9 x 1.8 studs: octagonal steel plate with three landing legs and a
    glowing ring socket on top."""
    parts = [C(f, "steel", 0.8, 0.18, (0, 0, 0.44), verts=8)]
    parts.append(C(f, "metal", 0.6, 0.12, (0, 0, 0.59), verts=8))
    parts.append(f.apply(f.shape(arc_band(s(0, 0, 0), 0.24 * STUD, 0.36 * STUD, 0, 2 * math.pi, 16, 0.1 * STUD),
                                 round_edges=False), "glow", along="x"))
    parts[-1].rotation_euler = (math.pi / 2, 0, 0)
    parts[-1].location = s(0, 0, 0.68)
    bpy.ops.object.select_all(action="DESELECT")
    parts[-1].select_set(True)
    bpy.context.view_layer.objects.active = parts[-1]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=False)
    parts.append(C(f, "tire", 0.22, 0.06, (0, 0, 0.67), verts=10))                        # socket hole
    for k in range(3):                                                                    # legs and feet
        a = k * 2 * math.pi / 3 - math.pi / 2
        x, y = math.cos(a), math.sin(a)
        parts.append(R(f, "metal", (0.55 * x, 0.55 * y, 0.4), (0.8 * x, 0.8 * y, 0.06), 0.06))
        parts.append(C(f, "steel", 0.14, 0.08, (0.82 * x, 0.82 * y, 0.04), verts=8))
        parts.append(B(f, "glow", (0.1, 0.06, 0.06), (0.8 * x, 0.8 * y, 0.44), rot=(0, 0, a + math.pi / 2), rounded=False))
    return parts


# ---------------------------------------------------------------- mythic bits

def master_needle_shard(f):
    """About 0.9 x 1.5 x 0.7 studs: a broken glowing crystal needle fragment with a steel eye slot,
    a dark glass collar at the break, leaning in a little heap of stone with two glowing splinters."""
    parts = [R(f, "glow", (0, 0, 0.1), (0.15, -0.05, 1.5), 0.17, sides=6, r1=0.05)]
    parts.append(R(f, "glass", (0, 0, 0.05), (0.02, -0.01, 0.35), 0.22, sides=6, r1=0.2))      # jagged collar
    for k in range(3):                                                                    # crystal spikes
        a = k * 2 * math.pi / 3
        parts.append(R(f, "glass", (0.15 * math.cos(a), 0.15 * math.sin(a), 0.3),
                       (0.24 * math.cos(a), 0.24 * math.sin(a), 0.52), 0.06, sides=5, r1=0.01))
    parts.append(R(f, "glow", (0.25, 0.15, 0.05), (0.45, 0.2, 0.55), 0.07, sides=6, r1=0.02))
    parts.append(R(f, "glow", (-0.2, 0.1, 0.05), (-0.42, 0.02, 0.45), 0.06, sides=6, r1=0.015))
    parts.append(B(f, "steel", (0.14, 0.2, 0.26), (0.12, -0.04, 1.18), rot=(0, -0.1, 0), rounded=False))  # eye
    parts.append(B(f, "tire", (0.06, 0.24, 0.16), (0.12, -0.04, 1.18), rot=(0, -0.1, 0), rounded=False))
    for x, y, r in ((0.0, 0.0, 0.3), (-0.25, -0.2, 0.18), (0.28, -0.15, 0.16)):            # stones
        parts.append(C(f, "stone", r, 0.16, (x, y, 0.08), verts=7, rounded=True))
    return parts


def frozen_bobbin(f):
    """About 0.9 x 1.2 x 0.9 studs: steel bobbin wound with ice-blue thread, a glass ice
    chunk frozen to one side and icicles hanging from the top flange."""
    parts = [C(f, "steel", 0.45, 0.1, (0, 0, 0.05), verts=12), C(f, "steel", 0.45, 0.1, (0, 0, 1.12), verts=12)]
    parts.append(C(f, "metal", 0.12, 1.2, (0, 0, 0.6), verts=8))
    parts.append(C(f, "paint_blue", 0.33, 0.92, (0, 0, 0.58), verts=12))
    for z in (0.3, 0.6, 0.9):                                                             # thread layers
        parts.append(C(f, "paint_cream", 0.335, 0.03, (0, 0, z), verts=12))
    ice = box(s(0.3, 0.16, 0.42), s(0.26, -0.3, 0.36), rot=(0.1, 0.0, 0.5))      # ice chunk
    parts.append(f.apply(f.shape(ice), "glass"))
    for x, ln in ((-0.3, 0.3), (-0.1, 0.22), (0.12, 0.34), (0.32, 0.2)):                    # icicles
        parts.append(R(f, "glass", (x, -0.38, 1.07), (x, -0.4, 1.07 - ln), 0.05, sides=5, r1=0.005))
    parts.append(C(f, "metal", 0.07, 0.06, (0, 0, 1.2), verts=8))
    return parts


def captains_log(f):
    """1.0 x 0.3 x 1.4 studs (lying flat): closed leather ship's log, cream page edges, steel corner
    caps, a twine strap with a buckle and a red ribbon bookmark."""
    parts = [B(f, "leather", (1.0, 1.4, 0.07), (0, 0, 0.035))]                              # back cover
    parts.append(B(f, "leather", (1.0, 1.4, 0.07), (0, 0, 0.265)))                         # front cover
    parts.append(B(f, "paint_cream", (0.92, 1.34, 0.17), (0.03, 0, 0.15), rounded=False))  # pages
    parts.append(B(f, "leather", (0.1, 1.4, 0.3), (-0.47, 0, 0.15)))                       # spine
    for x, y in ((0.42, 0.62), (0.42, -0.62)):                                            # corner caps
        parts.append(B(f, "steel", (0.18, 0.18, 0.32), (x + 0.03, y + 0.03 * (1 if y > 0 else -1), 0.15),
                       rounded=False))
    parts.append(B(f, "twine", (1.1, 0.12, 0.32), (0.0, 0, 0.15), rounded=False))           # strap
    parts.append(B(f, "metal", (0.06, 0.18, 0.34), (0.52, 0, 0.15), rounded=False))        # buckle
    parts.append(B(f, "paint_red", (0.08, 0.3, 0.02), (-0.2, -0.82, 0.15), rot=(0.4, 0, 0), rounded=False))
    for y in (-0.35, 0.35):                                                                # spine ribs
        parts.append(B(f, "leather", (0.14, 0.06, 0.32), (-0.47, y, 0.15), rounded=False))
    parts.append(B(f, "dirt", (0.4, 0.3, 0.01), (0.12, 0.3, 0.305), rounded=False))        # title label
    return parts


def tailor_journal_page(f):
    """About 1.2 x 1.6 x 0.4 studs: a parchment journal page (cloth) pinned with a red-headed
    pin to a small standing board, with ink lines and a glove sketch."""
    lean = (math.radians(-12), 0, 0)
    def onboard(z, y=0.0):
        a = lean[0]
        return (0, 0.06 + y + z * -math.sin(a) * -1, z * math.cos(a))
    parts = []
    board = box(s(1.2, 0.1, 1.5), s(0, 0, 0.75), rot=lean)
    parts.append(f.apply(f.shape(board), "handle", along="z"))
    parts.append(B(f, "handle", (0.12, 0.6, 0.12), (0, 0.22, 0.06), rounded=False))        # foot
    page = box(s(0.9, 0.03, 1.2), s(0.04, -0.07, 0.82), rot=(lean[0], 0.06, 0))
    parts.append(f.apply(f.shape(page), "cloth", along="z"))
    for k in range(6):                                                                    # ink lines
        z = 1.2 - k * 0.12
        w = 0.65 if k % 3 else 0.42
        y = -0.09 - z * math.tan(-lean[0]) + 0.82 * math.tan(-lean[0])
        parts.append(B(f, "tire", (w, 0.01, 0.03), (0.04 + (0.65 - w) / -2 + 0.02, y, z),
                       rot=(lean[0], 0.06, 0), rounded=False))
    y = -0.09 - 0.45 * math.tan(-lean[0]) + 0.82 * math.tan(-lean[0])
    parts.append(B(f, "dirt", (0.24, 0.01, 0.2), (0.22, y, 0.45), rot=(lean[0], 0.06, 0), rounded=False))  # sketch
    yp = -0.12 - 1.3 * math.tan(-lean[0]) + 0.82 * math.tan(-lean[0])
    parts.append(R(f, "steel", (0.04, yp - 0.12, 1.3), (0.04, yp + 0.1, 1.3 + 0.02), 0.015, sides=4))
    parts.append(C(f, "paint_red", 0.06, 0.06, (0.04, yp - 0.14, 1.3), axis="y", verts=8))
    return parts


def crop_circle_marker(f):
    """About 1.3 x 3.0 x 0.4 studs: weathered wooden stake driven into the ground, a round board
    sign at the top framed by a glowing ring, with a glowing crop-circle mark on it."""
    parts = [B(f, "handle", (0.22, 0.22, 2.2), (0, 0, 1.1))]
    parts.append(B(f, "dirt", (0.5, 0.5, 0.08), (0, 0, 0.04), rounded=False))              # dirt mound
    parts.append(C(f, "wood", 0.55, 0.14, (0, -0.16, 2.4), axis="y", verts=16))             # round sign
    parts.append(ring(f, "glow", (0, -0.24, 2.4), 0.55, 0.64, 0.08, n=24))                   # glowing frame
    parts.append(ring(f, "glow", (0, -0.25, 2.4), 0.18, 0.24, 0.04, n=16))                   # mark: circle
    for k in range(3):                                                                     # mark: spokes
        a = k * 2 * math.pi / 3 + math.pi / 2
        x, z = 0.36 * math.cos(a), 0.36 * math.sin(a)
        parts.append(C(f, "glow", 0.07, 0.04, (x, -0.25, 2.4 + z), axis="y", verts=8))
    parts.append(B(f, "metal", (0.3, 0.08, 0.1), (0, -0.06, 2.05), rounded=False))           # bracket
    parts.append(B(f, "twine", (0.26, 0.26, 0.08), (0, 0, 1.6), rounded=False))              # lashing
    return parts


PROPS = {
    "golden_shovel": golden_shovel,
    "thread_rake": thread_rake,
    "corn_maze_key_1": corn_maze_key_1,
    "corn_maze_key_2": corn_maze_key_2,
    "corn_maze_key_3": corn_maze_key_3,
    "barn_key": barn_key,
    "golden_hay_bale": golden_hay_bale,
    "beacon_part_1": beacon_part_1,
    "beacon_part_2": beacon_part_2,
    "beacon_part_3": beacon_part_3,
    "master_needle_shard": master_needle_shard,
    "frozen_bobbin": frozen_bobbin,
    "captains_log": captains_log,
    "tailor_journal_page": tailor_journal_page,
    "crop_circle_marker": crop_circle_marker,
}

"""Design mockups for the part-built world pieces in #16: the free Hay Wagon (HayWagon.luau), the ferry snack
stand (Ferry.luau), the Spindle door with its twelve shard sockets (Regions LANDMARKS.spindle), the Master Needle
pedestal in the Loom Room (SpindleDoor.luau), and the Straw Labyrinth start arch and finish bell (Quests
LOOKS.labyrinth). Sizes are the game's; each piece is built in game axes (X, Y up, Z) and turned for the sheet.

Run:
  python blender/mockups/landmarks_sheet.py [out_folder]
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
CREAM = mock.mat("cream_text", rgb(236, 226, 204), 0.8)
GOLD = mock.mat("shard_gold", rgb(242, 183, 5), 0.3, emit=3.0)
DIM_GOLD = mock.mat("socket_empty", rgb(120, 96, 40), 0.5, 0.6)
BRASS = mock.mat("brass", rgb(200, 160, 70), 0.35, 0.8)
SPINDLE = mock.rustic_finish(name="spindle", stone=((0.66, 0.62, 0.70), (0.59, 0.56, 0.63), (0.45, 0.42, 0.50)),
                             steel=((0.44, 0.40, 0.54), (0.38, 0.34, 0.47), (0.27, 0.24, 0.34)))
ROOT = None
UP = (math.pi / 2, 0, 0)


def g(x, y, z):
    """Game (X, Y up, Z) -> Blender location."""
    return (x, -z, y)


def own(o):
    o.parent = ROOT
    return o


def finish(o, kind, f, along):
    if isinstance(kind, str):
        return own(mock.finish_part(o, kind, f, along, studs=True))
    o.data.materials.clear()
    o.data.materials.append(kind)
    return own(o)


def P(kind, size, pos, rot=(0, 0, 0), along="x", f=F):
    """A game part: size (X, Y, Z) at game position pos, rot in Blender radians."""
    return finish(mock.box("p", size, g(*pos), BLANK, rot), kind, f, along)


def Cyl(kind, r, length, pos, axis="x", verts=16, f=F):
    rot = {"x": (0, math.pi / 2, 0), "y": (0, 0, 0), "z": UP}[axis]
    return finish(mock.cylinder("c", r, length, g(*pos), BLANK, verts=verts, rot=rot), kind, f, "xyz"[["x", "z", "y"].index(axis)])


def text(t, pos, size, mat=CREAM, rot_y=0.0):
    o = mock.label(t, g(*pos), size, mat, rot=(math.pi / 2, 0, rot_y))
    return own(o)


def start(name, x, turn):
    global ROOT
    ROOT = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(ROOT)
    ROOT.location = (x, 0, 0)
    ROOT.rotation_euler = (0, 0, turn)


# ---------------------------------------------------------------- the free Hay Wagon (faces -Z in game)
def hay_wagon():
    P("handle", (8, 0.8, 14), (0, 2.4, 2), along="y")
    for side in (-1, 1):
        P("handle", (0.4, 1.4, 14), (side * 3.9, 3.5, 2), along="y")
        for z in (-3, 7):
            Cyl("handle", 1.6, 0.6, (side * 4.3, 1.6, z), "x", verts=16)  # Wheel_*: wooden wheel
            bpy.ops.mesh.primitive_torus_add(major_radius=1.55, minor_radius=0.13, location=g(side * 4.45, 1.6, z),
                                             rotation=(0, math.pi / 2, 0), major_segments=20, minor_segments=6)
            finish(bpy.context.active_object, "metal", F, "x")  # iron tire
            for k in range(4):
                P("handle", (0.2, 2.9, 0.25), (side * 4.62, 1.6, z), rot=(k * math.pi / 4, 0, 0))  # spokes
            Cyl("metal", 0.4, 0.8, (side * 4.4, 1.6, z), "x", verts=8)
    P("hay", (2.4, 1.6, 12), (0, 3.6, 2), along="y")
    for i in range(6):
        side = -1 if i % 2 == 0 else 1
        z = -2 + (i // 2) * 4
        P("handle", (2, 0.4, 2), (side * 2.5, 2.95, z))  # bench
        P("paint_red", (1.8, 0.25, 1.8), (side * 2.5, 3.25, z))  # cushion (the Seat)
        P("handle", (0.3, 1.2, 2), (side * 1.55, 3.6, z))  # backrest against the hay
    P("metal", (0.4, 0.4, 3), (0, 1.8, -6.5))  # drawbar
    # Tractor.
    t = -9
    P("paint_green", (4, 3, 6), (0, 3, t))
    P("paint_green", (3, 2, 3), (0, 3.5, t - 3.5))
    P("metal", (3.1, 1.2, 0.3), (0, 3.2, t - 5.05))  # grille
    Cyl("metal", 0.25, 3, (1, 6, t - 3), "y", verts=8)  # stack
    P("handle", (3.4, 0.4, 2.2), (0, 4.7, t + 1.5))  # seat pan
    for side in (-1, 1):
        Cyl("tire", 2.2, 1.2, (side * 2.6, 2.2, t + 1.5), "x", verts=20)
        Cyl("paint_cream", 1.0, 1.3, (side * 2.6, 2.2, t + 1.5), "x", verts=12)
        Cyl("tire", 1.2, 0.8, (side * 1.8, 1.2, t - 3.5), "x", verts=16)
        P("paint_green", (1.4, 0.3, 2.6), (side * 2.6, 4.5, t + 1.5))  # fenders
    P("cloth", (1.6, 2.6, 1), (0, 5.6, t + 1.5))  # driver
    Cyl("hay", 1.1, 0.25, (0, 7.2, t + 1.5), "y", verts=16)  # straw hat brim
    Cyl("hay", 0.6, 0.6, (0, 7.55, t + 1.5), "y", verts=12)
    P("paint_cream", (6, 1.4, 0.3), (0, 5.2, 9.2))  # WagonBoard
    for x in (-2.6, 2.6):
        P("handle", (0.3, 2.6, 0.3), (x, 4.5, 9.2))
    text("HAY RIDES  ·  FREE", (0, 5.0, 9.4), 0.62, INK)
    return "hay_wagon", "bed 8 x 14, 6 seats, tractor in front", "wheels and tractor wheels are their own meshes"


# ---------------------------------------------------------------- ferry snack stand (counter faces +X)
def snack_stand():
    P("handle", (7, 0.4, 12), (0, 0.2, 0))  # promenade planks under it
    P("paint_cream", (3, 3.2, 8), (-1.5, 2, 0))  # SnackCounter
    P("handle", (3.4, 0.25, 8.4), (-1.4, 3.7, 0))  # counter top
    for k in range(-3, 4):
        P("handle", (0.08, 3.0, 0.15), (0.02, 2, k * 1.1))  # board lines on the front
    # Striped awning, tipped 12 degrees down toward the customers.
    tilt = (0, -math.radians(12), 0)
    for k in range(9):
        P("paint_red" if k % 2 == 0 else "paint_cream", (5, 0.3, 1.0), (-1, 6.2, -4 + k), rot=tilt)
    for k in range(9):
        P("paint_red" if k % 2 == 0 else "paint_cream", (0.08, 0.7, 1.0), (1.45, 5.35, -4 + k))  # valance
    for z in (-4, 4):
        P("handle", (0.3, 4.4, 0.3), (1.2, 4, z), along="z")  # SnackPole
    P("handle", (0.4, 6.4, 0.4), (-2.9, 3.2, -3.8), along="z")  # back posts
    P("handle", (0.4, 6.4, 0.4), (-2.9, 3.2, 3.8), along="z")
    P("paint_yellow", (0.2, 1.2, 5), (0.1, 4.5, 0))  # SnackSign
    text("SNACKS  $15", (0.25, 4.5, 0), 0.62, INK, rot_y=math.pi / 2)
    # Goods on the counter: pretzel jar, chowder pot, toffee apples, cocoa mugs.
    Cyl("glass", 0.45, 1.0, (-1.2, 4.3, -2.6), "y", verts=12)
    Cyl("hay", 0.3, 0.12, (-1.2, 4.15, -2.6), "y", verts=10)
    Cyl("metal", 0.55, 0.8, (-1.4, 4.2, -0.6), "y", verts=14)
    for k in range(3):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=0.22, location=g(-1.0, 4.05, 1.2 + k * 0.5))
        finish(bpy.context.active_object, "paint_red", F, "x")
        Cyl("handle", 0.04, 0.4, (-1.0, 4.4, 1.2 + k * 0.5), "y", verts=6)
    for k in range(2):
        Cyl("paint_cream", 0.2, 0.35, (-1.1, 4.0, 2.9 + k * 0.5), "y", verts=10)
    P("handle", (0.2, 2.4, 1.8), (-2.85, 5.2, 0))  # menu board behind
    P("tire", (0.1, 2.0, 1.5), (-2.72, 5.2, 0))
    return "ferry_snack_stand", "counter 3 x 3.2 x 8, awning 5 x 9", "red and cream awning; sign is the click target"


# ---------------------------------------------------------------- the Spindle door (sockets face -Z)
def spindle_door():
    f = SPINDLE
    # Door frame 20 x 26 x 4, built as dressed stone blocks with a pointed head.
    for side in (-1, 1):
        for k in range(6):
            P("stone", (3, 3.3, 4), (side * 8.5, 1.65 + k * 3.4, 2.5), f=f)
    for k in range(7):  # a shallow arch springing from the post tops, keystone in the middle
        a = math.radians(-90 + k * 30)
        P("stone", (3.6, 2.8, 4.2 if k == 3 else 4), (math.sin(a) * 8.5, 20.4 + math.cos(a) * 4.6, 2.5),
          rot=(0, a * 0.55, 0), f=f)
    P("stone", (15, 5, 3.6), (0, 22.4, 2.7), f=f)  # tympanum filling the arch over the door
    P("stone", (20, 1, 4.6), (0, 0.5, 2.5), f=f)  # threshold
    P("steel", (14, 20, 1), (0, 10, 0.2), f=f)  # SpindleDoor
    for x in (-3.5, 3.5):
        P("steel", (0.5, 20, 1.3), (x, 10, 0.1), f=f)  # iron straps
    # Carved needle eye down the middle, and the ring of twelve sockets around it.
    bpy.ops.mesh.primitive_torus_add(major_radius=1.4, minor_radius=0.22, location=g(0, 13.5, -0.35), rotation=UP)
    finish(bpy.context.active_object, BRASS, f, "x")
    P(BRASS, (0.5, 7, 0.3), (0, 8.4, -0.35))
    lit = {0, 1, 2, 4, 5, 7, 9}
    for i in range(12):
        a = i / 12 * math.pi * 2
        x, y = math.cos(a) * 5, math.sin(a) * 5 + 12
        Cyl("metal", 0.55, 0.5, (x, y, -0.45), "z", verts=12)  # iron cup
        if i in lit:
            P(GOLD, (0.3, 1.2, 0.3), (x, y, -0.9), rot=(0, a, 0))  # the shard standing in it
        else:
            Cyl(DIM_GOLD, 0.38, 0.55, (x, y, -0.5), "z", verts=12)
    return "spindle_door", "frame 20 x 26 x 4, door 14 x 20", "12 shard sockets on a 5-stud ring (7 shown lit)"


# ---------------------------------------------------------------- Master Needle pedestal (Loom Room, 4 x 4 x 4)
def pedestal():
    f = SPINDLE
    P("stone", (5, 0.6, 5), (0, 0.3, 0), f=f)
    P("stone", (4, 2.8, 4), (0, 2.0, 0), f=f)
    P("stone", (4.6, 0.6, 4.6), (0, 3.7, 0), f=f)
    for side in (-1, 1):
        P(BRASS, (4.05, 0.25, 0.1), (0, 2.6, side * 2.02))
        P(BRASS, (0.1, 0.25, 4.05), (side * 2.02, 2.6, 0))
    # Empty cradle: two iron forks the Master Needle will lie in, and a gold thread groove.
    for x in (-1.3, 1.3):
        P("metal", (0.3, 1.2, 0.3), (x, 4.6, 0))
        P("metal", (0.3, 0.6, 0.15), (x, 5.3, -0.25), rot=(0.4, 0, 0))
        P("metal", (0.3, 0.6, 0.15), (x, 5.3, 0.25), rot=(-0.4, 0, 0))
    bpy.ops.mesh.primitive_torus_add(major_radius=1.7, minor_radius=0.06, location=g(0, 4.02, 0))
    finish(bpy.context.active_object, GOLD, f, "x")
    # A loom-room lamp on each side, as SpindleDoor.luau lights the room.
    for side in (-1, 1):
        P(GOLD, (0.8, 0.8, 0.8), (side * 4.5, 3, 0))
        P("stone", (0.6, 3, 0.6), (side * 4.5, 1.2, 0), f=f)
    return "master_needle_pedestal", "4 x 4 x 4 (Loom Room)", "empty iron cradle; the Master Needle lands here"


# ---------------------------------------------------------------- Straw Labyrinth start arch and finish bell
def labyrinth():
    cell, wall, h = 8, 1.6, 10
    straw = mock.rustic_finish(name="labstraw", hay=((0.84, 0.74, 0.47), (0.77, 0.67, 0.40), (0.60, 0.50, 0.30)))
    # Entrance: a stub of straw wall either side and the arch over the gap.
    for side in (-1, 1):
        P("hay", (6, h, wall), (side * (cell / 2 + 3 - wall / 2 + 0.8), h / 2, 0), f=straw)
        for k in range(3):
            P("twine", (6.05, 0.2, wall + 0.05), (side * (cell / 2 + 3 - wall / 2 + 0.8), 2 + k * 3, 0), f=straw)
        P("bark", (0.9, 12.5, 0.9), (side * 5.5, 6.25, -1), along="z")  # arch posts at the lantern spots
        P("metal", (0.2, 0.2, 1.2), (side * 5.5, 11, -1.7))
        P("metal", (1, 1.3, 1), (side * 5.5, 10.2, -2.2))  # hanging lantern
        P(mock.mat("lantern_glow", rgb(255, 200, 120), 0.4, emit=2.5), (0.6, 0.8, 0.6), (side * 5.5, 10.2, -2.2))
    # Lintel: a long straw bundle bound with twine, with the name board under it.
    Cyl("hay", 0.9, 12.6, (0, 12.4, -1), "x", verts=12, f=straw)
    for k in range(-2, 3):
        Cyl("twine", 0.95, 0.25, (k * 2.6, 12.4, -1), "x", verts=12, f=straw)
    P("paint_red", (8, 1.6, 0.3), (0, 10.7, -1.6))
    text("STRAW LABYRINTH", (0, 10.7, -1.8), 0.78, CREAM, rot_y=math.pi)
    P("paint_cream", (cell - wall, 0.1, 1), (0, 0.05, -1.5))  # StartLine
    # The finish bell, shown beside the arch: 6 x 6 hay floor, post, iron bracket, brass bell and a rope.
    bx, bz = -13, -4
    P("hay", (6, 0.2, 6), (bx, 0.1, bz), f=straw)
    P("bark", (0.5, 7, 0.5), (bx, 3.5, bz), along="z")  # BellPost
    P("metal", (0.25, 0.25, 1.3), (bx, 7.0, bz - 0.55))
    bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=0.75, radius2=0.35, depth=1.3, location=g(bx, 6.35, bz - 1.1))
    finish(bpy.context.active_object, BRASS, F, "x")  # Bell
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=5, radius=0.18, location=g(bx, 5.65, bz - 1.1))
    finish(bpy.context.active_object, "metal", F, "x")
    Cyl("twine", 0.06, 3.6, (bx, 3.9, bz - 1.1), "y", verts=6)
    return "labyrinth_arch + labyrinth_bell", "arch 11 wide x 13 tall, bell post 7", "arch on the entrance lantern posts; bell at the heart"


PIECES = [  # builder, x on the sheet, turn so its front faces the camera
    (hay_wagon, -62, -math.pi / 2),
    (snack_stand, -34, -math.pi / 2),
    (spindle_door, -8, math.pi),
    (pedestal, 15, 0.0),
    (labyrinth, 34, math.pi),
]
for build, x, turn in PIECES:
    start(build.__name__, x, turn)
    key, size, note = build()
    lx = x + (6 if build is labyrinth else 0)
    mock.label(key, (lx, -17, 0.05), 1.25, INK)
    mock.label(size, (lx, -19, 0.05), 0.75, SUB)
    mock.label(note, (lx, -20.6, 0.05), 0.6, SUB)
mock.label("PART-BUILT PIECES IN #16  ·  Rustic block-outs", (-12, -24.5, 0.05), 1.9, INK)

mock.box("ground", (260, 0.6, 140), (-10, 25, -0.3), mock.mat("ground", rgb(150, 132, 104), 0.95))
mock.scene_setup(world_color=(0.78, 0.82, 0.86), res=(2800, 1200), samples=48)
mock.sun(rotation=(0.75, 0.2, -0.5), energy=3.6)
mock.camera((-12, -150, 42), look_at=(-12, -6, 8), lens=40)
mock.render(mock.out_path("part_built_sheet.png"))

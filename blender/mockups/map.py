"""Top-down map of the base camp in the house style (LT2 shapes, Rustic finish),
built from the positions and colors in src/server/Services/World.luau:
spawn, bale spots, bale drop-off, hay shop and sell pad.

Run:
  python blender/mockups/map.py [out_folder]
  blender --background --python blender/mockups/map.py -- [out_folder]
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mock  # noqa: E402
from mock import rbx, rgb  # noqa: E402

bpy.ops.wm.read_factory_settings(use_empty=True)
F = mock.rustic_finish()

# Colors from World.luau (rustic palette).
GRASS = mock.mat("grass", rgb(112, 128, 82), 1.0)
GRASS_DARK = mock.mat("grass_dark", rgb(96, 112, 70), 1.0)
PATH = mock.mat("path", rgb(150, 132, 100), 1.0)
SPAWN = mock.mat("spawn", rgb(189, 168, 112), 0.8)
SPAWN_RING = mock.mat("spawn_ring", rgb(230, 222, 200), 0.8)
ROOF = mock.mat("roof", rgb(102, 66, 42), 0.9)
ROOF_DARK = mock.mat("roof_dark", rgb(80, 50, 32), 0.9)
SELL = mock.mat("sell", rgb(219, 204, 153), 0.6, emit=0.1)
HAY = [mock.mat(f"hay{i}", rgb(*c), 0.9) for i, c in enumerate(
    [(219, 204, 153), (189, 168, 112), (168, 149, 95), (133, 115, 71)])]  # Hay.luau loose pieces
INK = mock.mat("ink", rgb(40, 34, 28), 0.9)
ARROW = mock.mat("arrow", rgb(150, 60, 40), 0.7)

# Ground with a few darker grass patches.
mock.box("ground", (120, 1, 100), rbx(3, -3, -0.5), GRASS)
rng = random.Random(3)
for i in range(30):
    x, z = rng.uniform(-40, 46), rng.uniform(-40, 34)
    o = mock.cylinder(f"patch{i}", rng.uniform(1.5, 4), 0.05, rbx(x, z, 0.01 + i * 0.002), GRASS_DARK, verts=10)
    o.scale = (1, rng.uniform(0.5, 1), 1)

# A few LT2-style trees at the edges: bark trunk and a blocky crown.
LEAF = mock.mat("leaf", rgb(74, 98, 56), 0.9)
LEAF_DARK = mock.mat("leaf_dark", rgb(60, 82, 46), 0.9)
for i, (x, z) in enumerate([(-29, 0), (-29, 12), (35, 6), (35, 18), (14, 25), (-14, 26)]):
    trunk = mock.cylinder(f"trunk{i}", 0.9, 8, rbx(x, z, 4), mock.mat("tmp", (1, 1, 1)), verts=10)
    mock.finish_part(trunk, "bark", F, along="z")
    s = rng.uniform(4.0, 5.0)
    mock.box(f"crown{i}", (s, s * 0.8, s), rbx(x, z, 7.5), LEAF if i % 2 else LEAF_DARK,
             rot=(0, 0, rng.uniform(0, 1.5)))


def path(a, b, width=3.0, lift=0.0):
    (x0, z0), (x1, z1) = a, b
    dx, dz = x1 - x0, z1 - z0
    length = math.hypot(dx, dz)
    o = mock.box("path", (length + width, 0.06, width), rbx((x0 + x1) / 2, (z0 + z1) / 2, 0.03 + lift), PATH)
    o.rotation_euler = (0, 0, math.atan2(-dz, dx))


path((0, 14), (0, -4))
path((0, -4), (-11, -18), lift=0.01)
path((0, -4), (22, -6), lift=0.02)

# Spawn (8x8 at 0, 14).
mock.box("spawn", (8, 1, 8), rbx(0, 14, 0.5), SPAWN)
mock.cylinder("spawn_ring", 2.6, 1.05, rbx(0, 14, 0.5), SPAWN_RING, verts=24)
mock.cylinder("spawn_ring_in", 2.1, 1.1, rbx(0, 14, 0.5), SPAWN, verts=24)

# Three bale spots in a row at z = -18 (Bales.spawn). One bale each, refilled over time.
for i in range(3):
    mock.bale(rbx(-18 + i * 7, -18, 0), 0.1 * (i - 1), F)

# Bale drop-off (14 x 10 at 0, -4): set-down bales stack here.
mock.finish_part(mock.box("dropoff", (14, 0.2, 10), rbx(0, -4, 0.1), mock.mat("tmp", (1, 1, 1))), "handle", F)
mock.bale_stack(4, 6.5, 0.2, F, layers=2)
for i in range(18):  # loose hay pieces from a smashed bale
    x, z = rng.uniform(-6, -1), rng.uniform(-8, 0)
    o = mock.box(f"piece{i}", (rng.uniform(0.9, 1.5), 0.3, 0.3), rbx(x, z, 0.35), HAY[i % 4])
    o.rotation_euler[2] = rng.uniform(0, math.pi)

# Hay shop (floor 16x12 at 22, -18), plank walls, cutaway roof so the counter reads.
plank = lambda o: mock.finish_part(o, "handle", F)  # noqa: E731
blank = mock.mat("tmp", (1, 1, 1))
plank(mock.box("shop_floor", (16, 1, 12), rbx(22, -18, 0.5), blank))
plank(mock.box("back_wall", (16, 9, 1), rbx(22, -23.5, 5.5), blank))
plank(mock.box("left_wall", (1, 9, 12), rbx(14.5, -18, 5.5), blank))
plank(mock.box("right_wall", (1, 9, 12), rbx(29.5, -18, 5.5), blank))
mock.box("roof_back", (18, 1, 7), rbx(22, -21.5, 10.5), ROOF)
for k in range(5):
    mock.box("roof_line", (18, 1.05, 0.2), rbx(22, -24.5 + k * 1.5, 10.5), ROOF_DARK)
plank(mock.box("counter", (10, 4, 2), rbx(22, -14, 3), blank))
mock.bale(rbx(17, -20.5, 1), 0.0, F)  # stock on the shop floor
mock.bale(rbx(17, -20.5, 3), 0.15, F)

# Sell pad (12 x 9 at 22, -6).
mock.box("sell", (12, 0.4, 9), rbx(22, -6, 0.2), SELL)


def tag(text, x, z, size=1.6, mat=INK):
    mock.label(text, rbx(x, z, 13), size, mat)


tag("SPAWN", 0, 20)
tag("HAY BALES", -11, -23.5)
tag("lift a bale with bare hands,", -24, -12.5, 0.9)
tag("or shovel it to smash and scoop", -24, -11.2, 0.9)
tag("BALE DROP-OFF", 0, 3.0)
tag("set bales down and stack them", 0, 4.6, 0.9)
tag("HAY SHOP", 22, -21.5, 1.8, mock.mat("cream", rgb(236, 226, 200), 0.9))
tag("SELL HERE", 22, -6, 1.6)
tag("walk on with hay, or set a bale down", 22, -0.5, 0.9)
tag("NEEDLEWOOD  BASE CAMP", 3, -28, 2.4)


def arrow(x, z, angle):
    bpy.ops.mesh.primitive_cone_add(vertices=3, radius1=1.1, depth=0.1, location=rbx(x, z, 12))
    o = bpy.context.active_object
    o.rotation_euler = (0, 0, angle)
    o.scale = (0.75, 1.5, 1)
    o.data.materials.append(ARROW)


arrow(0, 9, 0.0)            # spawn -> drop-off
arrow(-6, -11.5, -2.476)    # bales -> drop-off
arrow(11, -5, -1.48)        # drop-off -> sell pad

mock.box("scale", (10, 0.1, 0.4), rbx(-26, 21, 12), INK)
tag("10 studs", -26, 22.6, 0.9)
tag("N", 34, -26, 1.6)
bpy.ops.mesh.primitive_cone_add(vertices=3, radius1=0.9, depth=0.1, location=rbx(34, -24, 12))
bpy.context.active_object.data.materials.append(INK)

mock.scene_setup(world_color=(0.72, 0.74, 0.72), res=(1600, 1200), samples=40)
mock.sun(rotation=(0.45, 0.2, 0.6), energy=3.0)
mock.camera((3, 3, 60), ortho_scale=72, rot=(0, 0, 0))
mock.render(mock.out_path("map_base_camp.png"))

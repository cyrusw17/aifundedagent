"""Top-down map of the base camp, built from the positions in
src/server/Services/World.luau (spawn, barrels, drop-off, hay shop, sell pad).

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

GRASS = mock.mat("grass", rgb(106, 166, 90), 1.0)
GRASS_DARK = mock.mat("grass_dark", rgb(88, 145, 74), 1.0)
PATH = mock.mat("path", rgb(196, 170, 118), 1.0)
SPAWN = mock.mat("spawn", rgb(200, 180, 120), 0.6)
SPAWN_RING = mock.mat("spawn_ring", rgb(255, 255, 255), 0.4)
PLANKS = mock.mat("planks", rgb(150, 110, 70), 0.9)
SHOP_FLOOR = mock.mat("shop_floor", rgb(200, 180, 140), 0.9)
WALL = mock.mat("wall", rgb(244, 239, 224), 0.7)
ROOF = mock.mat("roof", rgb(192, 57, 43), 0.8)
COUNTER = mock.mat("counter", rgb(139, 90, 43), 0.8)
SELL = mock.mat("sell", rgb(240, 173, 46), 0.4, emit=0.15)
WOOD = mock.mat("wood", rgb(139, 90, 43), 0.8)
HOOP = mock.mat("hoop", rgb(70, 70, 76), 0.4, 0.8)
HAY = [mock.mat(f"hay{i}", rgb(*c), 0.9) for i, c in enumerate(
    [(232, 201, 90), (220, 184, 70), (244, 218, 120), (205, 170, 60)])]
INK = mock.mat("ink", rgb(40, 34, 28), 0.9)
WHITE = mock.mat("white", rgb(255, 255, 255), 0.9)
ARROW = mock.mat("arrow", rgb(60, 110, 200), 0.6)

# Ground with a few darker grass patches.
mock.box("ground", (120, 1, 100), rbx(3, -3, -0.5), GRASS)
rng = random.Random(3)
for i in range(30):
    x, z = rng.uniform(-40, 46), rng.uniform(-40, 34)
    o = mock.cylinder(f"patch{i}", rng.uniform(1.5, 4), 0.05, rbx(x, z, 0.01 + i * 0.002), GRASS_DARK, verts=12)
    o.scale = (1, rng.uniform(0.5, 1), 1)

# Dirt paths connecting the loop: spawn -> barrels -> drop-off -> sell pad.
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
ring = mock.cylinder("spawn_ring", 2.6, 1.05, rbx(0, 14, 0.5), SPAWN_RING, verts=32)
inner = mock.cylinder("spawn_ring_in", 2.1, 1.1, rbx(0, 14, 0.5), SPAWN, verts=32)

# Three hay barrels in a row at z = -18.
for i in range(3):
    x = -18 + i * 7
    mock.tub(f"barrel{i}", rbx(x, -18, 0), 2.0, 2.4, WOOD, HOOP)
    mock.hay_heap(f"barrelhay{i}", rbx(x, -18, 2.4), 2.3, 1.8, HAY, tufts=30, seed=i, straws=0)

# Barrel drop-off (14 x 10 at 0, -4) with plank lines and one set-down barrel.
mock.box("dropoff", (14, 0.2, 10), rbx(0, -4, 0.1), PLANKS)
for k in range(6):
    mock.box("plankline", (14, 0.22, 0.12), rbx(0, -8.3 + k * 1.7, 0.11), WOOD)
mock.tub("dropbarrel", rbx(3.5, -5.5, 0.2), 2.0, 2.4, WOOD, HOOP)
mock.hay_heap("drophay", rbx(3.5, -5.5, 2.6), 2.3, 1.6, HAY, tufts=25, seed=9, straws=0)
for i in range(18):  # loose hay pieces from a smashed barrel
    x, z = rng.uniform(-6, 0), rng.uniform(-8, 0)
    o = mock.box(f"piece{i}", (rng.uniform(0.9, 1.5), 0.3, 0.3), rbx(x, z, 0.35), HAY[i % 4])
    o.rotation_euler[2] = rng.uniform(0, math.pi)

# Hay shop (floor 16x12 at 22, -18), shown with a cutaway roof so the counter reads.
mock.box("shop_floor", (16, 1, 12), rbx(22, -18, 0.5), SHOP_FLOOR)
mock.box("back_wall", (16, 9, 1), rbx(22, -23.5, 5.5), WALL)
mock.box("left_wall", (1, 9, 12), rbx(14.5, -18, 5.5), WALL)
mock.box("right_wall", (1, 9, 12), rbx(29.5, -18, 5.5), WALL)
mock.box("roof_back", (18, 1, 7), rbx(22, -21.5, 10.5), ROOF)
for k in range(5):
    mock.box("roof_line", (18, 1.05, 0.15), rbx(22, -24.5 + k * 1.5, 10.5), mock.mat("roof_dark", rgb(150, 40, 30)))
mock.box("counter", (10, 4, 2), rbx(22, -14, 3), COUNTER)

# Sell pad (12 x 9 at 22, -6).
mock.box("sell", (12, 0.4, 9), rbx(22, -6, 0.2), SELL)

# Labels on the ground (they lie flat, readable from above).
def tag(text, x, z, size=1.6, mat=INK):
    mock.label(text, rbx(x, z, 12), size, mat)

tag("SPAWN", 0, 20)
tag("HAY BARRELS", -11, -23.5)
tag("click with bare hands to lift,", -24, -12.5, 0.9)
tag("or shovel to smash and scoop", -24, -11.2, 0.9)
tag("BARREL DROP-OFF", 0, 3.0)
tag("set barrels down here", 0, 4.6, 0.9)
tag("HAY SHOP", 22, -16.4, 1.8, INK)
tag("counter", 22, -14, 0.9, WHITE)
tag("SELL HERE", 22, -6, 1.6)
tag("walk on with hay, or set a barrel down", 22, -0.5, 0.9)
tag("NEEDLEWOOD  BASE CAMP", 3, -28, 2.4)

# Direction arrows along the loop.
def arrow(x, z, angle):
    bpy.ops.mesh.primitive_cone_add(vertices=3, radius1=1.1, depth=0.1, location=rbx(x, z, 11))
    o = bpy.context.active_object
    o.rotation_euler = (0, 0, angle)
    o.scale = (0.75, 1.5, 1)
    o.data.materials.append(ARROW)

arrow(0, 9, 0.0)                     # spawn -> drop-off
arrow(-6, -11.5, -2.476)             # barrels -> drop-off
arrow(11, -5, -1.48)                 # drop-off -> sell pad

# Scale bar (10 studs) and north marker.
mock.box("scale", (10, 0.1, 0.4), rbx(-26, 21, 11), INK)
tag("10 studs", -26, 22.6, 0.9)
tag("N", 34, -26, 1.6)
bpy.ops.mesh.primitive_cone_add(vertices=3, radius1=0.9, depth=0.1, location=rbx(34, -24, 11))
bpy.context.active_object.data.materials.append(INK)

mock.scene_setup(res=(1600, 1200), samples=40)
mock.sun(rotation=(0.45, 0.2, 0.6), energy=3.0)
mock.camera((3, 3, 60), ortho_scale=72, rot=(0, 0, 0))
mock.render(mock.out_path("map_base_camp.png"))

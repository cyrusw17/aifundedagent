"""Mockup of the three tools, using the part sizes from
src/server/Services/Avatar.luau (shovel and rake) and the R6 arm size for bare hands.
Shown head-down, the way they meet the hay.

Run:
  python blender/mockups/tools.py [out_folder]
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mock  # noqa: E402
from mock import rgb  # noqa: E402

bpy.ops.wm.read_factory_settings(use_empty=True)

WOOD = mock.mat("wood", rgb(139, 90, 43), 0.7)
STEEL = mock.mat("steel", rgb(150, 158, 166), 0.3, 0.9)
HOOP = mock.mat("hoop", rgb(70, 70, 76), 0.4, 0.8)
SKIN = mock.mat("skin", rgb(234, 184, 146), 0.6)
SLEEVE = mock.mat("sleeve", rgb(52, 118, 196), 0.7)
FLOOR = mock.mat("floor", rgb(106, 166, 90), 1.0)
PLINTH = mock.mat("plinth", rgb(225, 215, 195), 0.8)
INK = mock.mat("ink", rgb(40, 34, 28), 0.9)
SUB = mock.mat("sub", rgb(90, 80, 70), 0.9)
HAY = [mock.mat(f"hay{i}", rgb(*c), 0.9) for i, c in enumerate(
    [(232, 201, 90), (220, 184, 70), (244, 218, 120), (205, 170, 60)])]
rng = random.Random(4)

mock.box("floor", (80, 1, 40), (0, 0, -0.5), FLOOR)
UP = (math.pi / 2, 0, 0)  # labels stand up facing the camera


def plinth(x):
    mock.cylinder("plinth", 3.6, 0.6, (x, 0, 0.3), PLINTH, verts=40)


def pieces(cx, cy, cz, n, spread):
    for i in range(n):
        o = mock.box(f"piece{i}", (rng.uniform(0.9, 1.5), 0.3, 0.3),
                     (cx + rng.uniform(-spread, spread), cy + rng.uniform(-spread, spread) * 0.6, cz + 0.15),
                     HAY[i % 4])
        o.rotation_euler = (rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(0, math.pi))


def titles(x, name, lines):
    mock.label(name, (x, 0, 10.6), 1.1, INK, rot=UP)
    for k, line in enumerate(lines):
        mock.label(line, (x, 0, 9.6 - k * 0.7), 0.5, SUB, rot=UP)


# Bare hands: two blocky arms gripping a whole hay barrel.
X = -10
plinth(X)
mock.tub("barrel", (X, 0, 0.6), 1.9, 2.4, WOOD, HOOP)
mock.hay_heap("barrelhay", (X, 0, 3.0), 2.1, 1.6, HAY, tufts=35, seed=2, straws=25)
for side in (-1, 1):
    arm = mock.box("arm", (1, 2, 1), (X + side * 2.6, -0.2, 3.2), SLEEVE, rot=(0, side * 0.35, 0))
    hand = mock.box("hand", (1, 0.9, 1), (X + side * 2.25, -0.2, 2.0), SKIN, rot=(0, side * 0.35, 0))
titles(X, "BARE HANDS", ["Click a barrel to lift the whole thing", "Carry it to the drop-off or sell pad"])

# Shovel: handle 0.4x1.6, shaft 0.4x3, blade 1.2x1.5x0.12, flipped so the blade is at the bottom.
X = 0
plinth(X)
tilt = (0.25, 0, 0)
top = 7.6
mock.box("handle", (0.4, 1.6, 0.4), (X, 0, top - 0.8), WOOD)
mock.box("grip", (1.1, 0.3, 0.3), (X, 0, top), WOOD)
mock.box("shaft", (0.4, 3, 0.4), (X, 0, top - 3.1), WOOD)
mock.box("blade", (1.2, 1.5, 0.12), (X, -0.05, top - 5.35), STEEL)
mock.box("blade_lip", (1.2, 0.12, 0.5), (X, -0.25, top - 6.05), STEEL)
pieces(X + 0.3, -0.6, 0.6, 9, 1.4)
titles(X, "SHOVEL", ["Click a barrel to smash it into pieces", "Click loose hay to scoop 6 pieces"])

# Rake: shaft 0.4x3.6, crossbar 3.2x0.25, six 1-stud teeth, flipped so the teeth are at the bottom.
X = 10
plinth(X)
top = 7.8
mock.box("handle", (0.4, 1.6, 0.4), (X, 0, top - 0.8), WOOD)
mock.box("shaft", (0.4, 3.6, 0.4), (X, 0, top - 3.4), WOOD)
mock.box("bar", (3.2, 0.25, 0.3), (X, 0, top - 5.3), STEEL)
for i in range(6):
    mock.box("tooth", (0.12, 1, 0.12), (X - 1.4 + i * 0.56, 0, top - 5.9), STEEL)
pieces(X, -1.0, 0.6, 14, 2.6)
titles(X, "RAKE", ["Click the ground to drag loose hay", "toward you, spreading it out"])

mock.label("TOOLS", (0, 4, 13.2), 1.6, INK, rot=UP)

mock.scene_setup(world_color=(0.78, 0.84, 0.9), res=(1800, 1000), samples=48)
mock.sun(rotation=(0.8, 0.1, 0.5), energy=3.5)
mock.camera((0, -48, 11), look_at=(0, 0, 6.0), lens=42)
mock.render(mock.out_path("tools.png"))

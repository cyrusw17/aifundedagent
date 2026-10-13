"""Mockup of the tools in the house style, using the props in
blender/props/rustic_props.py. Front three are in the game today
(bare hands, shovel, rake); the rest are modeled but not in the game yet.

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
F = mock.rustic_finish()

SKIN = mock.mat("skin", rgb(204, 160, 124), 0.7)
SLEEVE = mock.mat("sleeve", rgb(88, 102, 120), 0.8)
FLOOR = mock.mat("floor", rgb(112, 128, 82), 1.0)
PLINTH = mock.mat("plinth", rgb(196, 186, 162), 0.9)
INK = mock.mat("ink", rgb(40, 34, 28), 0.9)
SUB = mock.mat("sub", rgb(90, 80, 70), 0.9)
HAY = [mock.mat(f"hay{i}", rgb(*c), 0.9) for i, c in enumerate(
    [(219, 204, 153), (189, 168, 112), (168, 149, 95), (133, 115, 71)])]
rng = random.Random(4)
UP = (math.pi / 2, 0, 0)

mock.box("floor", (120, 1, 60), (0, 0, -0.5), FLOOR)


def plinth(x, r=2.3):
    mock.cylinder("plinth", r, 0.5, (x, 0, 0.25), PLINTH, verts=12)


def pieces(cx, cy, cz, n, spread):
    for i in range(n):
        o = mock.box(f"piece{i}", (rng.uniform(0.9, 1.5), 0.3, 0.3),
                     (cx + rng.uniform(-spread, spread), cy + rng.uniform(-spread, spread) * 0.6, cz + 0.15),
                     HAY[i % 4])
        o.rotation_euler = (rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(0, math.pi))


def titles(x, name, lines, z=7.2, size=0.85):
    mock.label(name, (x, 0, z), size, INK, rot=UP)
    for k, line in enumerate(lines):
        mock.label(line, (x, 0, z - 0.85 - k * 0.6), 0.42, SUB, rot=UP)


GAP = 7.2
xs = [(i - 2.5) * GAP for i in range(6)]

# Bare hands: two R6 arms lifting a whole bale.
X = xs[0]
plinth(X)
mock.bale((X, 0, 1.6), 0.0, F)
for side in (-1, 1):
    mock.box("arm", (1, 2, 1), (X + side * 2.6, 0, 3.6), SLEEVE, rot=(0, side * 0.25, 0))
    mock.box("hand", (1, 0.9, 1), (X + side * 2.45, 0, 2.5), SKIN, rot=(0, side * 0.25, 0))
titles(X, "BARE HANDS", ["Click a bale to lift it", "Carry it, stack it, sell it"])

# Shovel: the small spade (about 2.7 studs), standing in loose hay.
X = xs[1]
plinth(X)
mock.prop("basic_shovel", (X, 0, 0.5), rot=(0.12, 0, 0.3), f=F)
pieces(X + 0.4, -0.8, 0.5, 9, 1.3)
titles(X, "SHOVEL", ["Click a bale to smash it", "Click loose hay to scoop it"])

# Rake: long garden rake, teeth down.
X = xs[2]
plinth(X)
mock.prop("garden_rake", (X, 0, 0.55), rot=(0.18, 0, 0.2), f=F)
pieces(X, -1.0, 0.5, 12, 2.2)
titles(X, "RAKE", ["Click loose hay to drag it", "toward you"])

# Modeled, not in the game yet.
for X, key, name in ((xs[3], "wide_scoop", "WIDE SCOOP"), (xs[4], "pitchfork", "PITCHFORK"),
                     (xs[5], "hay_hook", "HAY HOOK")):
    plinth(X, 2.0)
    mock.prop(key, (X, 0, 0.5), rot=(0.12, 0, 0.3), f=F)
    titles(X, name, ["Modeled, not in", "the game yet"], z=7.2, size=0.65)

mock.label("TOOLS", (0, 4, 10.2), 1.5, INK, rot=UP)

mock.scene_setup(world_color=(0.74, 0.76, 0.74), res=(2000, 1000), samples=48)
mock.sun(rotation=(0.8, 0.1, 0.5), energy=3.2)
mock.camera((0, -52, 9), look_at=(0, 0, 4.4), lens=40)
mock.render(mock.out_path("tools.png"))

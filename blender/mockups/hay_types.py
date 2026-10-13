"""Mockup sheet of the hay types: one hay per map, matching the needle types in
src/shared/Config/Needles.luau (each map's hay hides that map's needle).
Colors and effects are a proposal; the game only has Meadow hay so far.

Run:
  python blender/mockups/hay_types.py [out_folder]
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

# name, needle, sorted value, hay colors, needle color, needle glow, extra
HAY_TYPES = [
    ("Meadow", "Steel", 100, [(232, 201, 90), (220, 184, 70), (244, 218, 120)], (170, 175, 182), 0, None),
    ("Pine Forest", "Pine", 110, [(196, 186, 92), (170, 160, 78), (120, 140, 70)], (46, 100, 52), 0, "pinecone"),
    ("Desert", "Sand", 140, [(236, 214, 160), (222, 196, 136), (246, 230, 186)], (214, 170, 96), 0, None),
    ("Snow Peak", "Ice", 160, [(226, 214, 168), (210, 200, 160), (245, 248, 252)], (150, 210, 245), 1.5, "snow"),
    ("Swamp", "Bog", 170, [(128, 128, 64), (104, 108, 56), (92, 80, 48)], (70, 96, 60), 0, "moss"),
    ("Volcano", "Obsidian", 300, [(70, 56, 48), (52, 44, 40), (96, 64, 44)], (24, 20, 30), 0, "embers"),
    ("Cave", "Geode", 340, [(150, 146, 140), (124, 122, 120), (170, 160, 146)], (170, 90, 220), 2.0, "crystals"),
    ("Sky Island", "Cloud", 700, [(236, 240, 250), (214, 224, 244), (246, 236, 210)], (170, 210, 255), 1.0, "cloud"),
    ("Haunted Grove", "Phantom", 800, [(120, 104, 140), (96, 84, 116), (140, 128, 150)], (140, 255, 190), 4.0, "wisps"),
    ("Star Hay", "Cosmic", 5000, [(48, 40, 110), (70, 50, 140), (30, 28, 80)], (255, 230, 140), 6.0, "stars"),
]

WOOD = mock.mat("wood", rgb(139, 90, 43), 0.8)
HOOP = mock.mat("hoop", rgb(70, 70, 76), 0.4, 0.8)
FLOOR = mock.mat("floor", rgb(214, 206, 188), 1.0)
TILE = mock.mat("tile", rgb(238, 232, 218), 0.9)
INK = mock.mat("ink", rgb(40, 34, 28), 0.9)
SUB = mock.mat("sub", rgb(100, 90, 80), 0.9)
UP = (math.pi / 2, 0, 0)

mock.box("floor", (120, 1, 80), (0, 0, -0.5), FLOOR)
SPACING_X, SPACING_Y = 9.0, 10.5


def needle(x, y, z, color, glow, rng):
    m = mock.mat(f"needle{color}", rgb(*color), 0.3, 0.6 if not glow else 0.0, emit=glow)
    mock.cylinder("needle", 0.07, 1.6, (x, y, z), m, verts=6,
                  rot=(rng.uniform(0.5, 1.2), 0, rng.uniform(0, math.tau)))


for idx, (name, needle_name, value, cols, ncol, glow, extra) in enumerate(HAY_TYPES):
    row, col = divmod(idx, 5)
    cx = (col - 2) * SPACING_X
    cy = row * SPACING_Y
    rng = random.Random(idx + 11)
    hay = [mock.mat(f"{name}{i}", rgb(*c), 0.9, emit=(0.4 if extra == "stars" else 0.0)) for i, c in enumerate(cols)]

    mock.box("tile", (7.6, 0.2, 8.6), (cx, cy - 0.6, 0.1), TILE)
    mock.tub(name + "_tub", (cx, cy, 0.2), 1.9, 2.2, WOOD, HOOP)
    mock.hay_heap(name, (cx, cy, 2.4), 2.15, 1.7, hay, tufts=40, seed=idx, straws=30)
    for k in range(3):
        a = rng.uniform(-2.2, -0.9)
        needle(cx + math.cos(a) * 1.4, cy + math.sin(a) * 1.1, 3.3 + rng.uniform(-0.2, 0.4), ncol, glow, rng)

    if extra == "snow":
        mock.sphere("snowcap", 1.5, (cx, cy, 4.0), mock.mat("snow", rgb(236, 242, 250), 0.6), scale=(0.8, 0.8, 0.25), subdiv=3)
    elif extra == "pinecone":
        for k in range(3):
            mock.sphere("cone", 0.32, (cx + rng.uniform(-1.4, 1.4), cy - 1.6 - rng.uniform(0, 0.6), 0.5),
                        mock.mat("pinecone", rgb(110, 70, 40)), scale=(0.8, 0.8, 1.2), subdiv=1)
    elif extra == "moss":
        for k in range(6):
            mock.sphere("moss", 0.35, (cx + rng.uniform(-1.6, 1.6), cy + rng.uniform(-1.6, 1.0), 3.0 + rng.uniform(0, 0.8)),
                        mock.mat("mossy", rgb(70, 120, 50)), scale=(1.2, 1.2, 0.5), subdiv=1)
    elif extra == "embers":
        ember = mock.mat("ember", rgb(255, 120, 30), 0.5, emit=8.0)
        for k in range(10):
            a, d = rng.uniform(0, math.tau), rng.uniform(0, 1.8)
            mock.sphere("ember", 0.14, (cx + math.cos(a) * d, cy + math.sin(a) * d, 3.3 + rng.uniform(0, 0.9)), ember, subdiv=1)
    elif extra == "crystals":
        crystal = mock.mat("crystal", rgb(170, 90, 220), 0.1, emit=1.2)
        for k in range(4):
            bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.25, depth=1.0,
                                            location=(cx + rng.uniform(-1.5, 1.5), cy - 1.8, 0.7))
            o = bpy.context.active_object
            o.rotation_euler = (rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), 0)
            o.data.materials.append(crystal)
    elif extra == "cloud":
        puff = mock.mat("puff", rgb(255, 255, 255), 0.9, emit=0.3)
        for k in range(5):
            mock.sphere("puff", rng.uniform(0.5, 0.8), (cx + rng.uniform(-2.4, 2.4), cy + 0.5, 0.6 + rng.uniform(0, 0.4)), puff, subdiv=2)
    elif extra == "wisps":
        wisp = mock.mat("wisp", rgb(140, 255, 190), 0.5, emit=5.0)
        for k in range(5):
            mock.sphere("wisp", rng.uniform(0.12, 0.22), (cx + rng.uniform(-2.2, 2.2), cy - 1.0, 4.4 + rng.uniform(0, 1.4)), wisp, subdiv=1)
    elif extra == "stars":
        star = mock.mat("star", rgb(255, 240, 180), 0.5, emit=10.0)
        for k in range(14):
            a, d = rng.uniform(0, math.tau), rng.uniform(0, 2.1)
            mock.sphere("star", 0.1, (cx + math.cos(a) * d, cy + math.sin(a) * d, 3.0 + rng.uniform(0, 1.3)), star, subdiv=1)

    mock.label(name.upper(), (cx, cy - 3.5, 0.25), 0.62, INK)
    mock.label(f"{needle_name} needles  ·  {value}", (cx, cy - 4.3, 0.25), 0.42, SUB)

mock.label("HAY TYPES  (one per map)", (0, 2 * SPACING_Y - 3.0, 0.25), 1.0, INK)

mock.scene_setup(world_color=(0.8, 0.82, 0.86), res=(2000, 1300), samples=48)
mock.sun(rotation=(0.6, 0.15, 0.4), energy=2.6)
mock.camera((0, -30, 52), look_at=(0, 4.6, 0), lens=40)
mock.render(mock.out_path("hay_types.png"))

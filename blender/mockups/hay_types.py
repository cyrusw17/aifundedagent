"""Mockup sheet of the hay types in the house style: stacks of square bales,
one hay per map, matching the needle types in src/shared/Config/Needles.luau.
Only Meadow hay is in the game; the other colors and extras are a proposal.

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
from regions import REGIONS  # noqa: E402

bpy.ops.wm.read_factory_settings(use_empty=True)

# name, needle, sorted value, hay (light, mid, dark) 0-255 or None for the house hay,
# twine (0-255) or None for plain twine, needle color, needle glow, extra
HAY_TYPES = [
    ("Meadow", "Steel", 100, None, None, (170, 175, 182), 0, None),
    ("Pine Forest", "Pine", 110, ((206, 196, 112), (170, 160, 78), (110, 128, 62)), None, (46, 100, 52), 0, "pinecone"),
    ("Desert", "Sand", 140, ((246, 230, 186), (226, 204, 150), (196, 166, 110)), None, (214, 170, 96), 0, None),
    ("Snow Peak", "Ice", 160, ((240, 236, 214), (214, 204, 164), (176, 168, 136)), (120, 150, 176), (150, 210, 245), 1.5, "snow"),
    ("Swamp", "Bog", 170, ((140, 140, 76), (110, 112, 58), (78, 70, 42)), None, (70, 96, 60), 0, "moss"),
    ("Volcano", "Obsidian", 300, ((112, 84, 64), (72, 58, 48), (44, 36, 32)), (140, 52, 34), (24, 20, 30), 0, "embers"),
    ("Cave", "Geode", 340, ((176, 170, 160), (140, 136, 130), (100, 98, 96)), (110, 76, 140), (170, 90, 220), 2.0, "crystals"),
    ("Sky Island", "Cloud", 700, ((246, 246, 250), (220, 226, 240), (184, 192, 214)), (120, 160, 210), (170, 210, 255), 1.0, "cloud"),
    ("Haunted Grove", "Phantom", 800, ((150, 136, 168), (110, 98, 130), (76, 66, 96)), (70, 150, 110), (140, 255, 190), 4.0, "wisps"),
    ("Star Hay", "Cosmic", 5000, ((96, 84, 170), (62, 50, 130), (34, 30, 84)), (220, 180, 80), (255, 230, 140), 6.0, "stars"),
]

FLOOR = mock.mat("floor", rgb(112, 128, 82), 1.0)
TILE = mock.mat("tile", rgb(196, 186, 162), 0.9)
INK = mock.mat("ink", rgb(40, 34, 28), 0.9)
SUB = mock.mat("sub", rgb(80, 72, 62), 0.9)

mock.box("floor", (140, 1, 90), (0, 0, -0.5), FLOOR)
SPACING_X, SPACING_Y = 11.5, 14.0


def needle(x, y, z, color, glow, rng):
    m = mock.mat(f"needle{color}", rgb(*color), 0.4, 0.5 if not glow else 0.0, emit=glow)
    mock.box("needle", (0.14, 1.8, 0.14), (x, y, z), m, rot=(rng.uniform(0.6, 1.1), 0, rng.uniform(0, math.tau)))


for idx, (name, needle_name, value, hay, twine, ncol, glow, extra) in enumerate(HAY_TYPES):
    row, col = divmod(idx, 5)
    cx = (col - 2) * SPACING_X
    cy = row * SPACING_Y
    rng = random.Random(idx + 11)
    region = {"Pine Forest": "pine", "Desert": "desert", "Snow Peak": "snow", "Swamp": "swamp"}.get(name)
    if hay is None:
        f = mock.rustic_finish()
    elif region:  # region hays come from regions.py so both sheets agree
        tw = mock.rustic_palette(twine, twine, tuple(int(c * 0.7) for c in twine), 0.2) if twine else None
        f = mock.rustic_finish("hay_" + region, hay=REGIONS[region]["hay"], twine=tw)
    else:
        pal = mock.rustic_palette(*hay, weather=0.25)
        tw = mock.rustic_palette(twine, twine, tuple(int(c * 0.7) for c in twine), 0.2) if twine else None
        f = mock.rustic_finish("hay_" + name.lower().replace(" ", "_"), hay=pal, twine=tw)

    mock.box("tile", (10.0, 0.2, 12.6), (cx, cy - 1.4, 0.1), TILE)
    mock.bale_stack(cx, cy, 0.2, f, layers=2)
    top = 0.2 + 2 * mock.BALE[2]
    for k in range(3):
        needle(cx + rng.uniform(-1.6, 1.6), cy - 3.3, rng.uniform(1.0, 4.2), ncol, glow, rng)

    if extra == "snow":
        mock.box("snow", (3.0, 0.35, 4.4), (cx, cy, top + 0.17), mock.mat("snow", rgb(236, 242, 250), 0.7))
    elif extra == "pinecone":
        for k in range(3):
            mock.box("cone", (0.5, 0.75, 0.5), (cx + rng.uniform(-2.5, 2.5), cy - 4.0, 0.6),
                     mock.mat("pinecone", rgb(110, 70, 40)), rot=(0, 0, rng.uniform(0, 1)))
    elif extra == "moss":
        for k in range(6):
            mock.box("moss", (rng.uniform(0.6, 1.1), 0.25, rng.uniform(0.6, 1.1)),
                     (cx + rng.uniform(-0.8, 0.8), cy + rng.uniform(-1.6, 1.6), top + 0.2),
                     mock.mat("mossy", rgb(70, 110, 50)), rot=(0, 0, rng.uniform(0, 1)))
    elif extra == "embers":
        ember = mock.mat("ember", rgb(255, 120, 30), 0.5, emit=8.0)
        for k in range(10):
            mock.box("ember", (0.25, 0.25, 0.25), (cx + rng.uniform(-1, 1), cy + rng.uniform(-2, 2), top + rng.uniform(0.2, 1.2)), ember,
                     rot=(rng.uniform(0, 1), rng.uniform(0, 1), 0))
    elif extra == "crystals":
        crystal = mock.mat("crystal", rgb(170, 90, 220), 0.2, emit=1.2)
        for k in range(4):
            bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.3, depth=1.2,
                                            location=(cx + rng.uniform(-2.5, 2.5), cy - 3.9, 0.8))
            o = bpy.context.active_object
            o.rotation_euler = (rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), 0)
            o.data.materials.append(crystal)
    elif extra == "cloud":
        puff = mock.mat("puff", rgb(255, 255, 255), 0.9, emit=0.2)
        for k in range(4):
            s = rng.uniform(0.9, 1.4)
            mock.box("puff", (s, s * 0.7, s), (cx + rng.uniform(-3, 3), cy - 3.8, 0.6), puff, rot=(0, 0, rng.uniform(0, 1)))
    elif extra == "wisps":
        wisp = mock.mat("wisp", rgb(140, 255, 190), 0.5, emit=5.0)
        for k in range(5):
            mock.sphere("wisp", rng.uniform(0.15, 0.25), (cx + rng.uniform(-2, 2), cy - 2.0, top + rng.uniform(0.4, 1.8)), wisp, subdiv=1)
    elif extra == "stars":
        star = mock.mat("star", rgb(255, 240, 180), 0.5, emit=10.0)
        for k in range(14):
            mock.box("star", (0.18, 0.18, 0.18), (cx + rng.uniform(-2.6, 2.6), cy + rng.uniform(-3.4, 3.4), rng.uniform(0.6, top + 1.4)), star,
                     rot=(0.6, 0.6, 0))

    mock.label(name.upper(), (cx, cy - 5.2, 0.25), 0.72, INK)
    mock.label(f"{needle_name} needles  ·  {value}", (cx, cy - 6.1, 0.25), 0.46, SUB)

mock.label("HAY TYPES  (one per map)", (0, 2 * SPACING_Y - 3.5, 0.25), 1.1, INK)

mock.scene_setup(world_color=(0.74, 0.76, 0.74), res=(2000, 1300), samples=48)
mock.sun(rotation=(0.6, 0.15, 0.4), energy=3.0)
mock.camera((0, -36, 66), look_at=(0, 5.5, 0), lens=40)
mock.render(mock.out_path("hay_types.png"))

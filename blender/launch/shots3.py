"""Third batch of launch art: golden bales, the Spindle and the Hay Wagon (features that landed in PR #16).

Run: python blender/launch/shots3.py -- --only golden --preview
"""
import argparse
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scene as S  # noqa: E402
import shots  # noqa: E402

bpy = S.bpy
OUT = os.environ.get("LAUNCH_OUT", shots.OUT)
GOLD = (222, 182, 72)  # Bales.makeGolden


def golden_bale(loc, rot=0.0, light=True):
    """A golden field bale: gold hay, a soft glow and a few glints around it (Bales.makeGolden)."""
    b = S.bale(loc, rot)
    S.paint(b, {"rustic_hay": GOLD}, rough=0.5, emit=0.45)
    if light:
        bpy.ops.object.light_add(type="POINT", location=(loc[0], loc[1], loc[2] + 2.0))
        l = bpy.context.active_object
        l.data.energy = 900
        l.data.color = S.srgb(255, 210, 110)
        l.data.shadow_soft_size = 2.0
    rng = random.Random(int(loc[0] * 7 + loc[1]))
    for _ in range(10):
        a, r = rng.uniform(0, 6.28), rng.uniform(2.6, 4.2)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=rng.uniform(0.06, 0.13),
                                              location=(loc[0] + math.cos(a) * r, loc[1] + math.sin(a) * r, loc[2] + rng.uniform(0.6, 4.0)))
        bpy.context.active_object.data.materials.append(S.mat("glint", (255, 214, 110), 0.3, 0, 20.0))
    return b


def golden(rng):
    """Thumbnail: a golden bale among ordinary ones at golden hour, a farmer running for it."""
    S.ground(1600, seed=51, hills=55)
    S.sky(top=(116, 146, 186), horizon=(244, 206, 150), strength=0.9)
    S.sun(elev_deg=12, azim_deg=250, energy=3.6, color=(255, 210, 160))
    S.fill(60, 0.6)
    for row in range(5):
        for col in range(7):
            x, y = -30 + col * 10 + rng.uniform(-1.5, 1.5), 6 + row * 10 + rng.uniform(-1.5, 1.5)
            if (row, col) != (0, 3):
                S.bale((x, y, 0), rng.uniform(-0.3, 0.3))
    golden_bale((0, 6, 0), 0.25)
    S.farmer((-7, 5, 0), -1.1, pose={"rarm": (0.8, 0), "larm": (-0.8, 0), "lleg": 0.5, "rleg": -0.5, "gloves": True})
    S.prop("basic_shovel", (-3.5, -3, 0), 0.4, tilt=(0.4, 0.2))
    shots.rig(34, 34, math.radians(200), rng, trailer=False)
    shots.backdrop(rng)
    S.camera((5, -10, 3.4), (-1.2, 5, 2.4), lens=30)


def spire(x, y, base_r, h, rgb=(150, 142, 160)):
    """The Spindle: a faceted slate needle of stacked tapering blocks."""
    stone = S.mat("spindle_stone", rgb, 0.95)
    dark = S.mat("spindle_dark", tuple(int(c * 0.8) for c in rgb), 0.95)
    n = 9
    for i in range(n):
        t = i / n
        r = base_r * (1 - t) ** 1.25 + 2
        S.cyl(r, h / n * 1.02, (x, y, h / n * (i + 0.5)), stone if i % 2 == 0 else dark, verts=8, rot=(0, 0, i * 0.2))
    bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=3, depth=h * 0.18, location=(x, y, h + h * 0.09))
    bpy.context.active_object.data.materials.append(dark)


def spindle(rng):
    """Thumbnail: the Spindle on the skyline, its sealed door with twelve shard sockets, some glowing."""
    S.ground(1600, seed=61, hills=70, color=(118, 128, 96))
    S.sky(top=(108, 132, 176), horizon=(236, 206, 176), strength=0.9)
    S.sun(elev_deg=18, azim_deg=240, energy=3.8, color=(255, 220, 180))
    S.fill(60, 0.6)
    spire(0, 60, 34, 210)
    # door in the spire's face, toward the camera (-y)
    frame = S.mat("door_frame", (150, 142, 160), 0.95)
    S.box((20, 4, 26), (0, 26.5, 12.5), frame, bevel=0.3)
    S.box((14, 1, 20), (0, 24.3, 10.5), S.mat("door", (96, 86, 120), 0.9), bevel=0.1)
    lit = S.mat("socket_lit", (242, 183, 5), 0.4, 0, 8.0)
    dim = S.mat("socket_dim", (120, 100, 50), 0.6)
    for i in range(12):
        a = i / 12 * math.pi * 2
        on = i in (0, 1, 2, 4, 5, 8, 9)
        S.cyl(0.55, 0.6, (math.cos(a) * 5, 23.7, 12.5 + math.sin(a) * 5), lit if on else dim, verts=10, rot=(math.pi / 2, 0, 0))
    bpy.ops.object.light_add(type="POINT", location=(0, 20, 12.5))
    bpy.context.active_object.data.energy = 1500
    bpy.context.active_object.data.color = S.srgb(255, 200, 90)
    # a path up to it and a farmer holding a shard
    S.road([(0, -80), (0, -20), (0, 22)], width=7)
    f, arms = S.farmer((4, -8, 0), 0.35, pose={"rarm": (-1.6, 0.0), "gloves": True})
    sh = bpy.data.objects.new("shard", None)
    bpy.context.scene.collection.objects.link(sh)
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.35, depth=1.8, location=(0, 0, 0))
    c = bpy.context.active_object
    c.data.materials.append(S.mat("shard", (255, 214, 90), 0.3, 0, 10.0))
    c.parent = arms["rarm"]
    c.location = (0, 0, -2.4)
    for x, y in [(-30, 20), (28, 14), (-44, -4), (40, 40), (-20, 70), (26, 80)]:
        S.pine(x, y, rng, 1.2)
    shots.backdrop(rng, ring=(140, 420), pines=0.7)
    S.camera((24, -84, 8), (0, 30, 30), lens=26)


def wagon(loc, rot_z, rng):
    """The Hay Wagon (HayWagon.luau buildWagon): plank bed, hay heap, red seats, a little green tractor in front.
    Built facing -y like the game's -Z, in studs."""
    root = bpy.data.objects.new("haywagon", None)
    bpy.context.scene.collection.objects.link(root)
    wood = S.mat("wagon_wood", (153, 128, 97), 0.9)
    wood_dark = S.mat("wagon_wood_dark", (102, 82, 60), 0.9)
    hay = S.mat("wagon_hay", (189, 168, 112), 0.95)
    red = S.mat("wagon_seat", (133, 61, 48), 0.9)
    green = S.mat("tractor_green", (87, 107, 71), 0.6, 0.3)
    rubber = S.mat("rubber", (40, 38, 36), 0.9)
    parts = [S.box((8, 14, 0.8), (0, -2, 2.4), wood)]
    for side in (-1, 1):
        parts.append(S.box((0.4, 14, 1.4), (side * 3.9, -2, 3.5), wood_dark))
        for y in (3, -7):
            parts.append(S.cyl(1.6, 0.6, (side * 4.3, y, 1.6), wood_dark, verts=12, rot=(0, math.pi / 2, 0)))
    parts.append(S.box((2.4, 12, 1.6), (0, -2, 3.6), hay, bevel=0.3))
    riders = []
    for i in range(6):
        side = -1 if i % 2 == 0 else 1
        y = 2 - (i // 2) * 4
        parts.append(S.box((2, 2, 0.6), (side * 2.5, y, 3.1), red))
        riders.append((side * 2.7, y, side))
    t = (0, 9)
    parts.append(S.box((4, 6, 3), (0, t[1], 3), green))
    parts.append(S.box((3, 3, 2), (0, t[1] + 3.5, 3.5), green))
    parts.append(S.cyl(0.25, 3, (1, t[1] + 3, 6), S.mat("iron", (122, 122, 120), 0.5, 0.6), verts=8))
    for side in (-1, 1):
        parts.append(S.cyl(2.2, 1.2, (side * 2.6, t[1] - 1.5, 2.2), rubber, verts=14, rot=(0, math.pi / 2, 0)))
        parts.append(S.cyl(1.2, 0.8, (side * 1.8, t[1] + 3.5, 1.2), rubber, verts=12, rot=(0, math.pi / 2, 0)))
    parts.append(S.box((6, 0.3, 1.4), (0, -9.2, 5.2), S.mat("board", (226, 214, 186), 0.9)))
    for p in parts:
        p.parent = root
    # the wagon faces +y here; turn it so the tractor leads toward -y like the game
    root.rotation_euler = (0, 0, rot_z + math.pi)
    root.location = loc
    # riders and the driver, placed in world space
    c, s = math.cos(rot_z + math.pi), math.sin(rot_z + math.pi)
    shirts = [(140, 72, 58), (92, 112, 126), (170, 140, 80), (110, 90, 120), (90, 120, 90), (160, 100, 90)]
    for i, (lx, ly, side) in enumerate(riders):
        wx, wy = loc[0] + lx * c - ly * s, loc[1] + lx * s + ly * c
        f, _ = S.farmer((wx, wy, 2.0), rot_z + math.pi + side * math.pi / 2, shirt=shirts[i], hat=i % 2 == 0,
                        pose={"lleg": 1.5, "rleg": 1.5, "rarm": (0.0, -0.4 * side) if i == 1 else (0, 0)})
        f.scale = (0.9, 0.9, 0.9)
    dx, dy = loc[0] - t[1] * s * -1 * 0 + (0 * c - (t[1] - 1.5) * s), loc[1] + (0 * s + (t[1] - 1.5) * c)
    S.farmer((dx, dy, 2.6), rot_z + math.pi + math.pi, shirt=(120, 92, 70), pants=(78, 88, 104))
    return root


def haywagon(rng):
    """Thumbnail: the free Hay Wagon rolling up the North Road with players aboard, Spindle and zeppelin beyond."""
    S.ground(1600, seed=71, hills=60)
    S.sky(top=(126, 160, 200), horizon=(238, 222, 190), strength=1.0)
    S.sun(elev_deg=28, azim_deg=225, energy=4.2)
    S.fill(40, 0.6)
    S.road([(-10, -400), (-4, -60), (0, 0), (10, 80), (40, 400)], width=14)
    wagon((0, 2, 0), math.radians(10), rng)
    spire(-160, 520, 40, 260)
    S.zeppelin((80, 260, 90), math.radians(140), 1.2)
    S.fence(-14, -60, -14, 60)
    for i in range(10):
        S.bale((rng.uniform(16, 70), rng.uniform(-40, 60), 0), rng.uniform(0, 3.14))
    shots.backdrop(rng)
    S.camera((22, -30, 7), (0, 6, 5), lens=30)


def icon_golden(rng):
    S.ground(600, seed=8, color=(104, 122, 78))
    S.sky(top=(110, 140, 186), horizon=(244, 210, 160), strength=0.9)
    S.sun(elev_deg=24, azim_deg=235, energy=3.8, color=(255, 214, 170))
    S.fill(40, 0.5)
    golden_bale((0, 0, 0), 0.0)
    S.bale((-6, 5, 0), 0.4)
    S.bale((6, 6, 0), -0.3)
    S.straw((1, -2.5, 0), 30, rng, spread=3)
    S.camera((5.2, -7.2, 3.0), (0.2, 0, 1.6), lens=40)


def icon_spindle(rng):
    S.ground(1600, seed=9, hills=40, color=(118, 128, 96))
    S.sky(top=(90, 112, 160), horizon=(240, 200, 160), strength=0.9)
    S.sun(elev_deg=14, azim_deg=250, energy=3.6, color=(255, 214, 170))
    S.fill(40, 0.5)
    spire(0, 60, 34, 210)
    for x, y in [(-30, 20), (28, 14), (-44, -4), (40, 40)]:
        S.pine(x, y, rng, 1.2)
    shots.backdrop(rng, ring=(140, 420), pines=0.7)
    S.camera((10, -70, 6), (0, 60, 100), lens=26)


SHOTS = {
    "golden": (golden, (1920, 1080)),
    "spindle": (spindle, (1920, 1080)),
    "haywagon": (haywagon, (1920, 1080)),
    "icon_golden": (icon_golden, (1024, 1024)),
    "icon_spindle": (icon_spindle, (1024, 1024)),
}

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=",".join(SHOTS))
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--samples", type=int, default=96)
    a = ap.parse_args(argv)
    os.makedirs(OUT, exist_ok=True)
    for name in a.only.split(","):
        fn, res = SHOTS[name]
        S.reset()
        S.set_season_default()
        fn(random.Random(7))
        S.render(os.path.join(OUT, name + ".png"), res, samples=a.samples, preview=a.preview)

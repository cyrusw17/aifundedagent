"""Launch art shots: Roblox thumbnails (1920x1080), the game icon (512) and the loading screen.

Run: python blender/launch/shots.py -- --only haul --preview
Writes raw renders to blender/launch/renders/raw/; finish.py adds titles.
"""
import argparse
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scene as S  # noqa: E402

OUT = os.path.join(S.HERE, "renders", "raw")

PICKUP_BED = (0.0, 5.6)      # bed centre (x, y) in the rusty_pickup model, front faces -y
TRAILER_OFF = 32.4           # medium_trailer origin behind the pickup so the tongue meets the hitch
TRAILER_BED = 1.5            # bed centre y offset inside medium_trailer
FLOOR = 3.5                  # every bed floor top (BUILD_REGISTRY)


def place(x, y, a, lx, ly):
    """Local (lx, ly) on an object at (x, y) turned by a -> world."""
    c, s = math.cos(a), math.sin(a)
    return x + lx * c - ly * s, y + lx * s + ly * c


def rig(x, y, a, rng, loaded=True, trailer=True):
    """Rusty pickup (front toward local -y) with the conveyor trailer hitched, beds full of loose bales."""
    S.prop("rusty_pickup", (x, y, 0), a)
    if loaded:
        for i in range(3):
            for j in range(3):
                for k in range(2 if (i + j) % 2 == 0 else 1):
                    lx = PICKUP_BED[0] + (i - 1) * 3.3
                    ly = PICKUP_BED[1] + (j - 1) * 4.7
                    wx, wy = place(x, y, a, lx, ly)
                    S.bale((wx, wy, FLOOR + k * 2.6), a + math.pi / 2, 0.06, rng)
    if trailer:
        tx, ty = place(x, y, a, 0, TRAILER_OFF)
        S.prop("medium_trailer", (tx, ty, 0), a)
        if loaded:
            for i in range(2):
                for j in range(5):
                    for k in range(2 if j != 4 else 1):
                        lx = (i - 0.5) * 3.3
                        ly = TRAILER_BED + (j - 2) * 4.65
                        wx, wy = place(tx, ty, a, lx, ly)
                        S.bale((wx, wy, FLOOR + k * 2.6), a + math.pi / 2, 0.05, rng)


def backdrop(rng, ring=(170, 420), n_trees=90, pines=0.3):
    for _ in range(n_trees):
        r = rng.uniform(*ring)
        t = rng.uniform(0, 2 * math.pi)
        x, y = r * math.cos(t), r * math.sin(t)
        (S.pine if rng.random() < pines else S.tree)(x, y, rng, rng.uniform(1.0, 1.6))


# ------------------------------------------------------------------ shots

def haul(rng):
    """Thumbnail 1: the loaded pickup and trailer rolling down the meadow road at golden hour."""
    S.ground(1600, seed=2, hills=55)
    S.sky(top=(128, 160, 190), horizon=(238, 214, 170), strength=0.9)
    S.sun(elev_deg=24, azim_deg=235, energy=4.2, color=(255, 222, 180))
    S.fill(30, 0.9)
    S.road([(-30, -400), (-12, -60), (0, 0), (10, 120), (40, 400)], width=16)
    rig(-4, -6, math.radians(-4), rng)
    # meadow edge: scattered bales, fences, trees
    S.fence(-22, -70, -22, 60)
    S.fence(18, 40, 18, 120)
    for i in range(14):
        S.bale((rng.uniform(30, 120) * rng.choice((-1, 1)), rng.uniform(-60, 140), 0),
               rng.uniform(0, 3.14))
    S.prop("barn", (-80, 90, 0), math.radians(200))
    S.prop("silo_large", (-50, 108, 0))
    S.prop("silo_small", (-38, 120, 0))
    S.prop("round_bale", (20, -4, 0), 0.4)
    S.prop("round_bale", (23, 0, 0), 1.2)
    for x, y in [(55, 20), (70, 70), (-60, 20), (-110, 40), (95, -10), (40, 140), (-25, 170)]:
        S.tree(x, y, rng, rng.uniform(1.0, 1.4))
    backdrop(rng)
    S.camera((24, -44, 8.5), (-3, 6, 5.0), lens=30)


def factory(rng):
    """Thumbnail 2: the bale line, belts feeding the sorter, needles dropping into the vault."""
    S.ground(1600, seed=5, hills=45)
    S.sky(top=(134, 166, 196), horizon=(236, 220, 186), strength=0.95)
    S.sun(elev_deg=30, azim_deg=215, energy=4.0)
    concrete = S.mat("pad", (150, 144, 132), 0.95)
    S.box((84, 50, 0.3), (6, 6, 0.15), concrete, bevel=0)
    # belt line along x at y=0, tiles every 6
    for i in range(-6, 6):
        S.prop("conveyor_straight", (i * 6, 0, 0.3), math.pi / 2)
    S.prop("conveyor_sorter", (39, 0, 0.3), math.pi / 2)
    S.prop("conveyor_corner", (-39, 0, 0.3), 0)
    for i in range(1, 5):
        S.prop("conveyor_straight", (-39, -i * 6, 0.3), 0)
    for i in range(-6, 6, 2):
        S.bale((i * 6 + rng.uniform(-1, 1), 0, 3.8), rng.uniform(-0.08, 0.08))
    S.prop("needle_vault", (48, 12, 0.3), math.pi)
    S.prop("needle_tray", (44, -10, 0.3), 0.2)
    S.prop("sorter_shed", (-2, 30, 0.3), math.pi)
    S.prop("silo_large", (34, 34, 0.3))
    S.prop("silo_small", (50, 32, 0.3))
    # needles spilling at the sorter's out side and clean bales on a second belt
    for i in range(10):
        S.needle((44 + rng.uniform(-3, 3), -6 + rng.uniform(-2, 2), 0.45), rng.uniform(0, 3.14),
                 "steel" if i % 4 else "obsidian")
    S.needle((42, -7.5, 0.6), 0.6, "cosmic", scale=1.4)
    rig(-60, -18, math.radians(90), rng, trailer=False)
    S.farmer((24, -9, 0.3), math.radians(40), pose={"rarm": (1.2, 0.2), "gloves": True})
    S.prop("hay_crate", (16, -12, 0.3), 0.3)
    S.prop("wheelbarrow", (8, -14, 0.3), 2.4)
    backdrop(rng, ring=(160, 420))
    S.camera((50, -44, 19), (14, 0, 2), lens=32)


def field(rng):
    """Thumbnail 3: two farmers working a bale field with shovel and rake, straw everywhere."""
    S.ground(1600, seed=9, hills=60)
    S.sky(top=(130, 164, 196), horizon=(236, 222, 190), strength=1.0)
    S.sun(elev_deg=24, azim_deg=220, energy=4.2)
    # broken bale spill
    S.straw((4, 2, 0), 120, rng, spread=7)
    S.needle((5.5, 0.8, 0.3), 0.8, "steel", scale=1.3)
    S.needle((1.8, 4.0, 0.3), 2.1, "steel", scale=1.3)
    for _ in range(4):
        S.box((rng.uniform(1.5, 3), rng.uniform(1, 2), rng.uniform(0.6, 1.2)),
              (rng.uniform(1, 7), rng.uniform(-1, 5), 0.4), S.mat("hayclump", (189, 168, 112), 0.95),
              rot=(rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(0, 3)), bevel=0.2)
    # one farmer lifts a bale overhead, the other rakes the spill
    f1, _ = S.farmer((-4, 3, 0), 0.35, pose={"rarm": (math.pi, 0.0), "larm": (math.pi, 0.0), "gloves": True})
    lifted = S.bale((0, 0, 0), 0.0)
    lifted.parent = f1
    lifted.location = (0, 0, 6.4)
    f2, _ = S.farmer((11, 7, 0), -0.45, shirt=(92, 112, 126), pants=(96, 82, 66),
                     pose={"rarm": (-0.7, 0), "larm": (-0.7, 0)})
    rk = S.prop("garden_rake", (0, 0, 0), 0)
    rk.parent = f2
    rk.location = (0.0, -2.2, 0.0)
    rk.rotation_euler = (0.35, 0, 0)
    S.prop("basic_shovel", (6.5, 1.5, 0.0), 0.6, tilt=(0.3, 0.2))
    # field of bales in rows
    for row in range(5):
        for col in range(9):
            x = -50 + col * 12 + rng.uniform(-2, 2)
            y = 28 + row * 14 + rng.uniform(-2, 2)
            S.bale((x, y, 0), rng.uniform(-0.3, 0.3))
            if rng.random() < 0.3:
                S.bale((x, y, 2.6), rng.uniform(-0.3, 0.3))
    for x, y in [(-20, -6), (22, -4)]:
        S.bale((x, y, 0), 0.4)
    S.bale((-14, -2, 0), 1.3)
    S.prop("wheelbarrow", (16, -2, 0), 2.6)
    S.prop("pitchfork", (-15, 1, 0), 0.2, tilt=(0.25, 0))
    rig(48, 40, math.radians(-120), rng, trailer=False)
    S.prop("barn", (-70, 140, 0), math.radians(160))
    backdrop(rng, ring=(180, 420))
    S.camera((14, -26, 6), (3, 8, 2.6), lens=28)


def needles(rng):
    """Thumbnail 4: find the needle. A split bale at dusk with rare needles glowing in the straw."""
    S.ground(1600, seed=12, hills=50, color=(98, 110, 74))
    S.sky(top=(100, 110, 150), horizon=(236, 178, 128), strength=1.1)
    S.sun(elev_deg=12, azim_deg=250, energy=4.0, color=(255, 196, 146))
    S.fill(170, 0.8, (150, 160, 210))
    S.straw((0, 0, 0), 160, rng, spread=6)
    for _ in range(5):
        S.box((rng.uniform(1.5, 3), rng.uniform(1, 2), rng.uniform(0.6, 1.2)),
              (rng.uniform(-4, 4), rng.uniform(-1, 5), 0.4), S.mat("hayclump2", (219, 204, 153), 0.95),
              rot=(rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(0, 3)), bevel=0.2)
    S.bale((-6, 6, 0), 0.5)
    S.bale((-6.5, 6.3, 2.6), 0.3)
    S.bale((5, 9, 0), -0.2)
    S.needle((0.5, -1.5, 0.45), 0.5, "cosmic", tilt=-0.15, scale=1.6)
    S.needle((-2.8, 0.8, 0.35), 2.3, "cloud", scale=1.2)
    S.needle((3, 1.6, 0.35), 1.2, "obsidian", scale=1.2)
    S.needle((1.6, 3.6, 0.3), 2.8, "steel", scale=1.2)
    S.prop("starlight_gloves", (-3.6, -3.2, 0.05), 0.9)
    S.prop("garden_rake", (4.2, -2.4, 0.15), 1.9, tilt=(math.pi / 2, 0))
    S.prop("hay_crate", (9, 3, 0), 0.4)
    bpy = S.bpy
    bpy.ops.object.light_add(type="POINT", location=(-8, -10, 8))
    bpy.context.active_object.data.energy = 600
    bpy.context.active_object.data.color = S.srgb(255, 200, 150)
    for x, y in [(-30, 30), (25, 40), (-12, 60)]:
        S.tree(x, y, rng)
    backdrop(rng, ring=(120, 400))
    S.camera((2, -15, 7.5), (0.4, 1.0, 0.4), lens=35)


def icon(rng):
    """512 game icon: one bale with a glowing needle stuck in it, close and bold."""
    S.ground(400, seed=3, color=(104, 122, 78))
    S.sky(top=(126, 160, 194), horizon=(236, 216, 176), strength=1.0)
    S.sun(elev_deg=34, azim_deg=225, energy=4.4)
    S.bale((0, 0, 0), 0.0)
    S.straw((0, 0, 0), 40, rng, spread=4.5)
    S.needle((0.9, -0.5, 2.85), 0.45, "cosmic", tilt=-0.6, scale=1.9)
    S.camera((4.4, -6.2, 3.3), (0.2, 0, 1.8), lens=40)


def loading(rng):
    """Loading screen: the base at sunrise, wide and calm, room at the bottom for the bar."""
    S.ground(1600, seed=21, hills=70)
    S.sky(top=(150, 170, 196), horizon=(244, 214, 172), strength=1.0)
    S.sun(elev_deg=10, azim_deg=110, energy=3.8, color=(255, 214, 170))
    S.road([(-400, 30), (-60, 22), (0, 14), (80, 18), (400, 40)], width=14)
    S.prop("barn", (-34, 60, 0), math.radians(185))
    S.prop("silo_large", (-6, 70, 0))
    S.prop("silo_small", (6, 74, 0))
    S.prop("sorter_shed", (30, 58, 0), math.radians(170))
    for i in range(6):
        S.prop("conveyor_straight", (14 + i * 6, 40, 0), math.pi / 2)
    rig(-14, 4, math.radians(90), rng)
    S.fence(-80, -4, 70, -4)
    for i in range(18):
        S.bale((rng.uniform(-110, 110), rng.uniform(-60, -12), 0), rng.uniform(0, 3.14))
    for x, y in [(-70, 50), (-90, 80), (60, 80), (80, 50), (-120, 20), (110, 30)]:
        S.tree(x, y, rng, 1.3)
    backdrop(rng, ring=(150, 450), n_trees=120)
    S.camera((10, -80, 14), (0, 30, 8), lens=30)


SHOTS = {
    "haul": (haul, (1920, 1080)),
    "factory": (factory, (1920, 1080)),
    "field": (field, (1920, 1080)),
    "needles": (needles, (1920, 1080)),
    "icon": (icon, (1024, 1024)),
    "loading": (loading, (1920, 1080)),
}

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=",".join(SHOTS))
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--samples", type=int, default=128)
    a = ap.parse_args(argv)
    os.makedirs(OUT, exist_ok=True)
    for name in a.only.split(","):
        fn, res = SHOTS[name]
        S.reset()
        fn(random.Random(7))
        S.render(os.path.join(OUT, name + ".png"), res, samples=a.samples, preview=a.preview)

"""Hero thumbnails: R15 avatars large in the foreground, mid-action, with the scene behind (Cyrus 2026-10-13:
"more r15 style with a character"). Run: python blender/launch/shots4.py -- --only hero_haul --preview
"""
import argparse
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scene as S  # noqa: E402
import shots  # noqa: E402
import shots2  # noqa: E402
import shots3  # noqa: E402
from avatar import R15  # noqa: E402

bpy = S.bpy
OUT = os.environ.get("LAUNCH_OUT", shots.OUT)


def key_light(loc, energy=900, rgb=(255, 236, 214), size=4):
    """A soft area light on the hero's face, the way thumbnail art lights its character."""
    bpy.ops.object.light_add(type="AREA", location=loc)
    l = bpy.context.active_object
    l.data.energy = energy
    l.data.size = size
    l.data.color = S.srgb(*rgb)
    target = mathutils_vec((0, 0, 3))
    return l


def mathutils_vec(v):
    import mathutils
    return mathutils.Vector(v)


def aim(obj, target):
    import mathutils
    d = mathutils.Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def soft_key(loc, target, energy=900, rgb=(255, 236, 214), size=5):
    bpy.ops.object.light_add(type="AREA", location=loc)
    l = bpy.context.active_object
    l.data.energy = energy
    l.data.size = size
    l.data.color = S.srgb(*rgb)
    aim(l, target)
    return l


def meadow(rng, seed=2, hills=55, sky=((120, 158, 200), (240, 218, 180)), sun=(22, 235, 4.2)):
    S.ground(1600, seed=seed, hills=hills)
    S.sky(top=sky[0], horizon=sky[1], strength=1.0)
    S.sun(elev_deg=sun[0], azim_deg=sun[1], energy=sun[2], color=(255, 228, 190))
    S.fill(40, 0.7)


# ------------------------------------------------------------------ shots

def hero_haul(rng):
    """A farmer hoists a bale overhead beside the loaded pickup and trailer."""
    meadow(rng)
    S.road([(-30, -400), (-12, -60), (0, 0), (10, 120), (40, 400)], width=16)
    shots.rig(4, 14, math.radians(-8), rng)
    S.prop("barn", (-70, 110, 0), math.radians(200))
    S.prop("silo_large", (-40, 128, 0))
    shots.backdrop(rng)
    a = R15("farmer", "grin").pose(
        l_shoulder=(-172, -24, 0), r_shoulder=(-172, 24, 0), l_elbow=(-20, 0, 0), r_elbow=(-20, 0, 0),
        neck=(-14, 0, 0), l_hip=(-10, 6, 0), r_hip=(8, -6, 0), l_knee=(15, 0, 0)).place((-6.5, -9, 0), 25)
    b = S.bale((0, 0, 0), 0.0)
    b.parent = a.j["waist"]
    b.location = (0, -0.3, 4.15)
    for i in range(2):
        S.bale((-11 + i * 1.5, -5 + i, 0), 0.3 + i * 0.2)
    k = R15("kid", "grin").pose(r_shoulder=(-165, 35, 0), r_elbow=(-30, 0, 0), l_shoulder=(10, 12, 0)).place((8.5, -2, 0), -30)
    soft_key((-2, -22, 9), (-6, -9, 5), 1200)
    S.camera((2, -24, 3.2), (-1.5, 0, 4.4), lens=26)


def hero_needle(rng):
    """Close-up: a player holds up a glowing cosmic needle, wide-eyed, straw flying."""
    meadow(rng, seed=12, sky=((96, 110, 160), (240, 186, 140)), sun=(10, 250, 3.6))
    S.straw((1, 3, 0), 140, rng, spread=7)
    for _ in range(70):
        S.box((rng.uniform(0.5, 0.9), 0.08, 0.08), (rng.uniform(-6, 7), rng.uniform(0.5, 6), rng.uniform(1, 8)),
              S.mat("straw1", (189, 168, 112), 0.9), rot=(rng.uniform(0, 3), rng.uniform(0, 3), rng.uniform(0, 3)), bevel=0)
    S.bale((-7, 8, 0), 0.4)
    S.bale((6, 9, 0), -0.3)
    S.bale((6.3, 9, 2.6), -0.1)
    a = R15("girl", "wow").pose(
        r_shoulder=(-160, 38, 0), r_elbow=(-25, 0, 0), l_shoulder=(-30, 30, 0), l_elbow=(-60, 0, 0),
        neck=(-12, 0, 0)).place((-0.6, 0, 0), 10)
    n = S.needle((0, 0, 0), 0.0, "cosmic", scale=2.6)
    a.hold(n, "r", offset=(0, 0, -0.75), rot=(0, 70, 0))
    soft_key((3, -10, 8), (0, 0, 5), 1100, (210, 220, 255))
    shots.backdrop(rng, ring=(100, 400))
    S.camera((1.0, -10.5, 4.6), (0.4, 0, 5.6), lens=28)


def hero_golden(rng):
    """Two players race for a golden bale; the front one dives for it."""
    meadow(rng, seed=51, sky=((116, 146, 186), (244, 206, 150)), sun=(12, 250, 3.6))
    for row in range(4):
        for col in range(7):
            x, y = -30 + col * 10 + rng.uniform(-1.5, 1.5), 14 + row * 10 + rng.uniform(-1.5, 1.5)
            S.bale((x, y, 0), rng.uniform(-0.3, 0.3))
    shots3.golden_bale((4.5, 0, 0), 0.5)
    bpy.ops.object.light_add(type="POINT", location=(4.5, -1.5, 4))
    bpy.context.active_object.data.energy = 600
    bpy.context.active_object.data.color = S.srgb(255, 200, 90)
    a = R15("farmer", "wow").pose(
        root=(18, 0, 0), r_shoulder=(-95, 10, 0), r_elbow=(-10, 0, 0), l_shoulder=(55, -10, 0), l_elbow=(-60, 0, 0),
        l_hip=(-55, 0, 0), l_knee=(60, 0, 0), r_hip=(35, 0, 0), r_knee=(70, 0, 0), neck=(-22, 0, 0)).place((-3.2, -4.5, 0.5), 62)
    k = R15("kid", "determined").pose(
        root=(15, 0, 0), l_shoulder=(-70, 0, 0), r_shoulder=(50, 0, 0), l_elbow=(-50, 0, 0), r_elbow=(-60, 0, 0),
        l_hip=(35, 0, 0), l_knee=(60, 0, 0), r_hip=(-50, 0, 0), r_knee=(40, 0, 0), neck=(-15, 0, 0)).place((-11, 3, 0.4), 70, 0.95)
    soft_key((-2, -16, 8), (-3, -4, 3), 900)
    shots.backdrop(rng)
    S.camera((1, -16, 3.2), (0, 0, 3.4), lens=27)


def hero_smash(rng):
    """Mid-swing: the shovel comes down and the bale bursts into straw, a needle flying out."""
    meadow(rng, seed=41)
    cols = [(219, 204, 153), (189, 168, 112), (168, 149, 95), (133, 115, 71)]
    for i in range(200):
        r = 6 * rng.random() ** 0.7
        a = rng.uniform(0, 6.28)
        z = 0.5 + rng.random() ** 1.3 * 8 * (1 - r / 8)
        S.box((rng.uniform(0.5, 1.0), 0.09, 0.09), (3 + r * math.cos(a), 3 + r * math.sin(a), z),
              S.mat("straw%d" % (i % 4), cols[i % 4], 0.9), rot=(rng.uniform(0, 3), rng.uniform(0, 3), rng.uniform(0, 3)), bevel=0)
    for _ in range(5):
        S.box((rng.uniform(1.4, 2.4), rng.uniform(1, 1.8), rng.uniform(0.8, 1.2)), (3 + rng.uniform(-2, 2), 3 + rng.uniform(-2, 2), rng.uniform(0.5, 3)),
              S.mat("hayclump2", (219, 204, 153), 0.95), rot=(rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(0, 3)), bevel=0.25)
    S.needle((4, 1.5, 6.0), 0.4, "steel", tilt=0.6, scale=1.8)
    bpy.ops.object.light_add(type="POINT", location=(4, 1.2, 6.2))
    bpy.context.active_object.data.energy = 150
    a = R15("farmer", "determined").pose(
        r_shoulder=(-75, -15, 0), r_elbow=(-5, 0, 0), l_shoulder=(-80, 15, 0), l_elbow=(-15, 0, 0),
        root=(14, 0, 0), l_hip=(-35, 0, 0), l_knee=(40, 0, 0), r_hip=(20, 0, 0), neck=(-20, 0, 0)).place((-2.2, -0.6, 0), 62)
    sh = S.prop("basic_shovel", (0, 0, 0), 0, scale=1.6)
    a.hold(sh, "r", offset=(0, 0, -0.35 - 3.6), rot=(0, 0, 0))
    S.bale((-12, 10, 0), 0.4)
    S.bale((-12, 10, 2.6), 0.2)
    soft_key((-4, -14, 8), (-2, -1, 4), 900)
    shots.backdrop(rng, ring=(100, 400))
    S.camera((2, -14, 3.6), (0.5, 1, 3.6), lens=26)


def hero_factory(rng):
    """A proud farm owner, hands on hips, in front of a full bale line."""
    S.ground(1600, seed=5, hills=45)
    S.sky(top=(126, 162, 200), horizon=(240, 222, 188), strength=1.0)
    S.sun(elev_deg=30, azim_deg=215, energy=4.0)
    S.fill(40, 0.6)
    S.box((84, 50, 0.3), (6, 14, 0.15), S.mat("pad", (150, 144, 132), 0.95), bevel=0)
    for i in range(-6, 6):
        S.prop("conveyor_straight", (i * 6, 10, 0.3), math.pi / 2)
    S.prop("conveyor_sorter", (39, 10, 0.3), math.pi / 2)
    for i in range(-6, 6, 2):
        S.bale((i * 6 + rng.uniform(-1, 1), 10, 3.8), rng.uniform(-0.08, 0.08))
    for i in range(12):
        S.needle((42 + rng.uniform(-3, 3), 3 + rng.uniform(-2, 2), 0.45 + rng.uniform(0, 4)), rng.uniform(0, 3.14),
                 "steel" if i % 4 else "obsidian", tilt=rng.uniform(-1, 1))
    S.prop("sorter_shed", (-2, 40, 0.3), math.pi)
    S.prop("silo_large", (30, 44, 0.3))
    S.prop("silo_small", (46, 42, 0.3))
    a = R15("rancher", "grin").pose(
        r_shoulder=(-165, 32, 0), r_elbow=(-20, 0, 0), l_shoulder=(-35, 14, 0), l_elbow=(-85, 0, 0),
        neck=(-6, 0, 0), l_hip=(0, 6, 0), r_hip=(0, -6, 0)).place((-1.5, -5, 0.3), 14)
    S.prop("hay_crate", (4, 0, 0.3), 0.3)
    soft_key((0, -16, 9), (-1.5, -5, 4), 900)
    shots.backdrop(rng)
    S.camera((3, -17, 3.6), (4, 4, 5.6), lens=26)


def hero_spindle(rng):
    """A player in starlight gear lifts a glowing shard before the Spindle's sealed door."""
    S.ground(1600, seed=61, hills=70, color=(118, 128, 96))
    S.sky(top=(70, 84, 140), horizon=(236, 180, 150), strength=0.8)
    S.sun(elev_deg=10, azim_deg=245, energy=3.0, color=(255, 200, 160))
    S.fill(60, 0.6, (160, 170, 230))
    shots3.spire(0, 70, 34, 210)
    frame = S.mat("door_frame", (150, 142, 160), 0.95)
    S.box((20, 4, 26), (0, 36.5, 12.5), frame, bevel=0.3)
    S.box((14, 1, 20), (0, 34.3, 10.5), S.mat("door", (96, 86, 120), 0.9), bevel=0.1)
    lit = S.mat("socket_lit", (242, 183, 5), 0.4, 0, 8.0)
    dim = S.mat("socket_dim", (120, 100, 50), 0.6)
    for i in range(12):
        a = i / 12 * math.pi * 2
        S.cyl(0.55, 0.6, (math.cos(a) * 5, 33.7, 12.5 + math.sin(a) * 5), lit if i not in (3, 7, 10) else dim, verts=10,
              rot=(math.pi / 2, 0, 0))
    bpy.ops.object.light_add(type="POINT", location=(0, 30, 12.5))
    bpy.context.active_object.data.energy = 2500
    bpy.context.active_object.data.color = S.srgb(255, 200, 90)
    S.road([(0, -80), (0, 32)], width=7)
    a = R15("starlight", "determined").pose(
        r_shoulder=(-165, 30, 0), r_elbow=(-10, 0, 0), l_shoulder=(10, 12, 0), neck=(-12, 0, 0)).place((-3.5, 0, 0), -20)
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.4, depth=2.2)
    shard = bpy.context.active_object
    shard.data.materials.append(S.mat("shard", (255, 200, 70), 0.3, 0, 3.0))
    a.hold(shard, "r", offset=(0, 0, -1.2))
    bpy.ops.object.light_add(type="POINT", location=(-2, -1, 9))
    bpy.context.active_object.data.energy = 300
    bpy.context.active_object.data.color = S.srgb(255, 210, 120)
    for x, y in [(-30, 30), (28, 24), (-24, 0), (40, 50)]:
        S.pine(x, y, rng, 1.2)
    shots.backdrop(rng, ring=(140, 420), pines=0.7)
    soft_key((2, -12, 7), (-3.5, 0, 4.5), 1600, (230, 222, 255))
    S.camera((3, -11, 2.6), (0, 20, 11), lens=24)


def hero_wagon(rng):
    """Riders wave from the free Hay Wagon, close up."""
    meadow(rng, seed=71)
    S.road([(-10, -400), (-4, -60), (0, 0), (10, 80), (40, 400)], width=14)
    # the wagon without its own little riders, then R15 riders on its seats
    root = shots3.wagon((0, 4, 0), math.radians(10), rng)
    doomed = set()
    for o in bpy.context.scene.objects:
        if o.name.startswith("farmer"):
            doomed.add(o.name)
            doomed.update(c.name for c in o.children_recursive)
    for n in doomed:
        bpy.data.objects.remove(bpy.data.objects[n], do_unlink=True)
    yaw = 10 + 180
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    looks = [("farmer", "grin"), ("girl", "grin"), ("kid", "wow"), ("rancher", "grin")]
    seats = [(-2.6, 2), (2.6, 2), (-2.6, -2), (2.6, -2)]
    for i, ((lx, ly), (outfit, face)) in enumerate(zip(seats, looks)):
        wx, wy = 0 + lx * c - ly * s, 4 + lx * s + ly * c
        wave = {"r_shoulder": (-165, 0, 25), "r_elbow": (-25, 0, 0)} if i % 2 == 0 else {"l_shoulder": (-165, 0, -25), "l_elbow": (-25, 0, 0)}
        R15(outfit, face).pose(l_hip=(-90, 0, 0), r_hip=(-90, 0, 0), l_knee=(90, 0, 0), r_knee=(90, 0, 0), **wave).place(
            (wx, wy, 1.4), -68 + (12 if ly > 0 else -8), 0.85)
    R15("rancher", "grin").pose(l_hip=(-90, 0, 0), r_hip=(-90, 0, 0), l_knee=(90, 0, 0), r_knee=(90, 0, 0),
                                l_shoulder=(-60, 0, 0), r_shoulder=(-60, 0, 0)).place((0 - (7.5) * s, 4 + 7.5 * c, 2.8), -40, 0.85)
    shots3.spire(-160, 520, 40, 260)
    S.zeppelin((80, 260, 90), math.radians(140), 1.2)
    shots.backdrop(rng)
    S.camera((-17, -3, 5.0), (0, 3, 3.6), lens=28)


def icon_hero(rng):
    """Icon: a grinning farmer's face, a glowing needle held up beside it."""
    meadow(rng, seed=12, sky=((96, 150, 220), (250, 214, 150)), sun=(18, 230, 4.0))
    a = R15("farmer", "grin").pose(r_shoulder=(-160, 38, 0), r_elbow=(-25, 0, 0), neck=(-6, 0, 6)).place((0, 0, 0), 8)
    n = S.needle((0, 0, 0), 0.0, "cosmic", scale=2.2)
    a.hold(n, "r", offset=(0, 0, -0.75), rot=(0, 70, 0))
    S.bale((-5, 7, 0), 0.4)
    S.bale((4, 8, 0), -0.3)
    soft_key((1, -9, 8), (0, 0, 6), 1000)
    S.camera((0.7, -6.4, 6.0), (0.7, 0, 5.9), lens=30)


def icon_hero_golden(rng):
    """Icon: a wide-eyed player hugging a golden bale."""
    meadow(rng, seed=51, sky=((110, 150, 210), (250, 210, 140)), sun=(18, 230, 4.0))
    b = shots3.golden_bale((-2.6, -0.4, 0), 0.25)
    a = R15("girl", "wow").pose(l_shoulder=(-95, 0, -45), l_elbow=(-10, 0, 0), r_shoulder=(-150, 34, 0), r_elbow=(-30, 0, 0),
                                neck=(-6, 0, 0)).place((1.6, -0.6, 0), -12)
    bpy.ops.object.light_add(type="POINT", location=(-2.6, -2.5, 4))
    bpy.context.active_object.data.energy = 400
    bpy.context.active_object.data.color = S.srgb(255, 200, 90)
    soft_key((1, -10, 8), (0, -1, 4), 900)
    S.camera((0.2, -9.5, 4.4), (0, 0, 3.9), lens=30)


SHOTS = {
    "icon_hero": icon_hero, "icon_hero_golden": icon_hero_golden,
    "hero_haul": hero_haul, "hero_needle": hero_needle, "hero_golden": hero_golden, "hero_smash": hero_smash,
    "hero_factory": hero_factory, "hero_spindle": hero_spindle, "hero_wagon": hero_wagon,
}

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=",".join(SHOTS))
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--samples", type=int, default=96)
    ap.add_argument("--res", default="1920x1080")
    a = ap.parse_args(argv)
    os.makedirs(OUT, exist_ok=True)
    res = tuple(int(v) for v in a.res.split("x"))
    for name in a.only.split(","):
        S.reset()
        S.set_season_default()
        SHOTS[name](random.Random(7))
        S.render(os.path.join(OUT, name + ".png"), res, samples=a.samples, preview=a.preview)

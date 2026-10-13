"""Second batch of launch art: the wider world, seasonal events, icon variants and Robux store items.

Run: python blender/launch/shots2.py -- --only ferry,regions --preview
Same kit and output folder as shots.py; finish2.py titles them.
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
FERRY = 1.7  # the cargo barge scaled up to ferry size (a pickup and its trailer fit end to end)


# ------------------------------------------------------------------ world thumbnails

def ferry(rng):
    """The ferry crossing with a loaded rig on deck, the zeppelin overhead and Sky Island beyond."""
    S.sky(top=(126, 164, 204), horizon=(236, 222, 196), strength=1.0)
    S.sun(elev_deg=26, azim_deg=230, energy=4.2)
    S.fill(40, 0.6)
    S.sea()
    # home harbour on the left, Desert Dunes island far right
    S.island(-150, 60, 120, 140, (112, 128, 82), z_top=2.0, seed=1)
    S.prop("harbor_dock", (-44, 40, 0.2), math.radians(90))
    for x, y in [(-120, 40), (-140, 100), (-100, 120), (-160, 0), (-90, 80)]:
        S.tree(x, y, rng, 1.3, z=1.5)
    S.prop("barn", (-110, -20, 1.5), math.radians(80))
    S.island(260, 340, 170, 120, (194, 168, 125), z_top=3.0, seed=2, beach=(220, 200, 160))
    for _ in range(14):
        S.region_tree("cactus", 260 + rng.uniform(-120, 120), 340 + rng.uniform(-70, 60), rng, 1.6, z=2.5)
    S.island(-60, 520, 200, 110, (84, 99, 66), z_top=3.0, seed=3)
    for _ in range(30):
        S.region_tree("pine", -60 + rng.uniform(-170, 170), 520 + rng.uniform(-70, 80), rng, 1.5, z=2.5)
    # the ferry: barge scaled up, rig parked on deck
    a = math.radians(-12)
    S.prop("cargo_barge", (18, 30, -1.6), a, scale=FERRY)
    deck = 3.66 * FERRY - 1.6 - 0.2
    x0, y0 = shots.place(18, 30, a, 0, -17)
    root = bpy.data.objects.new("rig", None)
    bpy.context.scene.collection.objects.link(root)
    before = set(bpy.context.scene.objects)
    shots.rig(x0, y0, a, rng)
    for o in bpy.context.scene.objects:
        if o not in before and o.parent is None:
            o.location.z += deck
    # wake behind the ferry
    foam = S.mat("foam", (230, 236, 236), 0.6)
    for i in range(30):
        wx, wy = shots.place(18, 30, a, rng.uniform(-8, 8) + (i % 2) * 6 - 3, 34 + i * 2.2)
        S.box((rng.uniform(1, 3), rng.uniform(1, 2.5), 0.15), (wx, wy, -0.5), foam, rot=(0, 0, rng.uniform(0, 3)), bevel=0)
    S.prop("sailboat", (78, -30, -0.8), 0.5)
    S.prop("rowboat", (-20, -40, -0.6), 2.0)
    S.zeppelin((30, 150, 62), math.radians(160), 1.1)
    S.sky_island(190, 520, 120, 50, rng)
    S.camera((92, -110, 30), (20, 60, 22), lens=30)


def regions(rng, which="pine", seed=0):
    """One panel of the regions collage: a bale stack in front of that region's trees and ground."""
    R = S.REGIONS[which]
    S.ground(1000, seed=seed + 4, hills=60, color=R["ground"])
    S.sky(top=R["sky"][0], horizon=R["sky"][1], strength=1.0)
    S.sun(elev_deg=28, azim_deg=225, energy=4.0)
    S.fill(30, 0.5)
    for i, (x, y, z, r) in enumerate([(-2.4, 0, 0, 0.05), (2.4, 0.2, 0, -0.05), (0, 0.1, 2.6, 0.08)]):
        S.paint(S.bale((x, y, z), r), {"rustic_hay": R["hay"]})
    S.straw((6, -3, 0), 30, rng, spread=3)
    for _ in range(26):
        S.region_tree(R["trees"], rng.uniform(-60, 60), rng.uniform(16, 90), rng, rng.uniform(1.0, 1.5),
                      leaves=R["leaves"] if which == "haunted" else None)
    if which == "desert":
        rock = S.mat("rock", (210, 196, 170), 0.95)
        for _ in range(8):
            S.box((rng.uniform(2, 5), rng.uniform(2, 5), rng.uniform(1, 3)), (rng.uniform(-30, 30), rng.uniform(8, 40), 0.6),
                  rock, rot=(0, 0, rng.uniform(0, 3)), bevel=0.4)
    if which == "swamp":
        water = S.mat("bog", (60, 70, 52), 0.2)
        for _ in range(6):
            o = S.cyl(rng.uniform(4, 9), 0.1, (rng.uniform(-30, 30), rng.uniform(6, 40), 0.06), water, verts=14)
        for _ in range(16):
            S.box((0.3, 0.3, 0.3), (rng.uniform(-14, 14), rng.uniform(4, 30), rng.uniform(2, 6)),
                  S.mat("firefly", (200, 230, 120), 0.5, 0, 12.0), bevel=0)
    if which == "snow":
        stone = S.mat("stone", (150, 150, 146), 0.95)
        for _ in range(6):
            S.box((rng.uniform(3, 7), rng.uniform(3, 7), 0.5), (rng.uniform(-30, 30), rng.uniform(6, 40), 0.1),
                  stone, rot=(0, 0, rng.uniform(0, 3)), bevel=0.2)
    if which == "volcano":
        lava = S.mat("lava", (255, 120, 40), 0.6, 0, 5.0)
        for _ in range(10):
            S.box((rng.uniform(4, 12), rng.uniform(0.4, 0.9), 0.08), (rng.uniform(-30, 30), rng.uniform(6, 50), 0.05), lava,
                  rot=(0, 0, rng.uniform(0, 3)), bevel=0)
        bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=60, depth=70, location=(10, 200, 35))
        bpy.context.active_object.data.materials.append(S.mat("peak_v", (60, 52, 50), 0.95))
        S.cyl(9, 2, (10, 200, 70), lava, verts=10)
    if which == "haunted":
        for _ in range(12):
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=rng.uniform(0.3, 0.6),
                                                  location=(rng.uniform(-14, 14), rng.uniform(4, 30), rng.uniform(1.5, 6)))
            bpy.context.active_object.data.materials.append(S.mat("wisp", (170, 160, 240), 0.5, 0, 10.0))
        S.fill(200, 1.2, (150, 140, 220))
    if which == "sky":
        cloud = S.mat("cloud", (246, 246, 250), 0.9)
        for _ in range(14):
            S.box((rng.uniform(10, 24), rng.uniform(6, 12), rng.uniform(3, 6)),
                  (rng.uniform(-90, 90), rng.uniform(60, 160), rng.uniform(-6, 30)), cloud, bevel=1.0)
    S.needle((5, -2.6, 0.3), 0.7, {"pine": "steel", "desert": "steel", "snow": "cloud", "swamp": "obsidian",
                                     "volcano": "obsidian", "haunted": "cloud", "sky": "cosmic"}.get(which, "steel"), scale=1.3)
    S.camera((7, -13, 4.5), (0, 6, 2.6), lens=28)


def rich(rng):
    """The rich field: a gold beam over a hay field, trucks racing in."""
    S.ground(1600, seed=31, hills=50)
    S.sky(top=(120, 150, 186), horizon=(240, 206, 160), strength=0.9)
    S.sun(elev_deg=14, azim_deg=250, energy=3.6, color=(255, 214, 170))
    S.fill(60, 0.5)
    for row in range(6):
        for col in range(8):
            S.bale((-35 + col * 10 + rng.uniform(-1, 1), 10 + row * 9 + rng.uniform(-1, 1), 0), rng.uniform(-0.2, 0.2))
    S.beam((0, 32, 0), h=260, r=3.5, strength=2.5)
    for _ in range(14):
        S.needle((rng.uniform(-10, 10), 32 + rng.uniform(-8, 8), rng.uniform(4, 30)), rng.uniform(0, 6),
                 "steel", tilt=rng.uniform(-1, 1), scale=1.4)
    S.road([(-400, -20), (0, -16), (400, -26)], width=14)
    shots.rig(-40, -18, math.radians(90), rng, loaded=False)
    S.prop("farm_flatbed", (34, -20, 0), math.radians(-90))
    S.farmer((12, -4, 0), 0.6, pose={"rarm": (math.pi * 0.9, 0.3), "larm": (0, 0)})
    shots.backdrop(rng)
    S.camera((16, -50, 9), (0, 26, 12), lens=30)


def burst(rng):
    """The bale burst: a shovel hit throws straw and a glinting needle into the air."""
    S.ground(800, seed=41)
    S.sky(top=(128, 164, 200), horizon=(236, 220, 186), strength=1.0)
    S.sun(elev_deg=30, azim_deg=220, energy=4.4)
    S.fill(40, 0.5)
    cols = [(219, 204, 153), (189, 168, 112), (168, 149, 95), (133, 115, 71)]
    for i in range(240):
        r = 7 * rng.random() ** 0.7
        a = rng.uniform(0, 6.28)
        z = 0.6 + rng.random() ** 1.3 * 9 * (1 - r / 9)
        S.box((rng.uniform(0.9, 1.5), 0.22, 0.22), (r * math.cos(a), r * math.sin(a), z),
              S.mat("straw%d" % (i % 4), cols[i % 4], 0.9), rot=(rng.uniform(0, 3), rng.uniform(0, 3), rng.uniform(0, 3)), bevel=0)
    for _ in range(6):
        S.box((rng.uniform(1.4, 2.4), rng.uniform(1, 1.8), rng.uniform(0.8, 1.2)),
              (rng.uniform(-3, 3), rng.uniform(-2, 2), rng.uniform(0.5, 3.5)), S.mat("hayclump2", (219, 204, 153), 0.95),
              rot=(rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(0, 3)), bevel=0.25)
    S.needle((0.5, -1.0, 6.5), 0.4, "steel", tilt=0.6, scale=1.8)
    S.needle((-2.4, 0.4, 4.2), 2.2, "steel", tilt=-0.4, scale=1.4)
    bpy.ops.object.light_add(type="POINT", location=(0.5, -1.4, 6.6))
    bpy.context.active_object.data.energy = 120
    f, arms = S.farmer((-5, -5, 0), 0.7, pose={"rarm": (-1.2, 0.0), "larm": (-1.0, 0.0), "gloves": True})
    sh = S.prop("basic_shovel", (0, 0, 0), 0)
    sh.parent = arms["rarm"]
    sh.location = (0, 0, -2.0)
    sh.rotation_euler = (math.radians(-90), 0, 0)
    S.bale((-14, 8, 0), 0.4)
    S.bale((-14, 8, 2.6), 0.2)
    S.bale((12, 10, 0), -0.3)
    for x, y in [(-30, 40), (30, 50), (5, 70)]:
        S.tree(x, y, rng, 1.2)
    shots.backdrop(rng, ring=(120, 400))
    S.camera((10, -21, 4.5), (-0.5, 0, 4.0), lens=30)


def worldmap(rng):
    """The Stitched Isles as a tilted diorama: every region its own patch of ground on one sea."""
    S.sky(top=(140, 176, 210), horizon=(226, 230, 228), strength=1.0)
    S.sun(elev_deg=40, azim_deg=210, energy=4.0)
    S.fill(30, 0.5)
    S.sea(rgb=(56, 100, 128))
    # (x, y, rx, ry, region) in diorama units, north = +y; laid out like the world map preview
    isles = [
        (0, -60, 160, 70, "meadow"), (-150, -10, 90, 90, "pine"), (-160, 120, 80, 60, "haunted"),
        (-120, 220, 80, 70, "snow"), (0, 140, 100, 80, "meadow"), (130, 200, 80, 70, "volcano"),
        (150, 60, 90, 80, "desert"), (120, -60, 80, 60, "swamp"), (360, -10, 50, 40, "pine"),
        (370, 230, 40, 34, "snow"),
    ]
    for i, (x, y, rx, ry, reg) in enumerate(isles):
        R = S.REGIONS[reg]
        S.island(x, y, rx, ry, R["ground"], z_top=3 + i * 0.05, seed=i)
        for _ in range(int(rx * ry / 500)):
            a = rng.uniform(0, 6.28)
            d = math.sqrt(rng.random()) * 0.85
            S.region_tree(R["trees"], x + math.cos(a) * rx * d, y + math.sin(a) * ry * d, rng, 1.2, z=2.6,
                          leaves=R["leaves"])
    # the snow peak, the volcano and the Spindle
    for (x, y, r, h, rgb) in [(-120, 220, 55, 70, (236, 238, 242)), (130, 200, 50, 55, (70, 60, 56)),
                              (-10, 40, 22, 90, (190, 186, 176))]:
        bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=r, depth=h, location=(x, y, 3 + h / 2))
        c = bpy.context.active_object
        c.data.materials.append(S.mat("peak_%d" % rgb[0], rgb, 0.95))
    S.cyl(8, 2, (130, 200, 58), S.mat("lava", (255, 120, 40), 0.6, 0, 6.0), verts=10)
    S.cyl(30, 0.3, (40, 110, 3.2), S.mat("lake", (90, 140, 170), 0.2), verts=20)
    # the Longstitch highway to Thimble Keys and the ferry lane to Bobbin Rock
    S.road([(80, -40), (200, -30), (310, -10)], width=8, base=3.2)
    S.prop("cargo_barge", (300, 120, -0.8), 0.3, scale=2.0)
    S.zeppelin((60, 30, 110), 0.6, 1.6)
    S.sky_island(-250, 300, 120, 34, rng)
    S.beam((-40, -60, 3), h=160, r=4)
    S.camera((60, -440, 340), (30, 90, 10), lens=33)


# ------------------------------------------------------------------ seasonal and event versions

def seasonal(rng, season):
    s = S.set_season(season)
    S.ground(1600, seed=2, hills=55)
    S.sky(top=s["sky"][0], horizon=s["sky"][1], strength=0.9 if season != "halloween" else 0.7)
    if season == "halloween":
        S.sun(elev_deg=24, azim_deg=235, energy=2.2, color=s["sun"])
    else:
        S.sun(elev_deg=20, azim_deg=235, energy=4.0, color=s["sun"])
    S.fill(30, 0.8 if season != "halloween" else 0.7, (200, 214, 235) if season != "halloween" else (150, 140, 220))
    S.road([(-30, -400), (-12, -60), (0, 0), (10, 120), (40, 400)], width=16,
           m=S.mat("snowroad", (196, 192, 186), 0.95) if season == "winter" else None)
    shots.rig(-4, -6, math.radians(-4), rng)
    S.prop("barn", (-80, 90, 0), math.radians(200))
    S.prop("silo_large", (-50, 108, 0))
    S.prop("silo_small", (-38, 120, 0))
    S.fence(-22, -70, -22, 60)
    for x, y in [(55, 20), (70, 70), (-60, 20), (-110, 40), (95, -10), (40, 140), (-25, 170)]:
        S.tree(x, y, rng, rng.uniform(1.0, 1.4))
    shots.backdrop(rng)
    if season == "winter":
        snow = S.mat("snowcap2", (236, 240, 244), 0.9)
        for o in [o for o in bpy.context.scene.objects if o.name.startswith("hay_bale")]:
            S.box((4.7, 3.3, 0.4), (o.location.x, o.location.y, o.location.z + 2.8), snow, rot=o.rotation_euler, bevel=0.15)
        string_pts = [(-24, -60), (-24, -30), (-24, 0), (-24, 30), (-24, 60)]
        S.string_lights(string_pts, (255, 214, 150), 2.5, z=5)
        for i in range(6):
            S.box((1.3, 1.3, 1.3), (20 + i * 1.8, -6 + (i % 2) * 1.5, 0.65),
                  S.mat("gift%d" % (i % 3), [(133, 61, 48), (61, 102, 94), (200, 170, 90)][i % 3], 0.8), bevel=0.1)
        for _ in range(400):
            S.box((0.15, 0.15, 0.15), (rng.uniform(-40, 60), rng.uniform(-50, 80), rng.uniform(1, 40)),
                  S.mat("flake", (250, 250, 255), 0.5, 0, 1.0), bevel=0)
    if season == "harvest":
        for i in range(10):
            S.pumpkin((16 + rng.uniform(0, 14), -20 + rng.uniform(-8, 12), 0), rng.uniform(0.9, 1.4))
        S.prop("round_bale", (20, -4, 0), 0.4)
        for i in range(30):
            S.box((0.6, 0.6, 0.05), (rng.uniform(-30, 30), rng.uniform(-40, 30), 0.1),
                  S.mat("leafdrop%d" % (i % 3), S.LEAF[i % 3], 0.95), rot=(0, 0, rng.uniform(0, 3)), bevel=0)
    if season == "halloween":
        for i in range(8):
            x, y = 16 + rng.uniform(0, 14), -20 + rng.uniform(-8, 14)
            S.pumpkin((x, y, 0), rng.uniform(1.0, 1.5))
            bpy.ops.object.light_add(type="POINT", location=(x, y, 1.0))
            bpy.context.active_object.data.energy = 60
            bpy.context.active_object.data.color = S.srgb(255, 150, 60)
        for p in [(-22, -40, 5), (-22, -10, 5), (-22, 20, 5), (10, -26, 3), (12, 0, 3)]:
            S.lantern(p)
        S.needle((19, -12, 2.5), 0.5, "cloud", tilt=0.3, scale=2.0)
        S.needle((14, -22, 1.2), 2.0, "obsidian", tilt=-0.2, scale=1.6)
        bpy.ops.object.light_add(type="SUN")
        moon = bpy.context.active_object
        moon.data.energy = 0.6
        moon.data.color = S.srgb(170, 180, 255)
        moon.rotation_euler = (0.6, 0.3, 2.4)
        S.cyl(9, 1, (-40, 300, 70), S.mat("moon", (240, 236, 220), 0.5, 0, 3.0), verts=24, rot=(1.45, 0, 0))
    S.camera((24, -44, 8.5), (-3, 6, 5.0), lens=30)


# ------------------------------------------------------------------ icon variants

def icon_truck(rng):
    """Icon B: the loaded pickup head-on, low and close."""
    S.ground(600, seed=5, hills=30)
    S.sky(top=(120, 156, 196), horizon=(238, 214, 170), strength=1.0)
    S.sun(elev_deg=30, azim_deg=210, energy=4.4)
    S.fill(40, 0.6)
    S.road([(0, -300), (0, 300)], width=16)
    shots.rig(0, 0, math.radians(18), rng, trailer=False)
    shots.backdrop(rng, ring=(80, 300), n_trees=40)
    S.camera((-12, -30, 4.5), (0, 0, 5.5), lens=36)


def icon_farmer(rng):
    """Icon C: a farmer lifting a bale overhead, a needle glinting in the straw at their feet."""
    S.ground(600, seed=6)
    S.sky(top=(116, 154, 198), horizon=(236, 218, 180), strength=1.0)
    S.sun(elev_deg=34, azim_deg=220, energy=4.4)
    S.fill(30, 0.6)
    f, _ = S.farmer((0, 0, 0), 0.4, pose={"rarm": (math.pi, 0.0), "larm": (math.pi, 0.0), "gloves": True})
    b = S.bale((0, 0, 0), 0.0)
    b.parent = f
    b.location = (0, 0, 6.4)
    S.straw((1, -2, 0), 40, rng, spread=3)
    S.needle((1.6, -2.6, 0.3), 0.8, "cosmic", scale=1.3)
    S.bale((-6, 4, 0), 0.3)
    S.bale((6, 5, 0), -0.4)
    shots.backdrop(rng, ring=(60, 300), n_trees=40)
    S.camera((4.5, -11, 3.0), (0.2, 0, 4.6), lens=32)


# ------------------------------------------------------------------ Robux store items

def plinth(rgb=(150, 144, 132)):
    S.cyl(22, 1.0, (0, 0, -0.5), S.mat("plinth", rgb, 0.9), verts=32)


def store_backdrop(top, horizon):
    S.sky(top=top, horizon=horizon, strength=1.0)
    S.sun(elev_deg=36, azim_deg=220, energy=4.2)
    S.fill(40, 0.8)
    bpy.ops.mesh.primitive_plane_add(size=4000, location=(0, 0, -1.0))
    floor = tuple(int(c * 0.8) for c in horizon)
    bpy.context.active_object.data.materials.append(S.mat("store_floor", floor, 0.95))


TRUCK_SKINS = {
    # id: (model, paints, extras, backdrop)
    "homestead_classic": ("rusty_pickup", {"rustic_paint_red": (186, 214, 200), "rustic_paint_cream": (240, 232, 214),
                                           "rustic_metal": (200, 200, 198)}, "chrome", ((150, 186, 200), (236, 230, 214))),
    "timber_wolf": ("farm_flatbed", {"rustic_paint_green": (70, 96, 70), "rustic_paint_red": (70, 96, 70),
                                     "rustic_paint_cream": (60, 58, 54)}, "lights", ((120, 146, 120), (214, 220, 196))),
    "midnight_express": ("box_truck", {"rustic_paint_cream": (40, 42, 50), "rustic_paint_red": (34, 36, 44)},
                         "neon", ((40, 44, 70), (110, 110, 140))),
    "prairie_schooner": ("heavy_hauler", {"rustic_paint_yellow": (150, 110, 70), "rustic_paint_red": (150, 110, 70)},
                         "canvas", ((180, 160, 130), (240, 222, 190))),
    "founders_semi": ("semi_rig", {"rustic_paint_blue": (40, 56, 92), "rustic_paint_red": (40, 56, 92),
                                   "rustic_paint_cream": (214, 180, 96)}, "plate", ((60, 76, 116), (214, 196, 150))),
}


def store_truck(rng, skin):
    model, paints, extra, bg = TRUCK_SKINS[skin]
    store_backdrop(*bg)
    plinth()
    t = S.prop(model, (0, 0, 0), math.radians(-35))
    S.paint(t, paints, rough=0.45 if extra == "chrome" else None)
    yaw = math.radians(-35)
    if extra == "chrome":
        chrome = S.mat("chrome", (230, 232, 236), 0.15, 1.0)
        for sx in (-1, 1):
            hx, hy = shots.place(0, 0, yaw, sx * 3.4, -13.6)
            S.cyl(0.35, 0.8, (hx, hy, 3.0), chrome, verts=12, rot=(math.pi / 2, 0, yaw))
    if extra == "lights":
        bar = S.mat("lightbar", (40, 40, 40), 0.5)
        lx, ly = shots.place(0, 0, yaw, 0, -6.5)
        S.box((8, 1, 0.5), (lx, ly, 8.6), bar, rot=(0, 0, yaw))
        for i in range(4):
            px, py = shots.place(0, 0, yaw, -3 + i * 2, -7.05)
            S.box((1.2, 0.1, 0.4), (px, py, 8.6), S.mat("lamp", (255, 240, 200), 0.3, 0, 8.0), rot=(0, 0, yaw), bevel=0)
    if extra == "neon":
        for (lx, ly, lz, L, rot) in [(5.6, 4, 6.5, 12, 0)]:
            px, py = shots.place(0, 0, yaw, lx, ly)
            S.box((0.15, L, 0.35), (px, py, lz), S.mat("neon", (120, 200, 255), 0.3, 0, 10.0), rot=(0, 0.25, yaw), bevel=0)
        for i in range(5):
            px, py = shots.place(0, 0, yaw, 5.6, -2 + i * 3.2)
            S.box((0.3, 0.5, 0.5), (px, py, 10.2), S.mat("marker", (255, 170, 60), 0.3, 0, 8.0), rot=(0, 0, yaw), bevel=0)
    if extra == "canvas":
        canvas = S.mat("canvas", (226, 214, 186), 0.9)
        for i in range(5):
            cx, cy = shots.place(0, 0, yaw, 0, -2 + i * 4.4)
            bpy.ops.mesh.primitive_torus_add(major_radius=5.6, minor_radius=0.25, location=(cx, cy, 8),
                                             rotation=(math.pi / 2, 0, yaw))
            bpy.context.active_object.scale = (1, 1, 1)
            bpy.context.active_object.data.materials.append(S.mat("hoop", (110, 86, 60), 0.9))
        cx, cy = shots.place(0, 0, yaw, 0, 6.8)
        bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=5.5, depth=19, location=(cx, cy, 8),
                                            rotation=(math.pi / 2, 0, yaw))
        c = bpy.context.active_object
        c.data.materials.append(canvas)
        bpy.ops.mesh.primitive_cube_add(size=1, location=(cx, cy, 2.5), rotation=(0, 0, yaw))
        cut = bpy.context.active_object
        cut.scale = (12, 20, 11)
        mod = c.modifiers.new("cut", "BOOLEAN")
        mod.object = cut
        mod.operation = "DIFFERENCE"
        cut.hide_render = True
    if extra == "plate":
        px, py = shots.place(0, 0, yaw, 0, 12.85)
        S.box((2.4, 0.1, 1.2), (px, py, 2.2), S.mat("plate", (236, 214, 140), 0.4, 0.6), rot=(0, 0, yaw), bevel=0)
        for sx in (-1, 1):
            hx, hy = shots.place(0, 0, yaw, sx * 4.2, -6)
            S.cyl(0.4, 7, (hx, hy, 9), S.mat("stack", (200, 200, 204), 0.2, 1.0), verts=12)
    S.camera((14, -40, 13), (0, 1, 4.4), lens=42)


PASSES = ["vip", "auto_dock", "big_silo", "paint_studio", "plot_themes", "truck_radio", "hay_fever", "meteor_shower",
          "harvest_pass"]


def store_pass(rng, which):
    bg = {
        "vip": ((96, 70, 110), (226, 200, 150)), "auto_dock": ((110, 140, 170), (226, 222, 206)),
        "big_silo": ((120, 150, 184), (236, 222, 190)), "paint_studio": ((150, 120, 150), (240, 222, 200)),
        "plot_themes": ((110, 140, 110), (226, 226, 196)), "truck_radio": ((70, 70, 96), (200, 170, 140)),
        "hay_fever": ((200, 160, 90), (246, 226, 170)), "meteor_shower": ((26, 30, 60), (90, 80, 130)),
        "harvest_pass": ((170, 110, 70), (244, 214, 160)),
    }[which]
    store_backdrop(*bg)
    plinth()
    cam = ((-14, -20, 10), (0, 0, 4), 40)
    if which == "vip":
        gold = S.mat("gold", (226, 186, 90), 0.25, 1.0)
        S.box((10, 6, 0.6), (0, 0, 0.3), S.mat("velvet", (120, 40, 50), 0.8))
        S.cyl(4, 4, (0, 0, 2.6), gold, verts=10)
        for i in range(5):
            a = i / 5 * 6.28
            bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.9, depth=2.4, location=(math.cos(a) * 3.4, math.sin(a) * 3.4, 5.6))
            bpy.context.active_object.data.materials.append(gold)
        S.needle((0, -4.4, 2.6), 0.0, "cosmic", scale=2.2)
        cam = ((-10, -16, 9), (0, 0, 3.2), 40)
    elif which == "auto_dock":
        for i in range(3):
            S.prop("conveyor_straight", (0, i * 6 - 6, 0), 0)
        S.prop("rusty_pickup", (0, 22, 0), math.pi)
        for i in range(4):
            S.bale((rng.uniform(-1, 1), -6 + i * 4.8, 3.6 + 0.4), math.pi / 2 + rng.uniform(-0.1, 0.1))
        S.box((3, 3, 0.2), (7, 2, 0.1), S.mat("pad_green", (87, 140, 71), 0.6, 0, 1.2))
        cam = ((-34, -30, 24), (0, 4, 3), 34)
    elif which == "big_silo":
        S.prop("silo_mega", (0, 0, 0), 0.4)
        for i in range(6):
            S.bale((-10 + (i % 3) * 5, -12 - (i // 3) * 3.4, 0), rng.uniform(-0.1, 0.1))
        cam = ((-34, -54, 18), (0, 0, 17), 34)
    elif which == "paint_studio":
        t = S.prop("rusty_pickup", (0, 0, 0), math.radians(-35))
        S.paint(t, {"rustic_paint_red": (90, 120, 160)})
        cols = [(133, 61, 48), (214, 180, 96), (70, 96, 70), (90, 120, 160), (226, 214, 186)]
        for i, c in enumerate(cols):
            x = -16 + i * 3.2
            S.cyl(1.2, 2.2, (x, -14, 1.1), S.mat("can%d" % i, (122, 122, 120), 0.5, 0.6), verts=12)
            S.cyl(1.0, 0.1, (x, -14, 2.25), S.mat("paint%d" % i, c, 0.3), verts=12)
        cam = ((-26, -36, 14), (-3, -2, 3.5), 40)
    elif which == "plot_themes":
        S.fence(-14, -8, 14, -8)
        S.fence(-14, -8, -14, 14)
        S.prop("sorter_shed", (2, 6, 0), 0)
        for p in [(-12, -6, 4.6), (12, -6, 4.6)]:
            S.lantern(p)
        S.string_lights([(-14, -8), (0, -8), (14, -8)], z=6)
        S.box((4, 0.4, 2.4), (0, -9, 3.6), S.mat("signboard", (153, 128, 97), 0.9))
        cam = ((-30, -46, 20), (0, 2, 4), 36)
    elif which == "truck_radio":
        wood = S.mat("radio_wood", (128, 90, 60), 0.6)
        S.box((8, 4, 5), (0, 0, 2.5), wood, bevel=0.4)
        S.box((6.6, 0.2, 2.4), (0, -2.0, 3.2), S.mat("cloth", (214, 196, 160), 0.95), bevel=0)
        S.cyl(0.7, 0.4, (-2, -2.1, 1.0), S.mat("knob", (60, 50, 40), 0.4), verts=12, rot=(math.pi / 2, 0, 0))
        S.cyl(0.7, 0.4, (2, -2.1, 1.0), S.mat("knob", (60, 50, 40), 0.4), verts=12, rot=(math.pi / 2, 0, 0))
        S.box((3, 0.1, 0.5), (0, -2.1, 1.0), S.mat("dial", (255, 214, 140), 0.3, 0, 3.0), bevel=0)
        for i, (x, z) in enumerate([(4.5, 7), (6, 9), (3.5, 10)]):
            S.box((0.5, 0.2, 1.6), (x, 0, z), S.mat("note", (255, 236, 200), 0.4, 0, 2.0), rot=(0, 0.3, 0), bevel=0)
            S.cyl(0.6, 0.2, (x - 0.4, 0, z - 0.8), S.mat("note", (255, 236, 200), 0.4, 0, 2.0), verts=10, rot=(math.pi / 2, 0, 0))
        cam = ((-10, -16, 8), (0, 0, 4), 40)
    elif which == "hay_fever":
        for i in range(9):
            S.bale(((i % 3 - 1) * 4.8, (i // 3 - 1) * 3.4, 0), rng.uniform(-0.1, 0.1))
        for i in range(4):
            S.bale(((i % 2 - 0.5) * 4.8, (i // 2 - 0.5) * 3.4, 2.6), rng.uniform(-0.1, 0.1))
        S.bale((0, 0, 5.2), 0.2)
        for _ in range(60):
            S.box((rng.uniform(0.9, 1.5), 0.22, 0.22), (rng.uniform(-10, 10), rng.uniform(-8, 8), rng.uniform(3, 14)),
                  S.mat("straw0", (219, 204, 153), 0.9), rot=(rng.uniform(0, 3), rng.uniform(0, 3), rng.uniform(0, 3)), bevel=0)
        cam = ((-18, -26, 12), (0, 0, 4.5), 40)
    elif which == "meteor_shower":
        for i in range(5):
            x, y, z = -8 + i * 4, 4 + i * 2, 14 + i * 3
            S.needle((x, y, z), 0.6, "cosmic", tilt=-0.7, scale=1.6)
            tr = S.box((0.3, 0.3, 7), (x - 2.2, y, z + 2.6), S.mat("trail", (150, 170, 255), 0.5, 0, 4.0), rot=(0, -0.7, 0.6), bevel=0)
        S.bale((0, 0, 0), 0.3)
        cam = ((-10, -24, 6), (0, 4, 9), 32)
    elif which == "harvest_pass":
        S.prop("round_bale", (-4, 2, 0), 0.4)
        S.bale((3, 0, 0), 0.2)
        for p in [(-6, -4), (0, -5), (5, -4)]:
            S.pumpkin((p[0], p[1], 0), 1.2)
        S.prop("starlight_gloves", (3, -1, 2.6), 0.6)
        cam = ((-10, -18, 8), (0, 0, 2.6), 40)
    S.camera(*cam)


SHOTS = {
    "ferry": (ferry, (1920, 1080)),
    "rich": (rich, (1920, 1080)),
    "burst": (burst, (1920, 1080)),
    "worldmap": (worldmap, (1920, 1080)),
    "winter": (lambda r: seasonal(r, "winter"), (1920, 1080)),
    "harvest": (lambda r: seasonal(r, "harvest"), (1920, 1080)),
    "halloween": (lambda r: seasonal(r, "halloween"), (1920, 1080)),
    "icon_truck": (icon_truck, (1024, 1024)),
    "icon_farmer": (icon_farmer, (1024, 1024)),
}
for reg in ["pine", "desert", "snow", "swamp", "volcano", "haunted", "sky", "meadow"]:
    SHOTS["region_" + reg] = ((lambda r, reg=reg: regions(r, reg)), (960, 1080))
for skin in TRUCK_SKINS:
    SHOTS["store_" + skin] = ((lambda r, skin=skin: store_truck(r, skin)), (768, 768))
for p in PASSES:
    SHOTS["pass_" + p] = ((lambda r, p=p: store_pass(r, p)), (768, 768))

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=",".join(SHOTS))
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--samples", type=int, default=96)
    a = ap.parse_args(argv)
    os.makedirs(OUT, exist_ok=True)
    names = []
    for part in a.only.split(","):
        names += [k for k in SHOTS if k == part or (part.endswith("*") and k.startswith(part[:-1]))]
    for name in names:
        fn, res = SHOTS[name]
        S.reset()
        S.set_season_default()
        fn(random.Random(7))
        S.render(os.path.join(OUT, name + ".png"), res, samples=a.samples, preview=a.preview)

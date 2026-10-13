"""Shared scene kit for the Roblox launch art (thumbnails, icon, loading screen).

Everything is in studs (1 Blender unit = 1 stud) with Blender axes: x east, y north, z up.
Props come from the Rustic .glb exports in blender/exports/rustic/, so the art shows the
same models the game uses.
"""
import math
import os
import random

import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORTS = os.path.join(HERE, "..", "exports", "rustic")
STUD = 0.28


def srgb(r, g, b):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _cache.clear()
    _mats.clear()


_mats = {}


def mat(name, rgb, rough=0.85, metal=0.0, emit=0.0, emit_rgb=None):
    key = (name, rgb, rough, metal, emit)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(*rgb), 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*srgb(*(emit_rgb or rgb)), 1)
        b.inputs["Emission Strength"].default_value = emit
    _mats[key] = m
    return m


def box(size, loc, m, rot=(0, 0, 0), name="box", bevel=0.06):
    """size = (x, y, z) in studs, loc = center."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    o.data.materials.append(m)
    if bevel:
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
    return o


def cyl(r, depth, loc, m, verts=12, rot=(0, 0, 0), name="cyl"):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(m)
    return o


# ------------------------------------------------------------------ props

_cache = {}


def _load(name):
    """Import a .glb once into a hidden collection and return its mesh objects."""
    if name in _cache:
        return _cache[name]
    lib = bpy.data.collections.get("_lib") or bpy.data.collections.new("_lib")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(EXPORTS, name + ".glb"))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = []
    for o in new:
        for c in o.users_collection:
            c.objects.unlink(o)
        if o.type == "MESH":
            o.data.transform(o.matrix_world)
            o.matrix_world = mathutils.Matrix()
            o.parent = None
            meshes.append(o)
    _cache[name] = meshes
    return meshes


def prop(name, loc, rot_z=0.0, scale=1.0, tilt=(0.0, 0.0)):
    """Place a Rustic prop (linked mesh copy) with its base at loc, in studs."""
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    for src in _load(name):
        o = bpy.data.objects.new(src.name + "_i", src.data)
        bpy.context.scene.collection.objects.link(o)
        o.parent = root
    root.scale = (scale / STUD,) * 3
    root.location = loc
    root.rotation_euler = (tilt[0], tilt[1], rot_z)
    return root


BALE = (4.6, 3.2, 2.6)  # along x, along y, up


def bale(loc, rot_z=0.0, jitter=0.0, rng=None):
    rng = rng or random
    r = rot_z + (rng.uniform(-jitter, jitter) if jitter else 0.0)
    return prop("hay_bale", loc, r)


# ------------------------------------------------------------------ world

GRASS = (112, 128, 82)


def ground(size=1600, seed=1, hills=0.0, color=GRASS):
    """A big grass plane with soft noise colour and optional rolling hills far out."""
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=160, y_subdivisions=160, size=size, location=(0, 0, 0))
    g = bpy.context.active_object
    g.name = "ground"
    if hills:
        rng = random.Random(seed)
        bumps = [(rng.uniform(-size / 2, size / 2), rng.uniform(-size / 2, size / 2),
                  rng.uniform(40, 140), rng.uniform(0.3, 1.0)) for _ in range(40)]
        for v in g.data.vertices:
            x, y = v.co.x, v.co.y
            d = math.hypot(x, y)
            fade = max(0.0, min(1.0, (d - 110) / 160))  # keep the play area flat
            h = 0.0
            for bx, by, br, bh in bumps:
                h += bh * math.exp(-((x - bx) ** 2 + (y - by) ** 2) / (br * br))
            v.co.z = h * hills * fade
    m = bpy.data.materials.new("grass")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.95
    tex = nt.nodes.new("ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = 0.035
    tex.inputs["Detail"].default_value = 3
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(tc.outputs["Object"], tex.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    r, gg, bb = color
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (*srgb(r - 18, gg - 16, bb - 14), 1)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = (*srgb(r + 14, gg + 12, bb + 4), 1)
    nt.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
    # fine speckle so the ground doesn't read as plastic
    tex2 = nt.nodes.new("ShaderNodeTexNoise")
    tex2.inputs["Scale"].default_value = 1.4
    nt.links.new(tc.outputs["Object"], tex2.inputs["Vector"])
    mixn = nt.nodes.new("ShaderNodeMix")
    mixn.data_type = "RGBA"
    mixn.blend_type = "OVERLAY"
    mixn.inputs["Factor"].default_value = 0.25
    nt.links.new(ramp.outputs["Color"], mixn.inputs[6])
    nt.links.new(tex2.outputs["Color"], mixn.inputs[7])
    nt.links.new(mixn.outputs[2], b.inputs["Base Color"])
    g.data.materials.append(m)
    return g


def road(points, width=12, m=None, base=0.05):
    m = m or mat("dirt", (150, 128, 96), 0.95)
    for n, ((x0, y0), (x1, y1)) in enumerate(zip(points, points[1:])):
        z = base + n * 0.012  # overlapping segments must not be coplanar, or Cycles renders black patches
        L = math.hypot(x1 - x0, y1 - y0)
        box((L + width * 0.6, width, 0.1), ((x0 + x1) / 2, (y0 + y1) / 2, z), m,
            rot=(0, 0, math.atan2(y1 - y0, x1 - x0)), bevel=0)
        # wheel ruts
        for s in (-1, 1):
            ox = -math.sin(math.atan2(y1 - y0, x1 - x0)) * s * width * 0.22
            oy = math.cos(math.atan2(y1 - y0, x1 - x0)) * s * width * 0.22
            box((L + width * 0.5, 1.4, 0.1), ((x0 + x1) / 2 + ox, (y0 + y1) / 2 + oy, z + 0.005 + s * 0.002),
                mat("rut", (128, 108, 80), 0.95), rot=(0, 0, math.atan2(y1 - y0, x1 - x0)), bevel=0)


LEAF = [(74, 98, 56), (60, 82, 46), (86, 108, 62), (96, 104, 58)]


def tree(x, y, rng, s=1.0, z=0.0):
    """LT2-style tree: a bark trunk and a crown of a few blocks."""
    h = rng.uniform(10, 16) * s
    bark = mat("bark", (76, 64, 51), 0.95)
    cyl(0.9 * s, h, (x, y, z + h / 2), bark, verts=10)
    for i in range(rng.randint(3, 5)):
        c = rng.uniform(5, 8) * s
        box((c, c, c * 0.8), (x + rng.uniform(-2.5, 2.5) * s, y + rng.uniform(-2.5, 2.5) * s,
                               z + h + rng.uniform(-1.5, 2.5) * s),
            mat("leaf%d" % (i % 4), LEAF[i % 4], 0.95), rot=(0, 0, rng.uniform(0, 1.6)), bevel=0.15)


def pine(x, y, rng, s=1.0, z=0.0):
    bark = mat("bark", (76, 64, 51), 0.95)
    h = rng.uniform(16, 24) * s
    cyl(0.8 * s, h * 0.4, (x, y, z + h * 0.2), bark, verts=8)
    green = mat("pine", (58, 78, 52), 0.95)
    for i in range(4):
        w = (7 - i * 1.5) * s
        box((w, w, h * 0.2), (x, y, z + h * 0.3 + i * h * 0.17), green, rot=(0, 0, 0.4 * i), bevel=0.1)


def fence(x0, y0, x1, y1):
    L = math.hypot(x1 - x0, y1 - y0)
    n = max(1, round(L / 12.65))
    a = math.atan2(y1 - y0, x1 - x0)
    for i in range(n):
        t = (i + 0.5) / n
        prop("fence_post_set", (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, 0), a)


def straw(center, n, rng, spread=4.0, z=0.15):
    """Loose straw strands (Hay.luau pieces)."""
    cols = [(219, 204, 153), (189, 168, 112), (168, 149, 95), (133, 115, 71)]
    for i in range(n):
        r = spread * math.sqrt(rng.random())
        a = rng.uniform(0, 2 * math.pi)
        box((rng.uniform(0.9, 1.5), 0.22, 0.22),
            (center[0] + r * math.cos(a), center[1] + r * math.sin(a), center[2] + z + rng.uniform(0, 0.25)),
            mat("straw%d" % (i % 4), cols[i % 4], 0.9), rot=(0, rng.uniform(-0.2, 0.2), rng.uniform(0, 3.14)),
            bevel=0)


def needle(loc, rot_z=0.0, kind="steel", tilt=0.0, scale=1.0):
    """A sorted needle: a thin metal pin with an eye. Rare kinds glow (STYLE: glow means rarity)."""
    looks = {
        "steel": ((148, 148, 145), 0.0),
        "cosmic": ((110, 140, 255), 1.4),
        "obsidian": ((200, 90, 150), 1.2),
        "cloud": ((235, 240, 250), 1.0),
    }
    rgb, glow = looks[kind]
    m = mat("needle_" + kind, rgb, 0.3, 0.9 if not glow else 0.2, glow)
    root = bpy.data.objects.new("needle", None)
    bpy.context.scene.collection.objects.link(root)
    L = 1.2 * scale
    shaft = cyl(0.06 * scale, L, (0, 0, 0), m, verts=8, rot=(0, math.pi / 2, 0))
    tip = None
    bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=0.06 * scale, depth=0.25 * scale,
                                    location=(L / 2 + 0.12 * scale, 0, 0), rotation=(0, math.pi / 2, 0))
    tip = bpy.context.active_object
    tip.data.materials.append(m)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.1 * scale, minor_radius=0.03 * scale,
                                     location=(-L / 2 - 0.08 * scale, 0, 0), rotation=(math.pi / 2, 0, 0))
    eye = bpy.context.active_object
    eye.data.materials.append(m)
    for o in (shaft, tip, eye):
        o.parent = root
    root.location = loc
    root.rotation_euler = (0, tilt, rot_z)
    if glow:
        bpy.ops.object.light_add(type="POINT", location=loc)
        lamp = bpy.context.active_object
        lamp.data.color = srgb(*rgb)
        lamp.data.energy = 25 * glow * scale
        lamp.data.shadow_soft_size = 0.5
    return root


def farmer(loc, rot_z=0.0, shirt=(140, 72, 58), pants=(78, 88, 104), hat=True, pose=None, hold=None):
    """A blocky R6-style Roblox player in muted farm clothes, 5 studs tall."""
    root = bpy.data.objects.new("farmer", None)
    bpy.context.scene.collection.objects.link(root)
    skin = mat("skin", (214, 172, 132), 0.8)
    sh = mat("shirt", shirt, 0.9)
    pa = mat("pants", pants, 0.9)
    boot = mat("boot", (70, 54, 40), 0.9)
    pose = pose or {}
    parts = []
    # legs
    for s, key in ((-0.5, "lleg"), (0.5, "rleg")):
        a = pose.get(key, 0.0)
        leg = box((1, 1, 2), (0, 0, -1), pa, bevel=0.05)
        bt = box((1.02, 1.02, 0.5), (0, 0, -1.75), boot, bevel=0.05)
        piv = bpy.data.objects.new(key, None)
        bpy.context.scene.collection.objects.link(piv)
        leg.parent = piv
        bt.parent = piv
        piv.location = (s, 0, 2)
        piv.rotation_euler = (a, 0, 0)
        piv.parent = root
    torso = box((2, 1, 2), (0, 0, 3), sh, bevel=0.05)
    torso.parent = root
    # plaid stripes
    stripe = mat("stripe", tuple(max(0, c - 40) for c in shirt), 0.9)
    for z in (2.5, 3.3):
        b = box((2.02, 1.02, 0.18), (0, 0, z), stripe, bevel=0)
        b.parent = root
    head = cyl(0.62, 1.2, (0, 0, 4.6), skin, verts=16)
    head.parent = root
    eye_m = mat("eye", (30, 26, 22), 0.5)
    for s in (-0.22, 0.22):
        e = box((0.12, 0.05, 0.2), (s, -0.6, 4.72), eye_m, bevel=0)
        e.parent = root
    smile = box((0.4, 0.05, 0.07), (0, -0.6, 4.35), eye_m, bevel=0)
    smile.parent = root
    if hat:
        straw_m = mat("strawhat", (205, 182, 120), 0.9)
        brim = cyl(1.25, 0.12, (0, 0, 5.2), straw_m, verts=20)
        crown = cyl(0.7, 0.6, (0, 0, 5.5), straw_m, verts=16)
        band = cyl(0.72, 0.15, (0, 0, 5.32), mat("band", (110, 70, 50), 0.9), verts=16)
        for o in (brim, crown, band):
            o.parent = root
    arms = {}
    for s, key in ((-1.5, "larm"), (1.5, "rarm")):
        a = pose.get(key, (0.0, 0.0))
        piv = bpy.data.objects.new(key, None)
        bpy.context.scene.collection.objects.link(piv)
        arm = box((1, 1, 2), (0, 0, -0.5), sh, bevel=0.05)
        hand = box((0.98, 0.98, 0.5), (0, 0, -1.75), skin if not pose.get("gloves") else
                   mat("glove", (143, 102, 69), 0.85), bevel=0.05)
        arm.parent = piv
        hand.parent = piv
        piv.location = (s, 0, 3.5)
        piv.rotation_euler = (a[0], a[1], 0)
        piv.parent = root
        arms[key] = piv
    root.location = loc
    root.rotation_euler = (0, 0, rot_z)
    return root, arms


# ------------------------------------------------------------------ light, sky, camera

def sky(top=(140, 170, 196), horizon=(232, 214, 178), strength=1.0, sun_glow=None):
    w = bpy.data.worlds.new("sky")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes["Background"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    e = ramp.color_ramp.elements
    e[0].position = 0.02
    e[0].color = (*srgb(*horizon), 1)
    e[1].position = 0.32
    e[1].color = (*srgb(*top), 1)
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = strength
    return w


def sun(elev_deg=28, azim_deg=200, energy=4.0, color=(255, 236, 205), soft=2.0):
    bpy.ops.object.light_add(type="SUN")
    s = bpy.context.active_object
    s.data.energy = energy
    s.data.color = srgb(*color)
    s.data.angle = math.radians(soft)
    el, az = math.radians(elev_deg), math.radians(azim_deg)
    d = mathutils.Vector((math.cos(el) * math.sin(az), math.cos(el) * math.cos(az), math.sin(el)))
    s.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    return s


def fill(azim_deg, energy=0.7, color=(200, 214, 235)):
    """Shadowless sky-coloured fill so big shadows read as shade, not holes."""
    f = sun(elev_deg=35, azim_deg=azim_deg, energy=energy, color=color, soft=20)
    f.visible_shadow = False
    return f


def camera(loc, target, lens=35):
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = lens
    cam_data.clip_end = 5000
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = loc
    d = mathutils.Vector(target) - mathutils.Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


def mist(density=0.0015, rgb=(225, 215, 190)):
    """Light aerial haze so far hills fade into the sky."""
    w = bpy.context.scene.world
    nt = w.node_tree
    vol = nt.nodes.new("ShaderNodeVolumeScatter")
    vol.inputs["Density"].default_value = density
    vol.inputs["Color"].default_value = (*srgb(*rgb), 1)
    out = nt.nodes["World Output"]
    nt.links.new(vol.outputs[0], out.inputs["Volume"])


def render(path, res=(1920, 1080), samples=96, preview=False):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24 if preview else samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 40 if preview else 100
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.image_settings.file_format = "PNG"
    sc.render.film_transparent = False
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("WROTE", path)

"""Shared helpers for mockup renders (map, tools, hay types).

Mockups are modeled in Roblox studs (1 Blender unit = 1 stud) and use the
game's Roblox axes mapped to Blender: X -> x, Z -> -y, Y (up) -> z.
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import common  # noqa: E402,F401


def rgb(r, g, b):
    """Roblox Color3.fromRGB -> linear color for Blender materials."""
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b))


_mats = {}


def mat(name, color, roughness=0.8, metallic=0.0, emit=0.0, alpha=1.0):
    key = (name, color, roughness, metallic, emit, alpha)
    if key in _mats:
        return _mats[key]
    m = common.material(name, color, roughness, metallic)
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
    _mats[key] = m
    return m


def rbx(x, z, y=0.0):
    """Roblox position -> Blender location."""
    return (x, -z, y)


def box(name, size, loc, material, rot=(0, 0, 0)):
    """Box with Roblox-style size (X, Y up, Z depth) at a Blender location."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0], size[2], size[1])
    o.data.materials.append(material)
    return o


def cylinder(name, radius, depth, loc, material, verts=24, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(material)
    return o


def sphere(name, radius, loc, material, scale=(1, 1, 1), subdiv=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    o.data.materials.append(material)
    return o


def label(text, loc, size, material, rot=(0, 0, 0), align="CENTER", bold=True):
    curve = bpy.data.curves.new(name="label", type="FONT")
    curve.body = text
    curve.size = size
    curve.align_x = align
    curve.align_y = "CENTER"
    curve.extrude = 0.01
    if bold:
        curve.offset = 0.0
    o = bpy.data.objects.new("label:" + text[:16], curve)
    o.location = loc
    o.rotation_euler = rot
    o.data.materials.append(material)
    bpy.context.collection.objects.link(o)
    return o


def hay_heap(name, center, radius, height, colors, tufts=60, seed=1, straws=40):
    """Lumpy hay mound: a squashed blob plus tufts and loose straws on top."""
    import random
    rng = random.Random(seed)
    objs = []
    cx, cy, cz = center
    objs.append(sphere(name + "_core", radius, (cx, cy, cz), colors[0], scale=(1, 1, height / radius), subdiv=3))
    for i in range(tufts):
        a = rng.uniform(0, math.tau)
        d = math.sqrt(rng.random()) * radius * 0.95
        h = height * (1 - (d / radius) ** 2) ** 0.5
        r = rng.uniform(0.18, 0.32) * radius
        objs.append(sphere(f"{name}_tuft{i}", r,
                           (cx + math.cos(a) * d, cy + math.sin(a) * d, cz + h * rng.uniform(0.75, 1.0)),
                           colors[i % len(colors)], scale=(1, rng.uniform(0.6, 1), rng.uniform(0.5, 0.8)),
                           subdiv=1))
    for i in range(straws):
        a = rng.uniform(0, math.tau)
        d = math.sqrt(rng.random()) * radius
        h = height * (1 - min(d / radius, 1) ** 2) ** 0.5
        length = rng.uniform(0.35, 0.7) * radius
        o = cylinder(f"{name}_straw{i}", radius * 0.025, length,
                     (cx + math.cos(a) * d, cy + math.sin(a) * d, cz + h * 0.9),
                     colors[(i + 1) % len(colors)], verts=5,
                     rot=(rng.uniform(0.6, 1.4), 0, a))
        objs.append(o)
    return objs


def tub(name, center, radius, height, wood, hoop):
    """Short wooden tub with two metal hoops, like the game's hay barrel."""
    cx, cy, cz = center
    objs = [cylinder(name + "_body", radius, height, (cx, cy, cz + height / 2), wood, verts=16)]
    for h in (0.2, 0.8):
        objs.append(cylinder(name + "_hoop", radius * 1.04, height * 0.1, (cx, cy, cz + height * h), hoop, verts=16))
    return objs


def scene_setup(world_color=(0.75, 0.8, 0.85), world_strength=0.9, res=(1600, 1200), samples=48):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    try:
        scene.cycles.use_denoising = True
    except Exception:
        pass
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (*world_color, 1)
    bg.inputs["Strength"].default_value = world_strength
    scene.world = world
    return scene


def sun(rotation=(0.6, 0.15, 0.9), energy=3.5):
    s = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    s.rotation_euler = rotation
    s.data.energy = energy
    s.data.angle = 0.2
    bpy.context.collection.objects.link(s)
    return s


def camera(loc, look_at=None, ortho_scale=None, rot=None, lens=50):
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.location = loc
    if ortho_scale:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho_scale
    else:
        cam.data.lens = lens
    if rot:
        cam.rotation_euler = rot
    bpy.context.collection.objects.link(cam)
    if look_at:
        target = bpy.data.objects.new("target", None)
        target.location = look_at
        bpy.context.collection.objects.link(target)
        c = cam.constraints.new("TRACK_TO")
        c.target = target
    bpy.context.scene.camera = cam
    return cam


def render(out):
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    bpy.context.scene.render.filepath = os.path.abspath(out)
    bpy.ops.render.render(write_still=True)
    print("wrote", os.path.abspath(out))


def out_path(default_name):
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    folder = argv[0] if argv else os.path.join(os.path.dirname(os.path.abspath(__file__)), "renders")
    return os.path.join(folder, default_name)

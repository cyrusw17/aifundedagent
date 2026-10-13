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
    o.visible_shadow = False
    bpy.context.collection.objects.link(o)
    return o


# ---------------------------------------------------------------- house style props

STUD = 0.28  # props in blender/props are modeled in meters


def rustic_finish(name="rustic", hay=None, twine=None):
    """The house finish (blender/lib/style.py). hay/twine swap those palettes
    (light, mid, dark sRGB 0-1) for map-specific hay."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "props"))
    import style
    f = style.rustic()
    if hay or twine:
        f.pal = dict(f.pal)
        f.pal["hay"] = hay or f.pal["hay"]
        f.pal["twine"] = twine or f.pal["twine"]
        f.name = name
    return f


def prop(key, loc, rot_z=0.0, f=None, rot=None):
    """Build a house-style prop from blender/props/rustic_props.py, scaled to studs."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "props"))
    import rustic_props
    f = f or rustic_finish()
    parts = rustic_props.PROPS[key](f)
    root = bpy.data.objects.new(key, None)
    bpy.context.collection.objects.link(root)
    for o in parts:
        o.parent = root
    root.scale = (1 / STUD,) * 3
    root.location = loc
    root.rotation_euler = rot or (0, 0, rot_z)
    return root


def finish_part(obj, kind, f, along="x"):
    """Give a plain mock part a house-style material (kind: hay, bark, wood, handle, metal)."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.data.materials.clear()
    return f.apply(f.shape(obj, round_edges=False), kind, along=along)


def bale(loc, rot_z=0.0, f=None):
    """One 4 x 2 x 2 stud bale with its bottom at loc."""
    return prop("hay_bale", loc, rot_z, f)


def bale_stack(x, y, z=0.0, f=None, layers=2):
    """Bales stacked in a bond: two side by side, then one across on top."""
    for layer in range(layers):
        if layer % 2 == 0:
            for dy in (-1, 1):
                bale((x, y + dy, z + layer * 2), 0.0, f)
        else:
            bale((x, y, z + layer * 2), math.pi / 2, f)


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def rustic_palette(light, mid, dark, weather=0.3):
    """Turn bright (0-255) shades into the muted Rustic look by pulling them toward warm grey."""
    grey = (0.55, 0.5, 0.42)
    return tuple(mix(tuple(c / 255 for c in col), grey, weather) for col in (light, mid, dark))


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

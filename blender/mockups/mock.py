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


# House palette (sRGB 0-255), shared with blender/props/hay_barrel.py. See style/STYLE.md.
HAY_PALETTE = {
    "root": (199, 158, 69),
    "mids": [(245, 214, 107), (235, 196, 87), (252, 227, 133), (224, 184, 79)],
    "tip": (255, 242, 179),
}
WOOD_TONES = [(140, 87, 46), (153, 97, 51), (128, 77, 41)]
WOOD_INSIDE = (77, 46, 26)
IRON = (61, 61, 69)


def palette(mids, root=None, tip=None):
    """Hay palette from a few mid shades: darker roots, lighter tips."""
    root = root or tuple(int(c * 0.78) for c in mids[0])
    tip = tip or tuple(int(c + (255 - c) * 0.45) for c in mids[-1])
    return {"root": root, "mids": list(mids), "tip": tip}


_vcol = None


def vcol_mat():
    """Matte material that takes its color from the mesh's 'Col' color attribute."""
    global _vcol
    if _vcol:
        return _vcol
    m = bpy.data.materials.new("vertex_color")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.9
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    _vcol = m
    return m


def spikes(name, items):
    """One mesh of straw spikes. items: (base, direction, length, radius, root_rgb, tip_rgb, twist)."""
    import bmesh
    from mathutils import Vector
    bm = bmesh.new()
    col = bm.loops.layers.float_color.new("Col")
    for base, direction, length, radius, root, tip, twist in items:
        d = Vector(direction).normalized()
        side = d.orthogonal().normalized()
        side.rotate(__import__("mathutils").Quaternion(d, twist))
        other = d.cross(side)
        b = Vector(base)
        ring = [bm.verts.new(b + (side * math.cos(a) + other * math.sin(a) * 0.45) * radius)
                for a in (0, math.tau / 3, 2 * math.tau / 3)]
        apex = bm.verts.new(b + d * length)
        rc, tc = (*rgb(*root), 1.0), (*rgb(*tip), 1.0)
        for i in range(3):
            f = bm.faces.new((ring[i], ring[(i + 1) % 3], apex))
            for loop in f.loops:
                loop[col] = tc if loop.vert is apex else rc
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new(name, mesh)
    o.data.materials.append(vcol_mat())
    bpy.context.collection.objects.link(o)
    return o


def hay_heap(name, center, radius, height, pal=None, tufts=160, seed=1, emit=0.0):
    """Spiky low-poly hay mound in the barrel's style: a dark-rooted core covered in
    straw spikes that run from a darker root to a light tip."""
    import random
    rng = random.Random(seed)
    pal = pal or HAY_PALETTE
    cx, cy, cz = center
    core = sphere(name + "_core", radius * 0.92, (cx, cy, cz),
                  mat(name + "_root", rgb(*pal["root"]), 0.95, emit=emit),
                  scale=(1, 1, height / radius * 0.92), subdiv=2)
    items = []
    for i in range(tufts):
        # Point on the upper part of the mound, pointing outward and a bit up.
        a = rng.uniform(0, math.tau)
        el = math.asin(rng.uniform(-0.15, 1.0))
        nx, ny, nz = math.cos(el) * math.cos(a), math.cos(el) * math.sin(a), math.sin(el)
        base = (cx + nx * radius * 0.8, cy + ny * radius * 0.8, cz + nz * height * 0.8)
        direction = (nx + rng.uniform(-0.35, 0.35), ny + rng.uniform(-0.35, 0.35),
                     nz * (height / radius) + rng.uniform(0.0, 0.5))
        mid = pal["mids"][i % len(pal["mids"])]
        tip = tuple(int((m + t) / 2) for m, t in zip(mid, pal["tip"])) if i % 3 else pal["tip"]
        root = tuple(int((m + r) / 2) for m, r in zip(mid, pal["root"]))
        items.append((base, direction, rng.uniform(0.35, 0.6) * radius, rng.uniform(0.09, 0.16) * radius,
                      root, tip, rng.uniform(0, math.tau)))
    return [core, spikes(name + "_straw", items)]


def tub(name, center, radius, height, staves=14, seed=0):
    """Wooden stave tub with two chunky iron bands, like the game's hay barrel."""
    import random
    rng = random.Random(seed)
    cx, cy, cz = center
    objs = []
    width = math.tau * radius / staves * 0.94
    for i in range(staves):
        a = i * math.tau / staves
        tone = WOOD_TONES[rng.randrange(len(WOOD_TONES))]
        o = box(f"{name}_stave{i}", (width, height * rng.uniform(0.98, 1.03), radius * 0.14),
                (cx + math.cos(a) * radius, cy + math.sin(a) * radius, cz + height / 2),
                mat("wood" + str(tone), rgb(*tone), 0.85), rot=(0, 0, a + math.pi / 2))
        objs.append(o)
    objs.append(cylinder(name + "_inside", radius * 0.95, height * 0.96, (cx, cy, cz + height / 2),
                         mat("wood_inside", rgb(*WOOD_INSIDE), 0.9), verts=16))
    iron = mat("iron", rgb(*IRON), 0.45, 0.85)
    for h in (0.18, 0.82):
        objs.append(cylinder(name + "_band", radius * 1.15, height * 0.12, (cx, cy, cz + height * h), iron, verts=16))
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

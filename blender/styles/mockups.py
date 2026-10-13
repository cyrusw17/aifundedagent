"""Art style mockups: the same three props built in three candidate styles.

Rows (styles):
  A  Low-poly faceted   - flat-shaded facets, painted vertex colors, no textures
  B  Blocky             - chunky beveled blocks, bold flat colors (classic Roblox feel)
  C  Soft cartoon       - smooth rounded shapes, warm soft colors

Columns (props): hay barrel, shovel, chopped log.

Run:
  blender --background --python blender/styles/mockups.py -- --out blender/exports/styles
Writes style_A.glb, style_B.glb, style_C.glb (three props each); preview each with\ntools/render_preview.py.
"""
import math
import os
import random
import sys

import bpy  # must be imported before bmesh/mathutils with the pip bpy module
from mathutils import Vector  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, os.path.join(HERE, "..", "props"))
import common  # noqa: E402
import hay_barrel  # noqa: E402

SPACING = 1.1


def active():
    return bpy.context.active_object


def apply_mods(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def bevel(obj, width, segments=1):
    m = obj.modifiers.new("bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    apply_mods(obj)


def subsurf(obj, levels=2):
    m = obj.modifiers.new("subsurf", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    apply_mods(obj)


def smooth(obj):
    for p in obj.data.polygons:
        p.use_smooth = True


def cyl(r, depth, loc, verts=16, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    return active()


def box(size, loc, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = active()
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return o


def sphere(r, loc, scale=(1, 1, 1), segs=16, rings=10):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=rings, radius=r, location=loc)
    o = active()
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return o


def solid(obj, color):
    common.paint(obj, lambda p, c: color)
    return obj


def faceted_paint(obj, color, top_light=0.18, jitter=0.04, rng=None):
    """Style A painting: per-face tone jitter plus lighter upward faces."""
    rng = rng or random.Random(1)
    tones = {}

    def fn(p, c):
        if p.index not in tones:
            k = 1 + rng.uniform(-jitter, jitter) + max(0.0, p.normal.z) * top_light
            tones[p.index] = tuple(min(1.0, x * k) for x in color)
        return tones[p.index]

    common.paint(obj, fn)
    return obj


# ---------------------------------------------------------------- style A: low-poly faceted

def a_shovel(rng):
    wood, steel, dark = (0.62, 0.40, 0.22), (0.62, 0.64, 0.68), (0.30, 0.20, 0.12)
    parts = [faceted_paint(cyl(0.025, 0.95, (0, 0, 0.62), verts=6), wood, rng=rng)]
    parts.append(faceted_paint(box((0.16, 0.04, 0.04), (0, 0, 1.12)), dark, rng=rng))
    parts.append(faceted_paint(cyl(0.035, 0.12, (0, 0, 0.12), verts=6), steel, rng=rng))
    blade = box((0.24, 0.05, 0.3), (0, 0, 0.0))
    for v in blade.data.vertices:
        if v.co.z < 0:
            v.co.x *= 0.65  # taper to a spade point
            v.co.z -= 0.06 * (1 - abs(v.co.x) / 0.08)
        if v.co.y > 0:
            v.co.x *= 0.85  # scoop curve
    parts.append(faceted_paint(blade, steel, rng=rng))
    return parts


def a_log(rng):
    bark, core, ring = (0.42, 0.27, 0.15), (0.90, 0.72, 0.46), (0.74, 0.55, 0.32)
    log = cyl(0.26, 0.42, (0, 0, 0.21), verts=8)
    for v in log.data.vertices:
        v.co.x *= rng.uniform(0.94, 1.04)
        v.co.y *= rng.uniform(0.94, 1.04)
    faceted_paint(log, bark, rng=rng)
    top = cyl(0.21, 0.02, (0, 0, 0.425), verts=8)
    common.paint(top, lambda p, c: ring if math.hypot(c.x, c.y) > 0.15 else core)
    inner = cyl(0.12, 0.022, (0, 0, 0.427), verts=8)
    faceted_paint(inner, core, rng=rng)
    return [log, top, inner]


# ---------------------------------------------------------------- style B: blocky

def b_hay_barrel(rng):
    wood, band, hay, hay2 = (0.70, 0.42, 0.20), (0.25, 0.25, 0.28), (1.0, 0.82, 0.25), (0.96, 0.70, 0.18)
    barrel = cyl(0.42, 0.6, (0, 0, 0.3), verts=8)
    bevel(barrel, 0.03)
    solid(barrel, wood)
    parts = [barrel]
    for z in (0.1, 0.5):
        b = cyl(0.44, 0.07, (0, 0, z), verts=8)
        bevel(b, 0.01)
        parts.append(solid(b, band))
    # Hay as a stepped stack of chunky blocks.
    for layer, (r, z) in enumerate(((0.44, 0.68), (0.36, 0.84), (0.24, 0.98))):
        n = 8 - layer * 2
        for k in range(n):
            a = 2 * math.pi * (k + 0.5 * layer) / n
            d = r * 0.55
            blk = box((r * 0.75, r * 0.75, 0.18), (d * math.cos(a), d * math.sin(a), z), rot=(0, 0, a))
            bevel(blk, 0.02)
            parts.append(solid(blk, hay if (k + layer) % 2 else hay2))
    top = box((0.2, 0.2, 0.16), (0, 0, 1.1), rot=(0, 0, 0.4))
    bevel(top, 0.02)
    parts.append(solid(top, hay))
    return parts


def b_shovel(rng):
    wood, grip, steel = (0.78, 0.50, 0.25), (0.85, 0.20, 0.18), (0.70, 0.72, 0.76)
    parts = []
    handle = box((0.05, 0.05, 0.95), (0, 0, 0.62))
    bevel(handle, 0.008)
    parts.append(solid(handle, wood))
    g = box((0.18, 0.06, 0.06), (0, 0, 1.12))
    bevel(g, 0.01)
    parts.append(solid(g, grip))
    blade = box((0.26, 0.05, 0.32), (0, 0, 0.0))
    bevel(blade, 0.012)
    parts.append(solid(blade, steel))
    neck = box((0.08, 0.06, 0.12), (0, 0, 0.2))
    bevel(neck, 0.01)
    parts.append(solid(neck, steel))
    return parts


def b_log(rng):
    bark, core, ring = (0.50, 0.30, 0.15), (0.98, 0.80, 0.50), (0.85, 0.62, 0.35)
    log = cyl(0.26, 0.42, (0, 0, 0.21), verts=8)
    bevel(log, 0.025)
    solid(log, bark)
    top = cyl(0.21, 0.02, (0, 0, 0.425), verts=8)
    solid(top, ring)
    inner = cyl(0.12, 0.024, (0, 0, 0.427), verts=8)
    solid(inner, core)
    return [log, top, inner]


# ---------------------------------------------------------------- style C: soft cartoon

def c_hay_barrel(rng):
    wood, band, hay, hay_lt = (0.80, 0.52, 0.32), (0.45, 0.40, 0.42), (1.0, 0.85, 0.45), (1.0, 0.93, 0.66)
    barrel = cyl(0.42, 0.6, (0, 0, 0.3), verts=24)
    for v in barrel.data.vertices:
        t = v.co.z / 0.3
        v.co.x *= 1 + 0.08 * (1 - t * t)
        v.co.y *= 1 + 0.08 * (1 - t * t)
    bevel(barrel, 0.04, segments=3)
    smooth(barrel)
    wood_dk = tuple(x * 0.78 for x in wood)
    # Alternate plank tones so it reads as a barrel, not a pot.
    common.paint(barrel, lambda p, c: wood if int((math.atan2(p.center.y, p.center.x) + math.pi) / (2 * math.pi) * 12) % 2 else wood_dk)
    parts = [barrel]
    for z in (0.1, 0.5):
        b = cyl(0.45, 0.06, (0, 0, z), verts=32)
        bevel(b, 0.015, segments=2)
        smooth(b)
        parts.append(solid(b, band))
    # Hay as soft puffy lumps.
    for i in range(14):
        u = (i + 0.5) / 14
        d = 0.36 * math.sqrt(u)
        a = i * 2.4
        z = 0.66 + 0.32 * (1 - (d / 0.42) ** 2)
        s = sphere(rng.uniform(0.15, 0.22), (d * math.cos(a), d * math.sin(a), z), scale=(1, 1, 0.8))
        smooth(s)
        parts.append(solid(s, hay if i % 3 else hay_lt))
    for i in range(10):  # a few soft strands poking out
        a = rng.uniform(0, 2 * math.pi)
        st = cyl(0.012, 0.22, (0.3 * math.cos(a), 0.3 * math.sin(a), 0.85), verts=6,
                 rot=(rng.uniform(-0.8, 0.8), rng.uniform(-0.8, 0.8), 0))
        smooth(st)
        parts.append(solid(st, hay_lt))
    return parts


def c_shovel(rng):
    wood, grip, steel = (0.86, 0.58, 0.36), (0.36, 0.62, 0.86), (0.78, 0.80, 0.86)
    parts = []
    h = cyl(0.03, 0.95, (0, 0, 0.62), verts=16)
    smooth(h)
    parts.append(solid(h, wood))
    g = cyl(0.04, 0.2, (0, 0, 1.12), verts=16, rot=(0, math.pi / 2, 0))
    bevel(g, 0.015, segments=3)
    smooth(g)
    parts.append(solid(g, grip))
    blade = sphere(0.18, (0, 0, 0.02), scale=(0.8, 0.18, 1.1), segs=24, rings=12)
    smooth(blade)
    parts.append(solid(blade, steel))
    return parts


def c_log(rng):
    bark, core, ring = (0.62, 0.40, 0.26), (1.0, 0.86, 0.62), (0.92, 0.70, 0.46)
    log = cyl(0.26, 0.42, (0, 0, 0.21), verts=32)
    bevel(log, 0.05, segments=4)
    smooth(log)
    solid(log, bark)
    top = cyl(0.2, 0.02, (0, 0, 0.425), verts=32)
    smooth(top)
    solid(top, ring)
    inner = cyl(0.11, 0.024, (0, 0, 0.427), verts=32)
    smooth(inner)
    solid(inner, core)
    return [log, top, inner]


STYLES = [
    ("A", lambda rng: hay_barrel.build(rng), a_shovel, a_log, True),
    ("B", b_hay_barrel, b_shovel, b_log, False),
    ("C", c_hay_barrel, c_shovel, c_log, False),
]


def main():
    args = common.parse_args("style")
    args.formats = "glb"
    base = args.name
    for row, (label, *builders, faceted) in enumerate(STYLES):
        common.reset_scene()
        mat = common.vertex_color_material("Paint", roughness=0.8)
        objs = []
        for col, build in enumerate(builders):
            rng = random.Random(100 + row * 10 + col)
            parts = build(rng)
            for o in parts:
                if not o.data.materials:
                    common.assign(o, mat)
            obj = common.join(parts, f"Style{label}_{['HayBarrel', 'Shovel', 'Log'][col]}")
            if faceted:
                common.flat(obj)
            obj.location = Vector(((col - 1) * SPACING, 0, 0))
            objs.append(obj)
        args.name = f"{base}_{label}"
        common.export(objs, args)


if __name__ == "__main__":
    main()

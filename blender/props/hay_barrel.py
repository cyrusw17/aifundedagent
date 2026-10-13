"""Hay barrel in a stylized low-poly look: a wooden stave barrel heaped with hay.

The hay is the star: a faceted mound covered in pointed straw clumps that
bristle up and spill over the rim, painted with vertex colors in a few gold
tones (darker at the roots, lighter at the tips), like hand-painted game props.

Exports two meshes so the game can treat them separately:
  HayBarrel_Barrel  - the container (physics body)
  HayBarrel_Hay     - the hay fill (hide/shrink it as hay is taken out)

Run:
  blender --background --python blender/props/hay_barrel.py -- --out blender/exports
"""
import math
import os
import random
import sys

import bpy  # must be imported before bmesh/mathutils with the pip bpy module
import bmesh  # noqa: E402
from mathutils import Quaternion, Vector  # noqa: E402

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import common  # noqa: E402

# Dimensions in meters (Roblox: 1 stud = 0.28 m; the whole prop is ~3.6 x 4.5 studs).
HEIGHT = 0.62
RADIUS_END = 0.40       # radius at top and bottom
RADIUS_MID = 0.46       # bulge at the middle
STAVES = 12
STAVE_THICKNESS = 0.045
STAVE_GAP = 0.010       # gap between staves, as arc length
HOOPS = ((0.08, 0.06), (0.50, 0.06))  # (height, width)
HOOP_THICKNESS = 0.018
MOUND_HEIGHT = 0.52     # hay dome above the rim
MOUND_OVERHANG = 1.12   # dome radius relative to the rim
CLUMPS = 280
SEED = 11

# sRGB palettes.
WOOD = [(0.55, 0.34, 0.18), (0.60, 0.38, 0.20), (0.50, 0.30, 0.16), (0.58, 0.36, 0.17)]
WOOD_DARK = (0.30, 0.18, 0.10)          # inside of the barrel and end grain
IRON = (0.24, 0.24, 0.27)
IRON_EDGE = (0.36, 0.36, 0.40)
HAY_BASE = (0.78, 0.62, 0.27)           # roots and the mound underneath
HAY_TONES = [(0.96, 0.84, 0.42), (0.92, 0.77, 0.34), (0.99, 0.89, 0.52), (0.88, 0.72, 0.31)]
HAY_TIP = (1.00, 0.95, 0.70)


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def radius_at(z):
    """Barrel profile: parabolic bulge between the end radius and mid radius."""
    t = (z / HEIGHT) * 2 - 1
    return RADIUS_END + (RADIUS_MID - RADIUS_END) * (1 - t * t)


def new_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


# ---------------------------------------------------------------- barrel

def build_stave(i, rng):
    rings = 6
    a0 = i * 2 * math.pi / STAVES
    arc = (2 * math.pi * RADIUS_END / STAVES - STAVE_GAP) / RADIUS_END
    top = HEIGHT + rng.uniform(-0.012, 0.012)  # uneven stave tops read as hand-made
    bm = bmesh.new()
    grid = []
    for r in range(rings + 1):
        z = top * r / rings
        ro = radius_at(z)
        ri = ro - STAVE_THICKNESS
        row = []
        for a in (a0, a0 + arc):
            row.append(bm.verts.new((ro * math.cos(a), ro * math.sin(a), z)))
            row.append(bm.verts.new((ri * math.cos(a), ri * math.sin(a), z)))
        grid.append(row)  # [outer0, inner0, outer1, inner1]
    for r in range(rings):
        lo, hi = grid[r], grid[r + 1]
        bm.faces.new((lo[0], lo[2], hi[2], hi[0]))
        bm.faces.new((lo[3], lo[1], hi[1], hi[3]))
        bm.faces.new((lo[1], lo[0], hi[0], hi[1]))
        bm.faces.new((lo[2], lo[3], hi[3], hi[2]))
    bot, tp = grid[0], grid[-1]
    bm.faces.new((bot[0], bot[1], bot[3], bot[2]))
    bm.faces.new((tp[2], tp[3], tp[1], tp[0]))
    obj = new_object(f"stave_{i}", bm)

    tone = rng.choice(WOOD)
    shade = rng.uniform(0.92, 1.06)

    def color(poly, co):
        n = poly.normal
        radial = n.x * math.cos(a0 + arc / 2) + n.y * math.sin(a0 + arc / 2)
        if radial < -0.5 or abs(n.z) > 0.9:
            return WOOD_DARK  # inner wall and end grain
        base = tuple(min(1.0, c * shade) for c in tone)
        # Lighter near the top and bottom edges, a classic painted-prop trick.
        edge = max(0.0, 1 - min(co.z, top - co.z) / 0.08)
        return mix(base, mix(base, (1, 1, 1), 0.25), edge)

    common.paint(obj, color)
    return obj


def build_bottom():
    bpy.ops.mesh.primitive_cylinder_add(vertices=STAVES, radius=RADIUS_END - STAVE_THICKNESS * 0.6,
                                        depth=0.04, location=(0, 0, 0.08))
    obj = bpy.context.active_object
    common.paint(obj, lambda p, c: WOOD_DARK)
    return obj


def build_hoop(z, width):
    bm = bmesh.new()
    segs = 24
    r = radius_at(z) + HOOP_THICKNESS * 0.3
    rings = []
    for k in range(segs):
        a = 2 * math.pi * k / segs
        c, s = math.cos(a), math.sin(a)
        ring = []
        for dz, dr in ((-width / 2, 0), (-width / 2, HOOP_THICKNESS), (width / 2, HOOP_THICKNESS), (width / 2, 0)):
            ring.append(bm.verts.new(((r + dr - HOOP_THICKNESS * 0.5) * c, (r + dr - HOOP_THICKNESS * 0.5) * s, z + dz)))
        rings.append(ring)
    for k in range(segs):
        a, b = rings[k], rings[(k + 1) % segs]
        for j in range(4):
            bm.faces.new((a[j], b[j], b[(j + 1) % 4], a[(j + 1) % 4]))
    obj = new_object("hoop", bm)
    common.paint(obj, lambda p, c: IRON_EDGE if abs(p.normal.z) > 0.5 else IRON)
    return obj


# ---------------------------------------------------------------- hay

def mound_height(d, wide, rim_z):
    """Height of the hay dome at distance d from the center."""
    t = min(1.0, d / wide)
    return rim_z + 0.02 + MOUND_HEIGHT * (1 - t ** 2.2)


def build_mound(rng, wide, rim_z):
    """Faceted dome that fills the barrel mouth and rounds over the rim."""
    bm = bmesh.new()
    rings, segs = 6, 14
    center = bm.verts.new((0, 0, mound_height(0, wide, rim_z)))
    verts = []
    for r in range(1, rings + 1):
        d = wide * r / rings
        row = []
        for k in range(segs):
            a = 2 * math.pi * (k + 0.5 * (r % 2)) / segs
            jd = d * rng.uniform(0.95, 1.05)
            z = mound_height(jd, wide, rim_z) + rng.uniform(-0.025, 0.025)
            if r == rings:
                z = rim_z - 0.03  # tuck the edge just inside/over the rim
            row.append(bm.verts.new((jd * math.cos(a), jd * math.sin(a), z)))
        verts.append(row)
    for k in range(segs):
        bm.faces.new((center, verts[0][k], verts[0][(k + 1) % segs]))
    for r in range(rings - 1):
        a, b = verts[r], verts[r + 1]
        for k in range(segs):
            bm.faces.new((a[k], b[k], b[(k + 1) % segs], a[(k + 1) % segs]))
    bottom = bm.verts.new((0, 0, rim_z - 0.06))
    for k in range(segs):
        bm.faces.new((verts[-1][(k + 1) % segs], verts[-1][k], bottom))
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    obj = new_object("mound", bm)
    common.paint(obj, lambda p, c: mix(HAY_BASE, HAY_TONES[1], max(0.0, min(1.0, (c.z - rim_z) / MOUND_HEIGHT))))
    return obj


def build_clump(rng, root, direction, length, width):
    """A pointed straw clump: a flattened, slightly bent 5-sided spike."""
    up = direction.normalized()
    side = up.cross(Vector((0, 0, 1)))
    if side.length < 1e-4:
        side = Vector((1, 0, 0))
    side.normalize()
    side.rotate(Quaternion(up, rng.uniform(0, math.pi)))
    fwd = up.cross(side).normalized()
    bend = (side * rng.uniform(-0.3, 0.3) + fwd * rng.uniform(-0.3, 0.3)) * length

    bm = bmesh.new()
    base = []
    for k in range(5):
        a = 2 * math.pi * k / 5
        # Flattened cross-section so clumps read as blades of straw, not cones.
        base.append(bm.verts.new(root + side * math.cos(a) * width + fwd * math.sin(a) * width * 0.45))
    mid = [bm.verts.new(v.co.lerp(root + up * length * 0.55 + bend * 0.4, 0.55)) for v in base]
    tip = bm.verts.new(root + up * length + bend)
    for k in range(5):
        n = (k + 1) % 5
        bm.faces.new((base[k], base[n], mid[n], mid[k]))
        bm.faces.new((mid[k], mid[n], tip))
    bm.faces.new(list(reversed(base)))
    obj = new_object("clump", bm)

    tone = rng.choice(HAY_TONES)
    tip_tone = mix(tone, HAY_TIP, rng.uniform(0.4, 0.8))
    root_z, tip_z = root.z, (root + up * length + bend).z
    span = max(1e-4, tip_z - root_z)

    def color(poly, co):
        t = max(0.0, min(1.0, (co.z - root_z) / span)) if span > 0.02 else 0.5
        return mix(mix(HAY_BASE, tone, 0.6), tip_tone, t) if t > 0.15 else mix(HAY_BASE, tone, 0.6)

    common.paint(obj, color)
    return obj


def build_hay(rng):
    rim_z = HEIGHT
    wide = (RADIUS_END + 0.01) * MOUND_OVERHANG
    parts = [build_mound(rng, wide, rim_z)]
    for i in range(CLUMPS):
        # Spread roots evenly over the dome (sunflower pattern + jitter).
        u = (i + 0.5) / CLUMPS
        d = wide * math.sqrt(u) * rng.uniform(0.9, 1.02)
        a = i * 2.399963 + rng.uniform(-0.3, 0.3)
        z = mound_height(min(d, wide), wide, rim_z) - 0.03
        root = Vector((d * math.cos(a), d * math.sin(a), z))
        outward = Vector((math.cos(a), math.sin(a), 0))
        edge = d / wide
        # Clumps lie along the pile like thatch: mostly following the surface
        # outward and down, lifting a little off it, more upright at the crown.
        slope = (mound_height(min(d + 0.02, wide), wide, rim_z) - mound_height(d, wide, rim_z)) / 0.02
        tangent = (outward + Vector((0, 0, slope))).normalized()
        normal = (Vector((0, 0, 1)) - outward * slope).normalized()
        lift = rng.uniform(0.25, 0.6) + (0.5 if edge < 0.25 else 0.0)
        direction = tangent + normal * lift
        if edge > 0.85:
            direction.z -= rng.uniform(0.2, 0.6)  # spill over the rim
        direction += Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), 0))
        length = rng.uniform(0.11, 0.20)
        width = rng.uniform(0.05, 0.085)
        parts.append(build_clump(rng, root, direction, length, width))
    return parts


def build(rng):
    """Build the barrel and hay meshes in the current scene; returns [barrel, hay]."""
    wood = common.vertex_color_material("Wood", roughness=0.85)
    iron = common.vertex_color_material("Iron", roughness=0.45, metallic=0.6)
    hay = common.vertex_color_material("Hay", roughness=0.95)

    staves = [build_stave(i, rng) for i in range(STAVES)] + [build_bottom()]
    for o in staves:
        common.assign(o, wood)
    hoops = [build_hoop(z, w) for z, w in HOOPS]
    for o in hoops:
        common.assign(o, iron)
    barrel = common.join(staves + hoops, "HayBarrel_Barrel")
    common.flat(barrel)

    hay_parts = build_hay(rng)
    for o in hay_parts:
        common.assign(o, hay)
    hay_obj = common.join(hay_parts, "HayBarrel_Hay")
    common.flat(hay_obj)
    return [barrel, hay_obj]


def main():
    args = common.parse_args("hay_barrel")
    common.reset_scene()
    common.export(build(random.Random(SEED)), args)


if __name__ == "__main__":
    main()

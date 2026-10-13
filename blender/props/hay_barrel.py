"""Hay barrel: a short wooden stave tub overflowing with a tall hay heap.

Mostly hay by design: the barrel is a low tub and the hay mound is wider than
the rim and stands taller than the barrel itself.

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

import bpy

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import common  # noqa: E402

# Dimensions in meters (Roblox: 1 stud = 0.28 m, so the whole prop is ~3.6 x 5 studs).
HEIGHT = 0.6           # barrel (tub) height; the hay above it is taller than this
RADIUS_END = 0.42      # radius at top and bottom
RADIUS_MID = 0.46      # bulge at the middle
STAVES = 14
STAVE_THICKNESS = 0.035
STAVE_GAP = 0.012      # gap between staves, as arc length
HOOP_HEIGHTS = (0.09, 0.5)
HOOP_WIDTH = 0.045
HOOP_THICKNESS = 0.012
HAY_TOP = HEIGHT + 0.6  # top of the hay heap
HAY_OVERHANG = 1.12      # hay bulges out past the rim by this factor
HAY_TUFTS = 70
SEED = 7


def radius_at(z):
    """Barrel profile: parabolic bulge between the end radius and mid radius."""
    t = (z / HEIGHT) * 2 - 1  # -1 at bottom, 1 at top
    return RADIUS_END + (RADIUS_MID - RADIUS_END) * (1 - t * t)


def build_staves():
    import bmesh
    rings = 10
    objs = []
    circumference = 2 * math.pi * RADIUS_END
    stave_arc = (circumference / STAVES - STAVE_GAP) / RADIUS_END  # angle at the ends
    for i in range(STAVES):
        a0 = i * 2 * math.pi / STAVES
        bm = bmesh.new()
        grid = []
        for r in range(rings + 1):
            z = HEIGHT * r / rings
            ro = radius_at(z)
            ri = ro - STAVE_THICKNESS
            row = []
            for edge in (0, 1):
                a = a0 + edge * stave_arc
                row.append(bm.verts.new((ro * math.cos(a), ro * math.sin(a), z)))
                row.append(bm.verts.new((ri * math.cos(a), ri * math.sin(a), z)))
            grid.append(row)  # [outer0, inner0, outer1, inner1]
        for r in range(rings):
            lo, hi = grid[r], grid[r + 1]
            bm.faces.new((lo[0], lo[2], hi[2], hi[0]))  # outer
            bm.faces.new((lo[3], lo[1], hi[1], hi[3]))  # inner
            bm.faces.new((lo[1], lo[0], hi[0], hi[1]))  # side 0
            bm.faces.new((lo[2], lo[3], hi[3], hi[2]))  # side 1
        bot, top = grid[0], grid[-1]
        bm.faces.new((bot[0], bot[1], bot[3], bot[2]))
        bm.faces.new((top[2], top[3], top[1], top[0]))
        mesh = bpy.data.meshes.new(f"stave_{i}")
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(mesh.name, mesh)
        bpy.context.collection.objects.link(obj)
        objs.append(obj)
    return objs


def build_bottom():
    bpy.ops.mesh.primitive_cylinder_add(vertices=STAVES * 2, radius=RADIUS_END - STAVE_THICKNESS * 0.5,
                                        depth=0.04, location=(0, 0, 0.06))
    return bpy.context.active_object


def build_hoops():
    objs = []
    for z in HOOP_HEIGHTS:
        r = radius_at(z) + HOOP_THICKNESS * 0.5
        bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=r, depth=HOOP_WIDTH,
                                            location=(0, 0, z), end_fill_type="NOTHING")
        hoop = bpy.context.active_object
        mod = hoop.modifiers.new("thick", "SOLIDIFY")
        mod.thickness = HOOP_THICKNESS
        mod.offset = 0
        bpy.ops.object.modifier_apply(modifier=mod.name)
        objs.append(hoop)
    return objs


def build_hay(rng):
    """A lumpy heap that overflows the rim, plus loose straws all over it."""
    inner = RADIUS_END - STAVE_THICKNESS - 0.005
    rim_z = HEIGHT
    wide = RADIUS_END * HAY_OVERHANG
    lumps = [(rng.uniform(0, 2 * math.pi), rng.uniform(1, 3), rng.uniform(0.015, 0.035)) for _ in range(5)]

    def lump(x, y, z):
        a = math.atan2(y, x)
        return 1 + sum(amp * math.sin(round(f) * a + ph + z * 1.5) for ph, f, amp in lumps) + rng.uniform(-0.015, 0.015)

    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=1.0, location=(0, 0, 0))
    dome = bpy.context.active_object
    for v in dome.data.vertices:
        x, y, z = v.co
        n = lump(x, y, z)
        if z >= 0:
            # Upper half: a wide, tall heap sitting just above the rim.
            v.co = (x * wide * n, y * wide * n, rim_z + 0.04 + z * (HAY_TOP - rim_z - 0.04) * (1 + (n - 1) * 0.5))
        else:
            # Lower half: tuck back in under the overhang and down into the tub.
            t = -z
            h = math.hypot(x, y)
            r = (wide + (inner - wide) * t) * n
            dx, dy = (x / h, y / h) if h > 1e-6 else (0.0, 0.0)
            v.co = (dx * r, dy * r, rim_z + 0.04 - t * 0.25)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.remove_doubles(threshold=0.005)
    bpy.ops.object.mode_set(mode="OBJECT")

    tufts = []
    for i in range(HAY_TUFTS):
        a = rng.uniform(0, 2 * math.pi)
        u = rng.uniform(0, 1)
        if i < HAY_TUFTS // 3:
            # Straws drooping over the rim.
            d, z = wide * rng.uniform(0.95, 1.05), rim_z + rng.uniform(0.0, 0.12)
            rot = (rng.uniform(-0.3, 0.3), rng.uniform(0.6, 1.2), a + rng.uniform(-0.5, 0.5))
        else:
            # Straws lying on the heap surface.
            d = wide * math.sqrt(u) * 0.95
            z = rim_z + 0.04 + (HAY_TOP - rim_z - 0.04) * math.sqrt(max(0.0, 1 - (d / wide) ** 2))
            rot = (rng.uniform(-0.5, 0.5), rng.uniform(-0.6, 0.6), rng.uniform(0, math.pi))
        bpy.ops.mesh.primitive_cube_add(size=1, location=(d * math.cos(a), d * math.sin(a), z))
        t = bpy.context.active_object
        t.scale = (rng.uniform(0.14, 0.28), 0.009, 0.009)
        t.rotation_euler = rot
        tufts.append(t)
    return [dome] + tufts


def main():
    args = common.parse_args("hay_barrel")
    common.reset_scene()
    rng = random.Random(SEED)

    wood = common.material("Wood", (0.42, 0.26, 0.13), roughness=0.85)
    iron = common.material("Iron", (0.18, 0.18, 0.19), roughness=0.5, metallic=0.8)
    hay = common.material("Hay", (0.86, 0.72, 0.36), roughness=0.95)

    staves = build_staves() + [build_bottom()]
    for o in staves:
        common.assign(o, wood)
    hoops = build_hoops()
    for o in hoops:
        common.assign(o, iron)
    barrel = common.join(staves + hoops, "HayBarrel_Barrel")
    common.shade_smooth(barrel)

    hay_parts = build_hay(rng)
    for o in hay_parts:
        common.assign(o, hay)
    hay_obj = common.join(hay_parts, "HayBarrel_Hay")
    common.shade_smooth(hay_obj, 60)

    common.export([barrel, hay_obj], args)


main()

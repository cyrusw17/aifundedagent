"""Hay barrel: wooden stave barrel with iron hoops, filled with a hay mound.

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

# Dimensions in meters (Roblox: 1 stud = 0.28 m, so this barrel is ~3.2 x 4 studs).
HEIGHT = 1.1
RADIUS_END = 0.38      # radius at top and bottom
RADIUS_MID = 0.45      # bulge at the middle
STAVES = 14
STAVE_THICKNESS = 0.035
STAVE_GAP = 0.012      # gap between staves, as arc length
HOOP_HEIGHTS = (0.12, 0.38, 0.72, 0.98)
HOOP_WIDTH = 0.045
HOOP_THICKNESS = 0.012
HAY_TOP = HEIGHT + 0.12  # hay heaps slightly above the rim
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
    """A noisy dome sitting inside the rim, plus a few loose straw tufts."""
    inner = RADIUS_END - STAVE_THICKNESS - 0.005
    rim_z = HEIGHT - 0.06
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=10, radius=1.0, location=(0, 0, 0))
    dome = bpy.context.active_object
    for v in dome.data.vertices:
        x, y, z = v.co
        if z < 0:
            z = 0  # flatten the lower half into a disc
        n = 1 + rng.uniform(-0.06, 0.06)
        v.co = (x * inner * n, y * inner * n, rim_z + z * (HAY_TOP - rim_z) * n)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.remove_doubles(threshold=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")

    tufts = []
    for _ in range(18):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(0.05, inner * 0.85)
        x, y = d * math.cos(a), d * math.sin(a)
        surface = rim_z + (HAY_TOP - rim_z) * math.sqrt(max(0.0, 1 - (d / inner) ** 2))
        length = rng.uniform(0.12, 0.22)
        bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, surface + 0.01))
        t = bpy.context.active_object
        t.scale = (length, 0.008, 0.008)
        t.rotation_euler = (rng.uniform(-0.4, 0.4), rng.uniform(-0.5, 0.5), rng.uniform(0, math.pi))
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

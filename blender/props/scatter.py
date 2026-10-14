"""Region scatter props (art specs, MODEL_SPECS.md "Region scatter props"): low-poly trees, cacti,
rocks, reeds, a dune and a firefly that the Map thread places hundreds of times.

Everything is flat-shaded and unbevelled except the oak leaf cubes (one-segment chamfer), and every
prop stays under its triangle budget (trees 300 or less, rocks 80 or less). Colors are the STYLE.md
"Regions" leaves, bark and ground for each region. Rocks are neutral grey stone, tinted in game.

  oak_tree_a/b/c     Meadow       blocky leaf cubes on a 10-sided trunk
  pine_tree_a/b/c    Pine Forest  stacked 8-sided cones over a visible trunk
  snowpine_tree_a/b  Snow Peak    the pine with a white snow band on each tier (separate "snow" material)
  cactus_a/b         Desert       block saguaro with one or two arms
  dead_tree_a/b      Swamp        leaning bare trunk with forked branches
  reeds_clump        Swamp        thin tapered reeds with two cattail heads
  rock_a/b/c         any          irregular flat-ish stone blobs
  dune_mound         Desert       low faceted sand mound
  firefly            Swamp        tiny glow cube

Run:
  python blender/props/rustic_props.py --out <dir> --category scatter
"""
import math
import os
import random
import sys

import bpy  # noqa: F401  (must be imported before bmesh/mathutils with the pip bpy module)
import bmesh  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
from style import box  # noqa: E402

STUD = 0.28


def s(*v):
    return tuple(x * STUD for x in v)


def flat(obj):
    for p in obj.data.polygons:
        p.use_smooth = False
    return obj


def mesh_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    return o


def frustum(f, kind, r1, r2, h, base, sides=8, lean=(0, 0), top=True, bottom=False, twist=0.0):
    """A tapered n-sided tube from base (studs) up h studs, leaning by (dx, dy) at the top.
    r2 = 0 makes a cone. Caps only where asked, to save triangles."""
    bm = bmesh.new()
    bx, by, bz = base
    lo, hi = [], []
    for i in range(sides):
        a = 2 * math.pi * i / sides + twist
        lo.append(bm.verts.new(s(bx + r1 * math.cos(a), by + r1 * math.sin(a), bz)))
        if r2 > 0:
            hi.append(bm.verts.new(s(bx + lean[0] + r2 * math.cos(a), by + lean[1] + r2 * math.sin(a), bz + h)))
    if r2 > 0:
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
        if top:
            bm.faces.new(hi)
    else:
        tip = bm.verts.new(s(bx + lean[0], by + lean[1], bz + h))
        for i in range(sides):
            bm.faces.new((lo[i], lo[(i + 1) % sides], tip))
    if bottom:
        bm.faces.new(list(reversed(lo)))
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    return f.apply(flat(mesh_obj(kind, bm)), kind, along="z")


def hull(f, kind, points):
    """Convex hull of points (studs): faceted rocks, leaf clumps and dunes."""
    bm = bmesh.new()
    for p in points:
        bm.verts.new(s(*p))
    bmesh.ops.convex_hull(bm, input=bm.verts[:])
    for v in [v for v in bm.verts if not v.link_faces]:
        bm.verts.remove(v)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return f.apply(flat(mesh_obj(kind, bm)), kind, along="z")


def leaf_cube(f, kind, size, loc, rot):
    """A chamfered leaf cube (one bevel segment keeps it at 44 triangles)."""
    o = box(s(*size), s(*loc), rot=rot)
    m = o.modifiers.new("bevel", "BEVEL")
    m.width = min(size) * STUD * 0.14
    m.segments = 1
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=m.name)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(o.data)
    bm.free()
    return f.apply(flat(o), kind, along="z")


# ---------------------------------------------------------------- trees

def oak(height, canopy, seed):
    rng = random.Random(seed)

    def build(f):
        trunk_h = height * 0.5
        p = [frustum(f, "bark", 0.9, 0.65, trunk_h + 1.5, (0, 0, 0), sides=10, top=False)]
        # A short limb toward the biggest cube so the canopy reads as held up.
        p.append(frustum(f, "bark", 0.4, 0.25, 3.0, (0, 0, trunk_h - 1.0), sides=5, lean=(1.8, 0.6), top=False))
        cubes = [(canopy * 0.62, (0.6, 0.3, 0)),
                 (canopy * 0.5, (-canopy * 0.22, -canopy * 0.12, -0.6)),
                 (canopy * 0.46, (canopy * 0.14, -canopy * 0.2, canopy * 0.28)),
                 (canopy * 0.4, (-canopy * 0.12, canopy * 0.22, canopy * 0.2))]
        top = height
        for i, (c, (x, y, dz)) in enumerate(cubes):
            sz = (c * rng.uniform(0.95, 1.1), c * rng.uniform(0.9, 1.05), c * rng.uniform(0.62, 0.75))
            z = trunk_h + sz[2] / 2 + dz
            z = min(z, top - sz[2] / 2)
            p.append(leaf_cube(f, "leaf_oak", sz, (x, y, z), (0, 0, rng.uniform(-0.5, 0.5))))
        return p
    return build


def pine_tiers(height, seed, tiers):
    """Tier list [(r, base_z, h)] for a pine of the given height."""
    rng = random.Random(seed)
    trunk_show = height * 0.2
    span = height - trunk_show
    out = []
    z = trunk_show
    for i in range(tiers):
        frac = 1 - i / tiers
        r = (2.4 + 3.6 * frac) * rng.uniform(0.92, 1.06) * (height / 22) ** 0.5
        h = span / tiers * (1.7 if i < tiers - 1 else 1.4)
        out.append((r, z, h))
        z += span / tiers * 0.8
    return out


def pine(height, tiers, seed, snowy=False):
    def build(f):
        leaf = "leaf_snow" if snowy else "leaf_pine"
        p = [frustum(f, "bark_pine", 0.7, 0.35, height * 0.5, (0, 0, 0), sides=6, top=False)]
        ts = pine_tiers(height, seed, tiers)
        for i, (r, z, h) in enumerate(ts):
            tw = i * 0.4
            p.append(frustum(f, leaf, r, 0, h, (0, 0, z), sides=8, bottom=True, twist=tw))
            if snowy:
                # Snow band on the upper visible part of the tier: a slightly larger cone slice from
                # mid tier up to where the next tier starts (or to the tip on the top tier).
                lo = 0.2 if i < len(ts) - 1 else 0.5
                hi = ((ts[i + 1][1] - z) / h + 0.06) if i < len(ts) - 1 else 1.0
                r_lo, r_hi = r * (1 - lo) + 0.18, r * (1 - min(hi, 1.0)) + 0.18
                if hi >= 1.0:
                    p.append(frustum(f, "snow", r_lo, 0, h * (1 - lo) + 0.15, (0, 0, z + h * lo), sides=8, twist=tw))
                else:
                    p.append(frustum(f, "snow", r_lo, r_hi, h * (hi - lo), (0, 0, z + h * lo), sides=8,
                                     top=False, twist=tw))
        return p
    return build


def cactus(height, arms, seed):
    rng = random.Random(seed)

    def build(f):
        w = 0.75
        p = [frustum(f, "leaf_desert", w, w * 0.9, height - 0.5, (0, 0, 0), sides=6, top=False),
             frustum(f, "leaf_desert", w * 0.9, w * 0.35, 0.5, (0, 0, height - 0.5), sides=6)]
        for i in range(arms):
            side = (1, -1)[i]
            z = height * rng.uniform(0.38, 0.55) + i * 0.8
            reach = rng.uniform(1.4, 1.8)
            up = rng.uniform(1.6, 2.6)
            aw = w * 0.62
            # Elbow: a short sideways block, then the arm going up.
            p.append(frustum(f, "leaf_desert", aw, aw, reach, (0, 0, 0), sides=6, top=False))
            p[-1].data.transform(_turn_x(side, z))
            p.append(frustum(f, "leaf_desert", aw, aw * 0.85, up, (side * reach, 0, z - aw * 0.4), sides=6, top=False))
            p.append(frustum(f, "leaf_desert", aw * 0.85, aw * 0.3, 0.35, (side * reach, 0, z - aw * 0.4 + up), sides=6))
        return p
    return build


def _turn_x(side, z):
    """Matrix laying a z-up tube along +x (side 1) or -x (side -1), lifted to height z (studs)."""
    from mathutils import Matrix
    return Matrix.Translation((0, 0, z * STUD)) @ Matrix.Rotation(side * math.pi / 2, 4, "Y")


def dead_tree(height, seed):
    rng = random.Random(seed)

    def build(f):
        lean = (rng.uniform(1.2, 2.2), rng.uniform(-0.8, 0.8))
        p = [frustum(f, "bark_swamp", 0.85, 0.3, height, (0, 0, 0), sides=6, lean=lean, top=True)]
        # Root flare so it sits in the mud.
        p.append(frustum(f, "bark_swamp", 1.4, 0.8, 0.8, (0, 0, 0), sides=6, top=False))
        for i in range(3 if seed % 2 else 2):
            t = 0.45 + i * 0.17
            bx, by, bz = lean[0] * t, lean[1] * t, height * t
            a = rng.uniform(0, 2 * math.pi) if i else math.atan2(-lean[1], -lean[0]) + 0.6
            ln = rng.uniform(5.0, 6.5) * (1 - i * 0.12)
            dx, dy = math.cos(a) * ln * 0.75, math.sin(a) * ln * 0.75
            p.append(frustum(f, "bark_swamp", 0.45, 0.14, ln * 0.7, (bx, by, bz), sides=5, lean=(dx, dy), top=False))
            # Fork: a smaller twig off the branch end.
            fx, fy, fz = bx + dx * 0.6, by + dy * 0.6, bz + ln * 0.42
            p.append(frustum(f, "bark_swamp", 0.24, 0.07, ln * 0.4, (fx, fy, fz), sides=4,
                             lean=(dx * 0.1 - dy * 0.35, dy * 0.1 + dx * 0.35), top=False))
        return p
    return build


def reeds_clump(f):
    rng = random.Random(7)
    p = []
    for i in range(8):
        a = 2 * math.pi * i / 8 + rng.uniform(-0.3, 0.3)
        d = rng.uniform(0.3, 1.2)
        x, y = d * math.cos(a), d * math.sin(a)
        h = rng.uniform(2.0, 3.0)
        p.append(frustum(f, "leaf_swamp", 0.16, 0, h, (x, y, 0), sides=3,
                         lean=(x * 0.35, y * 0.35)))
    for x, y, h in ((0.3, 0.2, 2.6), (-0.5, -0.3, 2.3)):
        p.append(frustum(f, "leaf_swamp", 0.08, 0.08, h, (x, y, 0), sides=3, top=False))
        p.append(frustum(f, "bark_swamp", 0.13, 0.13, 0.55, (x, y, h - 0.1), sides=5))
    return p


# ---------------------------------------------------------------- ground

def rock(size, flatness, seed):
    rng = random.Random(seed)

    def build(f):
        pts = []
        for i in range(11):
            a = 2 * math.pi * i / 11 + rng.uniform(-0.25, 0.25)
            z = rng.uniform(0, 1)
            r = size / 2 * rng.uniform(0.75, 1.0) * (1 - 0.35 * z * z)
            pts.append((r * math.cos(a), r * math.sin(a) * rng.uniform(0.7, 0.95), z * size * flatness))
        pts.append((rng.uniform(-0.2, 0.2) * size, 0, size * flatness * rng.uniform(1.0, 1.15)))
        return [hull(f, "stone", pts)]
    return build


def dune_mound(f):
    rng = random.Random(3)
    pts = []
    for i in range(10):
        a = 2 * math.pi * i / 10
        pts.append((15 * math.cos(a) * rng.uniform(0.9, 1.0), 10 * math.sin(a) * rng.uniform(0.9, 1.0), 0))
    for i in range(6):
        a = 2 * math.pi * i / 6 + 0.3
        pts.append((8 * math.cos(a), 5 * math.sin(a), rng.uniform(2.2, 2.8)))
    pts.append((-2, 1, 4.0))
    pts.append((3, -1, 3.6))
    o = hull(f, "sand", pts)
    # Drop the flat underside: the mound sits on terrain.
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[fc for fc in bm.faces if fc.normal.z < -0.99], context="FACES")
    bm.to_mesh(o.data)
    bm.free()
    return [o]


def firefly(f):
    o = box(s(0.3, 0.3, 0.3), s(0, 0, 0.15))
    return [f.apply(flat(o), "firefly")]


PROPS = {
    "oak_tree_a": oak(16, 12, 1),
    "oak_tree_b": oak(19, 14, 2),
    "oak_tree_c": oak(15.5, 10.5, 3),
    "pine_tree_a": pine(22, 4, 11),
    "pine_tree_b": pine(27, 4, 12),
    "pine_tree_c": pine(17, 3, 13),
    "snowpine_tree_a": pine(22, 4, 21, snowy=True),
    "snowpine_tree_b": pine(18, 3, 22, snowy=True),
    "cactus_a": cactus(9, 2, 31),
    "cactus_b": cactus(7, 1, 32),
    "dead_tree_a": dead_tree(16, 41),
    "dead_tree_b": dead_tree(13, 42),
    "reeds_clump": reeds_clump,
    "rock_a": rock(6.4, 0.5, 53),
    "rock_b": rock(3.5, 0.55, 52),
    "rock_c": rock(2.0, 0.6, 51),
    "dune_mound": dune_mound,
    "firefly": firefly,
}

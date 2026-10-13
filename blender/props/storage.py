"""Storage props in the house style (LT2 shapes, Rustic finish): mill bins, silos, bale rack,
needle tray and vault, plus fence posts and a driveway tile for plot dressing.

Builders only: props/rustic_props.py builds, exports and catalogs them (--category storage).
"""
import math
import os
import sys

import bpy  # must be imported before bmesh/mathutils with the pip bpy module
import bmesh  # noqa: E402,F401
from mathutils import Matrix  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, HERE)
import hay_bale  # noqa: E402
import style  # noqa: E402
from style import box, cap_uv, cyl  # noqa: E402,F401

STUD = 0.28
S = STUD


# ---------------------------------------------------------------- helpers

def fin(f, obj, kind, along="x", rounded=True):
    """Shape and texture one part."""
    return f.apply(f.shape(obj, round_edges=rounded), kind, along=along)


def cone(r1, r2, depth, loc, verts=12, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return o


def bake(obj, angle=0.0, offset=(0, 0, 0)):
    """Bake the object's transform into its mesh, then turn it about world Z and shift it."""
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    obj.data.transform(Matrix.Translation(offset) @ Matrix.Rotation(angle, 4, "Z"))
    obj.data.update()
    return obj


def ladder(height, width, rung_gap=0.9 * S, rail=0.14 * S, cage=False, cage_from=2.4):
    """Raw ladder parts standing at x=0 against a wall on its -y side, climbing up from z=0.
    Returns [(obj, along, rounded)]."""
    out = []
    for x in (-width / 2, width / 2):
        out.append((box((rail, rail, height), (x, -0.35 * S, height / 2)), "z", False))
        # Stand-off brackets to the wall.
        for z in (0.6 * S, height * 0.5, height - 0.4 * S):
            out.append((box((rail * 0.7, 0.45 * S, rail * 0.7), (x, -0.15 * S, z)), "y", False))
    n = int((height - 0.5 * S) / rung_gap)
    for i in range(n):
        z = 0.5 * S + i * rung_gap
        out.append((cyl(rail * 0.35, width, (0, -0.35 * S, z), verts=6, rot=(0, math.pi / 2, 0)), "x", False))
    if cage:
        r = width * 0.75
        z = cage_from * S + height * 0  # first hoop above head height
        hoops = []
        while z < height:
            hoops.append(z)
            z += 2.2 * S
        for z in hoops:
            # Half-hoop out from the wall, as a thin open cylinder slice.
            bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=r, depth=0.1 * S, location=(0, -0.35 * S, z),
                                                end_fill_type="NOTHING")
            h = bpy.context.active_object
            bm = bmesh.new()
            bm.from_mesh(h.data)
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y > 0.01], context="VERTS")
            m = bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.06 * S)
            bm.to_mesh(h.data)
            bm.free()
            out.append((h, "x", False))
        for a in (-0.6, 0.0, 0.6):
            ang = -math.pi / 2 + a * 1.4
            x, y = r * math.cos(ang), -0.35 * S + r * math.sin(ang)
            out.append((box((0.08 * S, 0.08 * S, hoops[-1] - hoops[0]), (x, y, (hoops[0] + hoops[-1]) / 2)), "z",
                        False))
    return out


def place(f, raw, kind, angle=0.0, offset=(0, 0, 0)):
    return [fin(f, bake(o, angle, offset), kind, along, rounded) for o, along, rounded in raw]


def heap(r, h, loc, verts=10):
    """Rounded heap of hay: a squat cone with a soft top."""
    o = cone(r, r * 0.35, h, (loc[0], loc[1], loc[2] + h / 2), verts=verts)
    return o


def square_hopper(top_half, bottom_half, depth, z_top):
    """Upside-down square pyramid frustum (bin hopper)."""
    o = cone(bottom_half * math.sqrt(2), top_half * math.sqrt(2), depth, (0, 0, z_top - depth / 2), verts=4,
             rot=(0, 0, math.pi / 4))
    return o


def needle(length, r, loc, yaw=0.0):
    """Thin metal needle lying along x with a pointed tip and a flattened eye end."""
    n = cyl(r, length, (0, 0, 0), verts=4, rot=(0, math.pi / 2, 0))
    for v in n.data.vertices:
        if v.co.x > 0:
            v.co.y *= 0.1
            v.co.z *= 0.1
            v.co.x += length * 0.06
    n.data.transform(Matrix.Translation(loc) @ Matrix.Rotation(yaw, 4, "Z"))
    return n


# ---------------------------------------------------------------- mill bins

def plank_walls(f, w, d, z0, h, planks, kind="handle"):
    """Horizontal plank walls around a w x d footprint, with small gaps between planks."""
    parts = []
    ph = h / planks
    t = 0.18 * S
    for i in range(planks):
        z = z0 + ph * (i + 0.5)
        jig = (i % 2) * 0.03 * S
        for y in (-d / 2, d / 2):
            parts.append(fin(f, box((w + jig, t, ph * 0.9), (0, y, z)), kind, "x"))
        for x in (-w / 2, w / 2):
            parts.append(fin(f, box((t, d - t, ph * 0.9), (x, 0, z)), kind, "y"))
    return parts


def corner_posts(f, w, d, z0, z1, size=0.45 * S, kind="handle"):
    return [fin(f, box((size, size, z1 - z0), (x, y, (z0 + z1) / 2)), kind, "z")
            for x in (-w / 2, w / 2) for y in (-d / 2, d / 2)]


def bands(f, w, d, zs, t=0.08 * S, hgt=0.25 * S):
    """Rusty iron straps around a box."""
    parts = []
    for z in zs:
        for y in (-d / 2 - t, d / 2 + t):
            parts.append(fin(f, box((w + 3 * t, t, hgt), (0, y, z)), "metal", "x", False))
        for x in (-w / 2 - t, w / 2 + t):
            parts.append(fin(f, box((t, d + 3 * t, hgt), (x, 0, z)), "metal", "y", False))
    return parts


def mill_bin_small(f):
    """Holds 200 hay. Open plank bin, 4 x 4 x 3.5 studs, on skids, heaped with hay."""
    w, h = 4 * S, 3.5 * S
    parts = []
    for x in (-w / 2 + 0.5 * S, w / 2 - 0.5 * S):
        parts.append(fin(f, box((0.5 * S, w + 0.4 * S, 0.35 * S), (x, 0, 0.175 * S)), "handle", "y"))
    parts.append(fin(f, box((w, w, 0.2 * S), (0, 0, 0.45 * S)), "handle", "x"))
    parts += plank_walls(f, w, w, 0.35 * S, h - 0.35 * S, 4)
    parts += corner_posts(f, w + 0.15 * S, w + 0.15 * S, 0.35 * S, h + 0.15 * S)
    parts += bands(f, w + 0.2 * S, w + 0.2 * S, [h - 0.5 * S])
    parts.append(fin(f, box((w - 0.3 * S, w - 0.3 * S, h - 0.9 * S), (0, 0, (h - 0.3 * S) / 2 + 0.3 * S)), "hay"))
    parts.append(fin(f, heap(w * 0.5, 0.9 * S, (0, 0, h - 0.4 * S), verts=8), "hay", "z"))
    # Painted capacity board on the front.
    parts.append(fin(f, box((1.8 * S, 0.1 * S, 0.7 * S), (0, -w / 2 - 0.12 * S, h * 0.55)), "paint_cream"))
    return parts


def hopper_bin(f, w, body_h, leg_h, hop_h, planks, band_n, metal_roof=False, ladder_side=False):
    """Plank bin raised on legs with a hopper bottom and a slide-gate chute."""
    parts = []
    z0 = leg_h + hop_h * 0.5
    z1 = z0 + body_h
    leg = 0.6 * S
    # Legs with cross braces.
    for x in (-w / 2, w / 2):
        for y in (-w / 2, w / 2):
            parts.append(fin(f, box((leg, leg, z1), (x, y, z1 / 2)), "handle", "z"))
    for y in (-w / 2, w / 2):
        brace = box((w * 1.15, 0.2 * S, 0.4 * S), (0, y + (0.3 * S if y > 0 else -0.3 * S), leg_h * 0.5),
                    rot=(0, math.atan2(leg_h * 0.7, w), 0))
        parts.append(fin(f, brace, "handle", "x"))
    for x in (-w / 2, w / 2):
        brace = box((0.2 * S, w * 1.15, 0.4 * S), (x + (0.3 * S if x > 0 else -0.3 * S), 0, leg_h * 0.5),
                    rot=(math.atan2(leg_h * 0.7, w), 0, 0))
        parts.append(fin(f, brace, "handle", "y"))
    # Hopper and chute.
    parts.append(fin(f, square_hopper(w / 2 - 0.1 * S, 0.7 * S, hop_h, z0 + 0.05 * S), "metal", "z"))
    parts.append(fin(f, box((1.4 * S, 1.4 * S, 0.8 * S), (0, 0, z0 - hop_h - 0.35 * S)), "metal", "z"))
    chute = box((1.1 * S, 2.2 * S, 0.3 * S), (0, -1.0 * S, z0 - hop_h - 0.9 * S), rot=(-0.5, 0, 0))
    parts.append(fin(f, chute, "metal", "y"))
    parts.append(fin(f, box((1.6 * S, 0.15 * S, 0.3 * S), (0, -0.75 * S, z0 - hop_h - 0.2 * S)), "paint_red"))
    # Body.
    parts.append(fin(f, box((w, w, 0.2 * S), (0, 0, z0 + 0.1 * S)), "handle", "x"))
    parts += plank_walls(f, w, w, z0, body_h, planks)
    parts += bands(f, w + 0.1 * S, w + 0.1 * S, [z0 + body_h * (i + 0.5) / band_n for i in range(band_n)])
    if metal_roof:
        # Pitched tin lid with a hatch.
        rh = w * 0.3
        for side in (-1, 1):
            ang = math.atan2(rh, w / 2)
            sl = math.hypot(rh, w / 2) + 0.4 * S
            roof = box((w + 0.8 * S, sl, 0.15 * S), (0, side * w / 4, z1 + rh / 2 + 0.1 * S), rot=(-side * ang, 0, 0))
            parts.append(fin(f, roof, "metal", "x"))
        gable = cone(w / 2 * math.sqrt(2) * 0.98, 0, rh, (0, 0, z1 + rh / 2), verts=4, rot=(0, 0, math.pi / 4))
        for v in gable.data.vertices:  # squash the pyramid into a gable prism
            if v.co.z > 0:
                pass
        bpy.data.objects.remove(gable)
        for x in (-w / 2, w / 2):
            bm = bmesh.new()
            pts = [(-w / 2, z1), (w / 2, z1), (0, z1 + rh)]
            vs = [bm.verts.new((x, y, z)) for y, z in pts]
            bm.faces.new(vs)
            mesh = bpy.data.meshes.new("gable")
            bm.to_mesh(mesh)
            bm.free()
            g = bpy.data.objects.new("gable", mesh)
            bpy.context.collection.objects.link(g)
            bpy.context.view_layer.objects.active = g
            m = g.modifiers.new("s", "SOLIDIFY")
            m.thickness = 0.18 * S
            m.offset = 0
            bpy.ops.object.modifier_apply(modifier=m.name)
            parts.append(fin(f, g, "handle", "y", False))
        parts.append(fin(f, box((1.6 * S, 1.6 * S, 0.25 * S), (0, -w / 4, z1 + rh / 2 + 0.25 * S),
                                rot=(math.atan2(rh, w / 2), 0, 0)), "paint_red"))
    else:
        parts.append(fin(f, box((w - 0.3 * S, w - 0.3 * S, body_h * 0.6), (0, 0, z1 - body_h * 0.3 - 0.4 * S)), "hay"))
        parts.append(fin(f, heap(w * 0.5, 1.2 * S, (0, 0, z1 - 0.45 * S), verts=10), "hay", "z"))
    if ladder_side:
        raw = ladder(z1 + 0.6 * S, 1.4 * S)
        parts += place(f, raw, "metal", angle=math.pi / 2, offset=(w / 2 + 0.25 * S, -w * 0.15, 0))
    parts.append(fin(f, box((2.4 * S, 0.1 * S, 0.9 * S), (0, -w / 2 - 0.15 * S, z0 + body_h * 0.62)), "paint_cream"))
    return parts


def mill_bin_medium(f):
    """Holds 800 hay. 6 x 6 studs, about 8 tall: raised plank bin with a hopper and chute."""
    return hopper_bin(f, 6 * S, 5 * S, 2.6 * S, 1.8 * S, 6, 2)


def mill_bin_large(f):
    """Holds 3,000 hay. 8 x 8 studs, about 14 tall: banded hopper bin with a tin lid and ladder."""
    return hopper_bin(f, 8 * S, 8 * S, 3.4 * S, 2.4 * S, 9, 3, metal_roof=True, ladder_side=True)


# ---------------------------------------------------------------- silos

def corrugated_wall(r, h, z0, sides=32, depth=0.035):
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=r, depth=h, location=(0, 0, z0 + h / 2),
                                        end_fill_type="NOTHING")
    o = bpy.context.active_object
    step = 2 * math.pi / sides
    for v in o.data.vertices:
        i = round(math.atan2(v.co.y, v.co.x) / step)
        if i % 2:
            v.co.x *= 1 - depth
            v.co.y *= 1 - depth
    return o


def silo(f, r, wall_h, roof_h, rings, base=False, cage=False, catwalk=False, vents=1, auger=False):
    parts = []
    z0 = 0.0
    if base:
        bh = 0.8 * S
        parts.append(fin(f, cyl(r + 0.8 * S, bh, (0, 0, bh / 2), verts=24), "stone", "z"))
        z0 = bh
    sides = 32 if r < 10 * S else 40
    parts.append(fin(f, corrugated_wall(r, wall_h, z0, sides), "steel", "z", False))
    zt = z0 + wall_h
    # Horizontal seam rings at the panel joins.
    for i in range(rings + 1):
        z = z0 + 0.15 * S + (wall_h - 0.3 * S) * i / rings
        parts.append(fin(f, cyl(r + 0.05 * S, 0.22 * S, (0, 0, z), verts=sides // 2), "steel", "z", False))
    # Conical roof, eave lip and top ring.
    parts.append(fin(f, cone(r + 0.5 * S, r * 0.12, roof_h, (0, 0, zt + roof_h / 2), verts=sides // 2), "paint_red", "z"))
    parts.append(fin(f, cyl(r + 0.55 * S, 0.3 * S, (0, 0, zt + 0.1 * S), verts=sides // 2), "steel", "z", False))
    parts.append(fin(f, cyl(r * 0.16, 0.7 * S, (0, 0, zt + roof_h + 0.2 * S), verts=10), "metal", "z"))
    parts.append(fin(f, cone(r * 0.22, 0.05, 0.6 * S, (0, 0, zt + roof_h + 0.85 * S), verts=10), "metal", "z"))
    # Roof vents.
    for k in range(vents):
        a = math.radians(-60 + k * 120 / max(1, vents - 1)) if vents > 1 else math.radians(-60)
        rr = r * 0.55
        z = zt + roof_h * (1 - 0.55 / 1.0) + 0.3 * S
        x, y = rr * math.cos(a + math.pi), rr * math.sin(a + math.pi)
        parts.append(fin(f, cyl(0.6 * S, 1.2 * S, (x, y, z + 0.5 * S), verts=8), "metal", "z"))
        parts.append(fin(f, cone(1.0 * S, 0.1 * S, 0.6 * S, (x, y, z + 1.4 * S), verts=8), "metal", "z"))
    # Access door at the base, front.
    dw, dh = min(3 * S, r * 0.5), min(4 * S, wall_h * 0.25)
    parts.append(fin(f, box((dw + 0.4 * S, 0.3 * S, dh + 0.4 * S), (0, -r - 0.05 * S, z0 + dh / 2 + 0.6 * S)), "paint_red"))
    parts.append(fin(f, box((dw, 0.2 * S, dh), (0, -r - 0.2 * S, z0 + dh / 2 + 0.6 * S)), "metal"))
    parts.append(fin(f, box((0.2 * S, 0.3 * S, dh * 0.5), (dw * 0.35, -r - 0.35 * S, z0 + dh / 2 + 0.6 * S)), "metal"))
    # Ladder up the front-right side.
    lang = math.radians(-35)
    lw = 1.4 * S
    raw = ladder(wall_h + (0.5 * S if not catwalk else 0), lw, cage=cage, cage_from=4)
    ang = lang + math.pi / 2  # ladder's -y faces outward
    out = (r + 0.05 * S)
    parts += place(f, raw, "metal", angle=lang + math.pi / 2,
                   offset=(out * math.cos(lang), out * math.sin(lang), z0))
    if catwalk:
        # Ring walkway with a railing round the eave.
        ro = r + 2.4 * S
        bpy.ops.mesh.primitive_cylinder_add(vertices=sides // 2, radius=ro, depth=0.25 * S,
                                            location=(0, 0, zt - 0.15 * S))
        deck = bpy.context.active_object
        bm = bmesh.new()
        bm.from_mesh(deck.data)
        bm.free()
        parts.append(fin(f, deck, "metal", "x", False))
        bpy.ops.mesh.primitive_cylinder_add(vertices=sides // 2, radius=ro, depth=0.15 * S,
                                            location=(0, 0, zt + 1.6 * S), end_fill_type="NOTHING")
        rail = bpy.context.active_object
        m = rail.modifiers.new("s", "SOLIDIFY")
        m.thickness = 0.12 * S
        bpy.context.view_layer.objects.active = rail
        bpy.ops.object.modifier_apply(modifier=m.name)
        parts.append(fin(f, rail, "paint_yellow", "x", False))
        n = sides // 2
        for i in range(n):
            a = 2 * math.pi * (i + 0.5) / n
            parts.append(fin(f, box((0.15 * S, 0.15 * S, 1.7 * S), (ro * math.cos(a), ro * math.sin(a), zt + 0.8 * S)),
                             "paint_yellow", "z", False))
        # Brackets under the deck.
        for i in range(8):
            a = 2 * math.pi * i / 8
            br = box((2.6 * S, 0.2 * S, 0.2 * S), ((r + 1.1 * S) * math.cos(a), (r + 1.1 * S) * math.sin(a), zt - 1.0 * S),
                     rot=(0, -0.6, a))
            parts.append(fin(f, br, "metal", "x", False))
    if auger:
        # Fill auger running up the side from a ground hopper to the roof peak.
        aa = math.radians(-20)
        bx, by = (r + 14 * S) * math.cos(aa), -(r + 14 * S) * math.sin(aa)
        top = ((r + 1.2 * S) * math.cos(aa), (r + 1.2 * S) * math.sin(aa), zt + 2.5 * S)
        foot = (bx, -by, 1.2 * S)
        d = [t - b for t, b in zip(top, foot)]
        length = math.sqrt(sum(c * c for c in d))
        mid = [(t + b) / 2 for t, b in zip(top, foot)]
        tube = cyl(0.55 * S, length, (0, 0, 0), verts=10)
        pitch = math.acos(d[2] / length)
        yaw = math.atan2(d[1], d[0])
        tube.data.transform(Matrix.Translation(mid) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(pitch, 4, "Y"))
        parts.append(fin(f, tube, "paint_green", "z", False))
        # Spout over the eave, down into a roof hatch.
        sp = box((3.4 * S, 1.0 * S, 0.8 * S), (0.2 * S, 0, 0))
        sp.data.transform(Matrix.Translation((r * math.cos(aa), r * math.sin(aa), zt + 2.2 * S)) @ Matrix.Rotation(aa, 4, "Z"))
        parts.append(fin(f, sp, "paint_green", "x"))
        parts.append(fin(f, square_hopper(1.6 * S, 0.6 * S, 1.8 * S, 2.0 * S), "metal", "z"))
        parts[-1].data.transform(Matrix.Translation((bx, -by, 0)))
        for sx in (-1, 1):
            parts.append(fin(f, box((0.3 * S, 0.3 * S, 1.2 * S), (bx + sx * 1.0 * S, -by, 0.6 * S)), "metal", "z"))
        # Support tower halfway up.
        mx, my = foot[0] + d[0] * 0.45, foot[1] + d[1] * 0.45
        mz = foot[2] + d[2] * 0.45
        for sx in (-1, 1):
            parts.append(fin(f, box((0.3 * S, 0.3 * S, mz), (mx, my + sx * 1.2 * S, mz / 2)), "metal", "z", False))
        parts.append(fin(f, box((0.3 * S, 2.7 * S, 0.3 * S), (mx, my, mz - 0.5 * S)), "metal", "y", False))
    return parts


def silo_small(f):
    """Holds 8,000 hay. 10 studs across, about 22 tall: plain corrugated silo with a ladder."""
    return silo(f, 5 * S, 16 * S, 4 * S, 4)


def silo_large(f):
    """Holds 30,000 hay. 16 across, about 36 tall: concrete pad, caged ladder, two roof vents."""
    return silo(f, 8 * S, 28 * S, 6.5 * S, 7, base=True, cage=True, vents=2)


def silo_mega(f):
    """Holds 150,000 hay. 26 across, about 58 tall: catwalk ring, caged ladder, three vents, fill auger."""
    return silo(f, 13 * S, 46 * S, 10 * S, 11, base=True, cage=True, catwalk=True, vents=3, auger=True)


# ---------------------------------------------------------------- bales

def bale(f, loc, yaw=0.0):
    hay_bale.BEVEL = max(f.bevel, 0.001)
    parts = [hay_bale.build_hay()] + hay_bale.build_twine()
    for p in parts:
        bake(p, yaw, loc)
    along = "y" if abs(math.sin(yaw)) > 0.5 else "x"
    return [f.apply(f.shape(parts[0], round_edges=False), "hay", along=along)] + [f.apply(b, "twine") for b in parts[1:]]


def bale_rack(f):
    """Holds 10 bales: two plank shelves of five, bales lying lengthwise front to back.
    About 18.6 x 5.4 x 7.6 studs."""
    bw, bl, bh = hay_bale.SIZE[1], hay_bale.SIZE[0], hay_bale.SIZE[2]
    gap = 0.3 * S
    bay = bw + gap
    w = 5 * bay + 0.3 * S
    d = bl + 0.8 * S
    shelf_z = (0.6 * S, 0.6 * S + bh + 0.9 * S)
    top = shelf_z[1] + bh + 1.0 * S
    parts = []
    post = 0.5 * S
    for i in range(6):
        x = -w / 2 + i * bay + 0.15 * S if 0 < i < 5 else (-w / 2 if i == 0 else w / 2)
        for y in (-d / 2, d / 2):
            parts.append(fin(f, box((post, post, top), (x, y, top / 2)), "handle", "z"))
    for z in shelf_z:
        for y in (-d / 2 + 0.3 * S, d / 2 - 0.3 * S):
            parts.append(fin(f, box((w + 0.3 * S, 0.4 * S, 0.45 * S), (0, y + (0.0), z - 0.25 * S)), "handle", "x"))
        # Shelf boards running front to back.
        for i in range(10):
            x = -w / 2 + (i + 0.5) * w / 10
            parts.append(fin(f, box((w / 10 - 0.08 * S, d - 0.2 * S, 0.15 * S), (x, 0, z + 0.05 * S)), "handle", "y"))
    for y in (-d / 2, d / 2):
        parts.append(fin(f, box((w + 0.4 * S, 0.35 * S, 0.4 * S), (0, y, top - 0.2 * S)), "handle", "x"))
    # Diagonal braces on the back and the ends.
    ang = math.atan2(top - 1.0 * S, w / 2)
    for sx in (-1, 1):
        parts.append(fin(f, box((math.hypot(w / 2, top - S), 0.2 * S, 0.35 * S), (sx * w / 4, d / 2 + 0.3 * S, top / 2),
                                rot=(0, sx * ang, 0)), "handle", "x"))
    # Bales: lower shelf full, upper shelf three (rack partly filled).
    for lvl, count in ((0, 5), (1, 3)):
        for i in range(count):
            x = -w / 2 + 0.15 * S + (i + 0.5) * bay
            parts += bale(f, (x, -0.05 * S + 0.04 * S * (i % 2), shelf_z[lvl] + 0.12 * S), math.pi / 2)
    # Plank sign.
    parts.append(fin(f, box((3.5 * S, 0.12 * S, 0.8 * S), (0, -d / 2 - 0.25 * S, top - 0.2 * S)), "paint_cream"))
    return parts


# ---------------------------------------------------------------- needles

def needle_tray(f):
    """Holds 100 sorted needles of one type. 3 x 2 x 0.5 studs wooden tray, needles laid in rows."""
    w, d, h = 3 * S, 2 * S, 0.5 * S
    t = 0.15 * S
    parts = [fin(f, box((w, d, 0.15 * S), (0, 0, 0.075 * S)), "handle", "x")]
    for y in (-d / 2 + t / 2, d / 2 - t / 2):
        parts.append(fin(f, box((w, t, h), (0, y, h / 2)), "handle", "x"))
    for x in (-w / 2 + t / 2, w / 2 - t / 2):
        parts.append(fin(f, box((t, d - 2 * t, h), (x, 0, h / 2)), "handle", "y"))
    # Felt-lined bed (cloth) and two dividers so needles sit in three rows.
    parts.append(fin(f, box((w - 2 * t, d - 2 * t, 0.05 * S), (0, 0, 0.17 * S)), "cloth", "x", False))
    rows = 3
    inner = d - 2 * t
    for k in range(1, rows):
        y = -inner / 2 + inner * k / rows
        parts.append(fin(f, box((w - 2 * t, 0.06 * S, h * 0.55), (0, y, h * 0.3)), "handle", "x", False))
    import random
    rng = random.Random(7)
    nl = w - 2 * t - 0.3 * S
    for k in range(rows):
        yc = -inner / 2 + inner * (k + 0.5) / rows
        for j in range(7):
            y = yc - inner / rows * 0.3 + j * inner / rows * 0.1
            z = 0.22 * S + (0.035 * S if j % 2 else 0)
            parts.append(f.apply(needle(nl, 0.035 * S, (rng.uniform(-0.1, 0.1) * S, y, z), rng.uniform(-0.03, 0.03)),
                                 "steel"))
    # Brass-ish label plate on the front.
    parts.append(fin(f, box((1.0 * S, 0.06 * S, 0.28 * S), (0, -d / 2 - 0.03 * S, h * 0.5)), "paint_yellow", "x", False))
    return parts


def needle_vault(f):
    """Holds 10,000 needles. 6 x 5 x 7 studs riveted safe on feet, wheel handle, dial and hinges."""
    w, d, h = 6 * S, 5 * S, 7 * S
    feet = 0.5 * S
    parts = []
    for x in (-w / 2 + 0.6 * S, w / 2 - 0.6 * S):
        for y in (-d / 2 + 0.6 * S, d / 2 - 0.6 * S):
            parts.append(fin(f, box((0.8 * S, 0.8 * S, feet), (x, y, feet / 2)), "metal", "z"))
    parts.append(fin(f, box((w, d, h - feet), (0, 0, feet + (h - feet) / 2)), "paint_green", "z"))
    # Plinth and cap trim.
    parts.append(fin(f, box((w + 0.3 * S, d + 0.3 * S, 0.5 * S), (0, 0, feet + 0.25 * S)), "metal", "x"))
    parts.append(fin(f, box((w + 0.3 * S, d + 0.3 * S, 0.4 * S), (0, 0, h - 0.2 * S)), "metal", "x"))
    # Door: a thick panel with a frame.
    dz = feet + 0.5 * S + (h - feet - 0.9 * S) / 2
    dw, dh = w - 1.2 * S, h - feet - 1.7 * S
    fy = -d / 2
    parts.append(fin(f, box((dw + 0.5 * S, 0.2 * S, dh + 0.5 * S), (0, fy - 0.08 * S, dz)), "metal", "x"))
    parts.append(fin(f, box((dw, 0.4 * S, dh), (0, fy - 0.2 * S, dz)), "paint_green", "x"))
    # Rivets round the door edge.
    for i in range(6):
        for zz in (dz - dh / 2 + 0.3 * S, dz + dh / 2 - 0.3 * S):
            x = -dw / 2 + 0.35 * S + i * (dw - 0.7 * S) / 5
            parts.append(f.apply(cyl(0.1 * S, 0.1 * S, (x, fy - 0.42 * S, zz), verts=6, rot=(math.pi / 2, 0, 0)), "metal"))
    # Hinges on the left.
    for zz in (dz - dh * 0.32, dz + dh * 0.32):
        parts.append(fin(f, cyl(0.25 * S, 1.0 * S, (-dw / 2 - 0.1 * S, fy - 0.35 * S, zz), verts=8), "metal", "z"))
    # Wheel handle with spokes.
    wx, wz = -0.3 * S, dz - 0.3 * S
    wr = 1.2 * S
    ring = cyl(wr, 0.18 * S, (0, 0, 0), verts=14, rot=(math.pi / 2, 0, 0))
    bm = bmesh.new()
    bm.from_mesh(ring.data)
    bm.free()
    bpy.ops.mesh.primitive_torus_add(major_radius=wr, minor_radius=0.12 * S, major_segments=14, minor_segments=5,
                                     location=(wx, fy - 0.9 * S, wz), rotation=(math.pi / 2, 0, 0))
    torus = bpy.context.active_object
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    bpy.data.objects.remove(ring)
    parts.append(f.apply(torus, "metal"))
    parts.append(fin(f, cyl(0.35 * S, 0.5 * S, (wx, fy - 0.65 * S, wz), verts=8, rot=(math.pi / 2, 0, 0)), "metal", "y"))
    for k in range(3):
        a = k * math.pi / 3
        sp = box((2 * wr, 0.12 * S, 0.12 * S), (wx, fy - 0.9 * S, wz), rot=(0, a, 0))
        parts.append(fin(f, sp, "metal", "x", False))
        for sgn in (-1, 1):
            parts.append(fin(f, cyl(0.13 * S, 0.5 * S, (wx + sgn * (wr + 0.2 * S) * math.cos(a), fy - 0.9 * S,
                                                         wz + sgn * (wr + 0.2 * S) * math.sin(-a)), verts=6,
                                    rot=(0, math.pi / 2 + a, 0)), "metal", "x", False))
    # Combination dial above the wheel.
    dial_z, dx = dz + 1.3 * S, 1.6 * S
    parts.append(fin(f, cyl(0.6 * S, 0.25 * S, (dx, fy - 0.5 * S, dial_z), verts=12, rot=(math.pi / 2, 0, 0)), "paint_cream", "y"))
    parts.append(fin(f, cyl(0.3 * S, 0.3 * S, (dx, fy - 0.7 * S, dial_z), verts=10, rot=(math.pi / 2, 0, 0)), "metal", "y"))
    # Needle emblem plate across the top of the door.
    pz = dz + dh / 2 - 0.6 * S
    parts.append(fin(f, box((2.8 * S, 0.12 * S, 0.7 * S), (-0.6 * S, fy - 0.45 * S, pz)), "paint_yellow", "x", False))
    parts.append(f.apply(needle(2.2 * S, 0.08 * S, (-0.7 * S, fy - 0.55 * S, pz)), "steel"))
    return parts


# ---------------------------------------------------------------- plot dressing

def fence_post_set(f):
    """A 12-stud run of split-rail fence: three posts with pointed tops, two rails per span."""
    span, ph = 6 * S, 4.2 * S
    parts = []
    import random
    rng = random.Random(3)
    xs = [-span, 0, span]
    for x in xs:
        yaw = rng.uniform(-0.15, 0.15)
        parts.append(fin(f, box((0.6 * S, 0.6 * S, ph), (x, 0, ph / 2), rot=(0, 0, yaw)), "bark", "z"))
        tip = cone(0.3 * S * math.sqrt(2), 0.06 * S, 0.5 * S, (x, 0, ph + 0.25 * S), verts=4,
                   rot=(0, 0, math.pi / 4 + yaw))
        parts.append(fin(f, tip, "bark", "z"))
    for a, b in zip(xs, xs[1:]):
        for z in (1.5 * S, 3.2 * S):
            dz = rng.uniform(-0.15, 0.15) * S
            rail = box((span - 0.1 * S, 0.35 * S, 0.45 * S), ((a + b) / 2, -0.45 * S, z + dz),
                       rot=(rng.uniform(-0.08, 0.08), 0, rng.uniform(-0.015, 0.015)))
            parts.append(fin(f, rail, "handle", "x"))
    # Nails holding the rails.
    for x in xs:
        for z in (1.5 * S, 3.2 * S):
            parts.append(f.apply(cyl(0.07 * S, 0.1 * S, (x, -0.62 * S, z), verts=6, rot=(math.pi / 2, 0, 0)), "metal"))
    return parts


def road_tile(f):
    """A flat 6 x 6 stud driveway tile: packed dirt with two gravel wheel tracks and flat stones."""
    s, t = 6 * S, 0.2 * S
    parts = [fin(f, box((s, s, t), (0, 0, t / 2)), "dirt", "y")]
    # Gravel tracks running front to back.
    for x in (-1.5 * S, 1.5 * S):
        parts.append(fin(f, box((1.4 * S, s, 0.06 * S), (x, 0, t + 0.02 * S)), "stone", "y", False))
    import random
    rng = random.Random(11)
    # Flat embedded stones along the tracks and middle.
    for i in range(6):
        x = rng.uniform(-0.25, 0.25) * S
        y = -2.4 * S + i * 0.96 * S + rng.uniform(-0.15, 0.15) * S
        r = rng.uniform(0.25, 0.36) * S
        st = cyl(r, 0.08 * S, (x, y, t + 0.03 * S), verts=6, rot=(0, 0, rng.uniform(0, 1)))
        k = rng.uniform(0.75, 1.25)
        for v in st.data.vertices:
            v.co.x *= k
        parts.append(f.apply(st, "stone"))
    # Stone kerb edges on the two sides so tiles read as a lane.
    for x in (-s / 2 + 0.2 * S, s / 2 - 0.2 * S):
        parts.append(fin(f, box((0.4 * S, s, 0.12 * S), (x, 0, t + 0.04 * S)), "stone", "y"))
    return parts


PROPS = {
    "mill_bin_small": mill_bin_small,
    "mill_bin_medium": mill_bin_medium,
    "mill_bin_large": mill_bin_large,
    "silo_small": silo_small,
    "silo_large": silo_large,
    "silo_mega": silo_mega,
    "bale_rack": bale_rack,
    "needle_tray": needle_tray,
    "needle_vault": needle_vault,
    "fence_post_set": fence_post_set,
    "road_tile": road_tile,
}

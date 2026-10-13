"""Farm buildings in the house style (LT2 shapes, Rustic finish).

Simple shells: walls, roofs, door openings big enough for players (4+ wide, 7+ tall studs) and
vehicles (truck about 6 x 7 studs), windows and a few signature details. No interiors.

Built and exported by rustic_props.py:
  python blender/props/rustic_props.py --out <dir> --category buildings
"""
import math
import os
import sys

import bpy  # must be imported before bmesh/mathutils with the pip bpy module
import bmesh  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, HERE)
import style  # noqa: E402,F401
from style import box, cap_uv, cyl  # noqa: E402,F401

STUD = 0.28
S = STUD
WALL = 0.8          # wall thickness, studs
BELT_TOP = 3.5      # conveyor belt top above ground, studs
TILE = 6.0          # conveyor grid tile, studs


# ---------------------------------------------------------------- helpers (all sizes in studs)

def B(f, kind, size, loc, along="x", rot=(0, 0, 0), rnd=True):
    """Box part: size and loc in studs."""
    o = box(tuple(v * S for v in size), tuple(v * S for v in loc), rot)
    return f.apply(f.shape(o, round_edges=rnd), kind, along=along)


def C(f, kind, r, depth, loc, verts=12, rot=(0, 0, 0), along="z", rnd=True):
    """Cylinder part (axis z before rot)."""
    o = cyl(r * S, depth * S, tuple(v * S for v in loc), verts=verts, rot=rot)
    return f.apply(f.shape(o, round_edges=rnd), kind, along=along)


def link(bm, name="part"):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    return obj


def to3(axis, at, u, z):
    """Map wall-plane coords (u along the wall, z up) to 3D, in studs. axis 'x': wall runs along x at y=at."""
    return (u, at, z) if axis == "x" else (at, u, z)


def wall(f, kind, axis, at, u0, u1, z0, z1, t=WALL, holes=(), rnd=True):
    """A wall split into blocks around rectangular holes (ua, ub, za, zb)."""
    parts = []
    cuts = sorted({u0, u1} | {h[0] for h in holes} | {h[1] for h in holes})
    for a, b in zip(cuts, cuts[1:]):
        mid = (a + b) / 2
        spans = [(z0, z1)]
        for h in holes:
            if h[0] <= mid <= h[1]:
                new = []
                for za, zb in spans:
                    if h[2] > za:
                        new.append((za, min(zb, h[2])))
                    if h[3] < zb:
                        new.append((max(za, h[3]), zb))
                spans = new
        for za, zb in spans:
            if zb - za > 0.05:
                size = (b - a, t, zb - za) if axis == "x" else (t, b - a, zb - za)
                parts.append(B(f, kind, size, to3(axis, at, mid, (za + zb) / 2), along=axis, rnd=rnd))
    return parts


def prism(f, kind, axis, at, t, pts, along="x", rnd=True):
    """Convex polygon (u, z) in a wall plane, extruded t thick: gable ends, pediments."""
    bm = bmesh.new()
    n = len(pts)
    for d in (-t / 2, t / 2):
        for u, z in pts:
            bm.verts.new(tuple(c * S for c in to3(axis, at + d, u, z)))
    bm.verts.ensure_lookup_table()
    v = bm.verts
    bm.faces.new([v[i] for i in range(n)])
    bm.faces.new([v[n + i] for i in reversed(range(n))])
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([v[i], v[j], v[n + j], v[n + i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return f.apply(f.shape(link(bm, "prism"), round_edges=rnd), kind, along=along)


def slope(pa, pb, t, ridge, length, mid=0.0, over=0.0):
    """Placement of a sloped plate whose underside runs from pa to pb (u, z) in the profile plane.
    ridge: 'y' means the profile is in xz (u = x) and the plate runs along y. over extends both ends."""
    du, dz = pb[0] - pa[0], pb[1] - pa[1]
    ln = math.hypot(du, dz)
    eu, ez = du / ln, dz / ln
    nu, nz = (-ez, eu) if du > 0 else (ez, -eu)
    cu = (pa[0] + pb[0]) / 2 + nu * t / 2
    cz = (pa[1] + pb[1]) / 2 + nz * t / 2
    if ridge == "y":
        return (ln + 2 * over, length, t), (cu, mid, cz), (0, -math.atan2(dz, du), 0)
    return (length, ln + 2 * over, t), (mid, cu, cz), (math.atan2(dz, du), 0, 0)


def plate(f, kind, pa, pb, t, ridge, length, mid=0.0, over=0.0, along=None, rnd=True):
    size, loc, rot = slope(pa, pb, t, ridge, length, mid, over)
    return B(f, kind, size, loc, along=along or ("x" if ridge == "y" else "y"), rot=rot, rnd=rnd)


def corrugated(f, kind, pa, pb, ridge, length, mid=0.0, over=0.0, pitch=1.0, amp=0.25, t=0.12):
    """Corrugated metal sheet laid like plate(); ribs run down the slope."""
    size, loc, rot = slope(pa, pb, t + amp, ridge, length, mid, over)
    run, width = (size[0], size[1]) if ridge == "y" else (size[1], size[0])
    n = max(2, int(round(width / pitch)) * 2)
    bm = bmesh.new()
    prof = [(-width / 2 + width * i / n, amp / 2 if i % 2 else -amp / 2) for i in range(n + 1)]
    rows = []
    for x in (-run / 2, run / 2):
        top = [bm.verts.new((x, w, z + t / 2)) for w, z in prof]
        bot = [bm.verts.new((x, w, z - t / 2)) for w, z in prof]
        rows.append((top, bot))
    (t0, b0), (t1, b1) = rows
    for i in range(n):
        bm.faces.new([t0[i], t0[i + 1], t1[i + 1], t1[i]])
        bm.faces.new([b0[i], b1[i], b1[i + 1], b0[i + 1]])
    for top, bot in rows:
        for i in range(n):
            bm.faces.new([top[i], bot[i], bot[i + 1], top[i + 1]])
    for side in (0, n):
        bm.faces.new([t0[side], b0[side], b1[side], t1[side]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for v in bm.verts:
        v.co *= S
    o = link(bm, "sheet")
    if ridge == "x":  # local x runs down the slope: turn it to run along y first
        o.rotation_euler = (0, 0, math.pi / 2)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    o.location = tuple(c * S for c in loc)
    o.rotation_euler = rot
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=False)
    return f.apply(f.shape(o, round_edges=False), kind, along="x" if ridge == "y" else "y")


def gable_roof(f, kind, half, eave, rise, length, ridge="y", t=0.6, over=1.2, cap="metal", sheet=False):
    """Two roof plates meeting at a ridge. half: half span; eave: wall top z."""
    parts = []
    for s in (-1, 1):
        pa, pb = (s * half, eave), (0, eave + rise)
        ln = math.hypot(half, rise)
        k = over / ln
        pa = (pa[0] + (pa[0] - pb[0]) * k, pa[1] + (pa[1] - pb[1]) * k)
        if sheet:
            parts.append(corrugated(f, kind, pa, pb, ridge, length + 2 * over))
        else:
            parts.append(plate(f, kind, pa, pb, t, ridge, length + 2 * over))
    size = (0.9, length + 2 * over + 0.2, 0.9) if ridge == "y" else (length + 2 * over + 0.2, 0.9, 0.9)
    parts.append(B(f, cap, size, (0, 0, eave + rise + t * 0.9), along=ridge))
    return parts


def window(f, axis, at, out, u, zc, w, h, trim="paint_cream", cross=True):
    """Dark glass pane on a wall face with a trim frame. out: +1/-1 which side of the wall plane is outside."""
    d = 0.12
    parts = []
    gsize = (w, 0.1, h) if axis == "x" else (0.1, w, h)
    parts.append(B(f, "glass", gsize, to3(axis, at + out * 0.05, u, zc), rnd=False))
    for dz in (-1, 1):
        size = (w + 0.8, 0.35, 0.4) if axis == "x" else (0.35, w + 0.8, 0.4)
        parts.append(B(f, trim, size, to3(axis, at + out * d, u, zc + dz * (h / 2 + 0.2)), along=axis, rnd=False))
    for du in (-1, 1):
        size = (0.4, 0.35, h) if axis == "x" else (0.35, 0.4, h)
        parts.append(B(f, trim, size, to3(axis, at + out * d, u + du * (w / 2 + 0.2), zc), along="z", rnd=False))
    if cross:
        size = (0.2, 0.3, h) if axis == "x" else (0.3, 0.2, h)
        parts.append(B(f, trim, size, to3(axis, at + out * d, u, zc), along="z", rnd=False))
        size = (w, 0.3, 0.2) if axis == "x" else (0.3, w, 0.2)
        parts.append(B(f, trim, size, to3(axis, at + out * d, u, zc), along=axis, rnd=False))
    return parts


def door_frame(f, axis, at, out, u0, u1, z0, z1, trim="paint_cream", t=0.5):
    """Trim around an opening (two jambs and a lintel)."""
    parts = []
    w = 0.6
    for u in (u0 - w / 2, u1 + w / 2):
        size = (w, t, z1 - z0 + w) if axis == "x" else (t, w, z1 - z0 + w)
        parts.append(B(f, trim, size, to3(axis, at + out * 0.2, u, (z0 + z1 + w) / 2), along="z", rnd=False))
    size = (u1 - u0 + 2 * w, t, w) if axis == "x" else (t, u1 - u0 + 2 * w, w)
    parts.append(B(f, trim, size, to3(axis, at + out * 0.2, (u0 + u1) / 2, z1 + w / 2), along=axis, rnd=False))
    return parts


def open_door(f, kind, hinge, y_face, w, h, z0, swing=1, t=0.4):
    """A plank door swung open 90 degrees outward (toward -y) from a hinge at x=hinge on a front wall."""
    parts = [B(f, kind, (t, w, h), (hinge, y_face - w / 2, z0 + h / 2), along="z")]
    for zz in (z0 + h * 0.2, z0 + h * 0.8):
        parts.append(B(f, "metal", (t + 0.2, w * 0.7, 0.3), (hinge, y_face - w * 0.35, zz), rnd=False))
    return parts


def bale(f, x, y, z, rot=0.0):
    """Square hay bale lying lengthwise (4.6 x 3.2 x 2.6 studs) with two twine bands."""
    parts = [B(f, "hay", (4.6, 3.2, 2.6), (x, y, z + 1.3), rot=(0, 0, rot))]
    c, s = math.cos(rot), math.sin(rot)
    for k in (-1.2, 1.2):
        parts.append(B(f, "twine", (0.15, 3.3, 2.7), (x + c * k, y + s * k, z + 1.3), rot=(0, 0, rot), rnd=False))
    return parts


def frustum(f, kind, top, bot, z0, z1, x=0.0, y=0.0, along="z"):
    """Square funnel: top half-size at z1, bottom half-size at z0 (hoppers)."""
    o = box((2 * S, 2 * S, (z1 - z0) * S), (x * S, y * S, (z0 + z1) / 2 * S))
    for v in o.data.vertices:
        k = top if v.co.z > 0 else bot
        v.co.x *= k
        v.co.y *= k
    return f.apply(f.shape(o), kind, along=along)


def floor(f, kind, w, d, h=1.0, x=0.0, y=0.0):
    return B(f, kind, (w, d, h), (x, y, h / 2), along="x")


def corner_posts(f, kind, hx, hy, z0, z1, s=1.0):
    return [B(f, kind, (s, s, z1 - z0), (x, y, (z0 + z1) / 2), along="z")
            for x in (-hx, hx) for y in (-hy, hy)]


def brace(f, kind, p0, p1, s=0.5):
    """Square beam between two 3D points (studs)."""
    d = [b - a for a, b in zip(p0, p1)]
    ln = math.sqrt(sum(c * c for c in d))
    mid = tuple((a + b) / 2 for a, b in zip(p0, p1))
    pitch = math.atan2(math.hypot(d[0], d[1]), d[2])
    yaw = math.atan2(d[1], d[0])
    o = box((s * S, s * S, ln * S), tuple(c * S for c in mid))
    o.rotation_euler = (0, pitch, yaw)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return f.apply(f.shape(o, round_edges=False), kind, along="z")


def plank_x(f, kind, hw, z, y, t=0.3, h=1.2):
    """Horizontal board running along x."""
    return B(f, kind, (2 * hw, t, h), (0, y, z), along="x", rnd=False)


def ring_x(f, kind, cx, cy, cz, r, n, w, t, phase=0.0):
    """Polygonal ring of boxes in the yz plane (a wheel rim around the x axis)."""
    parts = []
    seg = 2 * r * math.sin(math.pi / n) + t * 0.6
    for i in range(n):
        a = phase + 2 * math.pi * (i + 0.5) / n
        y, z = cy + r * math.cos(a), cz + r * math.sin(a)
        parts.append(B(f, kind, (w, seg, t), (cx, y, z), along="y", rot=(a + math.pi / 2, 0, 0), rnd=False))
    return parts


def water_wheel(f, x, y, z, r):
    parts = []
    for dx in (-0.9, 0.9):
        parts += ring_x(f, "handle", x + dx, y, z, r - 0.3, 12, 0.5, 0.6)
    for i in range(4):
        a = math.pi * i / 4
        parts.append(B(f, "handle", (0.5, 0.5, 2 * r - 0.6), (x, y, z), along="z", rot=(a, 0, 0), rnd=False))
    for i in range(12):
        a = 2 * math.pi * i / 12
        parts.append(B(f, "bark", (2.6, 0.3, 1.8), (x, y + (r - 0.6) * math.cos(a), z + (r - 0.6) * math.sin(a)),
                       rot=(a - math.pi / 2, 0, 0), rnd=False))
    parts.append(C(f, "metal", 0.7, 4.6, (x + 1.4, y, z), verts=10, rot=(0, math.pi / 2, 0), along="x"))
    parts.append(C(f, "metal", 1.1, 2.4, (x, y, z), verts=10, rot=(0, math.pi / 2, 0), along="x"))
    return parts


# ---------------------------------------------------------------- buildings

def mill(f):
    """First building, about 36 x 23 x 26 studs: plank mill with a gable roof, a hay hopper tower on
    stilts beside it and a chute that drops hay at belt height (3.5 studs) toward the front."""
    hw, hd, base, eave, rise = 11.0, 10.0, 1.0, 14.0, 8.0
    p = [floor(f, "stone", 2 * hw + 1, 2 * hd + 1, base)]
    a = hw - WALL / 2
    door = (-3.5, 3.5, base, base + 9)
    p += wall(f, "handle", "x", -hd + WALL / 2, -a, a, base, eave, holes=[door])
    p += wall(f, "handle", "x", hd - WALL / 2, -a, a, base, eave)
    for s in (-1, 1):
        p += wall(f, "handle", "y", s * (hw - WALL / 2), -hd, hd, base, eave)
        for y in (-4.5, 4.5):
            p += window(f, "y", s * hw, s, y, 9, 3, 3.5)
    p += door_frame(f, "x", -hd, -1, *door, trim="bark")
    p += open_door(f, "handle", -3.8, -hd, 3.5, 9, base)
    p += open_door(f, "handle", 3.8, -hd, 3.5, 9, base)
    for y in (-hd + WALL / 2, hd - WALL / 2):
        p.append(prism(f, "handle", "x", y, WALL, [(-hw, eave), (hw, eave), (0, eave + rise)]))
    p += corner_posts(f, "bark", hw - 0.2, hd - 0.2, base, eave + 0.3, 1.2)
    p += gable_roof(f, "bark", hw, eave, rise, 2 * hd, ridge="y", over=1.5, cap="bark")
    # Loft door and hay hoist on the front gable.
    p.append(B(f, "bark", (4, 0.3, 4), (0, -hd - 0.1, eave + 3), rnd=False))
    p += door_frame(f, "x", -hd - 0.1, -1, -2, 2, eave + 1, eave + 5, trim="handle")
    p.append(B(f, "bark", (0.8, 6, 0.8), (0, -hd - 2.0, eave + rise - 1.2), along="y"))
    p.append(C(f, "metal", 0.5, 0.4, (0, -hd - 4.4, eave + rise - 2.2), verts=10, rot=(0, math.pi / 2, 0)))
    p.append(C(f, "twine", 0.1, 4.5, (0, -hd - 4.4, eave + rise - 4.7), verts=6, rnd=False))
    # Hay hopper tower on stilts to the right.
    tx, ty, leg, hz = hw + 7, 1.0, 4.2, 12.0
    for x in (tx - leg, tx + leg):
        for y in (ty - leg, ty + leg):
            p.append(B(f, "bark", (1, 1, hz + 1), (x, y, (hz + 1) / 2), along="z"))
    for y in (ty - leg, ty + leg):
        p.append(brace(f, "handle", (tx - leg, y, 1), (tx + leg, y, hz - 1)))
    for x in (tx - leg, tx + leg):
        p.append(brace(f, "handle", (x, ty - leg, hz - 1), (x, ty + leg, 1)))
    p.append(B(f, "handle", (2 * leg + 1.5, 2 * leg + 1.5, 0.6), (tx, ty, hz + 0.2)))
    p.append(frustum(f, "handle", 5.2, 1.6, hz - 2.5, hz + 7, tx, ty, along="z"))
    for z in (hz + 2.5, hz + 6.2):
        k = 1.6 + (5.2 - 1.6) * (z - hz + 2.5) / 9.5
        p.append(B(f, "metal", (2 * k + 0.3, 2 * k + 0.3, 0.4), (tx, ty, z), rnd=False))
    hay = box((10 * S, 10 * S, 2.4 * S), (tx * S, ty * S, (hz + 7.4) * S))
    for v in hay.data.vertices:
        if v.co.z > 0:
            v.co.x *= 0.55
            v.co.y *= 0.55
    p.append(f.apply(f.shape(hay), "hay"))
    # Chute from the hopper mouth down to belt height at the front.
    y0, z0, y1, z1 = ty - 1, hz - 2.6, -hd - 3, BELT_TOP + 0.3
    p.append(plate(f, "metal", (y0, z0), (y1, z1), 0.3, "x", 3, mid=tx))
    for s in (-1, 1):
        size, loc, rot = slope((y0, z0 + 0.6), (y1, z1 + 0.6), 0.2, "x", 1.2, mid=tx + s * 1.5)
        p.append(B(f, "metal", (0.25, size[1], 1.2), loc, rot=rot, rnd=False))
    p.append(B(f, "bark", (0.8, 0.8, z1), (tx, y1 + 0.6, z1 / 2), along="z"))
    # Water wheel on the left wall.
    p += water_wheel(f, -hw - 2.4, 1.0, 6.6, 6.0)
    # A stack of bales by the door.
    p += bale(f, -hw + 1.5, -hd - 3.2, 0)
    p += bale(f, -hw + 6.5, -hd - 3.2, 0)
    p += bale(f, -hw + 4, -hd - 3.2, 2.6)
    return p


def sorter_shed(f):
    """Open-sided shed over a 3 x 2 patch of 6-stud conveyor tiles (18 x 12 studs of floor), with room
    for a 7-stud sorter on a 3.5-stud belt. About 23 x 17 x 19 studs."""
    hx, hy, slab, eave, rise = 11.0, 8.0, 0.3, 15.0, 4.0
    p = [floor(f, "stone", 2 * hx, 2 * hy, slab)]
    # Tile grid painted on the slab: 3 x 2 tiles of 6 studs.
    for x in (-9, -3, 3, 9):
        p.append(B(f, "tire", (0.2, 12.2, 0.06), (x, 0, slab + 0.02), rnd=False))
    for y in (-6, 0, 6):
        p.append(B(f, "tire", (18.2, 0.2, 0.06), (0, y, slab + 0.02), rnd=False))
    for x in (-hx + 0.6, 0, hx - 0.6):
        for y in (-hy + 0.6, hy - 0.6):
            p.append(B(f, "bark", (1.2, 1.2, eave - slab), (x, y, (eave + slab) / 2), along="z"))
            p.append(B(f, "stone", (1.8, 1.8, 0.8), (x, y, slab + 0.4)))
            for dx in ((-1, 1) if x == 0 else ((1,) if x < 0 else (-1,))):
                p.append(brace(f, "handle", (x, y, eave - 3.2), (x + dx * 3, y, eave - 0.4), 0.5))
    for y in (-hy + 0.6, hy - 0.6):
        p.append(B(f, "handle", (2 * hx + 0.4, 1.0, 1.2), (0, y, eave + 0.2)))
    for x in (-hx + 0.6, 0, hx - 0.6):
        p.append(B(f, "handle", (1.0, 2 * hy, 1.0), (x, 0, eave + 0.3), along="y"))
        p.append(B(f, "handle", (0.6, 0.6, rise - 0.6), (x, 0, eave + 0.8 + (rise - 0.6) / 2), along="z", rnd=False))
    p += gable_roof(f, "metal", hy, eave + 0.8, rise, 2 * hx, ridge="x", over=1.4, sheet=True)
    # Hanging lamps over the line and a sign board on the front beam.
    for x in (-6, 6):
        p.append(C(f, "twine", 0.08, 2.4, (x, 0, eave - 0.4), verts=5, rnd=False))
        p.append(C(f, "metal", 1.0, 0.8, (x, 0, eave - 1.8), verts=10))
        p.append(C(f, "paint_cream", 0.5, 0.2, (x, 0, eave - 2.25), verts=8, rnd=False))
    p.append(B(f, "paint_yellow", (8, 0.4, 2.2), (0, -hy - 0.1, eave - 1.6)))
    p.append(B(f, "paint_red", (6.6, 0.3, 1.0), (0, -hy - 0.35, eave - 1.6), rnd=False))
    # A low plank kick wall at the back so it still reads as a shed.
    p.append(B(f, "handle", (2 * hx - 1.2, 0.5, 3.0), (0, hy - 0.6, slab + 1.5)))
    return p


def barn(f):
    """Classic faded red barn with a gambrel roof, about 28 x 38 x 30 studs. Sliding doors stand open
    on a 12 x 12 stud doorway, wide enough for the truck."""
    hw, hd, base, eave = 14.0, 18.0, 0.6, 13.0
    knee, top = (9.5, 22.0), 26.5
    p = [floor(f, "stone", 2 * hw + 1, 2 * hd + 1, base)]
    a = hw - WALL / 2
    door = (-6, 6, base, base + 12)
    p += wall(f, "paint_red", "x", -hd + WALL / 2, -a, a, base, eave, holes=[door])
    p += wall(f, "paint_red", "x", hd - WALL / 2, -a, a, base, eave, holes=[(-4, 4, base, base + 9)])
    for s in (-1, 1):
        p += wall(f, "paint_red", "y", s * (hw - WALL / 2), -hd, hd, base, eave)
        for y in (-10, 0, 10):
            p += window(f, "y", s * hw, s, y, 7.5, 3, 3)
    gable = [(-hw, eave), (hw, eave), (knee[0], knee[1]), (0, top), (-knee[0], knee[1])]
    for y in (-hd + WALL / 2, hd - WALL / 2):
        p.append(prism(f, "paint_red", "x", y, WALL, gable))
    # Cream trim: corners, eave line, door frames.
    for x in (-hw, hw):
        for y in (-hd, hd):
            p.append(B(f, "paint_cream", (1.0, 1.0, eave - base), (x, y, (eave + base) / 2), along="z", rnd=False))
    for y in (-hd - 0.15, hd + 0.15):
        p.append(B(f, "paint_cream", (2 * hw + 1, 0.4, 0.8), (0, y, eave), rnd=False))
    p += door_frame(f, "x", -hd, -1, *door)
    p += door_frame(f, "x", hd, 1, -4, 4, base, base + 9)
    # Sliding doors pushed open along a track, each with the cream X brace.
    p.append(B(f, "metal", (2 * hw - 1, 0.5, 0.5), (0, -hd - 0.7, base + 12.9), rnd=False))
    for s in (-1, 1):
        cx, w, h = s * 9.4, 6.4, 12.0
        y = -hd - 0.9
        p.append(B(f, "paint_red", (w, 0.4, h), (cx, y, base + h / 2 + 0.1)))
        for z in (base + 0.6, base + h - 0.4):
            p.append(B(f, "paint_cream", (w, 0.3, 0.7), (cx, y - 0.3, z), rnd=False))
        for x in (cx - w / 2 + 0.35, cx + w / 2 - 0.35):
            p.append(B(f, "paint_cream", (0.7, 0.3, h), (x, y - 0.3, base + h / 2 + 0.1), along="z", rnd=False))
        for d in (-1, 1):
            p.append(brace(f, "paint_cream", (cx - d * (w / 2 - 0.6), y - 0.3, base + 1.0),
                           (cx + d * (w / 2 - 0.6), y - 0.3, base + h - 0.8), 0.6))
    # Hay loft door and hood up in the front gable.
    p.append(B(f, "bark", (5, 0.3, 5), (0, -hd - 0.1, 17.6), rnd=False))
    p += door_frame(f, "x", -hd - 0.1, -1, -2.5, 2.5, 15.1, 20.1)
    p.append(B(f, "paint_cream", (0.5, 0.25, 5.0), (0, -hd - 0.35, 17.6), along="z", rnd=False))
    p.append(B(f, "paint_red", (1, 5, 1), (0, -hd - 2.0, top - 1.4), along="y"))
    p.append(C(f, "metal", 0.5, 0.4, (0, -hd - 3.9, top - 2.3), verts=10, rot=(0, math.pi / 2, 0)))
    p.append(C(f, "twine", 0.1, 5, (0, -hd - 3.9, top - 5), verts=6, rnd=False))
    # Gambrel roof: four rusty plates.
    L = 2 * hd + 2.4
    for s in (-1, 1):
        pa = (s * (hw + 1.2), eave - 2.4)
        pb = (s * knee[0], knee[1])
        p.append(plate(f, "metal", pa, pb, 0.6, "y", L))
        p.append(plate(f, "metal", (s * (knee[0] + 0.25), knee[1] - 0.1), (0, top), 0.6, "y", L))
    p.append(B(f, "metal", (1, L + 0.2, 1), (0, 0, top + 0.5), along="y"))
    # Cupola on the ridge.
    p.append(B(f, "paint_cream", (3.4, 3.4, 3.2), (0, 0, top + 1.8)))
    for s in (-1, 1):
        p.append(B(f, "glass", (2.2, 0.2, 1.8), (0, s * 1.65, top + 2.0), rnd=False))
    p.append(frustum(f, "metal", 0.2, 2.6, top + 3.4, top + 5.8))
    return p


def garage(f):
    """Garage for the truck and trailers, about 36 x 42 x 21 studs: two 10 x 10 stud roll-up doors
    (one rolled up, one down) and a side door. Barn-red walls so it reads apart from the blue warehouse."""
    hw, hd, base, eave, rise = 17.0, 20.0, 0.4, 14.0, 5.0
    p = [floor(f, "stone", 2 * hw + 1, 2 * hd + 1, base)]
    a = hw - WALL / 2
    doors = [(-14.5, -4.5, base, base + 10), (4.5, 14.5, base, base + 10)]
    p += wall(f, "paint_red", "x", -hd + WALL / 2, -a, a, base, eave, holes=doors)
    p += wall(f, "paint_red", "x", hd - WALL / 2, -a, a, base, eave)
    side = (-12, -7.5, base, base + 7.5)
    for s in (-1, 1):
        p += wall(f, "paint_red", "y", s * (hw - WALL / 2), -hd, hd, base, eave, holes=[side] if s > 0 else [])
        for y in ((-2, 6, 14) if s > 0 else (-12, -4, 4, 12)):
            p += window(f, "y", s * hw, s, y, 9, 3.5, 2.5)
    p += door_frame(f, "y", hw, 1, *side)
    p.append(B(f, "paint_cream", (0.4, 4.5, 7.5), (hw + 0.1, -9.75, base + 3.75), along="z"))
    p.append(B(f, "metal", (0.5, 0.6, 0.3), (hw + 0.4, -11.2, base + 3.8), rnd=False))
    for y in (-hd + WALL / 2, hd - WALL / 2):
        p.append(prism(f, "paint_red", "x", y, WALL, [(-hw, eave), (hw, eave), (0, eave + rise)]))
    p += corner_posts(f, "paint_cream", hw - 0.2, hd - 0.2, base, eave + 0.2, 1.1)
    p += gable_roof(f, "metal", hw, eave, rise, 2 * hd, ridge="y", over=1.5, sheet=True)
    for (u0, u1, z0, z1), down in zip(doors, (False, True)):
        cx, w = (u0 + u1) / 2, u1 - u0
        p += door_frame(f, "x", -hd, -1, u0, u1, z0, z1, trim="paint_cream")
        p.append(B(f, "metal", (w + 1, 1.8, 1.8), (cx, -hd - 1.0, z1 + 1.6)))  # roll drum housing
        lo = z0 if down else z1 - 1.2
        p.append(B(f, "metal", (w, 0.3, z1 - lo), (cx, -hd + 0.5, (z1 + lo) / 2), rnd=False))
        z = lo + 0.5
        while z < z1 - 0.2:
            p.append(B(f, "metal", (w, 0.3, 0.25), (cx, -hd + 0.25, z), rnd=False))
            z += 0.9
        p.append(B(f, "tire", (w, 0.4, 0.4), (cx, -hd + 0.25, lo + 0.2), rnd=False))
        if down:
            p.append(B(f, "metal", (1.6, 0.4, 0.4), (cx, -hd + 0.1, lo + 1.4), rnd=False))
        for x in (u0 - 1.0, u1 + 1.0):
            p.append(C(f, "paint_yellow", 0.45, 3.0, (x, -hd - 1.6, 1.5), verts=8))
    # Sign board over the doors and a couple of oil drums.
    p.append(B(f, "paint_cream", (10, 0.4, 2.6), (0, -hd - 0.3, eave + 1.6)))
    p.append(B(f, "paint_red", (8.4, 0.3, 1.2), (0, -hd - 0.55, eave + 1.6), rnd=False))
    for x, y in ((-hw - 1.6, -hd + 2), (-hw - 1.6, -hd + 4.3)):
        p.append(C(f, "paint_red", 1.0, 3.0, (x, y, 1.5), verts=10))
        for z in (0.8, 2.2):
            p.append(C(f, "metal", 1.05, 0.2, (x, y, z), verts=10, rnd=False))
    return p


def sell_depot(f):
    """Shop where hay is sold, about 22 x 22 x 22 studs: counter window under a striped awning,
    a coin sign board on the roof and a side door."""
    hw, hd, base, eave, rise = 10.0, 7.0, 0.6, 11.0, 4.0
    p = [floor(f, "stone", 2 * hw + 1, 2 * hd + 1, base)]
    a = hw - WALL / 2
    counter = (-6.5, 6.5, base + 3.4, base + 8.6)
    p += wall(f, "paint_cream", "x", -hd + WALL / 2, -a, a, base, eave, holes=[counter])
    p += wall(f, "paint_cream", "x", hd - WALL / 2, -a, a, base, eave)
    door = (-1.5, 3.5, base, base + 8)
    for s in (-1, 1):
        p += wall(f, "paint_cream", "y", s * (hw - WALL / 2), -hd, hd, base, eave, holes=[door] if s > 0 else [])
        p.append(prism(f, "paint_cream", "y", s * (hw - WALL / 2), WALL, [(-hd, eave), (hd, eave), (0, eave + rise)]))
    p.append(window(f, "y", -hw, -1, 0, 6.5, 4, 3)[0])
    p += window(f, "y", -hw, -1, 0, 6.5, 4, 3, trim="paint_green")[1:]
    p += door_frame(f, "y", hw, 1, *door, trim="paint_green")
    p += open_door_side(f, hw, door[0], door[1] - door[0], 8, base)
    p += corner_posts(f, "paint_green", hw - 0.2, hd - 0.2, base, eave + 0.2, 1.0)
    p += gable_roof(f, "metal", hd, eave, rise, 2 * hw, ridge="x", over=1.2, sheet=True)
    # Counter with brackets, a scale and a cash box.
    cz = counter[2]
    p.append(B(f, "handle", (14.5, 3.2, 0.6), (0, -hd - 0.6, cz)))
    for x in (-5.5, 0, 5.5):
        p.append(brace(f, "handle", (x, -hd, cz - 2.2), (x, -hd - 1.8, cz - 0.3), 0.5))
    p += door_frame(f, "x", -hd, -1, counter[0], counter[1], cz + 0.3, counter[3], trim="paint_green")
    p.append(B(f, "metal", (2.0, 1.6, 0.3), (-3.5, -hd - 0.7, cz + 0.45), rnd=False))
    p.append(B(f, "metal", (0.3, 0.3, 1.4), (-3.5, -hd - 0.2, cz + 1.0), rnd=False))
    p.append(B(f, "metal", (2.2, 1.0, 0.2), (-3.5, -hd - 0.2, cz + 1.8), rnd=False))
    p.append(B(f, "paint_green", (1.8, 1.4, 1.0), (3.5, -hd - 0.8, cz + 0.8)))
    # Striped awning on two posts.
    z_hi, z_lo, out = eave - 0.3, eave - 2.8, 5.0
    stripes = 7
    w = 2 * hw / stripes
    for i in range(stripes):
        kind = "paint_red" if i % 2 == 0 else "cloth"
        p.append(plate(f, kind, (-hd + 0.2, z_hi), (-hd - out, z_lo), 0.25, "x", w, mid=-hw + w * (i + 0.5),
                       rnd=False))
        p.append(B(f, kind, (w, 0.15, 1.0), (-hw + w * (i + 0.5), -hd - out - 0.1, z_lo - 0.4), rnd=False))
    for x in (-hw + 0.5, hw - 0.5):
        p.append(B(f, "paint_green", (0.6, 0.6, z_lo), (x, -hd - out + 0.4, z_lo / 2), along="z"))
    # Sign board on the roof with a big coin.
    for x in (-5, 5):
        p.append(B(f, "bark", (0.8, 0.8, 7), (x, 0.5, eave + rise + 1.5), along="z"))
    sz = eave + rise + 3.4
    p.append(B(f, "paint_yellow", (16, 0.6, 4.6), (0, 0, sz)))
    p.append(B(f, "paint_red", (16.6, 0.4, 0.5), (0, -0.2, sz + 2.3), rnd=False))
    p.append(B(f, "paint_red", (16.6, 0.4, 0.5), (0, -0.2, sz - 2.3), rnd=False))
    p.append(C(f, "paint_red", 2.0, 0.4, (0, -0.4, sz), verts=16, rot=(math.pi / 2, 0, 0), rnd=False))
    p.append(C(f, "paint_yellow", 1.6, 0.4, (0, -0.6, sz), verts=16, rot=(math.pi / 2, 0, 0), rnd=False))
    # Stock out front.
    p += bale(f, -hw - 1.2, -hd - 3, 0, rot=math.pi / 2)
    p.append(B(f, "handle", (3, 3, 3), (hw + 2.5, -hd - 1, 1.5)))
    return p


def open_door_side(f, x_face, u0, w, h, z0, kind="paint_green", t=0.4):
    """A door on a +x wall swung open outward, hinged at y=u0."""
    parts = [B(f, kind, (w, t, h), (x_face + w / 2, u0, z0 + h / 2), along="z")]
    parts.append(B(f, "metal", (0.3, 0.6, 0.3), (x_face + w - 0.5, u0 - 0.4, z0 + 3.8), rnd=False))
    return parts


def anvil(f, x, y):
    parts = [C(f, "bark", 1.6, 1.8, (x, y, 0.9), verts=10)]
    parts.append(B(f, "metal", (2.4, 1.6, 0.6), (x, y, 2.1)))
    parts.append(B(f, "metal", (1.2, 0.9, 0.9), (x, y, 2.8)))
    parts.append(B(f, "metal", (3.6, 1.4, 0.9), (x - 0.3, y, 3.6)))
    hx = x + 1.5 + 1.2
    horn = cyl(0.65 * S, 2.4 * S, (hx * S, y * S, 3.75 * S), verts=8, rot=(0, math.pi / 2, 0))
    for v in horn.data.vertices:
        if v.co.x > hx * S:
            v.co.y = y * S + (v.co.y - y * S) * 0.15
            v.co.z = 3.95 * S + (v.co.z - 3.75 * S) * 0.15
    parts.append(f.apply(f.shape(horn), "metal", along="x"))
    parts.append(B(f, "metal", (0.3, 2.6, 0.4), (x - 0.6, y - 0.6, 4.2), rot=(0, 0, 0.4), rnd=False))  # tongs
    return parts


def giant_needle(f, tip, d, length, r):
    """Needle from its point (tip) along direction d: tapered point, dark eye slot near the top."""
    n = math.sqrt(sum(c * c for c in d))
    d = [c / n for c in d]
    point = 0.22 * length
    shaft = cyl(r * S, (length - point) * S, (0, 0, (length + point) / 2 * S), verts=8)
    tip_ = cyl(r * S, point * S, (0, 0, point / 2 * S), verts=8)
    for v in tip_.data.vertices:
        if v.co.z < point / 2 * S:
            v.co.x *= 0.05
            v.co.y *= 0.05
    eye = box((r * 0.8 * S, r * 2.4 * S, r * 2.8 * S), (0, 0, (length - 2.0 * r - 0.6) * S))
    parts = [f.apply(f.shape(shaft, round_edges=False), "metal", along="z"),
             f.apply(f.shape(tip_, round_edges=False), "metal", along="z"), f.apply(eye, "tire")]
    pitch = math.atan2(math.hypot(d[0], d[1]), d[2])
    yaw = math.atan2(d[1], d[0])
    for part in parts:
        bpy.ops.object.select_all(action="DESELECT")
        part.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
        part.rotation_euler = (0, pitch, yaw)
        part.location = tuple(c * S for c in tip)
        bpy.ops.object.select_all(action="DESELECT")
        part.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=False)
    return parts


def needle_forge(f):
    """Stone forge, about 22 x 20 x 28 studs: wide open front with a heavy lintel, glowing hearth
    inside, a tall chimney, an anvil on a stump, a quench barrel and a giant needle hanging as a sign."""
    hw, hd, base, eave, rise = 9.0, 8.0, 0.6, 10.0, 4.0
    p = [floor(f, "stone", 2 * hw + 1.2, 2 * hd + 1.2, base)]
    a = hw - 1.0 / 2
    opening = (-4, 4, base, base + 8)
    p += wall(f, "stone", "x", -hd + 0.5, -a, a, base, eave, t=1.0, holes=[opening])
    p += wall(f, "stone", "x", hd - 0.5, -a, a, base, eave, t=1.0)
    for s in (-1, 1):
        p += wall(f, "stone", "y", s * (hw - 0.5), -hd, hd, base, eave, t=1.0)
        p.append(prism(f, "stone", "y", s * (hw - 0.5), 1.0, [(-hd, eave), (hd, eave), (0, eave + rise)]))
        p += window(f, "y", s * hw, s, 2, 6, 2.6, 2.6, trim="bark")
    # Corner quoins and a big stone lintel.
    for x in (-hw, hw):
        for y in (-hd, hd):
            for i, z in enumerate((1.8, 4.6, 7.4)):
                p.append(B(f, "stone", (1.6 if i % 2 else 2.0, 1.6 if i % 2 else 2.0, 2.4), (x, y, z)))
    p.append(B(f, "stone", (10.5, 1.6, 1.8), (0, -hd - 0.1, base + 8.9)))
    for x in (-4.6, 4.6):
        p.append(B(f, "stone", (1.4, 1.5, 8), (x, -hd - 0.1, base + 4)))
    p += gable_roof(f, "bark", hd, eave, rise, 2 * hw, ridge="x", over=1.2, cap="stone")
    # Hearth against the back wall with hot coals.
    p.append(B(f, "stone", (7, 4, 3.4), (0, hd - 3, base + 1.7)))
    p.append(B(f, "paint_red", (5, 2.6, 0.5), (0, hd - 3, base + 3.5), rnd=False))
    p.append(B(f, "paint_yellow", (3, 1.6, 0.6), (0, hd - 3, base + 3.6), rnd=False))
    p.append(frustum(f, "stone", 2.4, 3.8, base + 3.4, eave - 1, 0, hd - 3))
    # Chimney stack at the back right, through the roof.
    cx, cy = 4.5, 3.5
    p.append(B(f, "stone", (4.4, 4.4, 26 - base), (cx, cy, (26 + base) / 2), along="z"))
    p.append(B(f, "stone", (5.4, 5.4, 1.2), (cx, cy, 26.2)))
    p.append(C(f, "metal", 1.2, 2.6, (cx, cy, 27.8), verts=10))
    # Anvil, quench barrel, coal pile.
    p += anvil(f, -4.5, -hd - 4.5)
    p.append(C(f, "handle", 1.5, 3.2, (4.5, -hd - 3.5, 1.6), verts=12))
    for z in (0.7, 2.5):
        p.append(C(f, "metal", 1.58, 0.3, (4.5, -hd - 3.5, z), verts=12, rnd=False))
    p.append(C(f, "glass", 1.3, 0.2, (4.5, -hd - 3.5, 3.15), verts=12, rnd=False))
    p.append(frustum(f, "tire", 0.5, 2.0, 0, 1.8, hw + 2.8, -hd + 3))
    # A giant needle stuck point-first into a stone block: the forge's sign.
    p.append(B(f, "stone", (3.4, 3.4, 1.6), (hw + 3.2, -hd - 3.5, 0.8)))
    tip, d, ln = (hw + 3.2, -hd - 3.5, 0.8), (0.55, -0.15, 1.0), 14.0
    p += giant_needle(f, tip, d, ln, 0.6)
    k = (ln - 1.8) / math.sqrt(sum(c * c for c in d))
    eye = tuple(t + c * k for t, c in zip(tip, d))
    # Red thread through the eye, looping down to the ground.
    pts = [eye, (eye[0] + 0.6, eye[1] - 2.0, eye[2] - 3.0), (eye[0] - 0.4, eye[1] - 4.0, 4.0),
           (eye[0] - 1.6, eye[1] - 4.2, 0.3), (eye[0] - 4.0, eye[1] - 3.0, 0.2)]
    for a, b in zip(pts, pts[1:]):
        p.append(brace(f, "paint_red", a, b, 0.35))
    return p


def workshop(f):
    """Crafting workshop with an open front, about 24 x 18 x 17 studs: shed roof, workbench with a
    vise, a tool rack, a sawhorse and a stack of planks."""
    hw, hd, base, back, front = 11.0, 8.0, 0.6, 12.0, 16.5
    p = [B(f, "handle", (2 * hw + 1, 2 * hd + 1, base), (0, 0, base / 2), along="x")]
    p += wall(f, "handle", "x", hd - WALL / 2, -hw + WALL, hw - WALL, base, back)
    for s in (-1, 1):
        p += wall(f, "handle", "y", s * (hw - WALL / 2), -hd, hd, base, back)
        p.append(prism(f, "handle", "y", s * (hw - WALL / 2), WALL, [(-hd, back), (hd, back), (-hd, front)]))
        p += window(f, "y", s * hw, s, 2, 7, 4, 3, trim="bark")
    for x in (-hw + 0.5, -3.7, 3.7, hw - 0.5):
        p.append(B(f, "bark", (1.0, 1.0, front - base), (-0 + x, -hd + 0.5, (front + base) / 2), along="z"))
    p.append(B(f, "bark", (2 * hw + 0.6, 1.2, 1.2), (0, -hd + 0.5, front - 1.2)))
    for x in (-hw + 1, hw - 1):
        p.append(B(f, "bark", (1, 1, back - base), (x, hd - 0.5, (back + base) / 2), along="z"))
    p.append(plate(f, "metal", (-hd - 1.8, front + 0.35), (hd + 1.8, back - 0.35), 0.5, "x", 2 * hw + 2.4))
    def roof_z(y):
        return front + 0.35 + (y + hd + 1.8) * (back - front - 0.7) / (2 * hd + 3.6)

    for x in (-hw + 0.5, -3.7, 3.7, hw - 0.5):
        p.append(plate(f, "bark", (-hd - 0.6, roof_z(-hd - 0.6) - 0.6), (hd + 0.6, roof_z(hd + 0.6) - 0.6), 0.6, "x",
                       0.8, mid=x, rnd=False))
    # Workbench along the back wall, with a vise and tools.
    bz = base + 3.4
    p.append(B(f, "handle", (12, 3.2, 0.7), (-2, hd - 2.6, bz)))
    for x in (-7.4, 3.4):
        for y in (hd - 3.8, hd - 1.4):
            p.append(B(f, "handle", (0.6, 0.6, bz - base), (x, y, (bz + base) / 2), along="z", rnd=False))
    p.append(B(f, "handle", (11, 2.6, 0.4), (-2, hd - 2.6, base + 1.0), rnd=False))
    p.append(B(f, "metal", (1.4, 1.2, 1.0), (-6.6, hd - 4.1, bz + 0.8)))
    p.append(C(f, "metal", 0.15, 2.0, (-6.6, hd - 5.0, bz + 0.6), verts=6, rot=(0, math.pi / 2, 0), rnd=False))
    p.append(B(f, "handle", (3.0, 1.4, 0.8), (0, hd - 2.4, bz + 0.75)))
    p.append(B(f, "metal", (1.0, 0.3, 1.6), (3, hd - 2.4, bz + 1.15), rnd=False))
    # Tool board on the back wall: saw, hammer, axe.
    p.append(B(f, "bark", (10, 0.3, 4.5), (-2, hd - WALL - 0.15, bz + 4)))
    p.append(B(f, "metal", (3.2, 0.2, 1.2), (-5, hd - WALL - 0.4, bz + 4.2), rnd=False))
    p.append(B(f, "handle", (0.9, 0.25, 1.0), (-6.9, hd - WALL - 0.4, bz + 4.3), rnd=False))
    for x in (-1.5, 1.5):
        p.append(B(f, "handle", (0.3, 0.25, 3.0), (x, hd - WALL - 0.4, bz + 3.6), along="z", rnd=False))
        p.append(B(f, "metal", (1.3, 0.3, 0.6) if x < 0 else (0.9, 0.3, 1.1), (x + (0 if x < 0 else 0.4),
                   hd - WALL - 0.45, bz + 5.0), rnd=False))
    # Hanging sign with a hammer and saw.
    p.append(B(f, "paint_yellow", (6, 0.4, 2.6), (0, -hd - 0.3, front - 3.4)))
    for x in (-2, 2):
        p.append(C(f, "twine", 0.08, 1.0, (x, -hd - 0.3, front - 1.6), verts=5, rnd=False))
    p.append(B(f, "handle", (0.35, 0.2, 2.0), (-1.0, -hd - 0.6, front - 3.5), rot=(0, 0.5, 0), rnd=False))
    p.append(B(f, "metal", (1.2, 0.25, 0.5), (-0.55, -hd - 0.65, front - 2.7), rot=(0, 0.5, 0), rnd=False))
    p.append(B(f, "metal", (2.4, 0.2, 0.8), (1.0, -hd - 0.6, front - 3.5), rot=(0, -0.5, 0), rnd=False))
    # Crafting bench in the front left bay: vise, a saw and a box of nails.
    fx, fy = -7.2, -hd + 2.6
    p.append(B(f, "handle", (6.0, 2.6, 0.7), (fx, fy, bz)))
    for x in (fx - 2.5, fx + 2.5):
        for y in (fy - 0.9, fy + 0.9):
            p.append(B(f, "handle", (0.6, 0.6, bz - base), (x, y, (bz + base) / 2), along="z", rnd=False))
    p.append(B(f, "handle", (5.4, 2.2, 0.4), (fx, fy, base + 1.0), rnd=False))
    p.append(B(f, "metal", (1.2, 1.0, 1.0), (fx + 2.2, fy - 1.0, bz + 0.8)))
    p.append(C(f, "metal", 0.15, 1.8, (fx + 2.2, fy - 1.9, bz + 0.6), verts=6, rot=(math.pi / 2, 0, 0), rnd=False))
    p.append(B(f, "metal", (2.6, 1.0, 0.15), (fx - 0.6, fy + 0.2, bz + 0.45), rot=(0, 0, 0.3), rnd=False))
    p.append(B(f, "handle", (0.8, 0.5, 0.6), (fx - 2.1, fy + 0.7, bz + 0.6), rot=(0, 0, 0.3), rnd=False))
    p.append(B(f, "paint_red", (1.2, 0.9, 0.7), (fx + 0.6, fy + 0.6, bz + 0.7)))
    # Sawhorse with a plank out front, and a plank stack by the right wall.
    for x in (3.5, 7.5):
        for d in (-1, 1):
            p.append(brace(f, "handle", (x, -hd - 4 + d * 1.0, 0), (x, -hd - 4, 3.0), 0.4))
    p.append(B(f, "handle", (6, 0.8, 0.5), (5.5, -hd - 4, 3.2), rnd=False))
    p.append(B(f, "handle", (9, 1.6, 0.4), (5.0, -hd - 4, 3.7)))
    for i in range(4):
        p.append(B(f, "handle", (1.6, 10, 0.5), (hw - 3 + (i % 2) * 0.2, -1, base + 0.3 + i * 0.55), along="y"))
    return p


def museum(f):
    """Stone museum, about 34 x 26 x 25 studs: stepped plinth, six columns under a pediment, a green
    copper roof, tall windows and a 6 x 10 stud entrance."""
    hw, base = 13.0, 3.0
    p = []
    for i, (w, d) in enumerate(((34, 26), (32, 24), (30, 22))):
        p.append(B(f, "stone", (w, d, 1.0), (0, -(2 - i) * 0.8 * 0, 0.5 + i)))
    back, front, eave = 10.0, -4.0, 16.0
    door = (-3, 3, base, base + 10)
    a = hw - WALL / 2
    p += wall(f, "paint_cream", "x", front + WALL / 2, -a, a, base, eave, holes=[door])
    p += wall(f, "paint_cream", "x", back - WALL / 2, -a, a, base, eave)
    for s in (-1, 1):
        p += wall(f, "paint_cream", "y", s * (hw - WALL / 2), front, back, base, eave)
        for y in (0, 6):
            p += window(f, "y", s * hw, s, y, 9.5, 2.4, 6, trim="stone", cross=False)
    for s in (-1, 1):
        p += window(f, "x", front, -1, s * 8.5, 9.5, 2.4, 6, trim="stone", cross=False)
    p += door_frame(f, "x", front, -1, *door, trim="stone")
    for s in (-1, 1):
        p.append(B(f, "bark", (0.4, 3.0, 10), (s * 3.2, front - 1.5, base + 5), along="z"))
    # Portico: six columns, entablature and pediment.
    for x in (-12.5, -7.5, -2.5, 2.5, 7.5, 12.5):
        p.append(B(f, "stone", (2.6, 2.6, 0.8), (x, -9, base + 0.4)))
        p.append(C(f, "paint_cream", 1.0, eave - base - 1.6, (x, -9, (eave + base) / 2), verts=12))
        p.append(B(f, "stone", (2.6, 2.6, 0.8), (x, -9, eave - 0.4)))
    p.append(B(f, "stone", (2 * hw + 4, 2 * 10 + 1.5, 1.6), (0, -0.25, eave + 0.8)))
    rise = 5.0
    p.append(prism(f, "stone", "x", -10.4, 0.8, [(-hw - 2, eave + 1.6), (hw + 2, eave + 1.6), (0, eave + 1.6 + rise)]))
    p.append(prism(f, "paint_cream", "x", -10.9, 0.3, [(-hw + 0.5, eave + 2.2), (hw - 0.5, eave + 2.2), (0, eave + 1.6 + rise - 0.9)],
                   rnd=False))
    p.append(prism(f, "stone", "x", 10.0, 0.8, [(-hw - 2, eave + 1.6), (hw + 2, eave + 1.6), (0, eave + 1.6 + rise)]))
    p += gable_roof(f, "paint_green", hw + 2, eave + 1.6, rise, 20.8, ridge="y", over=0.4, t=0.6, cap="paint_green")
    return p


def observatory(f):
    """Round stone observatory, about 22 x 26 x 25 studs: drum walls, a rusty dome with an open slit and a
    telescope poking out, plus an entry porch with a 4.4 x 8 stud doorway."""
    r, base, top, n = 10.0, 0.6, 12.0, 14
    p = [C(f, "stone", r + 0.8, base, (0, 0, base / 2), verts=n * 2)]
    seg = 2 * r * math.sin(math.pi / n)
    for i in range(n):
        ang = -math.pi / 2 + 2 * math.pi * i / n
        x, y = r * math.cos(ang), r * math.sin(ang)
        rot = (0, 0, ang + math.pi / 2)
        if i == 0:  # doorway facing front
            p.append(B(f, "stone", (seg + 0.1, 1.0, top - 8.6), (x, y, (top + 8.6) / 2), rot=rot))
            continue
        p.append(B(f, "stone", (seg + 0.1, 1.0, top - base), (x, y, (top + base) / 2), along="z", rot=rot))
        if i % 3 == 0:
            p.append(B(f, "glass", (1.2, 1.1, 3.0), (x * 1.01, y * 1.01, 7.5), rot=rot, rnd=False))
    p.append(C(f, "stone", r + 1.0, 1.0, (0, 0, top + 0.3), verts=n * 2))
    p.append(C(f, "glass", r - 0.6, 0.2, (0, 0, top + 0.7), verts=n * 2, rnd=False))
    # Dome: a hemisphere with one gore left open as the slit.
    dr, segs, rows = r + 0.2, 16, 6
    bm = bmesh.new()
    off = -math.pi / 2 - math.pi / segs
    grid = []
    for j in range(rows + 1):
        el = (math.pi / 2) * j / rows
        ring = []
        for i in range(segs):
            az = off + 2 * math.pi * i / segs
            ring.append(bm.verts.new((dr * math.cos(el) * math.cos(az) * S, dr * math.cos(el) * math.sin(az) * S,
                                      (top + 0.8 + dr * math.sin(el)) * S)))
        grid.append(ring)
    for j in range(rows):
        for i in range(segs):
            if i == 0 and j >= 1:
                continue
            k = (i + 1) % segs
            bm.faces.new([grid[j][i], grid[j][k], grid[j + 1][k], grid[j + 1][i]])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    dome = link(bm, "dome")
    m = dome.modifiers.new("solid", "SOLIDIFY")
    m.thickness = 0.5 * S
    bpy.ops.object.modifier_apply(modifier=m.name)
    p.append(f.apply(f.shape(dome, round_edges=False), "metal", along="z"))
    # Slit rails.
    for s in (-1, 1):
        az = -math.pi / 2 + s * math.pi / segs
        for j in range(1, rows):
            e0, e1 = (math.pi / 2) * j / rows, (math.pi / 2) * (j + 1) / rows
            pts = [(dr + 0.3) * math.cos(e) for e in (e0, e1)]
            p0 = (pts[0] * math.cos(az), pts[0] * math.sin(az), top + 0.8 + (dr + 0.3) * math.sin(e0))
            p1 = (pts[1] * math.cos(az), pts[1] * math.sin(az), top + 0.8 + (dr + 0.3) * math.sin(e1))
            p.append(brace(f, "paint_cream", p0, p1, 0.6))
    # Telescope out through the slit.
    el = math.radians(42)
    d = (0, -math.cos(el), math.sin(el))
    c0 = (0, 0, top + 1.5)
    mid = 6.0
    p.append(C(f, "paint_cream", 1.2, 14, tuple(c0[i] + d[i] * mid for i in range(3)), verts=12,
               rot=(math.pi / 2 - el, 0, 0)))
    for t, rr in ((12.6, 1.45), (2.0, 1.4)):
        p.append(C(f, "metal", rr, 0.6, tuple(c0[i] + d[i] * t for i in range(3)), verts=12,
                   rot=(math.pi / 2 - el, 0, 0), rnd=False))
    p.append(C(f, "glass", 1.0, 0.2, tuple(c0[i] + d[i] * 13.05 for i in range(3)), verts=12,
               rot=(math.pi / 2 - el, 0, 0), rnd=False))
    # Entry porch.
    py, pw = -r - 1.0, 3.2
    for s in (-1, 1):
        p.append(B(f, "stone", (1.0, 4.0, 9.0), (s * pw, py, base + 4.5), along="z"))
    p.append(B(f, "stone", (2 * pw + 1, 4.0, 1.0), (0, py, base + 8.5)))
    p.append(prism(f, "stone", "x", py - 1.6, 0.6, [(-pw - 0.5, 9.6), (pw + 0.5, 9.6), (0, 12.2)]))
    for s in (-1, 1):
        p.append(plate(f, "metal", (s * (pw + 1.2), 9.1), (0, 12.4), 0.4, "y", 4.6, mid=py + 0.1))
    p.append(B(f, "metal", (0.6, 4.8, 0.6), (0, py + 0.1, 12.7), along="y", rnd=False))
    p.append(B(f, "stone", (2 * pw + 2, 2.0, 0.5), (0, py - 1.5, 0.25)))
    return p


def greenhouse(f):
    """Glass greenhouse on a wooden frame, about 16 x 26 x 15 studs: low stone footing, glass walls and
    roof between posts and rafters, a 4.4 x 8 stud door and planters by the entrance."""
    hw, hd, base, sill, eave, rise = 7.0, 12.0, 0.4, 2.6, 10.0, 4.0
    p = [floor(f, "stone", 2 * hw + 0.8, 2 * hd + 0.8, base)]
    door = (-2.2, 2.2, base, base + 8)
    for s in (-1, 1):
        p.append(B(f, "stone", (1.0, 2 * hd, sill - base), (s * (hw - 0.5), 0, (sill + base) / 2), along="y"))
    p += wall(f, "stone", "x", -hd + 0.5, -hw, hw, base, sill, t=1.0, holes=[door])
    p.append(B(f, "stone", (2 * hw, 1.0, sill - base), (0, hd - 0.5, (sill + base) / 2)))
    # Glass panes.
    for s in (-1, 1):
        p.append(B(f, "glass", (0.2, 2 * hd - 0.4, eave - sill), (s * (hw - 0.5), 0, (eave + sill) / 2), rnd=False))
        p.append(plate(f, "glass", (s * hw, eave), (0, eave + rise), 0.15, "y", 2 * hd, rnd=False))
    for y in (-hd + 0.5, hd - 0.5):
        holes = [door] if y < 0 else []
        p += wall(f, "glass", "x", y, -hw + 0.6, hw - 0.6, sill, eave, t=0.2, holes=holes, rnd=False)
        p.append(prism(f, "glass", "x", y, 0.2, [(-hw, eave), (hw, eave), (0, eave + rise)], rnd=False))
    # Wooden frame: posts, rafters, purlins.
    for y in (-hd + 0.5, -hd / 2, 0, hd / 2, hd - 0.5):
        for s in (-1, 1):
            p.append(B(f, "handle", (0.6, 0.6, eave - sill), (s * (hw - 0.5), y, (eave + sill) / 2), along="z",
                       rnd=False))
            p.append(plate(f, "handle", (s * (hw + 0.2), eave - 0.1), (0, eave + rise - 0.1), 0.5, "y", 0.6,
                           mid=y, rnd=False))
    for s in (-1, 1):
        p.append(B(f, "handle", (0.7, 2 * hd, 0.6), (s * (hw - 0.4), 0, eave), along="y", rnd=False))
        p.append(B(f, "handle", (0.4, 2 * hd, 0.4), (s * (hw - 0.4), 0, (eave + sill) / 2 + 0.6), along="y", rnd=False))
        p.append(B(f, "handle", (0.4, 2 * hd, 0.4), (s * hw * 0.5, 0, eave + rise * 0.5 + 0.35), along="y",
                   rnd=False))
    for y in (-hd + 0.4, hd - 0.4):
        for x in (-hw / 2, hw / 2):
            p.append(B(f, "handle", (0.4, 0.4, eave - sill + rise * 0.5), (x, y, sill + (eave - sill + rise * 0.5) / 2),
                       along="z", rnd=False))
        p.append(B(f, "handle", (2 * hw - 1, 0.4, 0.4), (0, y, (eave + sill) / 2 + 0.6), rnd=False))
    p.append(B(f, "handle", (0.6, 2 * hd + 0.4, 0.6), (0, 0, eave + rise + 0.1), along="y", rnd=False))
    p += door_frame(f, "x", -hd + 0.5, -1, *door, trim="handle")
    p.append(B(f, "handle", (0.3, 4.4, 8), (2.4, -hd - 1.7, base + 4), along="z"))
    p.append(B(f, "glass", (0.35, 3.2, 4.5), (2.4, -hd - 1.7, base + 5.3), rnd=False))
    # Planters and pots by the door.
    for x in (-5.0, 5.0):
        p.append(B(f, "handle", (3.6, 2.2, 1.6), (x, -hd - 2.0, 0.8)))
        p.append(B(f, "bark", (3.2, 1.8, 0.2), (x, -hd - 2.0, 1.6), rnd=False))
        for dx in (-1.0, 0.0, 1.0):
            p.append(B(f, "paint_green", (0.9, 0.9, 1.3 + abs(dx) * 0.3), (x + dx, -hd - 2.0, 2.2), rot=(0, 0, 0.6)))
    for x, y in ((hw + 1.2, -hd + 3), (hw + 1.2, -hd + 5)):
        pot = frustum(f, "paint_red", 0.8, 0.55, 0, 1.4, x, y)
        p.append(pot)
        p.append(B(f, "paint_green", (1.2, 1.2, 1.2), (x, y, 1.9), rot=(0, 0, 0.7)))
    return p


def harbor_dock(f):
    """Wooden pier on posts, about 20 x 44 x 9 studs: a 10-wide walkway with a T head at the front end,
    deck 5 studs up, bollards, a lamp post, a ladder and a ramp down to the ground at the back."""
    deck, hw, y0, y1 = 5.0, 5.0, -16.0, 20.0
    th, tw, ty = 6.0, 10.0, -16.0  # T head: depth, half width, back edge
    p = []
    # Deck planks across x.
    y = ty - th + 0.5
    while y < y1:
        w = tw if y < ty else hw
        p.append(B(f, "handle", (2 * w, 0.9, 0.4), (0, y, deck - 0.2), rot=(0, 0, 0.0), rnd=False))
        y += 1.05
    # Stringers and posts.
    for x in (-hw + 0.7, 0, hw - 0.7):
        p.append(B(f, "bark", (0.8, y1 - y0, 0.8), (x, (y0 + y1) / 2, deck - 0.8), along="y", rnd=False))
    for x in (-tw + 0.7, -hw + 0.7, hw - 0.7, tw - 0.7):
        p.append(B(f, "bark", (0.8, th, 0.8), (x, ty - th / 2, deck - 0.8), along="y", rnd=False))
    p.append(B(f, "bark", (2 * tw, 0.8, 0.8), (0, ty - th + 0.5, deck - 0.8), rnd=False))
    p.append(B(f, "bark", (2 * tw, 0.8, 0.8), (0, ty - 0.5, deck - 0.8), rnd=False))
    posts = [(x, y) for x in (-hw - 0.2, hw + 0.2) for y in (-10, -4, 2, 8, 14, 19.4)]
    posts += [(x, y) for x in (-tw - 0.2, -5.5, 0, 5.5, tw + 0.2) for y in (ty - th - 0.2,)]
    posts += [(x, ty + 0.2) for x in (-tw - 0.2, tw + 0.2)]
    for x, y in posts:
        h = deck + 1.0
        p.append(C(f, "bark", 0.6, h, (x, y, h / 2), verts=8))
    # Bollards on the T head and along the sides.
    for x, y in ((-tw + 1.2, ty - th + 1.2), (tw - 1.2, ty - th + 1.2), (-hw + 1.0, 4), (hw - 1.0, 4)):
        p.append(C(f, "metal", 0.6, 1.4, (x, y, deck + 0.7), verts=10))
        p.append(C(f, "metal", 0.85, 0.35, (x, y, deck + 1.5), verts=10))
    p.append(C(f, "twine", 0.4, 0.3, (tw - 1.2, ty - th + 1.2, deck + 0.4), verts=10, rnd=False))
    for i in range(3):
        p.append(C(f, "twine", 1.2 - i * 0.05, 0.25, (-tw + 3.6, ty - 2.5, deck + 0.13 + i * 0.25), verts=12,
                   rnd=False))
    # Lamp post, ladder and a crate.
    lx, ly = hw - 0.8, -6.0
    p.append(B(f, "bark", (0.6, 0.6, 9), (lx, ly, deck + 4.5), along="z"))
    p.append(B(f, "bark", (2.2, 0.4, 0.4), (lx - 0.9, ly, deck + 8.8), rnd=False))
    p.append(B(f, "metal", (1.0, 1.0, 0.3), (lx - 1.6, ly, deck + 8.4), rnd=False))
    p.append(B(f, "paint_yellow", (0.8, 0.8, 1.2), (lx - 1.6, ly, deck + 7.6), rnd=False))
    p.append(B(f, "metal", (1.0, 1.0, 0.25), (lx - 1.6, ly, deck + 6.9), rnd=False))
    for x in (-1.0, 1.0):
        p.append(B(f, "metal", (0.3, 0.3, deck + 2.4), (x, ty - th - 0.5, (deck + 2.4) / 2), along="z", rnd=False))
    for z in (1.0, 2.2, 3.4, 4.6):
        p.append(B(f, "metal", (2.0, 0.25, 0.25), (0, ty - th - 0.5, z), rnd=False))
    p.append(B(f, "handle", (2.6, 2.6, 2.6), (-hw + 2.2, 10, deck + 1.3)))
    p.append(B(f, "handle", (2.0, 2.0, 2.0), (-hw + 2.0, 12.6, deck + 1.0), rot=(0, 0, 0.3)))
    # Rails along the walkway sides.
    for x in (-hw - 0.2, hw + 0.2):
        p.append(B(f, "handle", (0.4, y1 - ty, 0.4), (x, (ty + y1) / 2, deck + 0.9), along="y", rnd=False))
    # Ramp down to the ground at the shore end.
    rl = 9.0
    p.append(plate(f, "handle", (y1 - 0.2, deck - 0.4), (y1 + rl, 0.0), 0.4, "x", 6, mid=0))
    for x in (-3.2, 3.2):
        p.append(plate(f, "bark", (y1 - 0.2, deck - 0.9), (y1 + rl, 0.0), 0.5, "x", 0.6, mid=x, rnd=False))
    return p


def warehouse(f):
    """Large storage warehouse, about 46 x 34 x 27 studs: faded blue walls, two 14 x 14 stud sliding
    doors (one open), a side-entry door, high windows and a rusty corrugated roof with vents."""
    hw, hd, base, eave, rise = 22.0, 15.0, 0.6, 18.0, 6.0
    p = [floor(f, "stone", 2 * hw + 1, 2 * hd + 1, base)]
    a = hw - WALL / 2
    big = [(-19, -7, base, base + 14), (7, 19, base, base + 14)]
    side = (-4, 0, base, base + 7.5)
    p += wall(f, "paint_blue", "x", -hd + WALL / 2, -a, a, base, eave, holes=big)
    p += wall(f, "paint_blue", "x", hd - WALL / 2, -a, a, base, eave)
    for s in (-1, 1):
        p += wall(f, "paint_blue", "y", s * (hw - WALL / 2), -hd, hd, base, eave, holes=[side] if s > 0 else [])
        p.append(prism(f, "paint_blue", "y", s * (hw - WALL / 2), WALL, [(-hd, eave), (hd, eave), (0, eave + rise)]))
        p += window(f, "y", s * hw, s, 0, eave + 2.5, 5, 2.5)
    for x in (-15, -5, 5, 15):
        p += window(f, "x", hd, 1, x, eave - 3, 6, 2.5)
    p += corner_posts(f, "paint_cream", hw - 0.2, hd - 0.2, base, eave + 0.2, 1.2)
    p.append(B(f, "paint_cream", (2 * hw + 0.8, 0.5, 0.8), (0, -hd - 0.15, eave - 0.3), rnd=False))
    for u0, u1, z0, z1 in big:
        p += door_frame(f, "x", -hd, -1, u0, u1, z0, z1)
    p += door_frame(f, "y", hw, 1, *side)
    p.append(B(f, "paint_red", (0.4, 4, 7.5), (hw + 0.2, -2, base + 3.75), along="z"))
    p.append(B(f, "metal", (0.3, 0.6, 0.3), (hw + 0.5, -0.7, base + 3.6), rnd=False))
    # Sliding doors on an overhead track: the left pair pushed aside over the middle wall, the right pair shut.
    p.append(B(f, "metal", (2 * hw - 2, 0.5, 0.5), (0, -hd - 0.8, base + 15.0), rnd=False))
    for i, cx in enumerate((-3.6, -2.8)):
        p += slider(f, cx, -hd - 1.0 - i * 0.6, 6.0, 14.2, base)
    for cx in (10.0, 16.0):
        p += slider(f, cx, -hd - 1.0, 6.0, 14.2, base)
    p += gable_roof(f, "metal", hd, eave, rise, 2 * hw, ridge="x", over=1.6, sheet=True)
    for x in (-10, 10):
        p.append(B(f, "metal", (3, 3, 2.2), (x, 0, eave + rise + 1.0)))
        p.append(B(f, "metal", (4.2, 4.2, 0.4), (x, 0, eave + rise + 2.4)))
    # Bales and a crate stacked by the left wall.
    p += bale(f, -hw - 2.6, -6, 0, rot=math.pi / 2)
    p += bale(f, -hw - 2.6, -1, 0, rot=math.pi / 2)
    p += bale(f, -hw - 2.6, -3.5, 2.6, rot=math.pi / 2)
    p.append(B(f, "handle", (3, 3, 3), (-hw - 2.6, 3.5, 1.5)))
    return p


def slider(f, cx, y, w, h, z0):
    """A sliding door leaf: rusty metal with a cream frame and diagonal brace."""
    parts = [B(f, "metal", (w, 0.4, h), (cx, y, z0 + h / 2))]
    for z in (z0 + 0.4, z0 + h - 0.4):
        parts.append(B(f, "paint_cream", (w, 0.3, 0.7), (cx, y - 0.3, z), rnd=False))
    for x in (cx - w / 2 + 0.35, cx + w / 2 - 0.35):
        parts.append(B(f, "paint_cream", (0.7, 0.3, h), (x, y - 0.3, z0 + h / 2), along="z", rnd=False))
    parts.append(brace(f, "paint_cream", (cx - w / 2 + 0.6, y - 0.3, z0 + 0.8), (cx + w / 2 - 0.6, y - 0.3, z0 + h - 0.8), 0.6))
    parts.append(B(f, "metal", (0.8, 0.6, 0.8), (cx, y, z0 + h + 0.2), rnd=False))
    return parts


PROPS = {
    "mill": mill,
    "sorter_shed": sorter_shed,
    "barn": barn,
    "garage": garage,
    "sell_depot": sell_depot,
    "needle_forge": needle_forge,
    "workshop": workshop,
    "museum": museum,
    "observatory": observatory,
    "greenhouse": greenhouse,
    "harbor_dock": harbor_dock,
    "warehouse": warehouse,
}

"""Conveyor line pieces, sorters and workshop machines in the house style (LT2 shapes, Rustic finish).

Everything that sits on the conveyor line fits the game's 6 x 6 stud tile grid with the belt top
3.5 studs above the ground (Conveyors.luau / BaseLine.luau): dark rubber belt, wooden frame and side
rails (0.3 thick, 1.2 high), rusty metal legs. Line machines span whole tiles and the belt runs along x.

Shape only: props/rustic_props.py builds, exports and renders these (--category machines).
"""
import math
import os
import sys

import bpy  # must be imported before bmesh/mathutils with the pip bpy module
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, HERE)
import hay_bale  # noqa: E402
import style  # noqa: E402
from rig import tag  # noqa: E402
from style import box, cap_uv, cyl  # noqa: E402,F401

STUD = 0.28
S = STUD

TILE = 6.0          # conveyor tile, studs
BELT_Z = 3.5        # belt top above ground
BELT_W = 5.4        # rubber between the rails
BELT_T = 0.3
RAIL_T = 0.3
RAIL_H = 1.2
FRAME_D = 0.8       # wooden frame board below the belt top
RAMP_RISE = 3.5     # one level up: a belt passes over another belt (bale + frame clearance)


# ---------------------------------------------------------------- helpers (all sizes in studs)

def _longest(o):
    vs = [v.co for v in o.data.vertices]
    ext = [max(v[i] for v in vs) - min(v[i] for v in vs) for i in range(3)]
    return "xyz"[ext.index(max(ext))]


LOW = [False]  # set by low_poly(): pieces placed many times skip bevels and use fewer sides


def low_poly(build):
    """Build a tile placed many times (conveyors): no bevels, 6-sided cylinders."""
    def wrapped(f):
        LOW[0] = True
        try:
            return build(f)
        finally:
            LOW[0] = False
    wrapped.__doc__ = build.__doc__
    wrapped.__name__ = build.__name__
    return wrapped


def part(f, o, kind, along=None, rnd=True):
    return f.apply(f.shape(o, round_edges=rnd and not LOW[0]), kind, along=along or _longest(o))


def bx(f, size, loc, kind, along=None, rot=(0, 0, 0), rnd=True):
    o = box(tuple(s * S for s in size), tuple(c * S for c in loc), rot)
    return part(f, o, kind, along, rnd)


AXIS_ROT = {"x": (0, math.pi / 2, 0), "y": (math.pi / 2, 0, 0), "z": (0, 0, 0)}


def cy(f, r, depth, loc, kind, axis="z", verts=12, rnd=True, along=None, exact=False):
    if LOW[0] and not exact:
        verts = min(verts, 6)
    o = cyl(r * S, depth * S, tuple(c * S for c in loc), verts=verts, rot=AXIS_ROT[axis])
    return part(f, o, kind, along or axis, rnd)


def cone(f, r0, r1, depth, loc, kind, axis="z", verts=12, rnd=True):
    """Truncated cone: radius r0 at the low end of the axis, r1 at the high end."""
    o = cyl(1.0, depth * S, (0, 0, 0), verts=verts)
    for v in o.data.vertices:
        k = r1 if v.co.z > 0 else r0
        v.co.x *= k * S
        v.co.y *= k * S
    rot = {"x": Matrix.Rotation(math.pi / 2, 4, "Y"), "y": Matrix.Rotation(-math.pi / 2, 4, "X"),
           "z": Matrix.Identity(4)}[axis]
    o.data.transform(rot)
    o.location = tuple(c * S for c in loc)
    return part(f, o, kind, axis, rnd)


def bake(o):
    """Move an object's location into its mesh so it can be transformed as vertices."""
    o.data.transform(Matrix.Translation(o.location))
    o.location = (0, 0, 0)
    return o


def xform(objs, m):
    for o in objs:
        bake(o).data.transform(m)
    return objs


def mesh_obj(verts, faces, name="part"):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(c * S for c in v) for v in verts], [], faces)
    me.update()
    me.uv_layers.new(name="UVMap")  # like the primitives, so joined meshes keep one shared UV layer
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    return o


def solidify(o, t):
    m = o.modifiers.new("solid", "SOLIDIFY")
    m.thickness = t * S
    m.offset = -1
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=m.name)
    return o


def frustum(f, c, z0, bot, z1, top, kind, wall=None, closed=False, along="z"):
    """Square-ish funnel or block. bot/top are (w, d). wall=None makes a closed solid."""
    cx, cyy = c
    vs = []
    for z, (w, d) in ((z0, bot), (z1, top)):
        vs += [(cx - w / 2, cyy - d / 2, z), (cx + w / 2, cyy - d / 2, z),
               (cx + w / 2, cyy + d / 2, z), (cx - w / 2, cyy + d / 2, z)]
    faces = [(i, (i + 1) % 4, 4 + (i + 1) % 4, 4 + i) for i in range(4)]
    if wall is None or closed:
        faces += [(3, 2, 1, 0), (4, 5, 6, 7)]
    o = mesh_obj(vs, faces)
    if wall is not None:
        solidify(o, wall)
    return part(f, o, kind, along, rnd=wall is None)


def extrude(f, pts, plane, lo, hi, kind, along=None, rnd=True):
    """Prism from a 2D outline. plane 'xy' extrudes along z, 'xz' along y, 'yz' along x."""
    def p3(a, b, h):
        return {"xy": (a, b, h), "xz": (a, h, b), "yz": (h, a, b)}[plane]
    n = len(pts)
    vs = [p3(a, b, lo) for a, b in pts] + [p3(a, b, hi) for a, b in pts]
    faces = [tuple(range(n))[::-1], tuple(range(n, 2 * n))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return part(f, mesh_obj(vs, faces), kind, along, rnd)


def arc_slab(f, c, r0, r1, a0, a1, z0, z1, kind, n=8, along="z"):
    """A curved block: ring sector around c from angle a0 to a1 (degrees)."""
    vs = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        ca, sa = math.cos(a), math.sin(a)
        for r in (r0, r1):
            for z in (z0, z1):
                vs.append((c[0] + r * ca, c[1] + r * sa, z))
    # per angle step: 0 inner-low, 1 inner-high, 2 outer-low, 3 outer-high
    faces = []
    for i in range(n):
        a, b = 4 * i, 4 * (i + 1)
        faces += [(a + 1, a + 3, b + 3, b + 1), (a, b, b + 2, a + 2),
                  (a, a + 1, b + 1, b), (a + 2, b + 2, b + 3, a + 3)]
    e = 4 * n
    faces += [(0, 2, 3, 1), (e, e + 1, e + 3, e + 2)]
    return part(f, mesh_obj(vs, faces), kind, along, rnd=False)


def obox(f, p0, p1, w, h, kind, rnd=True):
    """A beam from p0 to p1 with a w x h cross-section (local z stays as close to up as it can)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    o = box((d.length * S, w * S, h * S), (0, 0, 0))
    m = Matrix.Translation((p0 + p1) / 2 * S) @ d.to_track_quat("X", "Z").to_matrix().to_4x4()
    o.data.transform(m)
    a = [abs(c) for c in d]
    return part(f, o, kind, "xyz"[a.index(max(a))], rnd)


def trough(f, p0, p1, w, wall_h, kind, t=0.15):
    """Open U chute from p0 to p1 (floor center line)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    m = Matrix.Translation((p0 + p1) / 2 * S) @ d.to_track_quat("X", "Z").to_matrix().to_4x4()
    objs = [box((d.length * S, w * S, t * S), (0, 0, 0))]
    for side in (-1, 1):
        objs.append(box((d.length * S, t * S, wall_h * S), (0, side * (w - t) / 2 * S, wall_h / 2 * S)))
    out = []
    a = [abs(c) for c in d]
    for o in objs:
        bake(o).data.transform(m)
        out.append(part(f, o, kind, "xyz"[a.index(max(a))]))
    return out


def hay_lump(f, c, size, z0=0.0):
    """A loose heap of hay: two stacked blocks, the top one smaller."""
    w, d, h = size
    return [frustum(f, c, z0, (w, d), z0 + h * 0.65, (w * 0.8, d * 0.8), "hay"),
            frustum(f, (c[0] + w * 0.05, c[1]), z0 + h * 0.6, (w * 0.6, d * 0.6), z0 + h, (w * 0.3, d * 0.3), "hay")]


def needles(f, c, n, z, spread=0.6, length=0.9, seed=1):
    """A little pile of steel needles lying around c."""
    import random
    rng = random.Random(seed)
    out = []
    for _ in range(n):
        a = rng.uniform(0, math.pi)
        x, y = c[0] + rng.uniform(-spread, spread), c[1] + rng.uniform(-spread, spread)
        dx, dy = math.cos(a) * length / 2, math.sin(a) * length / 2
        out.append(obox(f, (x - dx, y - dy, z), (x + dx, y + dy, z + rng.uniform(0, 0.1)), 0.07, 0.07, "metal",
                        rnd=False))
    return out


def handwheel(f, c, r, axis, kind="metal", spokes=4, hub="metal"):
    """Spoked wheel: rim made of short beams, spokes and a hub."""
    out = []
    n = 10
    u, v = {"x": (1, 2), "y": (0, 2), "z": (0, 1)}[axis]

    def pt(a, rr):
        p = list(c)
        p[u] += rr * math.cos(a)
        p[v] += rr * math.sin(a)
        return p
    for i in range(n):
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        out.append(obox(f, pt(a0 - 0.05, r), pt(a1 + 0.05, r), 0.22, 0.22, kind, rnd=False))
    for i in range(spokes):
        a = math.pi * i / spokes
        out.append(obox(f, pt(a, r), pt(a + math.pi, r), 0.14, 0.14, kind, rnd=False))
    out.append(cy(f, r * 0.18 + 0.1, 0.4, c, hub, axis=axis, verts=8))
    return out


def bale(f, loc, rot_z=0.0, tilt=0.0):
    """The game's hay bale (4.6 x 3.2 x 2.6 studs), bottom center at loc."""
    hay_bale.BEVEL = max(f.bevel, 0.001)
    objs = [f.apply(f.shape(hay_bale.build_hay(), round_edges=False), "hay")]
    objs += [f.apply(b, "twine") for b in hay_bale.build_twine()]
    m = (Matrix.Translation(Vector(loc) * S) @ Matrix.Rotation(rot_z, 4, "Z") @ Matrix.Rotation(tilt, 4, "Y"))
    return xform(objs, m)


# ---------------------------------------------------------------- conveyor pieces

def belt_run(f, x0, x1, y=0.0, z=BELT_Z, rails=(True, True), legs=True, cleat_h=0.12, rollers=True):
    """A straight piece of belt along x from x0 to x1 (studs)."""
    L, cx = x1 - x0, (x0 + x1) / 2
    parts = [bx(f, (L, BELT_W, BELT_T), (cx, y, z - BELT_T / 2), "tire")]
    n = max(2, int(round(L / 1.5)))
    for i in range(n):
        x = x0 + (i + 0.5) * L / n
        parts.append(bx(f, (0.22, BELT_W - 0.3, cleat_h), (x, y, z + cleat_h / 2 - 0.02), "metal", along="y",
                        rnd=False))
    tag(parts, "Belt", f"{x0}:{y}:{z}")
    for side, rail in zip((-1, 1), rails):
        sy = y + side * (BELT_W / 2 + RAIL_T / 2)
        parts.append(bx(f, (L, RAIL_T, FRAME_D), (cx, sy, z - FRAME_D / 2), "handle", along="x"))
        if rail:
            parts.append(bx(f, (L, RAIL_T, RAIL_H), (cx, sy, z + RAIL_H / 2 + 0.02), "handle", along="x"))
        if rollers:
            for x in (x0 + 0.45, x1 - 0.45):
                parts.append(cy(f, 0.18, 0.12, (x, sy + side * 0.2, z - 0.4), "metal", axis="y", verts=8))
    if rollers:
        for x in (x0 + 0.45, x1 - 0.45):
            parts += tag([cy(f, 0.32, BELT_W, (x, y, z - 0.4), "metal", axis="y", verts=10)], "Roller", f"{x}:{y}:{z}")
    if legs:
        parts += leg_pair_set(f, [x0 + 0.6, x1 - 0.6] if L <= 7 else [x0 + 0.6, cx, x1 - 0.6], y, z - FRAME_D)
    return parts


def leg_pair_set(f, xs, y, top):
    parts = []
    for x in xs:
        for side in (-1, 1):
            parts.append(bx(f, (0.42, 0.42, top), (x, y + side * 2.45, top / 2), "metal", along="z"))
            parts.append(bx(f, (0.8, 0.8, 0.12), (x, y + side * 2.45, 0.06), "metal", along="x"))
        parts.append(bx(f, (0.24, 4.9, 0.3), (x, y, top * 0.35), "metal", along="y"))
    return parts


def conveyor_straight(f):
    """One 6 x 6 tile of belt, top at 3.5 studs, rails 1.2 high."""
    return belt_run(f, -TILE / 2, TILE / 2)


def conveyor_corner(f):
    """Quarter-turn tile: belt comes in through the -x edge and leaves through the +y edge."""
    c, z = (-3.0, 3.0), BELT_Z
    r0, r1 = 0.3, 5.7
    parts = [arc_slab(f, c, r0, r1, -90, 0, z - BELT_T, z, "tire", n=10)]
    for a in range(-80, 0, 16):
        ar = math.radians(a + 3)
        ca, sa = math.cos(ar), math.sin(ar)
        parts.append(obox(f, (c[0] + 0.6 * ca, c[1] + 0.6 * sa, z + 0.04), (c[0] + 5.5 * ca, c[1] + 5.5 * sa, z + 0.04),
                          0.22, 0.12, "metal", rnd=False))
    parts.append(arc_slab(f, c, r1, r1 + RAIL_T, -90, 0, z - FRAME_D, z, "handle", n=10, along="x"))
    parts.append(arc_slab(f, c, r1, r1 + RAIL_T, -90, 0, z + 0.02, z + RAIL_H + 0.02, "handle", n=10, along="x"))
    # Inner corner post doubles as the inner rail.
    parts.append(bx(f, (0.7, 0.7, z + RAIL_H), (c[0] + 0.35, c[1] - 0.35, (z + RAIL_H) / 2), "handle", along="z"))
    # Tapered roller under the turn.
    rl = obox(f, (c[0] + 0.5, c[1] - 0.5, z - 0.4), (c[0] + 5.3 * 0.707, c[1] - 5.3 * 0.707, z - 0.4), 0.5, 0.5, "metal")
    parts.append(rl)
    for a in (-75, -45, -15):
        ar = math.radians(a)
        x, y = c[0] + 5.0 * math.cos(ar), c[1] + 5.0 * math.sin(ar)
        top = z - FRAME_D
        parts.append(bx(f, (0.42, 0.42, top), (x, y, top / 2), "metal", along="z"))
        parts.append(bx(f, (0.8, 0.8, 0.12), (x, y, 0.06), "metal", along="x"))
    for a0, a1 in ((-75, -45), (-45, -15)):
        p = [(c[0] + 5.0 * math.cos(math.radians(a)), c[1] + 5.0 * math.sin(math.radians(a)), 0.9) for a in (a0, a1)]
        parts.append(obox(f, p[0], p[1], 0.24, 0.3, "metal"))
    return parts


def conveyor_ramp(f):
    """One tile that lifts the belt one level (3.5 studs) from the -x edge to the +x edge."""
    run, rise = TILE, RAMP_RISE
    L = math.hypot(run, rise)
    ang = math.atan2(rise, run)
    parts = belt_run(f, -L / 2, L / 2, z=0.0, legs=False, cleat_h=0.25)
    m = Matrix.Translation((0, 0, (BELT_Z + rise / 2) * S)) @ Matrix.Rotation(-ang, 4, "Y")
    xform(parts, m)

    def top_at(x):
        return BELT_Z + (x + run / 2) * rise / run
    for x in (-2.3, 2.3):
        h = top_at(x) - FRAME_D / math.cos(ang) + 0.1
        for side in (-1, 1):
            parts.append(bx(f, (0.42, 0.42, h), (x, side * 2.45, h / 2), "metal", along="z"))
            parts.append(bx(f, (0.8, 0.8, 0.12), (x, side * 2.45, 0.06), "metal", along="x"))
        parts.append(bx(f, (0.24, 4.9, 0.3), (x, 0, 1.0), "metal", along="y"))
    for side in (-1, 1):
        parts.append(obox(f, (-2.3, side * 2.45, 1.0), (2.3, side * 2.45, top_at(2.3) - 1.6), 0.24, 0.3, "metal"))
    return parts


def junction(f, open_sides):
    """Square belt pad for splitters and mergers. open_sides: subset of 'NSEW'."""
    z = BELT_Z
    x0 = -3.0 if "W" in open_sides else -2.7
    x1 = 3.0 if "E" in open_sides else 2.7
    y0 = -3.0 if "S" in open_sides else -2.7
    y1 = 3.0 if "N" in open_sides else 2.7
    parts = [bx(f, (x1 - x0, y1 - y0, BELT_T), ((x0 + x1) / 2, (y0 + y1) / 2, z - BELT_T / 2), "tire")]
    edges = {"W": ((0.3, 5.4), (-2.85, 0)), "E": ((0.3, 5.4), (2.85, 0)),
             "S": ((5.4, 0.3), (0, -2.85)), "N": ((5.4, 0.3), (0, 2.85))}
    for k, ((w, d), (x, y)) in edges.items():
        parts.append(bx(f, (w, d, FRAME_D), (x, y, z - FRAME_D / 2), "handle"))
        if k not in open_sides:
            parts.append(bx(f, (w, d, RAIL_H), (x, y, z + RAIL_H / 2 + 0.02), "handle"))
    for x in (-2.7, 2.7):
        for y in (-2.7, 2.7):
            parts.append(bx(f, (0.5, 0.5, z + RAIL_H + 0.2), (x, y, (z + RAIL_H + 0.2) / 2), "handle", along="z"))
            parts.append(bx(f, (0.6, 0.6, 0.12), (x, y, 0.06), "metal", along="x"))
    for y in (-2.75, 2.75):
        parts.append(bx(f, (5.0, 0.24, 0.3), (0, y, 0.9), "metal", along="x"))
    # Short cleats show the belt's lanes.
    return parts


def lane_cleats(f, segs):
    return [obox(f, (a[0], a[1], BELT_Z + 0.04), (b[0], b[1], BELT_Z + 0.04), 0.22, 0.12, "metal", rnd=False)
            for a, b in segs]


def splitter(f):
    """One in (-x edge), two out (-y and +y edges): an iron wedge parts the flow, a red flap picks the side."""
    parts = junction(f, "WNS")
    parts += lane_cleats(f, [((-2.5, -1.0), (-2.5, 1.0)), ((-1.5, -2.0), (-1.5, 2.0)),
                             ((-0.4, -2.5), (0.7, -2.5)), ((-0.4, 2.5), (0.7, 2.5)),
                             ((-0.4, -1.5), (1.2, -1.5)), ((-0.4, 1.5), (1.2, 1.5))])
    wedge = [(2.7, -2.2), (2.7, 2.2), (-0.6, 0.0)]
    parts.append(extrude(f, wedge, "xy", BELT_Z, BELT_Z + RAIL_H, "metal"))
    parts.append(extrude(f, [(2.75, -2.3), (2.75, 2.3), (-0.75, 0.0)], "xy", BELT_Z + RAIL_H, BELT_Z + RAIL_H + 0.15,
                         "handle"))
    # Swinging flap on a post at the wedge tip.
    parts.append(cy(f, 0.15, RAIL_H + 1.2, (-0.8, 0, BELT_Z + (RAIL_H + 1.2) / 2), "metal", verts=8))
    parts.append(obox(f, (-0.8, 0, BELT_Z + 0.75), (-2.2, -0.9, BELT_Z + 0.75), 0.12, 1.1, "paint_red"))
    parts.append(cy(f, 0.3, 0.3, (-0.8, 0, BELT_Z + RAIL_H + 1.3), "paint_red", verts=8))
    return parts


def merger(f):
    """Two in (-y and +y edges), one out (+x edge): curved guides turn both lanes onto one belt."""
    parts = junction(f, "NSE")
    parts += lane_cleats(f, [((0.4, -2.5), (0.4, -0.5)), ((0.4, 0.5), (0.4, 2.5)),
                             ((1.5, -2.5), (1.5, 2.5)), ((2.6, -2.5), (2.6, 2.5)),
                             ((-2.2, -1.5), (-0.6, -1.5)), ((-2.2, 1.5), (-0.6, 1.5))])
    # Wedge on the closed -x side, tip pointing to the exit.
    parts.append(extrude(f, [(-2.7, -2.2), (-2.7, 2.2), (0.0, 0.0)], "xy", BELT_Z, BELT_Z + RAIL_H, "metal"))
    parts.append(extrude(f, [(-2.75, -2.3), (-2.75, 2.3), (0.15, 0.0)], "xy", BELT_Z + RAIL_H,
                         BELT_Z + RAIL_H + 0.15, "handle"))
    # Yellow arrow on the top of the wedge points the way out.
    parts.append(extrude(f, [(-2.1, -0.3), (-1.0, -0.3), (-1.0, -0.7), (-0.2, 0.0), (-1.0, 0.7), (-1.0, 0.3),
                             (-2.1, 0.3)], "xy", BELT_Z + RAIL_H + 0.15, BELT_Z + RAIL_H + 0.25, "paint_yellow",
                         rnd=False))
    # Funnel boards at the exit.
    for side in (-1, 1):
        parts.append(obox(f, (1.2, side * 2.7, BELT_Z + 0.6), (2.75, side * 2.1, BELT_Z + 0.6), 0.25, 1.2, "handle"))
    return parts


def hopper_feeder(f):
    """A wooden hay bin on four posts over one belt tile, dropping hay through a gated neck."""
    parts = belt_run(f, -TILE / 2, TILE / 2)
    top_z, bot_z = 9.6, 6.6
    for x in (-2.55, 2.55):
        for y in (-2.85, 2.85):
            parts.append(bx(f, (0.55, 0.55, top_z + 0.3), (x, y, (top_z + 0.3) / 2), "handle", along="z"))
    parts.append(frustum(f, (0, 0), bot_z, (2.6, 3.2), top_z, (5.6, 6.0), "handle", wall=0.25))
    # Iron rim and corner straps.
    for y in (-2.95, 2.95):
        parts.append(bx(f, (5.9, 0.2, 0.35), (0, y, top_z - 0.1), "metal", along="x"))
    for x in (-2.75, 2.75):
        parts.append(bx(f, (0.2, 5.9, 0.35), (x, 0, top_z - 0.1), "metal", along="y"))
    for y in (-2.85, 2.85):
        parts.append(bx(f, (5.6, 0.35, 0.35), (0, y, bot_z + 0.2), "handle", along="x"))
    # Hay filling the bin, heaped above the rim.
    parts += tag([frustum(f, (0, 0), bot_z + 0.3, (2.1, 2.7), top_z - 0.25, (5.0, 5.4), "hay"),
                  frustum(f, (0.2, 0), top_z - 0.3, (4.8, 5.0), top_z + 0.9, (2.0, 2.4), "hay")], "HayFill")
    # Neck and slide gate.
    parts.append(frustum(f, (0, 0), 5.1, (2.0, 2.6), bot_z + 0.05, (2.6, 3.2), "handle", wall=0.22))
    parts.append(bx(f, (0.15, 3.4, 0.7), (1.15, 0, 5.6), "metal", along="y"))
    parts.append(obox(f, (1.25, -1.7, 5.6), (1.25, -2.6, 5.6), 0.18, 0.18, "metal"))
    parts += handwheel(f, (1.25, -2.75, 5.6), 0.55, "y", spokes=2)
    # Hay dropping onto the belt.
    parts += hay_lump(f, (0, 0), (1.8, 2.2, 1.1), BELT_Z)
    parts += hay_lump(f, (1.9, 0.2), (1.3, 1.6, 0.8), BELT_Z)
    return parts


# ---------------------------------------------------------------- sorters (tiers 1-6)

def hand_sieve_table(f):
    """Decor (was tier 1): a wooden sieve frame with an iron mesh on four splayed legs, handles to shake it."""
    parts = []
    w, d, z = 4.4, 3.0, 3.0
    for y in (-d / 2, d / 2):
        parts.append(bx(f, (w, 0.25, 0.55), (0, y, z), "handle", along="x"))
    for x in (-w / 2, w / 2):
        parts.append(bx(f, (0.25, d + 0.25, 0.55), (x, 0, z), "handle", along="y"))
    for i in range(1, 9):
        x = -w / 2 + i * w / 9
        parts.append(bx(f, (0.06, d, 0.06), (x, 0, z - 0.1), "metal", along="y", rnd=False))
    for i in range(1, 6):
        y = -d / 2 + i * d / 6
        parts.append(bx(f, (w, 0.06, 0.06), (0, y, z - 0.14), "metal", along="x", rnd=False))
    for x in (-w / 2 + 0.3, w / 2 - 0.3):
        for y in (-d / 2 + 0.3, d / 2 - 0.3):
            sx, sy = (1 if x > 0 else -1), (1 if y > 0 else -1)
            parts.append(obox(f, (x + sx * 0.3, y + sy * 0.25, 0), (x, y, z - 0.2), 0.28, 0.28, "handle"))
    for y in (-d / 2 + 0.55, d / 2 - 0.55):
        parts.append(obox(f, (-w / 2 + 0.3, y, 1.0), (w / 2 - 0.3, y, 1.0), 0.18, 0.22, "handle"))
    for y in (-0.8, 0.8):
        parts.append(obox(f, (-w / 2 - 0.1, y, z), (-w / 2 - 1.3, y, z + 0.15), 0.2, 0.2, "handle"))
    # A little hay on the mesh and a bucket catching the needles.
    parts += hay_lump(f, (0.4, 0.1), (2.2, 1.7, 0.7), z - 0.12)
    parts.append(cone(f, 0.55, 0.7, 1.0, (0.3, 0.0, 0.5), "metal", verts=10))
    parts.append(cy(f, 0.62, 0.05, (0.3, 0, 0.95), "tire", verts=10, rnd=False))
    parts += needles(f, (0.3, 0.0), 3, 1.0, spread=0.25, length=0.6, seed=3)
    return parts


def shaker_table_small(f):
    """Decor (was tier 2): slatted table on spring legs, shaken by a crank wheel and pitman arm."""
    parts = []
    w, d, z = 6.4, 4.0, 3.5
    # Slats with gaps.
    n = 7
    for i in range(n):
        y = -d / 2 + 0.35 + i * (d - 0.7) / (n - 1)
        parts.append(bx(f, (w - 0.4, 0.34, 0.16), (0, y, z - 0.08), "handle", along="x"))
    for y in (-d / 2, d / 2):
        parts.append(bx(f, (w, 0.25, 0.8), (0, y, z + 0.1), "handle", along="x"))
    parts.append(bx(f, (0.25, d, 0.8), (w / 2, 0, z + 0.1), "handle", along="y"))
    parts.append(bx(f, (0.3, d + 0.2, 0.3), (-w / 2 + 0.2, 0, z - 0.4), "handle", along="y"))
    parts.append(bx(f, (0.3, d + 0.2, 0.3), (w / 2 - 0.2, 0, z - 0.4), "handle", along="y"))
    tag(parts, "Shaker")
    # Legs with leaf-spring stacks.
    for x in (-w / 2 + 0.6, w / 2 - 0.6):
        for y in (-d / 2 + 0.3, d / 2 - 0.3):
            parts.append(bx(f, (0.4, 0.4, 2.4), (x, y, 1.2), "handle", along="z"))
            for k in range(3):
                parts.append(bx(f, (0.7, 0.5, 0.1), (x, y, 2.5 + k * 0.17), "metal", along="x", rnd=False))
            parts.append(cy(f, 0.08, 0.6, (x, y, 2.8), "metal", verts=6))
    for y in (-d / 2 + 0.3, d / 2 - 0.3):
        parts.append(bx(f, (w - 1.2, 0.25, 0.3), (0, y, 0.8), "handle", along="x"))
    # Catch tray under the slats.
    parts.append(bx(f, (w - 1.6, d - 1.0, 0.1), (0, 0, 1.1), "metal", along="x"))
    for y in (-(d - 1.0) / 2, (d - 1.0) / 2):
        parts.append(bx(f, (w - 1.6, 0.1, 0.4), (0, y, 1.3), "metal", along="x"))
    parts += needles(f, (0, 0), 4, 1.2, spread=0.8, seed=5)
    # Crank drive at the +x end.
    wx = w / 2 + 1.5
    for y in (-1.3, -0.3):
        parts.append(bx(f, (0.4, 0.3, 2.6), (wx, y, 1.3), "handle", along="z"))
    parts.append(bx(f, (1.2, 1.6, 0.2), (wx, -0.8, 0.1), "handle", along="x"))
    parts.append(cy(f, 0.12, 1.6, (wx, -0.8, 2.4), "metal", axis="y", verts=8))
    parts += tag(handwheel(f, (wx, -1.7, 2.4), 1.0, "y"), "Crank")
    parts.append(obox(f, (wx + 0.3, -1.85, 2.4), (wx + 0.3, -2.4, 2.4), 0.16, 0.16, "handle"))
    parts.append(obox(f, (wx, -1.55, 2.9), (w / 2 + 0.1, -1.55, z - 0.3), 0.22, 0.22, "handle"))
    # Hay being shaken.
    parts += tag(hay_lump(f, (-0.8, 0.2), (2.8, 2.6, 0.9), z), "HayFill")
    return parts


def conveyor_sorter(f):
    """Tier 3 needle sorter: 1 x 2 tiles over the belt, wooden sides, rusty tin roof, hopper on top,
    needle chute out the front side. About 7 studs above the belt."""
    parts = belt_run(f, -TILE, TILE)
    x0, x1 = -4.4, 4.4
    wall_top = 8.0
    # Plank walls (front -y and back +y).
    for side in (-1, 1):
        y = side * 2.85
        z = 2.7
        while z < wall_top - 0.1:
            h = min(1.05, wall_top - z)
            parts.append(bx(f, (x1 - x0, 0.4, h - 0.06), (0, y, z + h / 2), "handle", along="x"))
            z += h
        for x in (x0, 0.0, x1):
            parts.append(bx(f, (0.6, 0.6, wall_top + 0.2), (x, y + side * 0.15, (wall_top + 0.2) / 2), "handle",
                            along="z"))
        for z in (3.4, wall_top - 0.5):
            parts.append(bx(f, (x1 - x0, 0.12, 0.3), (0, y + side * 0.24, z), "metal", along="x", rnd=False))
    # Ends: header boards over the belt opening, canvas flaps hanging in it.
    open_top = BELT_Z + 3.0
    for x in (x0, x1):
        parts.append(bx(f, (0.4, 5.3, wall_top - open_top), (x, 0, (open_top + wall_top) / 2), "handle", along="y"))
        for k in range(4):
            y = -2.0 + k * 1.33
            parts.append(bx(f, (0.08, 1.2, 1.4), (x + (0.25 if x > 0 else -0.25), y, open_top - 0.7), "cloth",
                            along="z", rnd=False))
    # Gable ends and tin roof.
    ridge, eave, ey = wall_top + 1.6, wall_top - 0.1, 3.4
    for x in (x0, x1):
        parts.append(extrude(f, [(-3.05, wall_top), (3.05, wall_top), (0, ridge - 0.1)], "yz", x - 0.2, x + 0.2,
                             "handle", along="y"))
    slope = math.hypot(ey, ridge - eave)
    ang = math.atan2(ridge - eave, ey)
    for side in (-1, 1):
        yc = side * ey / 2
        zc = (ridge + eave) / 2 + 0.15
        parts.append(bx(f, (x1 - x0 + 1.2, slope + 0.3, 0.18), (0, yc, zc), "paint_red", along="x",
                        rot=(-side * ang, 0, 0)))
        for k in range(6):
            x = x0 - 0.3 + k * (x1 - x0 + 0.6) / 5
            parts.append(bx(f, (0.14, slope + 0.3, 0.12), (x, yc, zc + 0.12), "metal", along="y",
                            rot=(-side * ang, 0, 0), rnd=False))
    parts.append(cy(f, 0.22, x1 - x0 + 1.2, (0, 0, ridge + 0.2), "metal", axis="x", verts=8))
    # Hopper on the roof with hay heaped in it.
    hz0, hz1 = ridge - 0.3, BELT_Z + 7.0
    parts.append(frustum(f, (-1.2, 0), hz0, (1.4, 1.4), hz1, (3.4, 3.4), "handle", wall=0.2))
    parts.append(bx(f, (3.6, 0.2, 0.3), (-1.2, -1.7, hz1 - 0.1), "metal", along="x"))
    parts.append(bx(f, (3.6, 0.2, 0.3), (-1.2, 1.7, hz1 - 0.1), "metal", along="x"))
    parts.append(frustum(f, (-1.2, 0), hz1 - 0.6, (3.0, 3.0), hz1 + 0.4, (1.4, 1.6), "hay"))
    # Needle chute out the front, into a small bin.
    parts += trough(f, (1.8, -3.1, 5.4), (1.8, -4.6, 3.0), 1.1, 0.4, "metal")
    parts.append(bx(f, (1.4, 1.2, 0.4), (1.8, -3.3, 5.6), "handle", along="x"))
    parts.append(frustum(f, (1.8, -4.8), 0.0, (1.5, 1.3), 1.5, (1.8, 1.6), "handle", wall=0.15, closed=False))
    parts.append(bx(f, (1.5, 1.3, 0.15), (1.8, -4.8, 0.1), "handle", along="x"))
    parts += needles(f, (1.8, -4.8), 4, 1.2, spread=0.35, length=0.8, seed=7)
    # Crank box on the back wall drives the sorting combs.
    parts.append(bx(f, (1.4, 0.8, 1.4), (-2.4, 3.4, 5.6), "metal", along="x"))
    parts += handwheel(f, (-2.4, 3.9, 5.6), 0.6, "y", spokes=2)
    return parts


def magnet_drum_small(f):
    """Decor (was tier 4): belt feeds a big rotating iron drum (red magnet poles); hay drops off the end,
    needles cling to the drum and fall into a chute. 1 x 2 tiles."""
    parts = belt_run(f, -TILE, 0.0)
    dc, r, L = (2.6, 0.0, 4.6), 2.4, 4.8
    drum = len(parts)
    parts.append(cy(f, r, L, dc, "paint_blue", axis="y", verts=16))
    for y in (-L / 2 + 0.2, L / 2 - 0.2):
        parts.append(cy(f, r + 0.15, 0.4, (dc[0], y, dc[2]), "metal", axis="y", verts=16, rnd=False))
    for k in range(8):
        a = 2 * math.pi * k / 8
        x, z = dc[0] + (r + 0.02) * math.cos(a), dc[2] + (r + 0.02) * math.sin(a)
        parts.append(bx(f, (0.3, L - 0.6, 0.15), (x, 0, z), "metal", along="y", rot=(0, -a + math.pi / 2, 0),
                        rnd=False))
    tag(parts[drum:], "Drum")
    for side in (-1, 1):
        parts += tag([cy(f, r * 0.9, 0.25, (dc[0], side * (L / 2 + 0.1), dc[2]), "paint_red", axis="y", verts=16)],
                     "Drum")
        for k in range(3):
            a = math.pi * k / 3
            parts += tag([obox(f, (dc[0] + r * 0.8 * math.cos(a), side * (L / 2 + 0.25), dc[2] + r * 0.8 * math.sin(a)),
                              (dc[0] - r * 0.8 * math.cos(a), side * (L / 2 + 0.25), dc[2] - r * 0.8 * math.sin(a)),
                              0.25, 0.15, "metal", rnd=False)], "Drum")
        parts.append(cy(f, 0.4, 1.0, (dc[0], side * (L / 2 + 0.5), dc[2]), "metal", axis="y", verts=8))
        y = side * (L / 2 + 0.7)
        # A-frame stands at both ends of the drum.
        for dx in (-1.6, 1.6):
            parts.append(obox(f, (dc[0] + dx, y, 0), (dc[0], y, dc[2] + 0.3), 0.45, 0.45, "metal"))
        parts.append(bx(f, (3.8, 0.45, 0.35), (dc[0], y, 1.0), "metal", along="x"))
        parts.append(bx(f, (1.0, 0.6, 0.9), (dc[0], y, dc[2]), "metal", along="z"))
    # Gear wheel and motor box on the back end.
    gear = len(parts)
    parts.append(cy(f, 1.3, 0.3, (dc[0], L / 2 + 1.25, dc[2]), "metal", axis="y", verts=16))
    for k in range(12):
        a = 2 * math.pi * k / 12
        parts.append(bx(f, (0.3, 0.3, 0.3), (dc[0] + 1.4 * math.cos(a), L / 2 + 1.25, dc[2] + 1.4 * math.sin(a)),
                        "metal", rot=(0, -a, 0), rnd=False))
    tag(parts[gear:], "Drum")
    parts.append(bx(f, (1.6, 1.4, 1.6), (dc[0] - 2.2, 2.3, 0.8), "paint_green", along="x"))
    parts.append(obox(f, (dc[0] - 2.2, 2.3, 1.6), (dc[0], L / 2 + 1.25, dc[2]), 0.2, 0.2, "metal"))
    # Needles stuck to the drum.
    for k, a in enumerate((1.0, 1.4, 1.9, 2.5)):
        x, z = dc[0] + (r + 0.15) * math.cos(-a), dc[2] + (r + 0.15) * math.sin(-a)
        parts += tag([bx(f, (0.08, 0.7, 0.08), (x, -1.4 + k * 0.9, z), "metal", along="y", rnd=False)], "Drum")
    # Under the drum: needle chute to the front into a bin.
    parts += trough(f, (dc[0] - 0.6, 1.6, 1.0), (dc[0] - 0.6, -3.2, 0.4), 1.4, 0.4, "metal")
    parts.append(frustum(f, (dc[0] - 0.6, -3.9), 0.0, (1.6, 1.3), 1.1, (1.9, 1.6), "handle", wall=0.15))
    parts.append(bx(f, (1.6, 1.3, 0.15), (dc[0] - 0.6, -3.9, 0.08), "handle"))
    parts += needles(f, (dc[0] - 0.6, -3.9), 4, 0.9, spread=0.3, length=0.7, seed=9)
    # Hay that came off the drum.
    parts += hay_lump(f, (dc[0] + 2.4, -0.5), (1.6, 2.4, 0.8), 0.0)
    return parts


# Sorter tiers 1, 2 and 4 as 2-tile machines with the game's fallback proportions (Machines.sorter):
# side walls 7 above the belt (top 10.5), tin roof to 11.5, hopper on the upstream (-x) roof half,
# the tier's silhouette on the downstream (+x) half, a painted tier band 0.9 tall near the top of both
# long walls (Machines.TierLooks), a flat Sign board on the front wall and a needle chute to a bin.
SH_X = 5.6        # wall ends / corner posts
SH_Y = 3.0        # wall center line
SH_TOP = BELT_Z + 7.0
SH_RIDGE = SH_TOP + 1.0
SH_DOWN = 3.0     # center x of the downstream roof half (where the silhouette sits)


def sorter_shed(f, band, sign="paint_cream"):
    """The shared tier shell. band: paint kind of the tier band (None = bare wood boards)."""
    parts = belt_run(f, -TILE, TILE)
    # Plank walls, corner and middle posts, the tier band.
    for side in (-1, 1):
        y = side * SH_Y
        z = 2.7
        while z < SH_TOP - 0.1:
            h = min(1.1, SH_TOP - z)
            parts.append(bx(f, (2 * SH_X, 0.4, h - 0.07), (0, y, z + h / 2), "handle", along="x", rnd=False))
            z += h
        for x in (-SH_X, 0.0, SH_X):
            parts.append(bx(f, (0.6, 0.6, SH_TOP + 0.1), (x, y + side * 0.15, (SH_TOP + 0.1) / 2), "handle",
                            along="z"))
        parts.append(bx(f, (2 * SH_X - 0.6, 0.2, 0.9), (0, y + side * 0.3, SH_TOP - 1.0), band or "handle",
                        along="x", rnd=False))
        parts.append(bx(f, (2 * SH_X - 0.6, 0.12, 0.2), (0, y + side * 0.24, 3.4), "metal", along="x", rnd=False))
    # Ends: header boards over the bale opening.
    open_top = BELT_Z + 3.5
    for x in (-SH_X, SH_X):
        parts.append(bx(f, (0.4, 2 * SH_Y, SH_TOP - open_top), (x, 0, (open_top + SH_TOP) / 2), "handle", along="y",
                        rnd=False))
        parts.append(bx(f, (0.5, 2 * SH_Y + 0.2, 0.3), (x, 0, open_top + 0.15), "metal", along="y", rnd=False))
        parts.append(extrude(f, [(-SH_Y - 0.2, SH_TOP), (SH_Y + 0.2, SH_TOP), (0, SH_RIDGE - 0.1)], "yz", x - 0.2,
                             x + 0.2, "handle", along="y", rnd=False))
    # Low gable tin roof with ribs, eaves overhanging the walls.
    ey = SH_Y + 0.6
    slope, ang = math.hypot(ey, SH_RIDGE - SH_TOP), math.atan2(SH_RIDGE - SH_TOP, ey)
    for side in (-1, 1):
        yc, zc = side * ey / 2, (SH_RIDGE + SH_TOP) / 2 + 0.05
        parts.append(bx(f, (2 * SH_X + 1.0, slope, 0.16), (0, yc, zc), "metal", along="x", rot=(-side * ang, 0, 0),
                        rnd=False))
        for k in range(7):
            x = -SH_X - 0.3 + k * (2 * SH_X + 0.6) / 6
            parts.append(bx(f, (0.14, slope, 0.1), (x, yc, zc + 0.11), "metal", along="y", rot=(-side * ang, 0, 0),
                            rnd=False))
    # Hopper on the upstream half with hay heaped in it.
    hx, hz0, hz1 = -SH_DOWN, SH_RIDGE - 0.6, SH_RIDGE + 1.6
    parts.append(frustum(f, (hx, 0), hz0, (1.6, 1.6), hz1, (3.4, 3.4), "handle", wall=0.2))
    for y in (-1.75, 1.75):
        parts.append(bx(f, (3.7, 0.2, 0.3), (hx, y, hz1 - 0.12), "metal", along="x", rnd=False))
    parts.append(frustum(f, (hx, 0), hz1 - 0.6, (3.1, 3.1), hz1 + 0.5, (1.6, 1.8), "hay"))
    # Needle chute out the front wall into a small wooden bin.
    cx = SH_DOWN
    parts += trough(f, (cx, -SH_Y - 0.2, 5.8), (cx, -4.2, 2.6), 1.1, 0.4, "metal")
    parts.append(bx(f, (1.5, 0.4, 1.2), (cx, -SH_Y - 0.3, 6.0), "metal", along="x", rnd=False))
    parts.append(frustum(f, (cx, -4.4), 0.0, (1.5, 1.3), 1.4, (1.8, 1.6), "handle", wall=0.15, closed=False))
    parts.append(bx(f, (1.5, 1.3, 0.15), (cx, -4.4, 0.1), "handle", along="x", rnd=False))
    parts += needles(f, (cx, -4.4), 4, 1.1, spread=0.35, length=0.8, seed=7)
    # Flat sign board on the front wall: the game draws the stars and rate on it.
    parts += tag([bx(f, (4.4, 0.2, 2.4), (-2.6, -SH_Y - 0.4, 6.9), sign, along="x", rnd=False)], "Sign")
    for x in (-4.6, -0.6):
        parts.append(bx(f, (0.25, 0.25, 2.8), (x, -SH_Y - 0.33, 6.9), "metal", along="z", rnd=False))
    # Two skids across the downstream roof half: a level seat for the tier's silhouette.
    for x in (SH_DOWN - 1.7, SH_DOWN + 1.7):
        parts.append(bx(f, (0.5, 2 * SH_Y + 0.4, 0.9), (x, 0, SH_RIDGE - 0.15), "handle", along="y", rnd=False))
    return parts


SKID_TOP = SH_RIDGE + 0.3


def hand_sieve(f):
    """Tier 1 sorter (1 star): a bare-wood plank shed over two belt tiles (12 x 9.4, walls 7 above the
    belt, tin roof to 11.5) with a round riddle sieve resting on the downstream roof half (Screen,
    shakes) worked by a hand crank on the back wall. No paint: the tier band is a plain board."""
    parts = sorter_shed(f, None, sign="greywood")
    c, r, z = (SH_DOWN, 0.0), 2.4, SKID_TOP + 0.5
    screen = []
    n = 12
    for i in range(n):
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        p0 = (c[0] + r * math.cos(a0 - 0.04), c[1] + r * math.sin(a0 - 0.04), z)
        p1 = (c[0] + r * math.cos(a1 + 0.04), c[1] + r * math.sin(a1 + 0.04), z)
        screen.append(obox(f, p0, p1, 0.3, 0.9, "handle", rnd=False))
    for k in range(-3, 4):
        d = k * 0.6
        half = math.sqrt(max(0.0, r * r - d * d)) - 0.1
        screen.append(bx(f, (2 * half, 0.08, 0.08), (c[0], c[1] + d, z - 0.3), "handle", along="x", rnd=False))
        screen.append(bx(f, (0.08, 2 * half, 0.08), (c[0] + d, c[1], z - 0.25), "handle", along="y", rnd=False))
    screen.append(bx(f, (0.3, 0.3, 0.9), (c[0] - r - 0.3, 0, z + 0.1), "handle", along="z", rnd=False))
    parts += tag(screen, "Screen")
    # Cradle blocks under the hoop.
    for x in (SH_DOWN - 1.7, SH_DOWN + 1.7):
        for y in (-1.6, 1.6):
            parts.append(bx(f, (0.5, 0.5, 0.35), (x, y, SKID_TOP - 0.05 + 0.15), "metal", along="x", rnd=False))
    # Hand crank on the back wall with a push rod up to the sieve.
    hc = (SH_DOWN, SH_Y + 0.55, 8.0)
    parts.append(bx(f, (1.0, 0.5, 1.0), (hc[0], SH_Y + 0.45, hc[2]), "metal", along="x", rnd=False))
    parts.append(cy(f, 0.1, 0.7, (hc[0], hc[1], hc[2]), "metal", axis="y", verts=6))
    parts.append(obox(f, (hc[0], hc[1] + 0.3, hc[2]), (hc[0] + 1.2, hc[1] + 0.3, hc[2] + 0.5), 0.2, 0.2, "metal",
                      rnd=False))
    parts.append(obox(f, (hc[0] + 1.2, hc[1] + 0.3, hc[2] + 0.4), (hc[0] + 1.2, hc[1] + 0.6, hc[2] + 0.4), 0.22,
                      0.22, "handle", rnd=False))
    parts.append(obox(f, (hc[0] - 0.4, hc[1] - 0.1, hc[2] + 0.3), (c[0] - r - 0.3, 0.6, z), 0.18, 0.18, "handle",
                      rnd=False))
    return parts


def coil_spring(f, c, z0, h, r=0.38):
    out = [cy(f, r * 0.45, h, (c[0], c[1], z0 + h / 2), "metal", verts=6, rnd=False)]
    for k in range(4):
        out.append(cy(f, r, 0.1, (c[0], c[1], z0 + 0.1 + k * (h - 0.2) / 3), "metal", verts=8, rnd=False))
    return out


def shaker_table(f):
    """Tier 2 sorter (2 stars): the plank shed with a sage-painted tier band; on the downstream roof half a
    slatted deck tipped 8 degrees toward the chute rides on four coil springs (Shaker), driven by a
    crank wheel on the back wall (Crank) through a pitman arm."""
    parts = sorter_shed(f, "paint_green")
    sz = SKID_TOP
    for x in (SH_DOWN - 1.7, SH_DOWN + 1.7):
        for y in (-1.8, 1.8):
            parts += coil_spring(f, (x, y), sz, 0.9)
    # The deck: two side rails, end boards and slats, built level then tipped 8 degrees toward -y.
    dz = sz + 1.05
    deck = []
    w, d = 5.0, 5.0
    for x in (-w / 2, w / 2):
        deck.append(bx(f, (0.3, d, 0.5), (SH_DOWN + x, 0, dz + 0.1), "handle", along="y", rnd=False))
    deck.append(bx(f, (w, 0.3, 0.6), (SH_DOWN, d / 2, dz + 0.15), "handle", along="x", rnd=False))
    for i in range(7):
        y = -d / 2 + 0.35 + i * (d - 0.7) / 6
        deck.append(bx(f, (w - 0.3, 0.42, 0.15), (SH_DOWN, y, dz), "handle", along="x", rnd=False))
    for y in (-1.8, 1.8):
        deck.append(bx(f, (w + 0.2, 0.4, 0.3), (SH_DOWN, y, dz - 0.2), "handle", along="x", rnd=False))
    m = (Matrix.Translation(Vector((SH_DOWN, 0, dz)) * S) @ Matrix.Rotation(math.radians(-8), 4, "X")
         @ Matrix.Translation(-Vector((SH_DOWN, 0, dz)) * S))
    parts += tag(xform(deck, m), "Shaker")
    # Crank wheel on the back wall, pitman arm up to the deck.
    wc = (SH_DOWN + 1.5, SH_Y + 0.7, 8.4)
    parts.append(bx(f, (0.4, 0.6, 2.2), (wc[0], SH_Y + 0.5, wc[2] - 0.6), "handle", along="z", rnd=False))
    parts.append(cy(f, 0.12, 0.8, (wc[0], SH_Y + 0.6, wc[2]), "metal", axis="y", verts=6))
    crank = handwheel(f, wc, 1.0, "y", spokes=2)
    crank.append(obox(f, (wc[0] + 0.7, wc[1] + 0.1, wc[2]), (wc[0] + 0.7, wc[1] + 0.4, wc[2]), 0.18, 0.18, "metal",
                      rnd=False))
    parts += tag(crank, "Crank")
    parts.append(obox(f, (wc[0] - 0.2, wc[1] - 0.25, wc[2] + 0.6), (SH_DOWN + 2.0, 2.6, dz - 0.3), 0.22, 0.22,
                      "metal", rnd=False))
    return parts


def magnet_drum(f):
    """Tier 4 sorter (4 stars): the plank shed with a barn-red tier band; a big red magnet drum
    (Drum, spins about y) crosses the downstream roof half between two iron bearing blocks, driven by a
    small motor and chain on the back."""
    parts = sorter_shed(f, "paint_red")
    r, L = 1.9, 4.6
    dc = (SH_DOWN, 0.0, SKID_TOP + r + 0.35)
    drum = [cy(f, r, L, dc, "paint_red", axis="y", verts=16, exact=True)]
    for y in (-L / 2 + 0.2, L / 2 - 0.2):
        drum.append(cy(f, r + 0.12, 0.35, (dc[0], y, dc[2]), "paint_red", axis="y", verts=16, rnd=False, exact=True))
    for k in range(8):
        a = 2 * math.pi * k / 8
        drum.append(bx(f, (0.3, L - 0.8, 0.14), (dc[0] + (r + 0.02) * math.cos(a), 0, dc[2] + (r + 0.02) * math.sin(a)),
                       "paint_red", along="y", rot=(0, -a + math.pi / 2, 0), rnd=False))
    drum.append(cy(f, 0.35, L + 1.6, dc, "paint_red", axis="y", verts=8, rnd=False))
    parts += tag(drum, "Drum")
    # Bearing blocks on the skids.
    for side in (-1, 1):
        y = side * (L / 2 + 0.55)
        parts.append(bx(f, (1.6, 0.8, dc[2] - SKID_TOP + 0.4), (dc[0], y, (SKID_TOP + dc[2] + 0.4) / 2), "metal",
                        along="z"))
        parts.append(bx(f, (3.8, 0.9, 0.3), (dc[0], y, SKID_TOP + 0.15), "metal", along="x", rnd=False))
        parts.append(cy(f, 0.55, 0.9, (dc[0], y, dc[2]), "metal", axis="y", verts=10, exact=True))
    # Motor on the back skid end with a drive chain to the drum axle.
    parts.append(bx(f, (1.4, 1.2, 1.2), (dc[0] + 1.6, SH_Y + 0.2, SKID_TOP + 0.6), "metal", along="x"))
    parts.append(obox(f, (dc[0] + 1.6, SH_Y + 0.9, SKID_TOP + 0.6), (dc[0], L / 2 + 1.1, dc[2]), 0.25, 0.12, "metal",
                      rnd=False))
    return parts


def optical_sorter(f):
    """Tier 5: an enclosed iron-and-paint cabinet over 2 tiles of belt with glass inspection windows,
    camera lenses on the front, a lamp and air-jet reject chute."""
    parts = belt_run(f, -TILE, TILE)
    x0, x1, yb, z0, z1 = -4.4, 4.4, 3.0, 2.5, 8.6
    parts.append(bx(f, (x1 - x0, 2 * yb, z1 - z0), (0, 0, (z0 + z1) / 2), "paint_cream", along="x"))
    for x in (x0, x1):
        for y in (-yb, yb):
            parts.append(bx(f, (0.4, 0.4, z1 + 0.1), (x, y, (z1 + 0.1) / 2), "metal", along="z"))
    for z in (z0 + 0.15, z1 - 0.1):
        for y in (-yb, yb):
            parts.append(bx(f, (x1 - x0, 0.3, 0.3), (0, y, z), "metal", along="x"))
    # Tunnel mouths at both ends with rubber strip curtains.
    for x in (x0, x1):
        sx = 1 if x > 0 else -1
        parts.append(bx(f, (0.1, 5.2, 2.9), (x + sx * 0.05, 0, BELT_Z + 1.45), "glass", rnd=False))
        for k in range(6):
            y = -2.2 + k * 0.88
            parts.append(bx(f, (0.08, 0.78, 2.3), (x + sx * 0.15, y, BELT_Z + 1.65), "tire", along="z", rnd=False))
        parts.append(bx(f, (0.4, 5.6, 0.4), (x + sx * 0.1, 0, BELT_Z + 3.0), "metal", along="y"))
    # Inspection windows on the front.
    for x in (-2.6, 0.0, 2.6):
        parts.append(bx(f, (2.0, 0.1, 1.6), (x, -yb - 0.05, 6.6), "glass", rnd=False))
        for dx in (-1.05, 1.05):
            parts.append(bx(f, (0.15, 0.2, 1.8), (x + dx, -yb - 0.08, 6.6), "metal", along="z", rnd=False))
        for dz in (-0.85, 0.85):
            parts.append(bx(f, (2.25, 0.2, 0.15), (x, -yb - 0.08, 6.6 + dz), "metal", along="x", rnd=False))
    # Camera lenses below the windows.
    for x in (-2.6, 0.0, 2.6):
        parts.append(cy(f, 0.55, 0.5, (x, -yb - 0.25, 4.4), "metal", axis="y", verts=12))
        parts.append(cy(f, 0.38, 0.12, (x, -yb - 0.52, 4.4), "glass", axis="y", verts=12, rnd=False))
    # Control box with red buttons.
    parts.append(bx(f, (1.2, 0.5, 1.4), (3.4, -yb - 0.25, 3.6), "metal", along="z"))
    for z in (3.3, 3.9):
        parts.append(cy(f, 0.15, 0.15, (3.4, -yb - 0.55, z), "paint_red", axis="y", verts=8, rnd=False))
    # Roof: lenses looking down, lamp, vent.
    parts.append(bx(f, (x1 - x0 + 0.6, 2 * yb + 0.6, 0.3), (0, 0, z1 + 0.15), "metal", along="x"))
    for x in (-2.5, 0.0, 2.5):
        parts.append(cy(f, 0.6, 1.0, (x, -0.8, z1 + 0.8), "metal", verts=12))
        parts.append(cy(f, 0.45, 0.1, (x, -0.8, z1 + 1.33), "glass", verts=12, rnd=False))
    parts.append(cy(f, 0.15, 1.6, (-3.4, 1.6, z1 + 1.1), "metal", verts=8))
    parts.append(cone(f, 0.5, 0.25, 0.5, (-3.4, 1.6, z1 + 2.0), "metal", verts=10))
    parts.append(cy(f, 0.3, 0.4, (-3.4, 1.6, z1 + 1.65), "glass", verts=10, rnd=False))
    parts.append(bx(f, (2.4, 1.6, 0.8), (2.6, 1.5, z1 + 0.7), "metal", along="x"))
    for k in range(4):
        parts.append(bx(f, (2.2, 0.12, 0.12), (2.6, 0.75 - 0.01, z1 + 0.45 + k * 0.17), "tire", along="x", rnd=False))
    # Reject chute to a needle bin at the back right.
    parts.append(cy(f, 0.35, 1.2, (1.5, yb + 0.4, 5.0), "metal", axis="y", verts=10))
    parts += trough(f, (1.5, yb + 0.9, 4.8), (1.5, yb + 1.8, 2.0), 1.0, 0.35, "metal")
    parts.append(frustum(f, (1.5, yb + 2.0), 0.0, (1.5, 1.2), 1.4, (1.8, 1.5), "metal", wall=0.12))
    parts.append(bx(f, (1.5, 1.2, 0.12), (1.5, yb + 2.0, 0.08), "metal"))
    return parts


def needle_type_splitter(f):
    """A sorting box with a hopper that sends each needle type down its own chute to its own bin."""
    parts = []
    hx0, hx1, hy0, hy1, hz0, hz1 = -2.8, 2.8, 0.4, 2.8, 2.0, 6.4
    parts.append(bx(f, (hx1 - hx0, hy1 - hy0, hz1 - hz0), (0, (hy0 + hy1) / 2, (hz0 + hz1) / 2), "handle",
                    along="x"))
    for x in (hx0, hx1):
        for y in (hy0, hy1):
            parts.append(bx(f, (0.5, 0.5, hz1 + 0.2), (x, y, (hz1 + 0.2) / 2), "handle", along="z"))
    for z in (hz0 + 0.2, hz1 - 0.15):
        parts.append(bx(f, (hx1 - hx0 + 0.2, 0.15, 0.3), (0, hy0 - 0.05, z), "metal", along="x"))
    parts.append(frustum(f, (0, 1.6), hz1, (1.6, 1.2), hz1 + 2.0, (3.4, 2.6), "metal", wall=0.15))
    parts += needles(f, (0, 1.6), 5, hz1 + 1.6, spread=0.6, length=0.8, seed=11)
    # Four chutes to four bins, each with its colour tag.
    tags = ("paint_red", "paint_green", "paint_blue", "paint_yellow")
    for k, tag in enumerate(tags):
        x = -2.1 + k * 1.4
        zc = 5.4 - k * 0.8
        parts += trough(f, (x, hy0, zc), (x, -1.6, 1.4), 0.9, 0.3, "metal")
        parts.append(bx(f, (1.0, 0.15, 0.5), (x, hy0 - 0.08, zc + 0.6), tag, along="x"))
        parts.append(frustum(f, (x, -2.2), 0.0, (1.1, 1.1), 1.2, (1.3, 1.3), "handle", wall=0.12))
        parts.append(bx(f, (1.1, 1.1, 0.12), (x, -2.2, 0.08), "handle"))
        parts.append(bx(f, (1.32, 1.32, 0.25), (x, -2.2, 0.95), tag, rnd=False))
        parts += needles(f, (x, -2.2), 2, 0.6, spread=0.2, length=0.6, seed=20 + k)
    # Lever on the side.
    parts.append(obox(f, (hx1 + 0.25, 1.4, 4.0), (hx1 + 0.6, 1.0, 5.6), 0.15, 0.15, "metal"))
    parts.append(cy(f, 0.25, 0.25, (hx1 + 0.62, 1.0, 5.7), "paint_red", verts=8))
    return parts


def needle_bundler(f):
    """A workbench that funnels needles into a forming tube and ties them with twine into bundles."""
    parts = []
    w, d, z = 5.4, 3.0, 3.0
    parts.append(bx(f, (w, d, 0.3), (0, 0, z - 0.15), "handle", along="x"))
    for x in (-w / 2 + 0.3, w / 2 - 0.3):
        for y in (-d / 2 + 0.3, d / 2 - 0.3):
            parts.append(bx(f, (0.35, 0.35, z - 0.3), (x, y, (z - 0.3) / 2), "handle", along="z"))
        parts.append(bx(f, (0.25, d - 0.6, 0.25), (x, 0, 0.7), "handle", along="y"))
    parts.append(bx(f, (w - 0.6, 0.25, 0.25), (0, d / 2 - 0.3, 0.7), "handle", along="x"))
    # Funnel feeding the forming tube.
    parts.append(frustum(f, (0.8, 0.4), z + 2.0, (0.6, 0.6), z + 3.4, (2.0, 2.0), "metal", wall=0.12))
    for x in (0.0, 1.6):
        parts.append(bx(f, (0.2, 0.2, 2.4), (x, 0.4, z + 1.2), "metal", along="z"))
    parts.append(cy(f, 0.45, 2.8, (0.3, 0.4, z + 1.2), "metal", axis="x", verts=10))
    parts.append(cy(f, 0.25, 1.0, (0.8, 0.4, z + 1.9), "metal", verts=8))
    parts.append(cone(f, 0.45, 0.6, 0.3, (-1.25, 0.4, z + 1.2), "metal", axis="x", verts=10))
    # Twine spool on a post.
    parts.append(bx(f, (0.3, 0.3, 2.2), (1.9, 1.0, z + 1.1), "handle", along="z"))
    parts.append(cy(f, 0.5, 0.9, (1.9, 0.5, z + 2.0), "twine", axis="y", verts=12))
    for dy in (-0.45, 0.45):
        parts.append(cy(f, 0.65, 0.1, (1.9, 0.5 + dy, z + 2.0), "handle", axis="y", verts=12))
    parts.append(obox(f, (1.9, 0.2, z + 1.55), (0.6, 0.4, z + 1.25), 0.06, 0.06, "twine", rnd=False))
    parts += handwheel(f, (2.0, -0.4, z + 1.2), 0.55, "y", spokes=2)
    parts.append(cy(f, 0.08, 1.0, (2.0, 0.1, z + 1.2), "metal", axis="y", verts=6))
    # Tray of finished bundles at the front-left.
    parts.append(bx(f, (2.4, 1.6, 0.12), (-1.3, -0.6, z + 0.06), "handle", along="x"))
    for y in (-1.4, 0.2):
        parts.append(bx(f, (2.4, 0.12, 0.35), (-1.3, y, z + 0.17), "handle", along="x"))
    for k, (bxx, by, bz) in enumerate(((-1.3, -1.0, 0.45), (-1.3, -0.25, 0.45), (-1.3, -0.62, 0.95))):
        for i in range(7):
            a = 2 * math.pi * i / 6
            rr = 0.0 if i == 6 else 0.17
            parts.append(cy(f, 0.08, 1.9, (bxx, by + rr * math.cos(a), z + bz + rr * math.sin(a) - 0.1),
                            "metal", axis="x", verts=5, rnd=False))
        for dx in (-0.45, 0.45):
            parts.append(cy(f, 0.3, 0.15, (bxx + dx, by, z + bz - 0.1), "twine", axis="x", verts=8, rnd=False))
    return parts


def needle_polisher(f):
    """A bench polisher: green motor in the middle, cloth buffing wheels on each end, tray of bright needles."""
    parts = []
    w, d, z = 5.0, 2.8, 3.0
    parts.append(bx(f, (w, d, 0.3), (0, 0, z - 0.15), "handle", along="x"))
    for x in (-w / 2 + 0.3, w / 2 - 0.3):
        for y in (-d / 2 + 0.3, d / 2 - 0.3):
            parts.append(bx(f, (0.35, 0.35, z - 0.3), (x, y, (z - 0.3) / 2), "handle", along="z"))
        parts.append(bx(f, (0.25, d - 0.6, 0.25), (x, 0, 0.7), "handle", along="y"))
    parts.append(bx(f, (w - 0.6, d - 0.6, 0.15), (0, 0, 0.7), "handle", along="x"))
    # Motor on a base.
    parts.append(bx(f, (1.8, 1.4, 0.4), (0, 0.3, z + 0.2), "metal", along="x"))
    parts.append(cy(f, 0.75, 1.8, (0, 0.3, z + 1.2), "paint_green", axis="x", verts=12))
    for x in (-0.95, 0.95):
        parts.append(cy(f, 0.6, 0.15, (x, 0.3, z + 1.2), "metal", axis="x", verts=12))
    for k in range(4):
        parts.append(bx(f, (1.4, 0.1, 0.1), (0, 0.3 - 0.76, z + 0.8 + k * 0.25), "metal", along="x", rnd=False))
    parts.append(cy(f, 0.1, 4.4, (0, 0.3, z + 1.2), "metal", axis="x", verts=8))
    for side in (-1, 1):
        x = side * 1.75
        parts.append(cy(f, 0.95, 0.45, (x, 0.3, z + 1.2), "cloth", axis="x", verts=14))
        parts.append(cy(f, 0.3, 0.5, (x, 0.3, z + 1.2), "metal", axis="x", verts=8))
        # Guard hood behind and over each wheel.
        parts.append(bx(f, (0.7, 0.3, 1.9), (x, 1.35, z + 1.2), "metal", along="z"))
        parts.append(bx(f, (0.7, 1.4, 0.2), (x, 0.75, z + 2.3), "metal", along="y"))
    # Polish compound tin and a tray of polished needles.
    parts.append(cy(f, 0.35, 0.5, (-1.6, -0.9, z + 0.25), "paint_yellow", verts=10))
    parts.append(bx(f, (1.8, 1.0, 0.1), (1.0, -0.85, z + 0.05), "metal", along="x"))
    for y in (-1.35, -0.35):
        parts.append(bx(f, (1.8, 0.1, 0.25), (1.0, y, z + 0.12), "metal", along="x"))
    parts += needles(f, (1.0, -0.85), 6, z + 0.15, spread=0.4, length=0.7, seed=13)
    # Off switch.
    parts.append(bx(f, (0.5, 0.3, 0.6), (0, -0.55, z + 0.3), "metal"))
    parts.append(cy(f, 0.12, 0.15, (0, -0.72, z + 0.4), "paint_red", axis="y", verts=8, rnd=False))
    return parts


# ---------------------------------------------------------------- hay and forge machines

def hay_baler(f):
    """Classic small square baler: red bale chamber, pickup reel with tines, flywheel, hitch tongue,
    two wheels and a bale chute at the back with a bale sliding out."""
    parts = []
    # Bale chamber along x on the +y side.
    cy0, cw, ch, cz = 1.4, 3.6, 3.0, 2.0
    parts.append(bx(f, (9.0, cw, ch), (0.5, cy0, cz + ch / 2), "paint_red", along="x"))
    for x in (-3.8, -1.0, 2.0, 4.6):
        parts.append(bx(f, (0.25, cw + 0.15, ch + 0.15), (x, cy0, cz + ch / 2), "metal", along="z"))
    parts.append(bx(f, (0.15, 3.0, 2.5), (-4.0, cy0, cz + ch / 2), "tire", rnd=False))
    # Knotter box and needle arch on top.
    parts.append(bx(f, (1.8, 2.6, 1.0), (-1.8, cy0, cz + ch + 0.5), "metal", along="x"))
    for y in (cy0 - 1.6, cy0 + 1.6):
        parts.append(obox(f, (-0.6, y, cz + ch), (-1.2, y, cz + ch + 1.5), 0.25, 0.25, "metal"))
    parts.append(bx(f, (0.25, 3.45, 0.25), (-1.2, cy0, cz + ch + 1.5), "metal", along="y"))
    parts.append(cy(f, 0.45, 0.6, (-1.8, cy0, cz + ch + 1.2), "twine", verts=10))
    # Pickup head on the -y side, ahead of the wheels.
    py0, py1 = -3.8, -0.3
    pm = (py0 + py1) / 2
    reel = len(parts)
    parts.append(cy(f, 0.55, py1 - py0, (3.9, pm, 0.95), "metal", axis="y", verts=10))
    for k in range(7):
        y = py0 + 0.3 + k * (py1 - py0 - 0.6) / 6
        for a in (0.2 + k * 0.4, 1.8 + k * 0.4, 3.4 + k * 0.4, 5.0 + k * 0.4):
            ca, sa = math.cos(a), math.sin(a)
            parts.append(obox(f, (3.9 + 0.45 * ca, y, 0.95 + 0.45 * sa), (3.9 + 1.0 * ca, y, 0.95 + 1.0 * sa),
                              0.12, 0.12, "metal", rnd=False))
    tag(parts[reel:], "Reel")
    # Auger trough over the reel carries the hay sideways into the chamber.
    parts.append(bx(f, (2.2, py1 - py0, 0.25), (3.1, pm, 2.15), "paint_red", along="y"))
    parts.append(bx(f, (0.25, py1 - py0, 1.3), (2.1, pm, 2.7), "paint_red", along="y"))
    parts.append(cy(f, 0.5, py1 - py0, (3.0, pm, 2.75), "metal", axis="y", verts=10))
    for k in range(5):
        parts.append(cy(f, 0.62, 0.1, (3.0, py0 + 0.4 + k * 0.7, 2.75), "metal", axis="y", verts=10, rnd=False))
    for side in (py0, py1):
        parts.append(extrude(f, [(2.0, 0.4), (4.9, 0.4), (4.9, 1.4), (3.6, 3.2), (2.0, 3.2)], "xz",
                             side - 0.1, side + 0.1, "paint_red", along="x"))
    # Flywheel at the front of the chamber.
    parts += tag(handwheel(f, (5.4, cy0 + 1.1, cz + 1.6), 1.4, "y", kind="metal", spokes=3), "Flywheel")
    parts.append(cy(f, 0.25, 1.4, (5.4, cy0 + 0.4, cz + 1.6), "metal", axis="y", verts=8))
    parts.append(bx(f, (1.0, 0.6, 1.0), (5.4, cy0, cz + 1.6), "metal"))
    # Tongue and hitch.
    parts.append(obox(f, (5.0, cy0 - 0.8, 2.2), (9.0, -1.0, 2.0), 0.4, 0.4, "paint_red"))
    parts.append(obox(f, (4.3, -3.4, 2.2), (9.0, -1.0, 2.0), 0.35, 0.35, "paint_red"))
    parts.append(cy(f, 0.35, 0.3, (9.1, -1.0, 2.0), "metal", verts=8))
    parts.append(bx(f, (0.3, 0.3, 1.9), (8.6, -1.0, 0.95), "metal", along="z"))
    # Wheels and axle.
    for y in (-4.2, 3.6):
        parts.append(cy(f, 1.4, 0.8, (0.4, y, 1.4), "tire", axis="y", verts=14))
        parts.append(cy(f, 0.75, 0.85, (0.4, y, 1.4), "paint_cream", axis="y", verts=12))
    parts.append(cy(f, 0.2, 7.8, (0.4, -0.3, 1.4), "metal", axis="y", verts=8))
    parts.append(bx(f, (1.0, 4.4, 0.6), (0.4, -1.8, 1.6), "paint_red", along="y"))
    # Bale chute off the back, a bale riding out on it.
    tilt = math.radians(8)
    cz0 = cz + 0.1
    cl = 5.2
    ex, ez = -4.0 - cl * math.cos(tilt), cz0 - cl * math.sin(tilt)
    for y in (cy0 - 1.7, cy0 + 1.7):
        parts.append(obox(f, (-4.0, y, cz0), (ex, y, ez), 0.2, 0.5, "metal"))
        parts.append(obox(f, (-4.0, y, cz0 + 0.5), (ex, y, ez + 0.5), 0.12, 0.12, "metal"))
        parts.append(obox(f, (ex + 0.3, y, ez), (ex + 0.8, y, 0.0), 0.2, 0.2, "metal"))
    for k in range(5):
        t = (k + 0.5) / 5
        parts.append(bx(f, (0.2, 3.4, 0.12), (-4.0 - cl * t * math.cos(tilt), cy0, cz0 - cl * t * math.sin(tilt)),
                        "metal", along="y", rnd=False))
    bc = 2.7
    parts += bale(f, (-4.0 - bc * math.cos(tilt) + 0.6 * math.sin(tilt), cy0, cz0 - bc * math.sin(tilt) + 0.08),
                  tilt=tilt)
    return parts


def hay_press(f):
    """Heavy screw press: stone base, oak posts and beam, iron screw with capstan bars,
    a strapped press box, and dense pressed blocks stacked beside it."""
    parts = []
    parts.append(bx(f, (7.4, 5.0, 1.0), (0, 0, 0.5), "stone", along="x"))
    for x in (-3.0, 3.0):
        parts.append(bx(f, (1.1, 1.3, 10.0), (x, 0, 5.0), "handle", along="z"))
        for side in (-1, 1):
            parts.append(obox(f, (x, side * 2.3, 1.0), (x, side * 0.5, 3.2), 0.5, 0.5, "handle"))
    parts.append(bx(f, (8.2, 1.6, 1.6), (0, 0, 10.4), "handle", along="x"))
    for x in (-3.0, 3.0):
        parts.append(bx(f, (1.3, 1.7, 0.3), (x, 0, 9.4), "metal", along="x"))
    # Screw, nut and capstan.
    parts.append(cy(f, 0.4, 5.6, (0, 0, 8.6), "metal", verts=10))
    for k in range(9):
        parts.append(cy(f, 0.5, 0.12, (0, 0, 6.6 + k * 0.5), "metal", verts=10, rnd=False))
    parts.append(cy(f, 0.9, 0.9, (0, 0, 11.6), "metal", verts=8))
    for a in (0, math.pi / 2):
        parts.append(obox(f, (2.4 * math.cos(a), 2.4 * math.sin(a), 11.6), (-2.4 * math.cos(a), -2.4 * math.sin(a), 11.6),
                          0.3, 0.3, "handle"))
    # Platen and press box.
    parts.append(bx(f, (4.4, 3.6, 0.5), (0, 0, 6.2), "metal", along="x"))
    parts.append(bx(f, (4.0, 3.2, 0.5), (0, 0, 5.7), "handle", along="x"))
    for side in (-1, 1):
        parts.append(bx(f, (4.4, 0.3, 3.2), (0, side * 1.95, 2.6), "handle", along="x"))
        parts.append(bx(f, (0.3, 3.6, 3.2), (side * 2.05, 0, 2.6), "handle", along="y"))
    for z in (1.4, 3.8):
        parts.append(bx(f, (4.6, 0.12, 0.3), (0, -2.12, z), "metal", along="x"))
        parts.append(bx(f, (4.6, 0.12, 0.3), (0, 2.12, z), "metal", along="x"))
    parts.append(bx(f, (3.8, 3.4, 4.4), (0, 0, 3.25), "hay"))
    # Pressed blocks beside the press.
    for (x, y, z) in ((5.2, -1.4, 0.0), (5.2, 0.9, 0.0), (5.2, -0.25, 1.6)):
        parts.append(bx(f, (2.0, 2.1, 1.55), (x, y, z + 0.78), "hay", along="x"))
        for dx in (-0.5, 0.5):
            parts.append(bx(f, (0.12, 2.18, 1.62), (x + dx, y, z + 0.78), "metal", along="z", rnd=False))
    return parts


def alloy_mixer(f):
    """Needle Forge alloy mixer: stone furnace, iron crucible of molten alloy, a geared stirring paddle
    on a frame, bellows, chimney and an ingot mould."""
    parts = []
    parts.append(cy(f, 2.6, 3.2, (0, 0, 1.6), "stone", verts=10))
    for z in (0.8, 2.2):
        parts.append(cy(f, 2.68, 0.25, (0, 0, z), "metal", verts=10, rnd=False))
    parts.append(bx(f, (1.6, 0.4, 1.2), (0, -2.45, 1.2), "tire"))
    parts.append(bx(f, (1.9, 0.3, 0.2), (0, -2.55, 1.9), "metal", along="x"))
    # Crucible.
    parts.append(cone(f, 1.4, 1.9, 2.2, (0, 0, 4.3), "metal", verts=14))
    parts.append(arc_slab(f, (0, 0), 1.7, 2.05, 0, 360, 5.2, 5.55, "metal", n=14))
    parts.append(cy(f, 1.75, 0.1, (0, 0, 5.4), "paint_yellow", verts=14, rnd=False))
    parts.append(extrude(f, [(1.6, -0.5), (2.6, -0.2), (2.6, 0.2), (1.6, 0.5)], "xy", 5.1, 5.45, "metal"))
    for side in (-1, 1):
        parts.append(cy(f, 0.25, 0.6, (0, side * 2.2, 4.6), "metal", axis="y", verts=8))
    # Frame and stirring paddle.
    for x in (-3.0, 3.0):
        for y in (-2.2, 2.2):
            parts.append(obox(f, (x, y, 0), (x, 0, 8.4), 0.45, 0.45, "handle"))
    parts.append(bx(f, (6.6, 0.6, 0.6), (0, 0, 8.6), "handle", along="x"))
    parts.append(cy(f, 0.18, 4.5, (0, 0, 6.6), "metal", verts=8))
    parts.append(bx(f, (1.6, 0.2, 0.6), (0, 0, 4.7), "metal", along="x"))
    parts.append(cy(f, 0.9, 0.25, (0, 0, 9.05), "metal", verts=12))
    for k in range(10):
        a = 2 * math.pi * k / 10
        parts.append(bx(f, (0.25, 0.25, 0.25), (0.95 * math.cos(a), 0.95 * math.sin(a), 9.05), "metal",
                        rot=(0, 0, a), rnd=False))
    parts.append(cy(f, 0.5, 0.25, (1.35, 0, 9.6), "metal", axis="x", verts=10))
    parts.append(cy(f, 0.1, 2.6, (2.4, 0, 9.6), "metal", axis="x", verts=6))
    parts += handwheel(f, (3.5, 0, 9.6), 0.8, "x", spokes=2)
    # Bellows on the left.
    by = -1.6
    parts.append(extrude(f, [(-5.4, 1.2), (-3.4, 1.0), (-3.4, 1.4), (-5.4, 2.4)], "xz", by - 0.8, by + 0.8, "cloth"))
    parts.append(obox(f, (-5.4, by, 1.15), (-3.3, by, 0.95), 1.7, 0.15, "handle"))
    parts.append(obox(f, (-5.4, by, 2.45), (-3.3, by, 1.45), 1.7, 0.15, "handle"))
    parts.append(obox(f, (-5.4, by, 2.5), (-6.4, by, 2.9), 0.2, 0.2, "handle"))
    parts.append(bx(f, (2.0, 1.2, 0.95), (-4.4, by, 0.48), "handle", along="x"))
    parts.append(obox(f, (-3.3, by, 1.2), (-2.2, by * 0.6, 1.4), 0.3, 0.3, "metal"))
    # Chimney at the back.
    parts.append(cy(f, 0.45, 9.0, (1.6, 1.6, 4.5), "metal", verts=10))
    parts.append(cone(f, 0.5, 0.75, 0.6, (1.6, 1.6, 9.2), "metal", verts=10))
    # Ingot mould with fresh ingots.
    parts.append(bx(f, (3.0, 1.4, 0.5), (2.6, -3.4, 0.25), "metal", along="x"))
    for k in range(3):
        parts.append(frustum(f, (1.7 + k * 0.9, -3.4), 0.5, (0.7, 0.9), 0.8, (0.5, 0.7), "metal", along="x"))
    return parts


# ---------------------------------------------------------------- consumables

def sorter_boost_oil(f):
    """A small rusty oil can (about 1.4 studs tall) with a long spout and a faded red label."""
    parts = []
    parts.append(cy(f, 0.42, 0.7, (0, 0, 0.36), "metal", verts=12))
    parts.append(cy(f, 0.44, 0.05, (0, 0, 0.03), "metal", verts=12, rnd=False))
    parts.append(cy(f, 0.43, 0.3, (0, 0, 0.4), "paint_red", verts=12, rnd=False))
    parts.append(cone(f, 0.42, 0.12, 0.35, (0, 0, 0.88), "metal", verts=12))
    parts.append(obox(f, (0.05, 0, 0.98), (0.8, 0, 1.38), 0.06, 0.06, "metal", rnd=False))
    parts.append(cy(f, 0.08, 0.12, (0, 0, 1.1), "metal", verts=8, rnd=False))
    for p0, p1 in (((-0.35, 0, 0.62), (-0.7, 0, 0.62)), ((-0.7, 0, 0.62), (-0.7, 0, 0.18)),
                   ((-0.7, 0, 0.18), (-0.35, 0, 0.18))):
        parts.append(obox(f, p0, p1, 0.1, 0.1, "metal", rnd=False))
    return parts


# ---------------------------------------------------------------- mythic

def alien_collector(f):
    """Mythic tier 6 sorter: a riveted iron saucer on three crooked legs over two belt tiles,
    glowing rim lights, a glass dome with a glowing core, a beam emitter and a glowing collection tank."""
    parts = belt_run(f, -TILE, TILE)
    zc = 9.0
    # Saucer: two flattened cones, stretched along the belt.
    sx = 1.6
    lo = cone(f, 1.6, 3.4, 1.2, (0, 0, zc - 0.6), "metal", verts=16)
    hi = cone(f, 3.4, 2.0, 0.9, (0, 0, zc + 0.45), "metal", verts=16)
    for o in (lo, hi):
        bake(o).data.transform(Matrix.Diagonal((sx, 1, 1, 1)))
    parts += [lo, hi]
    rim = cy(f, 3.5, 0.25, (0, 0, zc), "glow", verts=16, rnd=False)
    bake(rim).data.transform(Matrix.Diagonal((sx, 1, 1, 1)))
    parts.append(rim)
    for k in range(8):
        a = 2 * math.pi * k / 8
        parts.append(bx(f, (0.9, 0.5, 0.35), (3.25 * sx * math.cos(a), 3.25 * math.sin(a), zc - 0.15), "paint_green",
                        rot=(0, 0, a), rnd=False))
    # Dome.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=1.8 * S, location=(0, 0, (zc + 0.9) * S))
    dome = bpy.context.active_object
    bake(dome)
    for v in dome.data.vertices:
        v.co.z = (zc + 0.9) * S + (v.co.z - (zc + 0.9) * S) * 0.8
    parts.append(part(f, dome, "glass", "z", rnd=False))
    parts.append(cy(f, 0.7, 1.2, (0, 0, zc + 1.6), "glow", verts=10))
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        parts.append(obox(f, (1.9 * math.cos(a), 1.9 * math.sin(a), zc + 0.9), (0, 0, zc + 2.4), 0.15, 0.15, "metal",
                          rnd=False))
    # Antennae with glowing tips.
    for x in (-3.0, 3.0):
        parts.append(cy(f, 0.1, 2.4, (x, 0.8, zc + 1.6), "metal", verts=6))
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=5, radius=0.3 * S, location=(x * S, 0.8 * S,
                                                                                                (zc + 2.9) * S))
        parts.append(part(f, bpy.context.active_object, "glow", "z", rnd=False))
    # Beam emitter pointing down at the belt.
    parts.append(cone(f, 0.5, 1.4, 1.4, (0, 0, zc - 1.8), "metal", verts=12))
    parts.append(cy(f, 0.7, 0.15, (0, 0, zc - 2.5), "glow", verts=12, rnd=False))
    for k in range(3):
        parts.append(cy(f, 0.55 - k * 0.12, 0.08, (0, 0, BELT_Z + 1.0 + k * 1.1), "glow", verts=12, rnd=False))
    # Three crooked legs.
    for (x, y) in ((-5.6, -2.6), (-5.6, 2.6), (5.6, 0.0)):
        knee = (x * 0.85, y * 1.15 if y else 0, 5.0)
        top = (x * 0.55, y * 0.55, zc - 0.5)
        parts.append(obox(f, (x, y, 0.2), knee, 0.45, 0.45, "metal"))
        parts.append(obox(f, knee, top, 0.4, 0.4, "metal"))
        parts.append(cy(f, 0.35, 0.5, knee, "glow", verts=8, rnd=False))
        parts.append(cy(f, 0.6, 0.25, (x, y, 0.12), "metal", verts=8))
    # Collection tank at the front with a glowing window.
    parts.append(cy(f, 1.0, 2.6, (2.8, -4.4, 1.3), "metal", verts=12))
    parts.append(cy(f, 1.05, 0.2, (2.8, -4.4, 0.5), "paint_green", verts=12, rnd=False))
    parts.append(cy(f, 1.05, 0.2, (2.8, -4.4, 2.2), "paint_green", verts=12, rnd=False))
    parts.append(bx(f, (0.6, 0.2, 1.1), (2.8, -5.4, 1.35), "glow", rnd=False))
    parts.append(cone(f, 1.0, 0.4, 0.6, (2.8, -4.4, 2.9), "metal", verts=12))
    parts.append(obox(f, (2.8, -4.4, 3.2), (2.8, -2.0, 6.0), 0.35, 0.35, "metal"))
    parts.append(obox(f, (2.8, -2.0, 6.0), (2.0, -1.2, zc - 0.6), 0.35, 0.35, "metal"))
    return parts


def starbeam_collector(f):
    """Starbeam collector (Conveyor's Starbeam.luau): an iron arch over one belt tile that catches a
    falling star and drops a Star hay bale onto the belt every 10 minutes. A glowing five-point star
    (tagged Star, spins about the vertical axis) hangs in an iron ring at the top, glow rings run down
    the beam to a bale-sized cradle mouth just above the belt."""
    parts = belt_run(f, -TILE / 2, TILE / 2)
    top = 19.4
    # Two curved iron legs on each side of the belt meet in a ring at the top.
    for y in (-1, 1):
        for x in (-1, 1):
            foot = (x * 2.45, y * 2.45, 0.2)
            knee = (x * 1.9, y * 2.6, 9.5)
            crown = (x * 0.9, y * 1.8, top - 2.6)
            parts.append(obox(f, foot, knee, 0.5, 0.5, "metal"))
            parts.append(obox(f, knee, crown, 0.42, 0.42, "metal"))
            parts.append(cy(f, 0.4, 0.3, (foot[0], foot[1], 0.15), "metal", verts=8))
            parts.append(cy(f, 0.28, 0.28, knee, "glow", verts=6, rnd=False))
    # Crown ring (vertical, across the belt) around the star.
    n = 12
    rr = 2.4
    for i in range(n):
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        parts.append(obox(f, (0, rr * math.cos(a0 - 0.04), top + rr * math.sin(a0 - 0.04)),
                          (0, rr * math.cos(a1 + 0.04), top + rr * math.sin(a1 + 0.04)), 0.4, 0.4, "metal", rnd=False))
    parts.append(cy(f, 1.1, 1.0, (0, 0, top - 2.9), "metal", verts=10))
    # The star: a thick five-point outline standing in the ring.
    pts = []
    for k in range(10):
        a = math.pi / 2 + k * math.pi / 5
        r = 1.8 if k % 2 == 0 else 0.75
        pts.append((r * math.cos(a), top + r * math.sin(a)))
    star = extrude(f, pts, "yz", -0.35, 0.35, "glow", rnd=False)
    parts += tag([star], "Star")
    # Beam: stacked glow rings from the crown down to the cradle.
    for k in range(6):
        z = top - 4.2 - k * 1.7
        parts.append(cy(f, 1.3 - k * 0.06, 0.12, (0, 0, z), "glow", verts=12, rnd=False))
    # Cradle mouth: an open iron frame the bale drops through, bale-sized, its bottom 1 stud above the belt.
    z0 = BELT_Z + 1.0
    for y in (-1.9, 1.9):
        parts.append(bx(f, (5.4, 0.3, 0.3), (0, y, z0 + 3.0), "metal", rnd=False))
        parts.append(bx(f, (5.4, 0.3, 0.3), (0, y, z0), "metal", rnd=False))
    for x in (-2.6, 2.6):
        parts.append(bx(f, (0.3, 4.1, 0.3), (x, 0, z0 + 3.0), "metal", rnd=False))
        for y in (-1.9, 1.9):
            parts.append(bx(f, (0.3, 0.3, 3.0), (x, y, z0 + 1.5), "metal", rnd=False))
    for y in (-1.9, 1.9):
        for x in (-2.6, 2.6):
            parts.append(obox(f, (x, y, z0 + 3.0), (x * 0.4, y * 0.95, top - 4.2), 0.25, 0.25, "metal", rnd=False))
    # Little star studs on the legs' feet so it reads as alien from far off.
    for x, y in ((-2.45, -2.45), (2.45, -2.45), (-2.45, 2.45), (2.45, 2.45)):
        parts.append(cy(f, 0.3, 0.2, (x, y, 0.4), "glow", verts=5, rnd=False))
    return parts


# ---------------------------------------------------------------- region machines (Treat.luau)
# Each sits over two belt tiles (12 x 6, belt along x, top 3.5) and leaves 5 studs of clear height over
# the belt so a bale rides through.

def thawing_shed(f):
    """Thawing shed (Frozen hay, Snow Peak): a plank shed over two belt tiles (12 x 7.4, 14 tall with the
    vent) with a tin gable roof, ice-blue icicles hanging all along both eaves, one ice-blue painted trim
    band on the stove side, a cast-iron stove with a big glowing window against that wall, a stovepipe
    and a spinning roof ventilator (Vent)."""
    parts = belt_run(f, -TILE, TILE)
    top = 10.0
    for y in (-2.75, 2.75):
        parts.append(bx(f, (12.0, 0.4, top), (0, y, top / 2), "handle", along="x"))
        for x in (-5.75, 0, 5.75):
            parts.append(bx(f, (0.5, 0.5, top), (x, y, top / 2), "handle", along="z", rnd=False))
    # The region accent: one ice-blue painted trim band high on the stove (-y) side.
    parts.append(bx(f, (11.0, 0.15, 0.8), (0, -3.02, top - 1.0), "paint_blue", along="x", rnd=False))
    # Gable ends above the bale door (clear to 9.0), then the roof, overhanging the walls.
    for x in (-5.9, 5.9):
        parts.append(bx(f, (0.3, 5.6, 1.0), (x, 0, top - 0.5), "handle", along="y", rnd=False))
        parts.append(extrude(f, [(-2.8, top), (2.8, top), (0, top + 2.4)], "yz", x - 0.15, x + 0.15, "handle",
                             rnd=False))
    a = math.atan2(2.4, 2.8)
    ls = 4.6
    for side in (-1, 1):
        parts.append(bx(f, (12.4, ls, 0.2), (0, side * ls / 2 * math.cos(a), top + 2.5 - ls / 2 * math.sin(a)), "metal",
                        rot=(-side * a, 0, 0), rnd=False))
    # Icicles along both eaves: long and short, ice blue.
    ey, ez = ls * math.cos(a) - 0.15, top + 2.4 - ls * math.sin(a) + 0.05
    for side in (-1, 1):
        for i in range(11):
            x = -5.6 + i * 1.12 + (0.25 if side > 0 else 0.0)
            ln = (1.5, 0.8, 1.15, 0.6, 1.3)[(i + (2 if side > 0 else 0)) % 5]
            parts.append(cone(f, 0.0, 0.2, ln, (x, side * ey, ez - ln / 2), "paint_blue", verts=5, rnd=False))
    # Cast-iron stove against the -y wall with a big glowing window and an ash slot.
    parts.append(bx(f, (3.0, 0.9, 2.6), (-2.5, -3.4, 1.5), "metal", along="x", rnd=False))
    parts.append(bx(f, (3.3, 1.1, 0.25), (-2.5, -3.4, 2.9), "metal", along="x", rnd=False))
    parts.append(bx(f, (2.2, 0.08, 1.3), (-2.5, -3.88, 1.9), "lava", rnd=False))
    parts.append(bx(f, (2.2, 0.08, 0.25), (-2.5, -3.88, 0.75), "lava", rnd=False))
    for z in (1.15, 2.6):
        parts.append(bx(f, (2.6, 0.12, 0.22), (-2.5, -3.92, z), "metal", rnd=False))
    for x in (-3.7, -2.5, -1.3):
        parts.append(bx(f, (0.18, 0.12, 1.6), (x, -3.92, 1.9), "metal", rnd=False))
    # Stovepipe from the stove up the wall and out through the eave.
    parts.append(cy(f, 0.35, top + 1.0, (-2.5, -3.5, (3.0 + top + 4.0) / 2), "metal", verts=8))
    parts.append(cone(f, 0.55, 0.2, 0.5, (-2.5, -3.5, top + 4.3), "metal", verts=8))
    parts.append(bx(f, (0.3, 0.7, 0.3), (-2.5, -3.2, 7.0), "metal", rnd=False))
    # Ridge ventilator: a drum of vanes that spins in the steam.
    vent = [cy(f, 0.9, 1.2, (2.5, 0, top + 3.0), "metal", verts=10)]
    for k in range(6):
        a2 = k * math.pi / 3
        vent.append(bx(f, (0.6, 0.12, 1.2), (2.5 + 0.95 * math.cos(a2), 0.95 * math.sin(a2), top + 3.0), "metal",
                       rot=(0, 0, a2 + 0.6), rnd=False))
    vent.append(cone(f, 1.0, 0.2, 0.5, (2.5, 0, top + 3.85), "metal", verts=10))
    parts += tag(vent, "Vent")
    parts.append(cy(f, 0.5, 1.0, (2.5, 0, top + 2.0), "metal", verts=8))
    return parts


def drying_rack(f):
    """Drying rack (Bog reed): an open timber frame over two belt tiles with reed bundles hung on
    poles to dry, and a big wooden paddle fan under the top beam (Fan, spins about the vertical)."""
    parts = belt_run(f, -TILE, TILE)
    top = 10.5
    for x in (-5.7, 5.7):
        for y in (-2.7, 2.7):
            parts.append(bx(f, (0.6, 0.6, top), (x, y, top / 2), "handle", along="z", rnd=False))
            parts.append(obox(f, (x, y, top - 2.0), (x * 0.75, y, top - 0.3), 0.3, 0.3, "handle", rnd=False))
        parts.append(bx(f, (0.6, 6.0, 0.6), (x, 0, top - 0.3), "handle", along="y", rnd=False))
    for y in (-2.7, 2.7):
        parts.append(bx(f, (12.0, 0.6, 0.6), (0, y, top - 0.3), "handle", along="x", rnd=False))
    parts.append(bx(f, (12.0, 0.5, 0.5), (0, 0, top - 0.3), "handle", along="x", rnd=False))
    # Hanging poles along the sides, clear of the bale lane, with reed bundles hung over them.
    for y in (-2.3, 2.3):
        parts.append(cy(f, 0.14, 11.4, (0, y, 8.6), "metal", axis="x", verts=6))
        for i in range(6):
            x = -4.6 + i * 1.84
            parts.append(frustum(f, (x, y), 5.6, (0.5, 0.35), 8.6, (0.9, 0.5), "hay"))
            parts.append(bx(f, (0.95, 0.55, 0.15), (x, y, 8.0), "metal", rnd=False))
    # Paddle fan under the center beam.
    fan = [cy(f, 0.35, 0.6, (0, 0, top - 1.2), "handle", verts=8)]
    for k in range(4):
        a = k * math.pi / 2
        fan.append(bx(f, (2.4, 0.6, 0.1), (1.5 * math.cos(a), 1.5 * math.sin(a), top - 1.3), "handle",
                      rot=(0.2, 0, a), rnd=False))
    parts += tag(fan, "Fan")
    parts.append(cy(f, 0.1, 0.9, (0, 0, top - 0.6), "metal", verts=6))
    return parts


def ash_sifter(f):
    """Ash sifter (Ashen hay, Volcano): a charcoal-black iron hood over two belt tiles with a shaking sieve
    screen (Shaker), a rotary brush across the belt (Drum) knocking the ash out, an open hopper on the
    roof full of glowing embers and an ash tray of embers and grey ash under the belt."""
    parts = belt_run(f, -TILE, TILE)
    top = 9.5
    # Charcoal hood: side plates on iron posts, a flat top, an open ember hopper and a short flue.
    for y in (-2.75, 2.75):
        parts.append(bx(f, (11.0, 0.25, top - BELT_Z), (0, y, (top + BELT_Z) / 2), "tire", rnd=False))
        for x in (-5.4, -1.8, 1.8, 5.4):
            parts.append(bx(f, (0.4, 0.4, top), (x, y * 1.03, top / 2), "metal", along="z", rnd=False))
        for z in (BELT_Z + 0.3, top - 0.3):
            parts.append(bx(f, (11.0, 0.12, 0.25), (0, y * 1.06, z), "metal", along="x", rnd=False))
    parts.append(bx(f, (11.6, 6.0, 0.3), (0, 0, top + 0.15), "tire", rnd=False))
    hc = (-1.5, 0.0)
    parts.append(frustum(f, hc, top + 0.3, (2.4, 2.0), top + 2.4, (4.6, 4.0), "tire", wall=0.25))
    parts.append(frustum(f, hc, top + 0.3, (2.3, 1.9), top + 2.1, (4.3, 3.7), "lava"))
    for y in (-2.05, 2.05):
        parts.append(bx(f, (4.9, 0.2, 0.3), (hc[0], y, top + 2.3), "metal", along="x", rnd=False))
    for x, y in ((-2.4, 0.6), (-0.6, -0.8), (-1.3, 0.9)):
        parts.append(frustum(f, (x, y), top + 2.0, (1.3, 1.0), top + 2.4, (0.6, 0.5), "metal"))
    parts.append(cy(f, 0.5, 2.4, (3.4, 1.2, top + 1.5), "tire", verts=8))
    parts.append(cy(f, 0.6, 0.25, (3.4, 1.2, top + 2.75), "metal", verts=8, rnd=False))
    # Sieve screen above the lane: a frame with slats, hung on four rods so it can shake.
    sieve = []
    for y in (-2.4, 2.4):
        sieve.append(bx(f, (8.0, 0.25, 0.4), (-1.5, y, 9.0), "metal", rnd=False))
    for x in (-5.5, 2.5):
        sieve.append(bx(f, (0.25, 5.0, 0.4), (x, 0, 9.0), "metal", rnd=False))
    for i in range(9):
        sieve.append(bx(f, (0.12, 4.8, 0.08), (-5.0 + i * 0.85, 0, 8.9), "metal", rnd=False))
    parts += tag(sieve, "Shaker")
    # Rotary brush across the belt at the out end, bristles as short spokes.
    drum = [cy(f, 0.45, 5.2, (3.8, 0, BELT_Z + 1.9), "metal", axis="y", verts=8)]
    for k in range(8):
        a = k * math.pi / 4
        drum.append(bx(f, (0.12, 4.8, 0.9), (3.8 + 0.7 * math.cos(a), 0, BELT_Z + 1.9 + 0.7 * math.sin(a)), "metal",
                       rot=(0, -a, 0), rnd=False))
    parts += tag(drum, "Drum")
    for y in (-2.75, 2.75):
        parts.append(cy(f, 0.3, 0.3, (3.8, y * 1.05, BELT_Z + 1.9), "metal", axis="y", verts=8))
    # Ash tray under the belt, wider than the lane so its glowing embers and grey ash show at the sides.
    parts.append(frustum(f, (0, 0), 0.0, (10.0, 6.6), 1.3, (10.8, 7.4), "tire", wall=0.2, closed=True))
    parts.append(bx(f, (10.4, 7.0, 0.1), (0, 0, 0.95), "lava", rnd=False))
    for x, y in ((-4.2, 2.9), (-2.0, -3.0), (0.6, 3.0), (2.8, -2.9), (4.3, 2.8), (-4.4, -2.8)):
        parts.append(frustum(f, (x, y), 0.95, (1.5, 0.9), 1.45, (0.7, 0.4), "metal"))
    return parts


PROPS = {
    "conveyor_straight": low_poly(conveyor_straight),
    "conveyor_corner": low_poly(conveyor_corner),
    "conveyor_ramp": low_poly(conveyor_ramp),
    "splitter": low_poly(splitter),
    "merger": low_poly(merger),
    "hopper_feeder": hopper_feeder,
    "hand_sieve": low_poly(hand_sieve),
    "shaker_table": low_poly(shaker_table),
    "conveyor_sorter": conveyor_sorter,
    "magnet_drum": low_poly(magnet_drum),
    "hand_sieve_table": hand_sieve_table,
    "shaker_table_small": shaker_table_small,
    "magnet_drum_small": magnet_drum_small,
    "optical_sorter": optical_sorter,
    "needle_type_splitter": needle_type_splitter,
    "needle_bundler": needle_bundler,
    "needle_polisher": needle_polisher,
    "hay_baler": hay_baler,
    "hay_press": hay_press,
    "alloy_mixer": alloy_mixer,
    "sorter_boost_oil": sorter_boost_oil,
    "alien_collector": alien_collector,
    "starbeam_collector": low_poly(starbeam_collector),
    "thawing_shed": low_poly(thawing_shed),
    "drying_rack": low_poly(drying_rack),
    "ash_sifter": low_poly(ash_sifter),
}


if __name__ == "__main__":
    raise SystemExit("machines.py only provides shapes; build them with props/rustic_props.py --category machines")

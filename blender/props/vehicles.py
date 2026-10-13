"""Vehicles in the house style (LT2 shapes, Rustic finish): hand carriers, trucks, boats and trailers.

Every size is in studs (1 stud = 0.28 m). Builders face -y, wheels on the ground at z=0; the export
turns them to face +y (glTF/Roblox -Z) and splits wheels, tailgates and couplers into their own
meshes (lib/rig.py).
The medium_trailer and the truck cabs follow the game's Trailer.luau / BaseLine.luau parts.

Run through rustic_props.py:
  python blender/props/rustic_props.py --out <dir> --category vehicles
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
import style  # noqa: E402
from rig import tag, wheel_uid  # noqa: E402
from style import box, cap_uv, cyl  # noqa: E402,F401

STUD = 0.28
PI = math.pi


def s(*v):
    """Studs to meters."""
    return tuple(x * STUD for x in v)


# ---------------------------------------------------------------- part helpers (all in studs)

def B(f, kind, size, loc, along="x", rot=(0, 0, 0), rounded=None):
    """A box part. Only chunky boxes get the bevel (keeps the triangle count down)."""
    if rounded is None:
        rounded = min(size) >= 0.45
    return f.apply(f.shape(box(s(*size), s(*loc), rot=rot), round_edges=rounded), kind, along=along)


def C(f, kind, r, depth, loc, axis="z", verts=12, rounded=None):
    """A cylinder part along an axis. Only big cylinders get the bevel."""
    if rounded is None:
        rounded = r >= 0.9 and depth >= 0.45
    rot = {"x": (0, PI / 2, 0), "y": (PI / 2, 0, 0), "z": (0, 0, 0)}[axis]
    o = cyl(r * STUD, depth * STUD, s(*loc), verts=verts, rot=rot)
    return f.apply(f.shape(o, round_edges=rounded), kind, along=axis)


def beam(f, kind, p0, p1, t, along=None):
    """A square bar from p0 to p1 (studs)."""
    a, b = Vector(s(*p0)), Vector(s(*p1))
    d = b - a
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler()
    o = box((t * STUD, t * STUD, d.length), (a + b) / 2, rot=tuple(rot))
    axis = along or "xyz"[max(range(3), key=lambda i: abs(d[i]))]
    return f.apply(f.shape(o), kind, along=axis)


def mesh_obj(verts, faces, name="part"):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    return o


def solidify(o, thickness):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    bpy.context.view_layer.objects.active = o
    m = o.modifiers.new("solid", "SOLIDIFY")
    m.thickness = thickness
    m.offset = 0
    bpy.ops.object.modifier_apply(modifier=m.name)
    return o


def place(objs, loc, rz=0.0):
    """Move parts built around the origin: rotate about z, then translate (studs)."""
    M = Matrix.Translation(Vector(s(*loc))) @ Matrix.Rotation(rz, 4, "Z")
    for o in objs:
        o.data.transform(M @ Matrix.LocRotScale(o.location, o.rotation_euler, o.scale))
        o.location = (0, 0, 0)
        o.rotation_euler = (0, 0, 0)
        o.scale = (1, 1, 1)
    return objs


def tire(f, x, y, r, w, hub="metal", verts=20, treads=16):
    """Rubber tire with a stepped sidewall, a dished rim, a hub cap and five lug nuts; axle along x,
    sitting on the ground. Mid detail (2026-10-13): 16 sides instead of 12."""
    side = 1 if x >= 0 else -1
    parts = [C(f, "tire", r - 0.06, w, (x, y, r), axis="x", verts=verts)]
    parts.append(C(f, "tire", r * 0.84, w + 0.08, (x, y, r), axis="x", verts=verts, rounded=False))  # sidewall step
    for i in range(treads):                                                                    # tread blocks
        a = 2 * PI * i / treads
        parts.append(B(f, "tire", (w * 0.8, 2 * PI * r / treads * 0.55, 0.12), (x, y + (r - 0.04) * math.cos(a),
                       r + (r - 0.04) * math.sin(a)), along="x", rot=(a - PI / 2, 0, 0), rounded=False))
    parts.append(C(f, hub, r * 0.6, w + 0.14, (x + side * 0.02, y, r), axis="x", verts=verts, rounded=False))
    parts.append(C(f, hub, r * 0.46, w + 0.2, (x + side * 0.03, y, r), axis="x", verts=verts, rounded=False))
    parts.append(C(f, "metal", r * 0.2, w + 0.34, (x + side * 0.05, y, r), axis="x", verts=8, rounded=False))
    for i in range(5):
        a = 2 * PI * i / 5 + PI / 2
        parts.append(C(f, "metal", 0.07, w + 0.28, (x + side * 0.04, y + r * 0.33 * math.cos(a), r + r * 0.33 * math.sin(a)),
                       axis="x", verts=6, rounded=False))
    return tag(parts, "wheel", wheel_uid(x, y))


def fender_arch(f, kind, x, y, r, w, a0=0.25, a1=PI - 0.25, n=6, t=0.3):
    """A rounded fender: n short boxes following an arc of radius r over a wheel at (x, y), axle along x."""
    parts = []
    for i in range(n):
        a = a0 + (a1 - a0) * (i + 0.5) / n
        seg = 2 * r * math.sin((a1 - a0) / n / 2) + 0.08
        parts.append(B(f, kind, (w, seg, t), (x, y + r * math.cos(a), r * math.sin(a)), along="y",
                       rot=(a - PI / 2, 0, 0), rounded=False))
    return parts


def cab_door(f, paint, x, half_w, y0, y1, z0, z1, zw, flip=True, upper_w=None):
    """A hinged cab door on side x (+1 / -1): a 0.25-thick panel with a window frame cut through, a crease
    line and a handle (one material), plus its window glass as a separate mesh in the same plane, so it
    shares the door's front hinge line. Builders face -y and the exporter turns the truck 180 degrees, so
    the builder's +x door ends up on the driver's left: Door_L / Glass_L at -X in the .glb."""
    sx = x * (half_w + 0.02)
    su = x * ((upper_w or half_w) + 0.02)                                     # window frame (narrower greenhouse)
    d = []
    d.append(B(f, paint, (0.25, y1 - y0, zw - z0), (sx, (y0 + y1) / 2, (z0 + zw) / 2), along="y", rounded=False))
    for yy in (y0 + 0.11, y1 - 0.11):                                                         # window posts
        d.append(B(f, paint, (0.25, 0.22, z1 - zw), (su, yy, (zw + z1) / 2), along="z", rounded=False))
    d.append(B(f, paint, (0.25, y1 - y0, 0.2), (su, (y0 + y1) / 2, z1 - 0.1), along="y", rounded=False))
    d.append(B(f, paint, (0.06, y1 - y0 - 0.3, 0.08), (sx + x * 0.15, (y0 + y1) / 2, z0 + (zw - z0) * 0.3),
               along="y", rounded=False))                                                      # crease line
    d.append(B(f, paint, (0.12, 0.5, 0.12), (sx + x * 0.17, y1 - 0.5, zw - 0.35), along="y", rounded=False))  # handle
    d.append(B(f, paint, (0.08, 0.2, 0.2), (sx + x * 0.15, y1 - 0.75, zw - 0.35), rounded=False))
    left = x > 0 if flip else x < 0
    glass = B(f, "glass", (0.06, y1 - y0, z1 - zw - 0.2), (su, (y0 + y1) / 2, (zw + z1 - 0.2) / 2), along="y",
              rounded=False)
    return tag(d, "Door_L" if left else "Door_R") + tag([glass], "Glass_L" if left else "Glass_R")


def ring(r_out, r_in, width, n=14):
    """A ring (wheel rim) around the x axis, centered at the origin, in meters."""
    verts, faces = [], []
    for i in range(n):
        a = 2 * PI * i / n
        c, sn = math.cos(a), math.sin(a)
        for r in (r_out, r_in):
            for x in (-width / 2, width / 2):
                verts.append((x, r * c, r * sn))
    for i in range(n):
        j = (i + 1) % n
        o0, o1, i0, i1 = 4 * i, 4 * i + 1, 4 * i + 2, 4 * i + 3
        p0, p1, q0, q1 = 4 * j, 4 * j + 1, 4 * j + 2, 4 * j + 3
        faces += [(o0, p0, p1, o1), (i1, q1, q0, i0), (o0, i0, q0, p0), (o1, p1, q1, i1)]
    o = mesh_obj(verts, faces, "ring")
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    return o


def spoked_wheel(f, x, y, r, w, spokes=6):
    """Wooden wagon wheel: iron tyre, wooden felloe, spokes and a hub. Axle along x."""
    tyre = ring(r * STUD, r * 0.88 * STUD, w * STUD, n=18)
    felloe = ring(r * 0.9 * STUD, r * 0.74 * STUD, w * 0.9 * STUD, n=18)
    parts = [f.apply(f.shape(tyre, round_edges=False), "metal"),
             f.apply(f.shape(felloe, round_edges=False), "handle", along="y")]
    for i in range(spokes):
        a = PI * i / spokes
        parts.append(f.apply(f.shape(box(s(w * 0.4, 0.22, r * 1.6), (0, 0, 0), rot=(a, 0, 0)), round_edges=False),
                             "handle", along="z"))
    parts.append(f.apply(f.shape(cyl(r * 0.2 * STUD, (w + 0.3) * STUD, (0, 0, 0), verts=8, rot=(0, PI / 2, 0)),
                                 round_edges=False),
                         "handle", along="x"))
    parts.append(f.apply(cyl(r * 0.1 * STUD, (w + 0.5) * STUD, (0, 0, 0), verts=6, rot=(0, PI / 2, 0)), "metal"))
    return tag(place(parts, (x, y, r)), "wheel", wheel_uid(x, y))


def open_tray(f, kind, w, d, h, z0, wall=0.25, flare=1.0, along="y"):
    """Open-topped box (floor + 4 walls) centered on x=y=0 with its floor at z0 (studs)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.delete(bm, geom=[fc for fc in bm.faces if fc.normal.z > 0.9], context="FACES")
    for v in bm.verts:
        v.co.x *= w
        v.co.y *= d
        v.co.z = (v.co.z + 0.5) * h + z0
        if v.co.z > z0 + 0.01:
            v.co.x *= flare
            v.co.y *= flare
        v.co *= STUD
    me = bpy.data.meshes.new("tray")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("tray", me)
    bpy.context.collection.objects.link(o)
    solidify(o, wall * STUD)
    return f.apply(f.shape(o, round_edges=False), kind, along=along)


# ---------------------------------------------------------------- carriers

def two_wheel_handcart(f):
    """Hand-pulled cart for 14 scoops: wooden box on two big spoked wheels, long pull shafts."""
    parts = []
    bz = 1.8
    parts.append(open_tray(f, "handle", 3.8, 4.4, 1.7, bz, wall=0.22))
    # Plank lines on the sides.
    for x in (-1, 1):
        parts.append(B(f, "handle", (0.12, 4.5, 0.18), (x * 1.97, 0, bz + 0.85), along="y"))
    # Hay heaped inside.
    heap = B(f, "hay", (3.3, 3.9, 1.4), (0, 0, bz + 1.1), along="y")
    parts += tag([heap], "HayFill")
    # Under-frame, axle and wheels.
    for x in (-1.2, 1.2):
        parts.append(B(f, "handle", (0.35, 5.2, 0.35), (x, -0.3, bz - 0.15), along="y"))
    parts.append(C(f, "metal", 0.15, 5.4, (0, 0.4, 1.5), axis="x", verts=8))
    for x in (-2.35, 2.35):
        parts += spoked_wheel(f, x, 0.4, 1.5, 0.35)
    # Pull shafts with a crossbar, resting on a little prop leg.
    for x in (-1.2, 1.2):
        parts.append(beam(f, "handle", (x, -2.6, bz - 0.15), (x * 0.8, -7.0, 1.0), 0.3))
    parts.append(B(f, "handle", (2.4, 0.3, 0.3), (0, -6.8, 1.08)))
    parts.append(beam(f, "handle", (0, -2.8, bz - 0.25), (0, -3.0, 0.0), 0.3))
    parts.append(B(f, "handle", (2.2, 0.3, 0.3), (0, -2.8, bz - 0.25)))
    return parts


def pull_wagon(f):
    """Four-wheel pull wagon for 30 scoops: slatted bed, small wagon wheels, T pull handle."""
    parts = []
    bz, L, W = 1.7, 7.0, 4.0
    parts.append(B(f, "handle", (W, L, 0.3), (0, 0, bz + 0.15), along="y"))
    for x in (-1, 1):
        for i, z in enumerate((0.55, 1.15)):
            parts.append(B(f, "paint_red", (0.2, L, 0.45), (x * (W / 2 - 0.1), 0, bz + 0.3 + z), along="y"))
    for y in (-1, 1):
        for z in (0.55, 1.15):
            parts.append(B(f, "paint_red", (W - 0.4, 0.2, 0.45), (0, y * (L / 2 - 0.1), bz + 0.3 + z)))
    for x in (-1, 1):
        for y in (-1, 0, 1):
            parts.append(B(f, "metal", (0.25, 0.25, 1.7), (x * (W / 2 + 0.05), y * (L / 2 - 0.05), bz + 0.95),
                           along="z"))
    parts += tag([B(f, "hay", (W - 0.6, L - 0.6, 1.4), (0, 0, bz + 1.0), along="y")], "HayFill")
    # Frame, axles and wheels.
    parts.append(B(f, "metal", (0.4, L - 0.6, 0.35), (0, 0, bz - 0.15), along="y"))
    for y in (-2.4, 2.4):
        parts.append(B(f, "handle", (W - 0.4, 0.5, 0.45), (0, y, bz - 0.25)))
        parts.append(C(f, "metal", 0.12, W + 1.0, (0, y, 1.0), axis="x", verts=8))
        for x in (-1, 1):
            parts.append(B(f, "metal", (0.2, 0.2, 0.7), (x * 1.4, y, 1.3), along="z"))
        for x in (-2.35, 2.35):
            parts += spoked_wheel(f, x, y, 1.0, 0.35, spokes=5)
    # Pull handle from the front axle down to the ground with a T grip.
    parts.append(beam(f, "metal", (0, -2.4, 1.0), (0, -7.4, 0.25), 0.25))
    parts.append(C(f, "handle", 0.18, 1.8, (0, -7.5, 0.25), axis="x", verts=8))
    return parts


# ---------------------------------------------------------------- trucks

def truck(f, paint, k=1.0, wide=1.0, wheel_r=1.3, hood_d=3.4, rear_len=7.0, rear_axles=None, dual=False,
          sleeper=0.0, stacks=False, tanks=False, glow=False, lens="paint_cream", trim="metal"):
    """Shared truck front: chassis, hood, cab (game cab is 5.6 wide x 4.6 tall x 4.4 deep,
    hood 5.2 x 2.2 x 3.4), windows, lights, wheels. `wide` widens the cab and hood only, to match a
    3-bale-wide bed. Returns (parts, info) for the rear builder."""
    parts = []
    W, CH, CD = 5.6 * k * wide, 4.6 * k, 4.4 * k
    HW, HH, HD = 5.2 * k * wide, 2.2 * k, hood_d * k
    tw = 1.0 * k
    fz = wheel_r * 1.25
    total = HD + CD + sleeper + rear_len
    yF = -total / 2
    yc0 = yF + HD          # cab front
    yc1 = yc0 + CD         # cab back
    yR = total / 2
    # Frame rails and bumper.
    for x in (-1, 1):
        parts.append(B(f, "metal", (0.5, total - 0.4, 0.6), (x * W * 0.28, 0.1, fz - 0.3), along="y"))
    parts.append(B(f, trim, (W + 0.4, 0.6, 0.8), (0, yF - 0.25, fz + 0.15)))
    # Hood with a center seam, a framed slatted grille, bezeled headlights and turn signals.
    parts.append(B(f, paint, (HW, HD, HH), (0, yF + HD / 2, fz + HH / 2), along="y"))
    parts.append(B(f, paint, (0.18, HD - 0.3, 0.1), (0, yF + HD / 2 + 0.1, fz + HH + 0.04), along="y", rounded=False))
    parts.append(B(f, "tire", (HW * 0.62, 0.2, HH * 0.72), (0, yF - 0.05, fz + HH * 0.5)))
    gw, gh = HW * 0.66, HH * 0.78
    for x in (-1, 1):                                                                          # grille surround
        parts.append(B(f, trim, (0.2, 0.3, gh), (x * gw / 2, yF - 0.12, fz + HH * 0.5), along="z", rounded=False))
    for z in (fz + HH * 0.5 - gh / 2, fz + HH * 0.5 + gh / 2):
        parts.append(B(f, trim, (gw + 0.2, 0.3, 0.2), (0, yF - 0.12, z), rounded=False))
    for i in range(6):
        z = fz + HH * (0.2 + 0.12 * i)
        parts.append(B(f, trim, (gw - 0.2, 0.22, 0.1), (0, yF - 0.1, z), rounded=False))
    for x in (-1, 1):
        parts.append(C(f, trim, 0.5 * k, 0.32, (x * HW * 0.4, yF - 0.05, fz + HH * 0.58), axis="y", verts=16))
        parts.append(C(f, "glow" if glow else lens, 0.38 * k, 0.34, (x * HW * 0.4, yF - 0.12, fz + HH * 0.58),
                       axis="y", verts=16))
        parts.append(B(f, "paint_yellow", (0.5, 0.15, 0.22), (x * HW * 0.4, yF - 0.08, fz + HH * 0.2), rounded=False))
    # Cab: an open shell (floor, roof, back, firewall, side panels around the door openings) so an open
    # door shows the bench seat, dash and steering wheel; framed windscreen; hinged doors (Door_L/R) with
    # their windows (Glass_L/R) riding along.
    yc = (yc0 + yc1) / 2
    top = fz + CH
    zw = fz + CH * 0.73
    zwb = zw - CH * 0.19                                                                         # windscreen bottom
    dy0, dy1 = yc0 + 0.35, yc1 - 0.45
    dz0, dz1, dzw = fz + 0.45, fz + CH * 0.92, fz + CH * 0.55
    parts.append(B(f, paint, (W, CD, 0.35), (0, yc, fz + 0.175), along="y", rounded=False))      # floor
    parts.append(B(f, paint, (W, CD, 0.4), (0, yc, top - 0.2), along="y"))                       # roof
    parts.append(B(f, paint, (W - 0.3, CD - 0.4, 0.3), (0, yc, top + 0.1), along="y"))
    parts.append(B(f, paint, (W, 0.35, CH), (0, yc1 - 0.175, fz + CH / 2), rounded=False))      # back wall
    parts.append(B(f, paint, (W, 0.35, zwb - fz), (0, yc0 + 0.175, (fz + zwb) / 2), rounded=False))  # firewall
    for x in (-1, 1):
        xs = x * (W / 2 - 0.15)
        parts.append(B(f, paint, (0.3, dy0 - yc0, CH), (xs, (yc0 + dy0) / 2, fz + CH / 2), along="z", rounded=False))
        parts.append(B(f, paint, (0.3, yc1 - dy1, CH), (xs, (dy1 + yc1) / 2, fz + CH / 2), along="z", rounded=False))
        parts.append(B(f, paint, (0.3, dy1 - dy0, dz0 - fz), (xs, (dy0 + dy1) / 2, (fz + dz0) / 2), along="y",
                       rounded=False))                                                           # door sill
        parts.append(B(f, paint, (0.3, dy1 - dy0, top - dz1), (xs, (dy0 + dy1) / 2, (dz1 + top) / 2), along="y",
                       rounded=False))
        parts.append(B(f, trim, (0.12, CD - 0.2, 0.12), (x * (W / 2 - 0.1), yc, top + 0.02), along="y",
                       rounded=False))                                                           # drip rail
        parts.append(B(f, paint, (0.06, 0.08, CH - 0.4), (x * (W / 2 + 0.01), dy1 + 0.2, fz + CH / 2), along="z",
                       rounded=False))                                                           # panel seam
    parts.append(B(f, "glass", (W - 0.9, 0.12, CH * 0.36), (0, yc0 - 0.04, zw)))
    for x in (-1, 1):                                                                            # A pillars
        parts.append(B(f, paint, (0.3, 0.2, CH * 0.42), (x * (W / 2 - 0.3), yc0 - 0.08, zw), along="z", rounded=False))
    for z in (zwb, zw + CH * 0.19):
        parts.append(B(f, paint, (W - 0.6, 0.2, 0.16), (0, yc0 - 0.08, z), rounded=False))
    # Interior: bench seat, dash, steering wheel on the driver's side (builder +x, -X after the flip).
    parts.append(B(f, "tire", (W - 1.0, 1.3, 0.7), (0, yc1 - 1.1, fz + 1.05), rounded=False))
    parts.append(B(f, "tire", (W - 1.0, 0.4, 1.5), (0, yc1 - 0.6, fz + 1.9), rounded=False))
    parts.append(B(f, "tire", (W - 0.8, 0.8, 0.45), (0, yc0 + 0.75, zwb - 0.2), rounded=False))
    swx, swy, swz = W * 0.22, yc0 + 1.35, zwb - 0.1
    parts.append(C(f, "tire", 0.55 * k, 0.12, (swx, swy, swz), axis="y", verts=12, rounded=False))
    parts.append(beam(f, "metal", (swx, swy, swz), (swx, yc0 + 0.5, zwb - 0.6), 0.14))
    for x in (-1, 1):
        parts += cab_door(f, paint, x, W / 2, dy0, dy1, dz0, dz1, dzw)
        # Running board with step plates, mirror arm and mirror.
        parts.append(B(f, "metal", (0.7, CD * 0.7, 0.2), (x * (W / 2 + 0.3), yc, fz - 0.15), along="y"))
        for zz in (fz - 0.05, fz - 0.25):
            parts.append(B(f, "metal", (0.66, CD * 0.68, 0.04), (x * (W / 2 + 0.3), yc, zz), along="y", rounded=False))
        parts.append(B(f, "metal", (0.9, 0.12, 0.12), (x * (W / 2 + 0.45), yc0 + 0.3, fz + CH * 0.7)))
        parts.append(B(f, "metal", (0.12, 0.12, 0.5), (x * (W / 2 + 0.85), yc0 + 0.3, fz + CH * 0.55), rounded=False))
        parts.append(B(f, "metal", (0.18, 0.45, 1.0 * k), (x * (W / 2 + 0.9), yc0 + 0.3, fz + CH * 0.7), along="z"))
        parts.append(B(f, "glass", (0.04, 0.38, 0.9 * k), (x * (W / 2 + 0.81), yc0 + 0.3, fz + CH * 0.7), along="z",
                       rounded=False))
        parts.append(B(f, "paint_yellow", (0.1, 0.3, 0.16), (x * (W / 2 + 0.02), yc0 + 0.2, top - 0.25),
                       rounded=False))                                                           # running light
    # Fuel tank under the passenger door, and bolts on the bumper.
    if not tanks:
        parts.append(C(f, "metal", 0.55, CD * 0.55, (-(W / 2 - 0.2), yc, fz - 0.3), axis="y", verts=12))
        for dy in (-CD * 0.18, CD * 0.18):
            parts.append(C(f, "tire", 0.58, 0.1, (-(W / 2 - 0.2), yc + dy, fz - 0.3), axis="y", verts=12, rounded=False))
    for x in (-0.38, -0.13, 0.13, 0.38):
        parts.append(C(f, "metal", 0.09, 0.1, (x * (W + 0.4), yF - 0.57, fz + 0.15), axis="y", verts=6, rounded=False))
    if sleeper:
        ys = yc1 + sleeper / 2
        parts.append(B(f, paint, (W, sleeper, CH * 0.96), (0, ys, fz + CH * 0.48), along="y"))
        for x in (-1, 1):
            parts.append(B(f, "glass", (0.12, sleeper * 0.35, CH * 0.14), (x * (W / 2 + 0.04), ys, fz + CH * 0.72),
                           along="y"))
    else:
        parts.append(B(f, "glass", (W * 0.62, 0.12, CH * 0.26), (0, yc1 + 0.04, zw)))
    # Front wheels under the hood with fenders.
    yfw = yF + HD * 0.5
    wx = W / 2 - 0.15
    for x in (-1, 1):
        parts += tire(f, x * wx, yfw, wheel_r, tw, hub="glow" if glow else "metal")
        parts += place(fender_arch(f, paint, 0, 0, wheel_r + 0.45, tw + 0.5, a0=0.15, a1=PI - 0.15, n=7),
                       (x * wx, yfw, wheel_r))
    # Rear wheels.
    rear_axles = rear_axles or [yR - wheel_r * 1.8]
    for y in rear_axles:
        parts.append(C(f, "metal", 0.25, W - 0.5, (0, y, wheel_r), axis="x", verts=8))
        for x in (-1, 1):
            parts += tire(f, x * wx, y, wheel_r, tw, hub="glow" if glow else "metal")
            if dual:
                parts += tag([C(f, "tire", wheel_r, tw * 0.9, (x * (wx - tw * 0.95), y, wheel_r), axis="x")],
                             "wheel", wheel_uid(x * wx, y))
    if stacks:
        for x in (-1, 1):
            yst = yc1 + sleeper + 0.5
            top = fz + CH + 2.2 * k
            parts.append(C(f, "metal", 0.32 * k, top - fz, (x * (W / 2 - 0.4), yst, fz + (top - fz) / 2), verts=10,
                           rounded=False))
            parts.append(C(f, "glow" if glow else "metal", 0.38 * k, 0.3, (x * (W / 2 - 0.4), yst, top), verts=10))
    if tanks:
        tl = CD * 0.7
        for x in (-1, 1):
            tx = x * (W / 2 + 0.35)
            tz = max(0.95 * k + 0.25, fz - 0.6)
            parts.append(C(f, trim if glow else "metal", 0.95 * k, tl, (tx, (yc0 + yc1) / 2 + 0.2, tz), axis="y",
                           verts=12))
            for dy in (-tl * 0.3, tl * 0.3):
                parts.append(C(f, "tire" if not glow else "glow", 1.0 * k, 0.2,
                               (tx, (yc0 + yc1) / 2 + 0.2 + dy, tz), axis="y", verts=12, rounded=False))
            parts.append(C(f, "metal", 0.25, 0.3, (tx, (yc0 + yc1) / 2 + 0.2, tz + 1.0 * k), verts=8))
    info = dict(W=W, CH=CH, fz=fz, yF=yF, yc1=yc1 + sleeper, yR=yR, wheel_r=wheel_r, k=k, wx=wx, tw=tw,
                axles=rear_axles)
    return parts, info


# ---------------------------------------------------------------- cargo beds
# Beds hold loose game bales (4.6 long x 3.2 wide x 2.6 high studs, lying lengthwise, two across).
# Floors and walls are plain unbeveled, un-roughened boxes so their collision stays clean.

BALE = (4.6, 3.2, 2.6)
FLOOR = 3.5   # bed floor top, level with the conveyor dock
WALL_T = 0.3  # wall and floor thickness
BEDS = {}     # prop key -> (interior L, W, wall height, (long, wide, high) bales); filled by the builders


def bed_len(n):
    return n * BALE[0] + 0.8


def bed_wid(n):
    return 7.0 if n <= 2 else n * BALE[1] + 0.6


def flat(f, kind, size, loc, along="x"):
    """A clean collision box: no bevel, no lumpiness."""
    return f.apply(box(s(*size), s(*loc)), kind, along=along)


def cargo_bed(f, key, nl, nw, wall_h, yc, floor="handle", wall="handle", tail_h=None, layers=1, length=None):
    """Flat floor (top at FLOOR) + two side walls + front wall + tailgate around an interior that
    fits nl x nw bales. Centered on y=yc. Returns parts and the outer (L, W)."""
    Li, Wi = length or bed_len(nl), bed_wid(nw)
    Lo, Wo = Li + 2 * WALL_T, Wi + 2 * WALL_T
    BEDS[key] = (Li, Wi, wall_h, (nl, nw, layers))
    tail_h = tail_h or wall_h
    z = FLOOR
    parts = [flat(f, floor, (Wo, Lo, WALL_T), (0, yc, z - WALL_T / 2), along="y")]
    for x in (-1, 1):
        parts.append(flat(f, wall, (WALL_T, Lo, wall_h), (x * (Wi + WALL_T) / 2, yc, z + wall_h / 2), along="y"))
    parts.append(flat(f, wall, (Wi, WALL_T, wall_h), (0, yc - (Li + WALL_T) / 2, z + wall_h / 2)))
    parts += tag([flat(f, wall, (Wi, WALL_T, tail_h), (0, yc + (Li + WALL_T) / 2, z + tail_h / 2))], "Tailgate", yc)
    return parts, Lo, Wo


def plank_lines(f, kind, Lo, Wo, yc, wall_h, n=None):
    """Board seams on the outside of the side walls and tailgate (decoration only, outside the bed)."""
    parts = []
    n = n or max(2, round(wall_h / 0.9))
    for i in range(1, n):
        z = FLOOR + wall_h * i / n
        for x in (-1, 1):
            parts.append(flat(f, kind, (0.08, Lo, 0.12), (x * (Wo / 2 + 0.04), yc, z), along="y"))
        parts.append(flat(f, kind, (Wo - 0.6, 0.08, 0.12), (0, yc + Lo / 2 + 0.04, z)))
    return parts


def bed_support(f, info, yc, Lo):
    """Steel risers from the truck frame up to the underside of the bed floor."""
    fz = info["fz"]
    h = FLOOR - WALL_T - fz
    return [B(f, "metal", (0.5, Lo - 0.6, h), (x * info["W"] * 0.28, yc, fz + h / 2), along="y")
            for x in (-1, 1)]


def taillights(f, info, z, w=None):
    w = w or info["W"]
    return [B(f, "paint_red", (0.6, 0.15, 0.35), (x * (w / 2 - 0.5), info["yR"] + 0.05, z)) for x in (-1, 1)]


def mud_flaps(f, info, Wo):
    y = info["yR"] - 0.4
    return [flat(f, "tire", (1.4, 0.12, 1.4), (x * (info["wx"]), y, 1.6), along="z") for x in (-1, 1)]


def truck_with_bed(f, key, paint, nl, wall_h, k=1.0, wheel_r=1.3, gap=0.4, layers=1, **kw):
    Lo = bed_len(nl) + 2 * WALL_T
    rear_len = gap + Lo + 0.2
    hood_d = kw.pop("hood_d", 3.4)
    yR = (hood_d * k + 4.4 * k + rear_len) / 2
    axles = kw.pop("axles", None)
    if axles is None:
        axles = [yR - Lo * 0.3]
    else:
        axles = [yR - a for a in axles]
    parts, i = truck(f, paint, k=k, wheel_r=wheel_r, hood_d=hood_d, rear_len=rear_len, rear_axles=axles, **kw)
    yc = i["yc1"] + gap + Lo / 2
    return parts, i, yc


def rusty_pickup(f):
    """Starter truck: weathered red pickup, 27.5 long. Bed 14.6 x 10.2 inside with 3.2 walls:
    3 long x 3 wide bales (matches the game's truck, PR #15)."""
    wall_h = 3.2
    parts, i, yc = truck_with_bed(f, "rusty_pickup", "paint_red", 3, wall_h, k=1.5, wide=0.95, wheel_r=1.6,
                                  hood_d=2.92)
    bed, Lo, Wo = cargo_bed(f, "rusty_pickup", 3, 3, wall_h, yc, floor="metal", wall="paint_red")
    parts += bed + bed_support(f, i, yc, Lo) + mud_flaps(f, i, Wo)
    W, fz, yR = i["W"], i["fz"], i["yR"]
    for x in (-1, 1):
        parts.append(flat(f, "metal", (0.4, Lo, 0.15), (x * (Wo / 2 - 0.15), yc, FLOOR + wall_h + 0.07), along="y"))
    parts.append(B(f, "metal", (Wo - 0.6, 0.5, 0.6), (0, yR - 0.1, fz + 0.1)))
    parts += taillights(f, dict(i, yR=yc + Lo / 2), FLOOR + 2.4, Wo)
    return parts


def farm_flatbed(f):
    """Farm stake-bed truck: wooden bed 3 long x 3 wide bales, stake posts and a headache rack."""
    parts, i, yc = truck_with_bed(f, "farm_flatbed", "paint_green", 3, 2.8, wide=1.5, wheel_r=1.4, gap=0.5)
    bed, Lo, Wo = cargo_bed(f, "farm_flatbed", 3, 3, 2.8, yc)
    parts += bed + bed_support(f, i, yc, Lo) + mud_flaps(f, i, Wo) + plank_lines(f, "handle", Lo, Wo, yc, 2.8)
    for x in (-1, 1):
        for n in range(5):
            y = yc - Lo / 2 + 0.3 + n * (Lo - 0.6) / 4
            parts.append(B(f, "metal", (0.3, 0.3, 3.4), (x * (Wo / 2 + 0.15), y, FLOOR + 1.2), along="z"))
    # Headache rack above the front wall.
    yf = yc - Lo / 2 + 0.15
    parts.append(B(f, "metal", (Wo, 0.3, 0.3), (0, yf, FLOOR + 4.6)))
    for x in (-2, -1, 0, 1, 2):
        parts.append(B(f, "metal", (0.22, 0.22, 1.8), (x * (Wo / 4 - 0.1), yf, FLOOR + 3.7), along="z",
                       rounded=False))
    parts.append(B(f, "metal", (i["W"], 0.5, 0.6), (0, i["yR"] - 0.1, i["fz"] - 0.1)))
    parts += taillights(f, dict(i, yR=yc + Lo / 2), FLOOR - 0.4, Wo)
    return parts


def box_truck(f):
    """Box truck: tall ribbed cargo box (4 long x 3 wide x 2 high bales) with the roll-up door
    rolled up and a tailgate across the back, dual rear wheels."""
    wall_h = 6.4
    parts, i, yc = truck_with_bed(f, "box_truck", "paint_cream", 4, wall_h, k=1.05, wide=1.55, wheel_r=1.45, gap=0.4,
                                  dual=True, axles=[3.2])
    bed, Lo, Wo = cargo_bed(f, "box_truck", 4, 3, wall_h, yc, floor="handle", wall="paint_blue", tail_h=2.6,
                            layers=2)
    BEDS["box_truck"] = BEDS["box_truck"][:3] + ((4, 3, 2),)
    parts += bed + bed_support(f, i, yc, Lo)
    top = FLOOR + wall_h
    parts.append(flat(f, "paint_blue", (Wo, Lo, WALL_T), (0, yc, top + WALL_T / 2), along="y"))
    # Rolled-up door under the roof at the back, and its rails.
    yb = yc + Lo / 2
    parts.append(C(f, "metal", 0.35, Wo - 0.8, (0, yb - 0.5, top - 0.35), axis="x", verts=10, rounded=False))
    for x in (-1, 1):
        parts.append(flat(f, "metal", (0.12, 0.25, wall_h + WALL_T), (x * (Wo / 2 + 0.06), yb - 0.12,
                                                                        FLOOR + wall_h / 2)))
        for n in range(5):
            y = yc - Lo / 2 + 0.4 + n * (Lo - 1.0) / 4
            parts.append(flat(f, "metal", (0.12, 0.25, wall_h), (x * (Wo / 2 + 0.06), y, FLOOR + wall_h / 2)))
        parts.append(flat(f, "paint_red", (0.1, Lo - 1.2, 0.7), (x * (Wo / 2 + 0.05), yc, FLOOR + wall_h * 0.62),
                          along="y"))
    parts.append(B(f, "metal", (i["W"], 0.5, 0.5), (0, i["yR"] + 0.0, i["fz"] - 0.35)))
    parts += taillights(f, dict(i, yR=yb), FLOOR + 0.4, Wo)
    for y in i["axles"]:
        for x in (-1, 1):
            parts.append(flat(f, "tire", (0.12, 1.6, 1.6), (x * i["wx"], y + 1.9, 1.3)))
    return parts


def heavy_hauler(f):
    """Big yellow hauler: bigger cab, fuel tanks and stacks, tandem dual axles and a steel tub
    for 5 long x 3 wide x 2 high bales."""
    k, wall_h = 1.2, 5.4
    parts, i, yc = truck_with_bed(f, "heavy_hauler", "paint_yellow", 5, wall_h, k=k, wide=1.35, wheel_r=1.5, gap=1.3,
                                  dual=True, stacks=True, tanks=True, axles=[2.2, 5.6])
    bed, Lo, Wo = cargo_bed(f, "heavy_hauler", 5, 3, wall_h, yc, floor="metal", wall="metal", layers=2)
    parts += bed + bed_support(f, i, yc, Lo) + mud_flaps(f, i, Wo)
    for x in (-1, 1):
        for n in range(6):
            y = yc - Lo / 2 + 0.3 + n * (Lo - 0.6) / 5
            parts.append(flat(f, "paint_yellow", (0.25, 0.4, wall_h), (x * (Wo / 2 + 0.12), y, FLOOR + wall_h / 2),
                              along="z"))
        parts.append(flat(f, "paint_yellow", (0.3, Lo + 0.2, 0.4), (x * (Wo / 2 + 0.1), yc, FLOOR + wall_h + 0.2),
                          along="y"))
    yf = yc - Lo / 2
    parts.append(C(f, "metal", 0.4, 2.0, (0, yf + 1.0, i["fz"] + 0.9), axis="z", verts=8))
    parts.append(B(f, "metal", (i["W"], 0.5, 0.6), (0, i["yR"] - 0.1, i["fz"] - 0.3)))
    parts += taillights(f, dict(i, yR=yc + Lo / 2), FLOOR - 0.5, Wo)
    return parts


def semi_parts(f, paint, glow=False):
    k = 1.2
    rear = 9.0
    sl = 3.6
    total = 3.4 * 1.6 * k + 4.4 * k + sl + rear
    yR = total / 2
    trim = "paint_blue" if glow else "metal"
    parts, i = truck(f, paint, k=k, wheel_r=1.65, hood_d=3.4 * 1.6, rear_len=rear, sleeper=sl, dual=True,
                     stacks=True, tanks=True, rear_axles=[yR - 2.2, yR - 5.9], glow=glow, trim=trim)
    W, fz = i["W"], i["fz"]
    # Fifth wheel coupling plate over the drive axles.
    parts.append(B(f, "metal", (W * 0.7, 5.6, 0.3), (0, yR - 4.0, fz + 0.15), along="y"))
    parts.append(C(f, trim, 1.6, 0.4, (0, yR - 4.0, fz + 0.5), verts=14))
    parts.append(B(f, "tire", (0.5, 1.2, 0.5), (0, yR - 3.0, fz + 0.65), along="y"))
    # Fenders over the drive axles and mud flaps.
    for x in (-1, 1):
        parts.append(B(f, paint, (1.9, 8.0, 0.25), (x * (i["wx"] - 0.4), yR - 4.05, 2 * 1.65 + 0.3), along="y"))
        parts.append(B(f, "tire", (1.8, 0.15, 1.8), (x * (i["wx"] - 0.4), yR - 0.2, 1.3), along="z"))
    # Roof fairing / air horns.
    yc = i["yc1"] - sl
    parts.append(B(f, paint, (W - 0.6, 2.4, 0.8), (0, yc - 1.4, fz + i["CH"] + 0.6), along="y"))
    parts.append(B(f, trim, (W + 0.4, 0.4, 0.5), (0, yR + 0.1, fz - 0.3)))
    parts += taillights(f, i, fz + 0.1)
    return parts, i, trim


def semi_rig(f):
    """Long-nose semi tractor: sleeper cab, tall stacks, fuel tanks, tandem drive axles, fifth wheel."""
    parts, i, trim = semi_parts(f, "paint_blue")
    # Chrome-ish visor and hood ornament strip.
    W, fz = i["W"], i["fz"]
    parts.append(B(f, "metal", (W * 0.9, 0.6, 0.15), (0, i["yF"] + 3.4 * 1.6 * 1.2 + 0.2, fz + i["CH"] - 0.2)))
    parts.append(B(f, "metal", (0.25, 3.4 * 1.6 * 1.2, 0.1), (0, i["yF"] + 3.4 * 0.8 * 1.2, fz + 2.2 * 1.2 + 0.05),
                   along="y", rounded=False))
    return parts


def starlight_hauler(f):
    """Mythic semi: night-black paint with glowing trim strips, light bar, glowing hubs and stacks."""
    parts, i, trim = semi_parts(f, "tire", glow=True)
    W, fz, CH, k = i["W"], i["fz"], i["CH"], i["k"]
    HD, HH = 3.4 * 1.6 * k, 2.2 * k
    yF, yR = i["yF"], i["yR"]
    yc0 = yF + HD
    G = "glow"
    # Hood and cab side strips, cab beltline, underglow, roof light bar.
    for x in (-1, 1):
        parts.append(B(f, G, (0.1, HD - 0.4, 0.25), (x * (5.2 * k / 2 + 0.04), yF + HD / 2, fz + HH * 0.7), along="y",
                       rounded=False))
        parts.append(B(f, G, (0.1, i["yc1"] - yc0, 0.2), (x * (W / 2 + 0.05), (yc0 + i["yc1"]) / 2, fz + CH * 0.5),
                       along="y", rounded=False))
        parts.append(B(f, G, (0.15, yR - yF - 2.0, 0.15), (x * (W * 0.28 + 0.3), (yF + yR) / 2, fz - 0.55),
                       along="y", rounded=False))
    parts.append(B(f, "paint_blue", (0.9, HD, 0.1), (0, yF + HD / 2, fz + HH + 0.03), along="y", rounded=False))
    parts.append(B(f, G, (0.3, HD, 0.12), (0, yF + HD / 2, fz + HH + 0.06), along="y", rounded=False))
    parts.append(B(f, "paint_blue", (W - 0.4, 0.5, 0.4), (0, yc0 + 0.4, fz + CH + 0.4)))
    for n in range(5):
        parts.append(C(f, G, 0.22, 0.2, ((n - 2) * 0.9, yc0 + 0.13, fz + CH + 0.4), axis="y", verts=8))
    parts.append(B(f, G, (W - 0.8, 0.12, 0.2), (0, yF - 0.36, fz + 0.15), rounded=False))
    return parts


# ---------------------------------------------------------------- boats

def hull(L, W, D, stern=0.72, rocker=0.45, n=10, m=9):
    """Open boat hull (studs in, meters out): stern at +y with a transom, pointed bow at -y."""
    verts, faces = [], []
    for i in range(n + 1):
        t = i / n
        y = L / 2 - t * L
        if t < 0.35:
            w = W / 2 * (1 - (1 - stern) * ((0.35 - t) / 0.35) ** 2)
        else:
            w = W / 2 * math.sqrt(max(0.0, 1 - ((t - 0.35) / 0.65) ** 2))
        w = max(w, 0.06)
        zt = D + 0.3 * D * t ** 2
        zb = rocker * D * max(0.0, (t - 0.55) / 0.45) ** 2
        for j in range(m):
            a = -PI / 2 + PI * j / (m - 1)
            sa = math.sin(a)
            x = w * math.copysign(abs(sa) ** 0.6, sa)
            z = zt - (zt - zb) * abs(math.cos(a)) ** 0.45
            verts.append(Vector(s(x, y, z)))
    for i in range(n):
        for j in range(m - 1):
            a, b = i * m + j, i * m + j + 1
            faces.append((a, b, b + m, a + m))
    faces.append(tuple(range(m)))  # transom
    return mesh_obj(verts, faces, "hull")


def hull_halfwidth(L, W, y, stern=0.72):
    t = (L / 2 - y) / L
    if t < 0.35:
        return W / 2 * (1 - (1 - stern) * ((0.35 - t) / 0.35) ** 2)
    return W / 2 * math.sqrt(max(0.0, 1 - ((t - 0.35) / 0.65) ** 2))


def rowboat(f):
    """Wooden rowboat, 10 x 4 studs, with seats, oarlocks and two oars resting in it."""
    L, W, D = 10.0, 4.2, 1.9
    parts = [f.apply(f.shape(solidify(hull(L, W, D), 0.04), round_edges=False), "handle", along="y")]
    # Gunwale strips and keel.
    parts.append(B(f, "handle", (W * 0.36, L * 0.5, 0.1), (0, 0.6, 0.3), along="y", rounded=False))
    for y, z in ((2.6, 1.15), (-0.3, 1.15), (-2.8, 1.3)):
        hw = hull_halfwidth(L, W, y) * 0.93
        parts.append(B(f, "handle", (2 * hw, 1.0, 0.25), (0, y, z)))
    parts.append(B(f, "handle", (W * 0.6, 0.25, 1.0), (0, L / 2 - 0.15, D * 0.7)))
    # Oarlocks, and two oars shipped inside, blades sticking out over the stern.
    for x in (-1, 1):
        hw = hull_halfwidth(L, W, 0.3)
        parts.append(B(f, "metal", (0.25, 0.25, 0.5), (x * hw, 0.3, D + 0.2), along="z"))
        p0, p1 = Vector((x * 0.8, -3.6, 1.6)), Vector((x * 0.95, 5.4, 2.05))
        parts.append(beam(f, "handle", p0, p1, 0.22, along="y"))
        parts.append(beam(f, "handle", p0 - (p1 - p0).normalized() * 0.7, p0, 0.3, along="y"))
        d = (p1 - p0).normalized()
        parts.append(beam(f, "handle", p1, p1 + d * 2.0, 0.12, along="y"))
        blade = box(s(0.8, 2.0, 0.1), s(*(p1 + d * 1.1)), rot=(math.asin(d.z), 0, 0))
        parts.append(f.apply(f.shape(blade), "handle", along="y"))
    # A bow line coil.
    parts.append(C(f, "twine", 0.45, 0.2, (0, -L / 2 + 1.6, D * 0.55 + 0.2), verts=10))
    return parts


def sailboat(f):
    """Small sailboat, 14 studs long: painted hull with foredeck, mast, boom, cloth main and jib."""
    L, W, D = 14.0, 5.2, 2.4
    parts = [f.apply(f.shape(solidify(hull(L, W, D, stern=0.75, rocker=0.35), 0.045), round_edges=False),
                     "paint_blue", along="y")]
    parts.append(B(f, "handle", (W * 0.36, L * 0.45, 0.1), (0, 2.4, 0.3), along="y", rounded=False))
    # Foredeck and benches.
    yd = -2.0
    parts.append(B(f, "handle", (2 * hull_halfwidth(L, W, yd) * 0.98, 0.3, 0.3), (0, yd, D - 0.1)))
    deck_verts = []
    for i in range(7):
        y = yd - i * (L / 2 + yd - 0.2) / 6
        hw = max(0.1, hull_halfwidth(L, W, y) * 0.98)
        zt = D + 0.3 * D * ((L / 2 - y) / L) ** 2 - 0.05
        deck_verts += [Vector(s(-hw, y, zt)), Vector(s(hw, y, zt))]
    deck_faces = [(2 * i, 2 * i + 2, 2 * i + 3, 2 * i + 1) for i in range(6)]
    deck = solidify(mesh_obj(deck_verts, deck_faces, "deck"), 0.05)
    parts.append(f.apply(f.shape(deck, round_edges=False), "handle", along="y"))
    for x in (-1, 1):
        parts.append(B(f, "handle", (0.9, 6.0, 0.25), (x * (hull_halfwidth(L, W, 3.0) - 0.55), 3.4, D * 0.6),
                       along="y"))
    parts.append(B(f, "handle", (W * 0.66, 0.3, 1.4), (0, L / 2 - 0.2, D * 0.65)))
    # Tiller.
    parts.append(B(f, "handle", (0.25, 2.2, 0.25), (0, L / 2 - 1.0, D + 0.1), along="y"))
    # Mast, boom and sails.
    ym, mast_h = -1.6, 15.0
    parts.append(C(f, "handle", 0.22, mast_h, (0, ym, mast_h / 2 + 0.2), verts=8, rounded=False))
    zb = D + 1.2
    boom = 6.6
    parts.append(C(f, "handle", 0.18, boom, (0, ym + boom / 2, zb), axis="y", verts=8, rounded=False))
    main = mesh_obj([Vector(s(0.05, ym + 0.2, zb + 0.25)), Vector(s(0.05, ym + boom - 0.2, zb + 0.25)),
                     Vector(s(0.05, ym + 0.2, mast_h - 0.3))], [(0, 1, 2)], "sail")
    parts.append(f.apply(f.shape(solidify(main, 0.02), round_edges=False), "cloth", along="z"))
    jib = mesh_obj([Vector(s(0, ym - 0.3, mast_h - 2.5)), Vector(s(0, -L / 2 + 0.5, D + 0.9)),
                    Vector(s(0, ym - 0.3, D + 1.0))], [(0, 1, 2)], "jib")
    parts.append(f.apply(f.shape(solidify(jib, 0.02), round_edges=False), "cloth", along="z"))
    # Forestay line.
    parts.append(beam(f, "twine", (0, ym, mast_h), (0, -L / 2 + 0.3, D + 0.75), 0.08))
    return parts


def cargo_barge(f):
    """Car ferry barge: steel hull 22 x 74 studs with an open deck 18 wide x 66 long inside low rails
    (a pickup plus a medium trailer, about 60 long, drives on), a hinged ramp at each end and a small
    pilot house on a side sponson."""
    L, W, H = 66.0, 22.0, 2.6      # deck length between ramps, hull width, deck height
    inner = 18.0
    parts = []
    hb = box(s(W, L, H), s(0, 0, H / 2))
    for v in hb.data.vertices:
        if v.co.z < 0:
            v.co.y *= 0.94  # raked bow and stern
    parts.append(f.apply(f.shape(hb), "metal", along="y"))
    for x in (-1, 1):
        parts.append(B(f, "paint_red", (0.1, L - 0.6, 0.6), (x * (W / 2 + 0.04), 0, H - 0.5), along="y",
                       rounded=False))
    parts.append(flat(f, "stone", (inner, L, 0.12), (0, 0, H + 0.06), along="y"))
    # Low rails (1.2 tall) and walkways outside them, bollards and tire fenders.
    for x in (-1, 1):
        parts.append(flat(f, "metal", (0.3, L, 1.2), (x * (inner / 2 + 0.15), 0, H + 0.6), along="y"))
        for y in (-L / 2 + 2, -L / 4, 0, L / 4, L / 2 - 2):
            parts.append(C(f, "metal", 0.35, 0.9, (x * (W / 2 - 0.8), y, H + 0.45), verts=8))
        for y in (-24, -8, 8, 24):
            parts.append(C(f, "tire", 0.6, 0.6, (x * (W / 2 + 0.35), y, H - 1.1), axis="x", verts=10))
    # Lane stripes and wheel chocks.
    for x in (-4.5, 4.5):
        parts.append(flat(f, "paint_yellow", (0.3, L - 4, 0.02), (x, 0, H + 0.13), along="y"))
    # Hinged ramps at both ends (hinge on the deck edge), lying down slightly sloped.
    for y in (-1, 1):
        ramp = box(s(inner, 5.0, 0.3), s(0, y * (L / 2 + 2.4), H - 0.4), rot=(y * 0.12, 0, 0))
        parts += tag([f.apply(f.shape(ramp, round_edges=False), "metal", along="y")], "Ramp", y)
        for x in (-1, 1):
            parts.append(C(f, "metal", 0.3, 1.0, (x * (inner / 2 - 0.5), y * (L / 2 + 0.1), H - 0.1), axis="x", verts=8))
    # Pilot house on a sponson off the starboard side, outside the deck.
    px = W / 2 + 2.5
    parts.append(B(f, "metal", (5.0, 8.0, 0.6), (px, -L / 4, H - 0.3), along="y"))
    parts.append(B(f, "paint_cream", (4.2, 5.0, 4.2), (px, -L / 4, H + 2.1), along="y"))
    parts.append(B(f, "paint_red", (4.8, 5.6, 0.4), (px, -L / 4, H + 4.4), along="y"))
    for y in (-L / 4 - 2.55, -L / 4 + 2.55):
        parts.append(B(f, "glass", (3.4, 0.12, 1.4), (px, y, H + 3.0), rounded=False))
    parts.append(C(f, "metal", 0.25, 2.5, (px, -L / 4 + 1.5, H + 5.8), verts=8))
    return parts


# ---------------------------------------------------------------- trailers

def trailer(f, key, nl, nw, wall_h, wheel_r, axles, tongue=4.5, hitch_z=2.2, wall="handle", floor="handle",
            spoked=False, y0=0.0, jack=True, layers=1, posts=True, length=None):
    """Hay trailer: steel frame under a clean cargo bed (floor top at FLOOR), wheels, A-frame tongue
    and jack stand. Bed centered at y0; `axles` are offsets from the bed center."""
    bed, L, W = cargo_bed(f, key, nl, nw, wall_h, y0, floor=floor, wall=wall, layers=layers, length=length)
    parts = list(bed)
    yf, yb = y0 - L / 2, y0 + L / 2
    rx = min(W * 0.32, 2.4)
    rz = FLOOR - WALL_T - 0.3
    for x in (-1, 1):
        parts.append(B(f, "metal", (0.4, L, 0.6), (x * rx, y0, rz), along="y"))
    for n in range(int(L // 4) + 1):
        parts.append(flat(f, "metal", (W - 0.2, 0.3, 0.25), (0, yf + 0.3 + n * (L - 0.6) / (L // 4),
                                                             FLOOR - WALL_T - 0.125)))
    parts += plank_lines(f, wall, L, W, y0, wall_h) if wall == "handle" else []
    if posts:
        npost = max(2, round(L / 4)) + 1
        for x in (-1, 1):
            for n in range(npost):
                y = yf + 0.2 + n * (L - 0.4) / (npost - 1)
                parts.append(B(f, "metal", (0.3, 0.3, wall_h + 0.4), (x * (W / 2 + 0.15), y,
                                                                     FLOOR + wall_h / 2 - 0.2), along="z"))
    # Axles, springs and wheels (tucked under the bed).
    tw = 0.9 if wheel_r < 1.5 else 1.1
    wx = rx + 0.35 + tw / 2
    for dy in axles:
        y = y0 + dy
        parts.append(C(f, "metal", 0.2, 2 * wx, (0, y, wheel_r), axis="x", verts=8))
        for x in (-1, 1):
            h = rz - 0.3 - wheel_r
            parts.append(B(f, "metal", (0.3, 1.6, h), (x * rx, y, wheel_r + h / 2), along="z"))
            if spoked:
                parts += spoked_wheel(f, x * wx, y, wheel_r, 0.45)
            else:
                parts += tire(f, x * wx, y, wheel_r, tw, verts=16, treads=10)
    # Rail caps along the wall tops, tie-down rings under the side rails, corner reflectors.
    if posts:
        for x in (-1, 1):
            parts.append(flat(f, "metal", (WALL_T + 0.16, L, 0.14), (x * (W / 2 - WALL_T / 2), y0, FLOOR + wall_h + 0.07),
                              along="y"))
    for x in (-1, 1):
        for n in range(max(2, int(L // 5))):
            y = yf + 1.0 + n * (L - 2.0) / max(1, int(L // 5) - 1)
            parts.append(B(f, "metal", (0.12, 0.45, 0.3), (x * (W / 2 + 0.06), y, FLOOR - WALL_T - 0.05), rounded=False))
        parts.append(B(f, "paint_yellow", (0.06, 0.35, 0.25), (x * (W / 2 + 0.03), yf + 0.4, FLOOR + 0.4), rounded=False))
    # Tongue: A-frame to a coupler, a jack stand to the ground.
    tip = (0, yf - tongue, hitch_z)
    for x in (-1, 1):
        parts.append(beam(f, "metal", (x * rx, yf + 0.6, rz), tip, 0.4))
    parts += tag([B(f, "metal", (0.7, 1.0, 0.5), (0, tip[1] - 0.3, hitch_z)),
                  C(f, "metal", 0.35, 0.3, (0, tip[1] - 0.7, hitch_z - 0.2), verts=8)], "Coupler", y0)
    for x in (-1, 1):                                                       # safety chains, sagging in two links
        a, b = (x * 0.3, tip[1] - 0.1, hitch_z - 0.25), (x * 0.45, tip[1] + 0.9, hitch_z - 0.75)
        parts.append(beam(f, "metal", a, b, 0.1))
        parts.append(beam(f, "metal", b, (x * 0.6, tip[1] + 1.8, hitch_z - 0.15), 0.1))
    if jack:
        jy = tip[1] + tongue * 0.35
        jz = hitch_z + (rz - hitch_z) * 0.35
        parts.append(C(f, "metal", 0.18, jz, (0.0, jy, jz / 2), verts=8, rounded=False))
        parts.append(B(f, "metal", (0.9, 0.9, 0.15), (0.0, jy, 0.08)))
        parts.append(C(f, "metal", 0.28, 1.0, (0.0, jy, jz - 0.5), verts=8))
        parts.append(beam(f, "metal", (0.0, jy, jz + 0.05), (0.5, jy, jz + 0.05), 0.08))         # crank
        parts.append(C(f, "tire", 0.08, 0.3, (0.5, jy, jz + 0.2), verts=6, rounded=False))
    if tongue >= 4.0:                                                       # tongue box with a lid seam and hasp
        by = yf - tongue * 0.45
        bz = hitch_z + (rz - hitch_z) * 0.55 + 0.55
        parts.append(B(f, "metal", (2.0, 1.1, 0.9), (0, by, bz)))
        parts.append(B(f, "metal", (2.1, 1.2, 0.08), (0, by, bz + 0.3), rounded=False))
        parts.append(B(f, "metal", (0.2, 0.08, 0.3), (0, by - 0.58, bz + 0.15), rounded=False))
    for x in (-1, 1):
        parts.append(B(f, "paint_red", (0.5, 0.15, 0.3), (x * (W / 2 - 0.5), yb + 0.08, FLOOR - 0.5)))
    return parts


def wagon_trailer(f):
    """Old farm wagon (3 bale-loads): green-sided wooden bed for 1 long x 2 wide bales on four
    spoked wheels with a wooden tongue."""
    parts, L, W = cargo_bed(f, "wagon_trailer", 1, 2, 2.6, 0.0, floor="handle", wall="paint_green")
    parts += plank_lines(f, "handle", L, W, 0.0, 2.6, n=3)
    for x in (-1, 1):
        parts.append(B(f, "handle", (0.4, L + 0.4, 0.5), (x * 1.6, 0, FLOOR - WALL_T - 0.25), along="y"))
        for y in (-L / 2 + 0.2, L / 2 - 0.2):
            parts.append(B(f, "handle", (0.3, 0.3, 3.0), (x * (W / 2 + 0.15), y, FLOOR + 1.1), along="z"))
    for y in (-1.6, 1.6):
        parts.append(B(f, "handle", (W - 0.6, 0.5, 1.0), (0, y, FLOOR - WALL_T - 0.9)))
        parts.append(C(f, "metal", 0.15, W + 1.3, (0, y, 1.5), axis="x", verts=8))
        for x in (-1, 1):
            parts.append(B(f, "handle", (0.3, 0.3, 0.8), (x * 1.6, y, 1.85), along="z"))
            parts += spoked_wheel(f, x * (W / 2 + 0.45), y, 1.5, 0.4, spokes=6)
    # Iron corner straps and bolt heads on the green sides.
    for x in (-1, 1):
        for y in (-L / 2 + 0.6, L / 2 - 0.6):
            parts.append(flat(f, "metal", (0.08, 0.35, 2.4), (x * (W / 2 + 0.04), y, FLOOR + 1.3), along="z"))
            for z in (0.5, 1.3, 2.1):
                parts.append(B(f, "metal", (0.12, 0.14, 0.14), (x * (W / 2 + 0.09), y, FLOOR + z), rounded=False))
    # Wooden tongue with a ring hitch, resting on the ground.
    parts.append(beam(f, "handle", (0, -1.6, 2.0), (0, -L / 2 - 4.5, 0.35), 0.4))
    parts += tag([C(f, "metal", 0.45, 0.15, (0, -L / 2 - 4.9, 0.3), verts=10)], "Coupler")
    return parts


def small_trailer(f):
    """Small trailer (8): single axle, bed for 2 long x 2 wide bales."""
    return trailer(f, "small_trailer", 2, 2, 2.6, 1.2, [0.8], tongue=4.0)


def medium_trailer(f):
    """Game conveyor trailer (20): 24 long x 7 wide inside (the game's 6 wide fits only one bale across),
    5 long x 2 wide bales, 2.8-stud wheels on a tandem axle, plank sides."""
    parts = trailer(f, "medium_trailer", 5, 2, 2.6, 1.4, [4.0, 7.2], tongue=4.5, length=24.0)
    return parts


def large_trailer(f):
    """Large trailer (45): wide triple-axle bed for 6 long x 3 wide x 2 high bales, tall plank sides."""
    return trailer(f, "large_trailer", 6, 3, 5.4, 1.4, [5.0, 8.4, 11.8], tongue=5.0, hitch_z=2.4, layers=2)


def double_trailer(f):
    """Double trailer: two linked beds, each for 3 long x 2 wide bales; the rear one rides its own dolly."""
    parts = trailer(f, "double_trailer", 3, 2, 2.8, 1.3, [2.2, 5.4], tongue=4.0, y0=-10.0)
    parts += trailer(f, "double_trailer", 3, 2, 2.8, 1.3, [-5.4, 5.4], tongue=2.2, hitch_z=1.6, y0=8.6, jack=False)
    # Pintle hitch hanging under the front bed's tail, meeting the rear trailer's coupler.
    yb = -10.0 + bed_len(3) / 2 + WALL_T
    parts.append(B(f, "metal", (0.5, 0.8, 0.5), (0, yb + 0.3, 1.6), along="y"))
    parts.append(B(f, "metal", (0.5, 0.5, 1.6), (0, yb - 0.1, 2.4), along="z"))
    BEDS["double_trailer"] = BEDS["double_trailer"][:3] + ((3, 2, 1),)
    return parts


def bale_rack_trailer(f):
    """Bale rack (30 whole bales): 5 long x 2 wide x 3 high, tall slatted rack sides and ladder ends."""
    wall_h = 8.0
    parts = trailer(f, "bale_rack_trailer", 5, 2, wall_h, 1.4, [4.6, 7.8, 11.0], tongue=5.0, wall="metal",
                    floor="handle", layers=3, posts=False)
    L, W = bed_len(5) + 2 * WALL_T, bed_wid(2) + 2 * WALL_T
    # Ladder racks outside the ends and sides (the walls inside stay flat).
    for y in (-L / 2 - 0.2, L / 2 + 0.2):
        for x in (-1, -0.33, 0.33, 1):
            parts.append(B(f, "metal", (0.3, 0.3, wall_h + 0.6), (x * (W / 2 - 0.15), y, FLOOR + wall_h / 2 + 0.3),
                           along="z"))
        for z in (1.4, 2.8, 4.2, 5.6, 7.0, wall_h + 0.4):
            parts.append(B(f, "metal", (W, 0.25, 0.25), (0, y, FLOOR + z)))
    for x in (-1, 1):
        for n in range(7):
            y = -L / 2 + 0.3 + n * (L - 0.6) / 6
            parts.append(B(f, "metal", (0.25, 0.25, wall_h + 0.6), (x * (W / 2 + 0.13), y, FLOOR + wall_h / 2 + 0.3),
                           along="z"))
        for z in (2.7, 5.3, wall_h):
            parts.append(flat(f, "handle", (0.12, L, 0.3), (x * (W / 2 + 0.06), 0, FLOOR + z), along="y"))
    return parts


RIG_FLIP = True  # builders face -y; turn to +y so the glTF faces -Z

PROPS = {
    "two_wheel_handcart": two_wheel_handcart,
    "pull_wagon": pull_wagon,
    "rusty_pickup": rusty_pickup,
    "farm_flatbed": farm_flatbed,
    "box_truck": box_truck,
    "heavy_hauler": heavy_hauler,
    "semi_rig": semi_rig,
    "starlight_hauler": starlight_hauler,
    "rowboat": rowboat,
    "sailboat": sailboat,
    "cargo_barge": cargo_barge,
    "wagon_trailer": wagon_trailer,
    "small_trailer": small_trailer,
    "medium_trailer": medium_trailer,
    "large_trailer": large_trailer,
    "double_trailer": double_trailer,
    "bale_rack_trailer": bale_rack_trailer,
}

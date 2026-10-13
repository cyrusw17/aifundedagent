"""Upgraded hand tools for the hay farm, in the house style (LT2 shapes, Rustic finish).

Held by a ~5-stud Roblox character, so sizes follow the starter tools in rustic_props.py
(basic_shovel ~2.7 studs, pitchfork ~5, hay_hook ~1.4). Each prop stands on the ground
(z=0), centered near x=y=0, front facing -y.

Run:
  python blender/props/rustic_props.py --out <dir> --category tools
"""
import math
import os
import sys

import bpy  # must be imported before bmesh/mathutils with the pip bpy module
import bmesh  # noqa: E402,F401
from mathutils import Vector  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, HERE)
import style  # noqa: E402,F401
from style import box, cap_uv, cyl  # noqa: E402,F401

STUD = 0.28
TAU = 2 * math.pi


# ---------------------------------------------------------------- helpers

def mesh_obj(name, verts, faces):
    """Link a new mesh object built from raw verts/faces and make it active."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    return obj


def frame(z):
    """Two unit vectors perpendicular to z (a, b): a lies in the plane of z and world y's normal."""
    z = Vector(z).normalized()
    a = z.cross(Vector((0, 1, 0)))
    if a.length < 1e-4:
        a = z.cross(Vector((1, 0, 0)))
    a.normalize()
    return a, z.cross(a).normalized()


def beam(p0, p1, a, b, a1=None, b1=None, name="beam"):
    """Box from p0 to p1. a is the size in the p0-p1/xz plane, b the other way (mostly along y).
    a1/b1 taper the far end."""
    p0, p1 = Vector(p0), Vector(p1)
    ea, eb = frame(p1 - p0)
    a1 = a if a1 is None else a1
    b1 = b if b1 is None else b1
    verts = []
    for p, sa, sb in ((p0, a, b), (p1, a1, b1)):
        for i, j in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            verts.append(p + ea * (i * sa / 2) + eb * (j * sb / 2))
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return mesh_obj(name, verts, faces)


def rod(p0, p1, r, sides=8, r1=None, name="rod"):
    """Capped cylinder from p0 to p1 (r1 tapers the far end)."""
    return tube([p0, p1], lambda t: r + ((r if r1 is None else r1) - r) * t, sides, name=name)


def tube(points, radius, sides=8, name="tube"):
    """Sweep a circle along a polyline. radius is a number or fn(t in 0..1). Ends are capped."""
    pts = [Vector(p) for p in points]
    rfn = radius if callable(radius) else (lambda t: radius)
    lengths = [0.0]
    for i in range(1, len(pts)):
        lengths.append(lengths[-1] + (pts[i] - pts[i - 1]).length)
    total = lengths[-1]
    verts, faces = [], []
    ea = None
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        if ea is None:
            ea, _ = frame(d)
        else:  # parallel transport keeps the rings from twisting
            ea = (ea - d * ea.dot(d)).normalized()
        eb = d.cross(ea).normalized()
        r = rfn(lengths[i] / total)
        for k in range(sides):
            ang = TAU * k / sides
            verts.append(p + ea * (math.cos(ang) * r) + eb * (math.sin(ang) * r))
    n = len(pts)
    for i in range(n - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            faces.append((i * sides + k, i * sides + k2, (i + 1) * sides + k2, (i + 1) * sides + k))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple((n - 1) * sides + k for k in range(sides)))
    obj = mesh_obj(name, verts, faces)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def arc_band(center, r_in, r_out, a0, a1, n, depth, name="arc"):
    """Thick ring sector in the xz plane around center, depth along y. Angle 0 = +x, pi/2 = +z.
    A full turn (a1 - a0 = 2 pi) closes into a ring."""
    cx, cy, cz = center
    closed = abs(abs(a1 - a0) - TAU) < 1e-6
    steps = n if closed else n + 1
    verts = []
    for i in range(steps):
        ang = a0 + (a1 - a0) * i / n
        c, s = math.cos(ang), math.sin(ang)
        for r in (r_in, r_out):
            for y in (-depth / 2, depth / 2):
                verts.append((cx + r * c, cy + y, cz + r * s))
    faces = []
    for i in range(n):
        a, b = i * 4, ((i + 1) % steps) * 4
        # vertex order in a slice: 0 in/front, 1 in/back, 2 out/front, 3 out/back
        faces += [(a + 0, a + 2, b + 2, b + 0), (a + 3, a + 1, b + 1, b + 3),
                  (a + 1, a + 0, b + 0, b + 1), (a + 2, a + 3, b + 3, b + 2)]
    if not closed:
        e = (steps - 1) * 4
        faces += [(0, 1, 3, 2), (e + 0, e + 2, e + 3, e + 1)]
    obj = mesh_obj(name, verts, faces)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def handle(f, length, z0, r=0.02, sides=8, x=0.0, y=0.0):
    """Wooden pole from z0 upward (like rustic_props.handle)."""
    h = cyl(r, length, (x, y, z0 + length / 2), verts=sides)
    return f.apply(f.shape(h, round_edges=False), "handle", along="z")


def hcyl(r, depth, loc, axis="x", verts=8):
    rot = {"x": (0, math.pi / 2, 0), "y": (math.pi / 2, 0, 0), "z": (0, 0, 0)}[axis]
    return cyl(r, depth, loc, verts=verts, rot=rot)


# ---------------------------------------------------------------- tools

def steel_fork(f):
    """Better pitchfork, about 5.4 studs: six steel tines, braced head, steel ferrule and a D grip."""
    parts = [handle(f, 0.9, 0.42, r=0.022)]
    # Steel ferrule with a painted band where the wood meets the steel.
    parts.append(f.apply(f.shape(cyl(0.03, 0.14, (0, 0, 0.45), verts=8)), "metal", along="z"))
    parts.append(f.apply(cyl(0.032, 0.025, (0, 0, 0.53), verts=8), "paint_red", along="z"))
    parts.append(f.apply(f.shape(beam((0, 0, 0.33), (0, 0, 0.39), 0.07, 0.045, 0.05, 0.04)), "metal", along="z"))
    # Shoulder bar, slightly arched.
    bar = box((0.36, 0.04, 0.045), (0, 0, 0.33))
    for v in bar.data.vertices:
        v.co.z -= (v.co.x / 0.18) ** 2 * 0.02
    parts.append(f.apply(f.shape(bar), "metal"))
    # Diagonal braces from neck to the outer tines: the "sturdier" tell.
    for s in (-1, 1):
        parts.append(f.apply(beam((s * 0.02, 0.0, 0.42), (s * 0.15, 0.0, 0.335), 0.02, 0.022), "metal"))
    # Six tines with a slight forward curve and points.
    for i in range(6):
        x = -0.15 + i * 0.06
        pts = []
        for j in range(6):
            t = j / 5
            pts.append((x, -0.05 * t ** 2, 0.32 * (1 - t) + 0.005))
        tine = tube(pts, lambda t: 0.012 * (1 - 0.75 * t), sides=6, name="tine")
        parts.append(f.apply(tine, "metal", along="z"))
    # D grip: steel straps and a wooden crossbar.
    top = 1.32
    for s in (-1, 1):
        parts.append(f.apply(beam((s * 0.015, 0, top - 0.04), (s * 0.065, 0, top + 0.1), 0.016, 0.03), "metal"))
    parts.append(f.apply(f.shape(hcyl(0.02, 0.16, (0, 0, top + 0.11), verts=8), round_edges=False),
                         "handle", along="x"))
    parts.append(f.apply(cyl(0.026, 0.05, (0, 0, top - 0.02), verts=8), "metal", along="z"))
    return parts


def needle_tweezers(f):
    """Oversized tweezers standing tips-down, about 2.2 studs, pinching a needle."""
    parts = []
    top, knee, tip = 0.6, 0.24, 0.02
    for s in (-1, 1):
        # Each arm: a flat strip that bows out, then tapers back in to the tip.
        parts.append(f.apply(beam((s * 0.018, 0, top), (s * 0.075, 0, knee), 0.016, 0.06, 0.016, 0.055),
                             "metal", along="z"))
        parts.append(f.apply(beam((s * 0.075, 0, knee), (s * 0.012, 0, tip), 0.016, 0.055, 0.012, 0.02),
                             "metal", along="z"))
        # Rubber grip pad on the outside of each arm.
        a = Vector((s * 0.018, 0, top))
        b = Vector((s * 0.075, 0, knee))
        out = Vector((s, 0, 0)) * 0.012
        p0 = a + (b - a) * 0.3 + out
        p1 = a + (b - a) * 0.85 + out
        parts.append(f.apply(beam(p0, p1, 0.014, 0.066), "paint_red", along="z"))
        for k in range(4):
            q = p0 + (p1 - p0) * (0.12 + 0.25 * k) + Vector((s * 0.008, 0, 0))
            parts.append(f.apply(beam(q - Vector((0, 0, 0.008)), q + Vector((0, 0, 0.008)), 0.01, 0.07),
                                 "tire", along="z"))
        # Bent-in tips.
        parts.append(f.apply(beam((s * 0.012, 0, tip + 0.005), (s * 0.004, 0, 0.0), 0.012, 0.02, 0.008, 0.016),
                             "metal", along="z"))
    # Hinge block at the top with a rivet.
    parts.append(f.apply(f.shape(box((0.07, 0.07, 0.07), (0, 0, top + 0.02))), "metal"))
    parts.append(f.apply(hcyl(0.016, 0.085, (0, 0, top + 0.02), axis="y", verts=8), "paint_red", along="y"))
    # A needle caught between the tips.
    parts.append(f.apply(rod((-0.14, -0.02, 0.012), (0.16, -0.02, 0.012), 0.006, sides=6, r1=0.0015), "metal"))
    parts.append(f.apply(arc_band((-0.15, -0.02, 0.012), 0.006, 0.012, 0, TAU, 8, 0.006), "metal"))
    return parts


def silver_sieve_net(f):
    """Handheld round sifter standing on its rim, about 3.4 studs: steel rim, fine mesh, wooden handle."""
    parts = []
    r, cz, depth = 0.24, 0.245, 0.08
    # Rim: a thick steel band plus a rolled lip at the front.
    parts.append(f.apply(arc_band((0, 0, cz), r - 0.014, r, 0, TAU, 20, depth, name="rim"), "metal"))
    parts.append(f.apply(arc_band((0, -depth / 2, cz), r - 0.02, r + 0.008, 0, TAU, 20, 0.018, name="lip"),
                         "metal"))
    # Mesh: pale cloth screen with a steel wire grid over it.
    screen = hcyl(r - 0.012, 0.006, (0, 0.025, cz), axis="y", verts=20)
    parts.append(f.apply(screen, "cloth", along="x"))
    step = 0.045
    n = int((r - 0.014) // step)
    for i in range(-n, n + 1):
        c = i * step
        half = math.sqrt(max(0.0, (r - 0.012) ** 2 - c ** 2))
        parts.append(f.apply(beam((c, 0.019, cz - half), (c, 0.019, cz + half), 0.006, 0.006), "metal", along="z"))
        parts.append(f.apply(beam((-half, 0.019, cz + c), (half, 0.019, cz + c), 0.006, 0.006), "metal"))
    # Handle: steel yoke from the rim into a ferrule, then a wooden grip upward.
    rim_top = cz + r
    for s in (-1, 1):
        a = math.radians(90 + s * 28)
        p = (r * math.cos(a), 0, cz + r * math.sin(a))
        parts.append(f.apply(beam(p, (s * 0.012, 0, rim_top + 0.1), 0.02, 0.03), "metal"))
    parts.append(f.apply(f.shape(cyl(0.026, 0.07, (0, 0, rim_top + 0.12), verts=8)), "metal", along="z"))
    parts.append(handle(f, 0.3, rim_top + 0.155, r=0.022))
    parts.append(f.apply(cyl(0.03, 0.03, (0, 0, rim_top + 0.47), verts=8), "metal", along="z"))
    parts.append(f.apply(arc_band((0, 0, rim_top + 0.52), 0.012, 0.022, 0, TAU, 8, 0.012, name="hang_ring"),
                         "metal"))
    return parts


def magnet_wand(f):
    """Rod with a big red horseshoe magnet on top, about 3.6 studs, a couple of needles stuck to it."""
    parts = []
    # Grip, guard and steel rod.
    parts.append(f.apply(cyl(0.032, 0.04, (0, 0, 0.02), verts=8), "metal", along="z"))
    parts.append(handle(f, 0.26, 0.04, r=0.026))
    for z in (0.09, 0.16, 0.23):
        parts.append(f.apply(cyl(0.029, 0.018, (0, 0, z), verts=8), "twine", along="z"))
    parts.append(f.apply(cyl(0.04, 0.03, (0, 0, 0.31), verts=8), "metal", along="z"))
    parts.append(f.apply(rod((0, 0, 0.32), (0, 0, 0.64), 0.016, sides=8), "metal", along="z"))
    # Horseshoe: lower half ring plus two legs, open end up.
    cz, r_in, r_out, depth = 0.78, 0.065, 0.155, 0.1
    mid = (r_in + r_out) / 2
    parts.append(f.apply(f.shape(arc_band((0, 0, cz), r_in, r_out, math.pi, TAU, 10, depth, name="shoe")),
                         "paint_red"))
    leg_h = 0.13
    for s in (-1, 1):
        parts.append(f.apply(f.shape(box((r_out - r_in, depth, leg_h), (s * mid, 0, cz + leg_h / 2))), "paint_red"))
        parts.append(f.apply(box((r_out - r_in + 0.008, depth + 0.008, 0.07), (s * mid, 0, cz + leg_h + 0.035)), "metal"))
    parts.append(f.apply(box((0.06, 0.06, 0.05), (0, 0, cz - r_out + 0.005)), "metal"))
    # Needles clinging to the tips.
    top = cz + leg_h + 0.07
    parts.append(f.apply(rod((-mid - 0.02, -0.02, top - 0.005), (-mid - 0.12, -0.03, top + 0.07), 0.005, 6, 0.0015),
                         "metal"))
    parts.append(f.apply(rod((mid + 0.01, 0.02, top - 0.002), (mid + 0.13, 0.03, top + 0.03), 0.005, 6, 0.0015),
                         "metal"))
    parts.append(f.apply(rod((mid - 0.02, -0.03, top), (mid + 0.06, -0.06, top + 0.11), 0.005, 6, 0.0015),
                         "metal"))
    return parts


def helix_flight(z0, z1, turns, r_in, r_out, thick, per_turn=16, name="flight"):
    """Auger flight: a solid helical ribbon around the z axis."""
    n = max(2, int(turns * per_turn))
    verts, faces = [], []
    for i in range(n + 1):
        t = i / n
        ang = TAU * turns * t
        z = z0 + (z1 - z0) * t
        c, s = math.cos(ang), math.sin(ang)
        ro = r_out * (0.45 + 0.55 * min(1.0, t * 4))  # flight grows out of the tip
        for r in (r_in, ro):
            for dz in (-thick / 2, thick / 2):
                verts.append((r * c, r * s, z + dz))
    for i in range(n):
        a, b = i * 4, (i + 1) * 4
        faces += [(a + 0, a + 2, b + 2, b + 0), (a + 3, a + 1, b + 1, b + 3),
                  (a + 1, a + 0, b + 0, b + 1), (a + 2, a + 3, b + 3, b + 2)]
    e = n * 4
    faces += [(0, 1, 3, 2), (e + 0, e + 2, e + 3, e + 1)]
    obj = mesh_obj(name, verts, faces)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def barrel_auger(f):
    """Epic: two-handed power auger, about 4.8 studs tall and 3.2 wide. Spiral flight on a steel
    shaft, gearbox, red engine with fins, pull starter, muffler and a wide handlebar."""
    parts = []
    # Drill point and shaft.
    parts.append(f.apply(rod((0, 0, 0.0), (0, 0, 0.09), 0.004, sides=8, r1=0.03), "metal", along="z"))
    parts.append(f.apply(rod((0, 0, 0.08), (0, 0, 0.92), 0.03, sides=8), "metal", along="z"))
    parts.append(f.apply(helix_flight(0.06, 0.74, 4.5, 0.028, 0.15, 0.014), "metal", along="z"))
    parts.append(f.apply(f.shape(cyl(0.045, 0.06, (0, 0, 0.8), verts=8)), "metal", along="z"))
    # Gearbox and handlebar frame.
    parts.append(f.apply(f.shape(box((0.2, 0.18, 0.13), (0, 0, 0.955))), "metal"))
    parts.append(f.apply(f.shape(cyl(0.06, 0.03, (0, 0, 0.875), verts=10)), "paint_red", along="z"))
    bar_z = 0.98
    parts.append(f.apply(f.shape(hcyl(0.022, 0.86, (0, 0.0, bar_z), verts=8), round_edges=False), "metal"))
    for s in (-1, 1):
        # Up-swept ends with rubber grips.
        parts.append(f.apply(rod((s * 0.42, 0, bar_z), (s * 0.48, -0.02, bar_z + 0.12), 0.022, 8), "metal"))
        parts.append(f.apply(rod((s * 0.47, -0.017, bar_z + 0.1), (s * 0.5, -0.025, bar_z + 0.24), 0.03, 8),
                             "tire"))
        parts.append(f.apply(f.shape(beam((s * 0.1, 0, bar_z - 0.02), (s * 0.24, 0, bar_z), 0.03, 0.03)),
                             "metal"))
    # Throttle lever on the right grip.
    parts.append(f.apply(beam((0.44, -0.05, bar_z + 0.12), (0.46, -0.05, bar_z + 0.22), 0.012, 0.025), "paint_red"))
    # Engine: red shroud on top of the gearbox, finned cylinder, fuel tank, starter and muffler.
    ez = 1.02
    parts.append(f.apply(f.shape(box((0.28, 0.22, 0.17), (0, 0.0, ez + 0.085))), "paint_red"))
    parts.append(f.apply(f.shape(box((0.22, 0.18, 0.08), (0, 0.0, ez + 0.21))), "paint_red"))
    parts.append(f.apply(cyl(0.022, 0.02, (0.05, 0.0, ez + 0.26), verts=8), "paint_cream", along="z"))
    for i in range(5):  # cooling fins sticking out the right side
        parts.append(f.apply(box((0.07, 0.16, 0.012), (0.16, -0.01, ez + 0.03 + i * 0.03)), "metal"))
    parts.append(f.apply(f.shape(hcyl(0.07, 0.04, (-0.16, 0.0, ez + 0.1), axis="x", verts=12)), "metal"))
    parts.append(f.apply(hcyl(0.026, 0.03, (-0.19, 0.0, ez + 0.1), axis="x", verts=8), "tire"))
    parts.append(f.apply(beam((-0.21, 0, ez + 0.085), (-0.21, 0, ez + 0.115), 0.02, 0.07), "tire"))
    parts.append(f.apply(f.shape(hcyl(0.04, 0.16, (0.06, 0.13, ez + 0.07), axis="x", verts=10)), "metal"))
    parts.append(f.apply(rod((0.14, 0.13, ez + 0.07), (0.17, 0.13, ez + 0.07), 0.014, 6), "tire"))
    # Air filter cap on the front.
    parts.append(f.apply(hcyl(0.05, 0.035, (0.0, -0.125, ez + 0.1), axis="y", verts=10), "paint_cream", along="y"))
    return parts


def hay_vacuum_hose(f):
    """Legendary: backpack canister vacuum, about 3 studs tall, with a long ribbed hose,
    steel wand and a wide floor nozzle resting on the ground."""
    parts = []
    cx, cy = -0.32, 0.12
    r, h = 0.19, 0.6
    base = 0.05
    # Canister on a steel base ring with feet.
    parts.append(f.apply(f.shape(cyl(r, h, (cx, cy, base + h / 2), verts=16)), "paint_green", along="z"))
    parts.append(f.apply(f.shape(cyl(r + 0.015, base, (cx, cy, base / 2), verts=16)), "metal", along="z"))
    for z in (base + 0.12, base + h - 0.1):
        parts.append(f.apply(cyl(r + 0.012, 0.03, (cx, cy, z), verts=16), "metal", along="z"))
    # Hay window on the front so you can see the catch.
    parts.append(f.apply(f.shape(box((0.17, 0.04, 0.2), (cx, cy - r + 0.005, base + 0.32))), "metal"))
    parts.append(f.apply(box((0.13, 0.04, 0.16), (cx, cy - r - 0.006, base + 0.32)), "hay"))
    # Motor cap: domed lid, vent fins and a carry handle.
    lid_z = base + h
    parts.append(f.apply(f.shape(cyl(r + 0.01, 0.06, (cx, cy, lid_z + 0.03), verts=16)), "metal", along="z"))
    parts.append(f.apply(f.shape(cyl(r * 0.75, 0.08, (cx, cy, lid_z + 0.1), verts=16)), "paint_cream", along="z"))
    for i in range(4):
        ang = math.pi / 4 + i * math.pi / 2
        x, y = cx + math.cos(ang) * r * 0.62, cy + math.sin(ang) * r * 0.62
        parts.append(f.apply(box((0.03, 0.03, 0.04), (x, y, lid_z + 0.16)), "tire"))
    parts.append(f.apply(cyl(0.05, 0.05, (cx, cy, lid_z + 0.165), verts=10), "paint_red", along="z"))
    parts.append(f.apply(tube([(cx - 0.1, cy, lid_z + 0.14), (cx - 0.08, cy, lid_z + 0.24),
                               (cx + 0.08, cy, lid_z + 0.24), (cx + 0.1, cy, lid_z + 0.14)], 0.015, 6),
                         "metal"))
    # Backpack straps on the back (+y) and a steel frame.
    for s in (-1, 1):
        x = cx + s * 0.08
        parts.append(f.apply(tube([(x, cy + r - 0.02, lid_z - 0.02), (x, cy + r + 0.08, lid_z - 0.12),
                                   (x, cy + r + 0.08, base + 0.2), (x, cy + r - 0.02, base + 0.1)],
                                  lambda t: 0.018, 6), "cloth"))
        parts.append(f.apply(beam((x + s * 0.04, cy + r + 0.01, base), (x + s * 0.04, cy + r + 0.01, lid_z),
                                  0.025, 0.025), "metal"))
    # Hose outlet on the right side.
    out_z = base + h - 0.12
    ox = cx + r
    parts.append(f.apply(f.shape(hcyl(0.055, 0.08, (ox + 0.03, cy, out_z), axis="x", verts=10)), "metal"))
    # Ribbed hose: a smooth curve from the outlet up, over and down to the wand.
    ctrl = [(ox + 0.06, cy, out_z), (ox + 0.25, cy, out_z + 0.12), (ox + 0.5, cy - 0.05, out_z + 0.1),
            (ox + 0.62, cy - 0.25, out_z - 0.1), (ox + 0.5, cy - 0.45, out_z - 0.3),
            (ox + 0.25, cy - 0.5, out_z - 0.35)]
    pts = catmull(ctrl, 36)
    ribs = 40
    hose = tube(pts, lambda t: 0.038 + 0.012 * (0.5 + 0.5 * math.cos(t * TAU * ribs)), sides=8, name="hose")
    parts.append(f.apply(hose, "tire", along="x"))
    # Hose cuffs at both ends.
    parts.append(f.apply(rod(Vector(pts[0]) - Vector((0.02, 0, 0)), pts[1], 0.052, 10), "paint_red"))
    end = Vector(ctrl[-1])
    wand_end = Vector((ox + 0.05, cy - 0.62, 0.05))
    d = (wand_end - end).normalized()
    parts.append(f.apply(rod(end - d * 0.05, end + d * 0.06, 0.05, 10), "paint_red"))
    # Steel wand down to the nozzle, with a grip.
    parts.append(f.apply(rod(end + d * 0.05, wand_end, 0.026, 8), "metal"))
    g0 = end + d * 0.08
    parts.append(f.apply(rod(g0, g0 + d * 0.1, 0.034, 8), "tire"))
    # Wide floor nozzle across x, lying on the ground with a slot mouth at the front.
    nx, ny = wand_end.x, wand_end.y
    parts.append(f.apply(f.shape(box((0.42, 0.11, 0.05), (nx, ny, 0.035))), "metal"))
    parts.append(f.apply(f.shape(box((0.36, 0.08, 0.035), (nx, ny + 0.01, 0.075))), "paint_red"))
    parts.append(f.apply(box((0.38, 0.012, 0.02), (nx, ny - 0.058, 0.02)), "tire"))
    parts.append(f.apply(cyl(0.04, 0.05, (nx, ny + 0.01, 0.105), verts=10), "metal", along="z"))
    for s in (-1, 1):
        parts.append(f.apply(hcyl(0.025, 0.02, (nx + s * 0.2, ny + 0.03, 0.025), axis="x", verts=8), "tire"))
    return parts


def catmull(ctrl, per_seg):
    """Catmull-Rom points through ctrl."""
    c = [Vector(p) for p in ctrl]
    c = [c[0] * 2 - c[1]] + c + [c[-1] * 2 - c[-2]]
    out = []
    for i in range(1, len(c) - 2):
        p0, p1, p2, p3 = c[i - 1], c[i], c[i + 1], c[i + 2]
        for j in range(per_seg):
            t = j / per_seg
            t2, t3 = t * t, t * t * t
            out.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(c[-2])
    return out


PROPS = {
    "steel_fork": steel_fork,
    "needle_tweezers": needle_tweezers,
    "silver_sieve_net": silver_sieve_net,
    "magnet_wand": magnet_wand,
    "barrel_auger": barrel_auger,
    "hay_vacuum_hose": hay_vacuum_hose,
}

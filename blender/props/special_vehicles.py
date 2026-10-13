"""Special vehicles: quest trucks and the big boats (Robux trucks are paint skins of the cash trucks).

Same house style and rules as vehicles.py (whose helpers this module reuses): sizes in studs,
builders face -y with wheels on the ground at z=0, the export turns them to face +y and splits
wheels, tailgates, ramps and propellers into their own meshes (lib/rig.py).

Every truck bed is a clean vehicles.cargo_bed(): floor top at 3.5, interior n*4.6+0.8 long x 10.2
wide (3 bales across), walls >= 2.6, tailgate tagged.
The exporter keeps 4 materials per body (1 per moving part), so each prop sticks to ~4 kinds.

  Quest trucks (earned, never sold)
    old_bessie          restored 1940s farm pickup, rounded fenders, wooden bed 4 x 3 bales (12)
    sandrunner          lifted desert off-road pickup, knobby tires, roll bar, bed 3 x 3
    ghost_hauler        pale ghostly hauler, glowing lamps, tattered cloth, bed 5 x 3 x 2
  Boats (bow at -y before the flip)
    captains_barge      private ferry for 2 trucks, 24 x 70 deck, bow ramp
    public_ferry        ferry for 6 trucks with trailers, 42 x 110 deck, bow and stern ramps
    zeppelin            sky island airship: cloth envelope, gondola, two propellers

Run through rustic_props.py:
  python blender/props/rustic_props.py --out <dir> --category special_vehicles
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
from rig import tag, wheel_uid  # noqa: E402
from style import box  # noqa: E402
from vehicles import (B, BEDS, C, FLOOR, PI, STUD, WALL_T, bed_len, beam, bed_support, cargo_bed, flat,  # noqa: E402
                      mesh_obj, mud_flaps, place, plank_lines, ring, s, taillights, tire, truck_with_bed)


# ---------------------------------------------------------------- shape helpers (studs)

def _recalc(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    return o


def half_ell(f, kind, a, b, depth, loc, axis="y", n=10, along=None, rounded=False):
    """Solid half-ellipse (flat bottom at loc z) extruded along `axis`: a is the horizontal
    half-width across the axis, b the height. Rounded fenders, hoods and roofs."""
    m = n + 1
    prof = [(a * math.cos(PI * i / n), b * math.sin(PI * i / n)) for i in range(m)]
    verts = []
    for d in (-depth / 2, depth / 2):
        for h, z in prof:
            p = (h, d, z) if axis == "y" else (d, h, z)
            verts.append(Vector(s(p[0] + loc[0], p[1] + loc[1], p[2] + loc[2])))
    faces = [(i, i + 1, m + i + 1, m + i) for i in range(n)]
    faces += [(n, 0, m, m + n), tuple(range(m)), tuple(range(2 * m - 1, m - 1, -1))]
    o = _recalc(mesh_obj(verts, faces, "half"))
    return f.apply(f.shape(o, round_edges=rounded), kind, along=along or axis)


def xform(o, M):
    """Bake M (meters) into a part built at the origin."""
    o.data.transform(M @ o.matrix_basis)
    o.matrix_basis = Matrix.Identity(4)
    return o


def wheel(f, x, y, r, w, hub="metal", tread=False):
    """vehicles.tire() plus optional knobby tread blocks in the same rigged wheel group."""
    parts = tire(f, x, y, r, w, hub=hub)
    extra = []
    if tread:
        for i in range(10):
            a = 2 * PI * i / 10
            o = box(s(w + 0.1, 0.5, 0.3), (0, 0, 0))
            M = Matrix.Translation(Vector(s(x, y, r))) @ Matrix.Rotation(a, 4, "X") @ \
                Matrix.Translation(Vector(s(0, 0, r - 0.1)))
            extra.append(f.apply(f.shape(xform(o, M), round_edges=False), "tire"))
    return parts + tag(extra, "wheel", wheel_uid(x, y))


# ---------------------------------------------------------------- truck fronts

def classic_front(f, paint, k=1.5, wide=0.95, wheel_r=1.5, hood_d=3.0, rear_len=16.0, rear_axles=None,
                  trim="steel", lens="paint_cream", roof=None, hub="metal"):
    """Rounded 1940s/50s pickup front: domed hood, vertical grille, pontoon fenders with bucket
    headlights, running boards, a cab with a rounded roof and split windshield.
    Returns (parts, info) like vehicles.truck()."""
    parts = []
    W, CH, CD = 5.6 * k * wide, 4.6 * k, 4.0 * k
    HW, HH, HD = 4.4 * k * wide, 2.3 * k, hood_d * k
    tw = 0.9 * k
    fz = wheel_r * 1.25
    total = HD + CD + rear_len
    yF = -total / 2
    yc0 = yF + HD
    yc1 = yc0 + CD
    yR = total / 2
    wx = W / 2 - 0.15
    yfw = yF + HD * 0.5
    # Frame and a round steel bumper with guards.
    for x in (-1, 1):
        parts.append(B(f, "metal", (0.5, total - 0.4, 0.6), (x * W * 0.28, 0.1, fz - 0.3), along="y"))
    parts.append(C(f, trim, 0.34, W + 0.5, (0, yF - 0.5, fz - 0.25), axis="x", verts=10))
    for x in (-1, 1):
        parts.append(B(f, trim, (0.3, 0.3, 1.0), (x * 1.5, yF - 0.75, fz + 0.05), along="z", rounded=False))
        parts.append(B(f, "metal", (0.25, 0.8, 0.25), (x * 1.5, yF - 0.25, fz - 0.25), along="y", rounded=False))
    # Domed hood with a tall vertical grille and an ornament.
    parts.append(B(f, paint, (HW, HD, HH * 0.5), (0, yF + HD / 2, fz + HH * 0.25), along="y"))
    parts.append(half_ell(f, paint, HW / 2, HH * 0.5, HD, (0, yF + HD / 2, fz + HH * 0.5), axis="y"))
    parts.append(B(f, "tire", (HW * 0.46, 0.2, HH * 0.82), (0, yF - 0.05, fz + HH * 0.47)))
    for i in range(-3, 4):
        parts.append(B(f, trim, (0.15, 0.24, HH * 0.8), (i * HW * 0.065, yF - 0.13, fz + HH * 0.47), along="z",
                       rounded=False))
    parts.append(B(f, trim, (HW * 0.5, 0.26, 0.2), (0, yF - 0.13, fz + HH * 0.88), rounded=False))
    parts.append(B(f, trim, (0.18, 1.2, 0.3), (0, yF + 0.6, fz + HH + 0.05), along="y", rounded=False))
    # Pontoon fenders, bucket headlights, running boards.
    fb, fa, fh = wheel_r * 0.95, wheel_r * 1.6, wheel_r * 1.1
    for x in (-1, 1):
        parts.append(half_ell(f, paint, fa, fh, tw + 0.5, (x * wx, yfw + 0.2, fb), axis="x"))
        ly, lz = yfw - fa * 0.55, fb + fh * 0.85 + 0.25
        parts.append(C(f, paint, 0.55 * k * 0.8, 1.0, (x * wx * 0.92, ly, lz), axis="y", verts=10))
        parts.append(C(f, trim, 0.62 * k * 0.8, 0.15, (x * wx * 0.92, ly - 0.5, lz), axis="y", verts=10,
                       rounded=False))
        parts.append(C(f, lens, 0.48 * k * 0.8, 0.15, (x * wx * 0.92, ly - 0.56, lz), axis="y", verts=10,
                       rounded=False))
        rb0, rb1 = yfw + fa * 0.8, yc1 + 0.2
        parts.append(B(f, "tire", (tw + 0.3, rb1 - rb0, 0.25), (x * wx, (rb0 + rb1) / 2, fb + 0.12), along="y"))
        parts.append(beam(f, paint, (x * wx, yfw + fa * 0.6, fb + fh * 0.75), (x * wx, rb0 + 0.6, fb + 0.25),
                          tw + 0.4, along="y"))
    # Cab: lower body, slimmer greenhouse, rounded roof.
    ycab = (yc0 + yc1) / 2
    GW, GD = W - 0.4, CD - 0.6
    yg = ycab + 0.15
    parts.append(B(f, paint, (W, CD, CH * 0.55), (0, ycab, fz + CH * 0.275), along="y"))
    parts.append(B(f, paint, (GW, GD, CH * 0.33), (0, yg, fz + CH * 0.715), along="y"))
    parts.append(half_ell(f, roof or paint, GW / 2, 0.55 * k, GD, (0, yg, fz + CH * 0.88), axis="y"))
    zw = fz + CH * 0.72
    yw = yg - GD / 2 - 0.04
    parts.append(B(f, "glass", (GW - 0.6, 0.12, CH * 0.25), (0, yw, zw), rounded=False))
    parts.append(B(f, trim, (0.16, 0.16, CH * 0.26), (0, yw - 0.03, zw), along="z", rounded=False))
    parts.append(B(f, "glass", (GW * 0.45, 0.12, CH * 0.18), (0, yg + GD / 2 + 0.04, zw), rounded=False))
    for x in (-1, 1):
        parts.append(B(f, "glass", (0.12, GD * 0.62, CH * 0.24), (x * (GW / 2 + 0.04), yg - GD * 0.1, zw),
                       along="y", rounded=False))
        parts.append(B(f, trim, (0.08, CD, 0.15), (x * (W / 2 + 0.03), ycab, fz + CH * 0.5), along="y",
                       rounded=False))
        parts.append(B(f, "metal", (0.1, 0.12, CH * 0.5), (x * (W / 2 + 0.03), yc1 - CD * 0.15, fz + CH * 0.28),
                       along="z", rounded=False))
        parts.append(B(f, trim, (0.14, 0.5, 0.14), (x * (W / 2 + 0.06), yc1 - CD * 0.3, fz + CH * 0.45),
                       along="y", rounded=False))
        parts.append(B(f, trim, (0.7, 0.12, 0.12), (x * (W / 2 + 0.35), yc0 + 0.3, fz + CH * 0.6), rounded=False))
        parts.append(C(f, trim, 0.3, 0.12, (x * (W / 2 + 0.75), yc0 + 0.3, fz + CH * 0.62), axis="y", verts=8,
                       rounded=False))
    # Wheels.
    parts += wheel(f, -wx, yfw, wheel_r, tw, hub=hub)
    parts += wheel(f, wx, yfw, wheel_r, tw, hub=hub)
    rear_axles = rear_axles or [yR - wheel_r * 1.8]
    for y in rear_axles:
        parts.append(C(f, "metal", 0.25, W - 0.5, (0, y, wheel_r), axis="x", verts=8))
        for x in (-1, 1):
            parts += wheel(f, x * wx, y, wheel_r, tw, hub=hub)
    info = dict(W=W, CH=CH, fz=fz, yF=yF, yc0=yc0, yc1=yc1, yR=yR, wheel_r=wheel_r, k=k, wx=wx, tw=tw,
                axles=rear_axles, HH=HH, HD=HD)
    return parts, info


def lifted_front(f, paint, k=1.4, wide=1.0, wheel_r=1.55, tw=1.35, fz=3.2, hood_d=3.0, rear_len=16.0,
                 rear_axles=None, trim="metal", flare="tire", shock="paint_yellow", lens="paint_cream"):
    """Lifted off-road front: square hood and cab riding high over knobby tires, fender flares,
    exposed axles with coil-over shocks, a skid plate and a tube bull bar.
    The bed floor stays at 3.5 (the dock height), so the lift shows in the cab, not the bed."""
    parts = []
    W, CH, CD = 5.6 * k * wide, 4.6 * k, 4.4 * k
    HW, HH, HD = 5.2 * k * wide, 2.0 * k, hood_d * k
    total = HD + CD + rear_len
    yF = -total / 2
    yc0 = yF + HD
    yc1 = yc0 + CD
    yR = total / 2
    wx = W / 2 - 0.15
    yfw = yF + HD * 0.5
    ycab = (yc0 + yc1) / 2
    for x in (-1, 1):
        parts.append(B(f, "metal", (0.5, total - 0.4, 0.6), (x * W * 0.28, 0.1, fz - 0.3), along="y"))
    # Bull bar, bumper, winch, skid plate.
    parts.append(B(f, "metal", (W + 0.2, 0.6, 0.7), (0, yF - 0.3, fz - 0.1)))
    parts.append(B(f, "metal", (1.4, 0.6, 0.6), (0, yF - 0.75, fz - 0.1)))
    for x in (-1, 1):
        parts.append(beam(f, trim, (x * HW * 0.35, yF - 0.6, fz + 0.2), (x * HW * 0.35, yF - 0.9, fz + HH * 0.8),
                          0.3))
    parts.append(beam(f, trim, (-HW * 0.35, yF - 0.9, fz + HH * 0.8), (HW * 0.35, yF - 0.9, fz + HH * 0.8), 0.3))
    parts.append(B(f, "metal", (W * 0.55, HD + 1.0, 0.2), (0, yF + HD / 2, fz - 0.9), along="y", rounded=False))
    # Hood, grille, square lamps.
    parts.append(B(f, paint, (HW, HD, HH), (0, yF + HD / 2, fz + HH / 2), along="y"))
    parts.append(B(f, "tire", (HW * 0.55, 0.2, HH * 0.6), (0, yF - 0.05, fz + HH * 0.5)))
    for i in range(5):
        parts.append(B(f, trim, (0.18, 0.25, HH * 0.6), ((i - 2) * HW * 0.11, yF - 0.1, fz + HH * 0.5),
                       along="z", rounded=False))
    for x in (-1, 1):
        parts.append(B(f, trim, (1.0, 0.25, 0.8), (x * HW * 0.39, yF - 0.08, fz + HH * 0.55), rounded=False))
        parts.append(B(f, lens, (0.75, 0.25, 0.55), (x * HW * 0.39, yF - 0.13, fz + HH * 0.55), rounded=False))
    # Cab.
    parts.append(B(f, paint, (W, CD, CH), (0, ycab, fz + CH / 2), along="y"))
    parts.append(B(f, paint, (W - 0.3, CD - 0.4, 0.3), (0, ycab, fz + CH + 0.1), along="y"))
    zw = fz + CH * 0.73
    parts.append(B(f, "glass", (W - 0.9, 0.12, CH * 0.34), (0, yc0 - 0.04, zw), rounded=False))
    parts.append(B(f, "glass", (W * 0.62, 0.12, CH * 0.26), (0, yc1 + 0.04, zw), rounded=False))
    for x in (-1, 1):
        parts.append(B(f, "glass", (0.12, CD * 0.5, CH * 0.3), (x * (W / 2 + 0.04), yc0 + CD * 0.36, zw),
                       along="y", rounded=False))
        parts.append(B(f, "metal", (0.1, 0.12, CH * 0.55), (x * (W / 2 + 0.03), yc1 - CD * 0.18, fz + CH * 0.42),
                       along="z", rounded=False))
        parts.append(B(f, "metal", (0.14, 0.5, 0.14), (x * (W / 2 + 0.06), yc1 - CD * 0.32, fz + CH * 0.5),
                       along="y", rounded=False))
        parts.append(B(f, "metal", (0.9, 0.12, 0.12), (x * (W / 2 + 0.45), yc0 + 0.3, fz + CH * 0.7),
                       rounded=False))
        parts.append(B(f, "metal", (0.18, 0.45, 1.0), (x * (W / 2 + 0.9), yc0 + 0.3, fz + CH * 0.7), along="z",
                       rounded=False))
        # Rock slider step and a snorkel on the right.
        parts.append(B(f, "metal", (0.5, CD * 0.9, 0.35), (x * (W / 2 + 0.2), ycab, fz - 0.45), along="y"))
    parts.append(B(f, "tire", (0.45, 0.45, CH), (W / 2 + 0.25, yc0 + 0.3, fz + CH / 2 + 0.2), along="z",
                   rounded=False))
    parts.append(B(f, "tire", (0.5, 0.9, 0.5), (W / 2 + 0.25, yc0 + 0.1, fz + CH + 0.4), along="y",
                   rounded=False))
    # Axles, shocks, wheels; flares over the front wheels.
    rear_axles = rear_axles or [yR - wheel_r * 1.8]
    for y in [yfw] + rear_axles:
        parts.append(C(f, "metal", 0.3, 2 * wx - tw, (0, y, wheel_r), axis="x", verts=8))
        parts.append(C(f, "metal", 0.65, 0.9, (0, y, wheel_r), axis="y", verts=10))
        for x in (-1, 1):
            sx = x * (wx - tw / 2 - 0.35)
            top = fz - 0.2
            parts.append(C(f, shock, 0.28, top - wheel_r, (sx, y + 0.5, (top + wheel_r) / 2), verts=8,
                           rounded=False))
            parts.append(C(f, "metal", 0.12, top - wheel_r + 0.4, (sx, y + 0.5, (top + wheel_r) / 2), verts=6,
                           rounded=False))
            parts += wheel(f, x * wx, y, wheel_r, tw, tread=True)
    for x in (-1, 1):
        parts.append(B(f, flare, (tw + 0.7, wheel_r * 2.7, 0.35), (x * wx, yfw, fz + 0.15), along="y"))
        for d in (-1, 1):
            parts.append(B(f, flare, (tw + 0.7, 0.35, 1.0), (x * wx, yfw + d * wheel_r * 1.35, fz - 0.35),
                           along="z"))
    info = dict(W=W, CH=CH, fz=fz, yF=yF, yc0=yc0, yc1=yc1, yR=yR, wheel_r=wheel_r, k=k, wx=wx, tw=tw,
                axles=rear_axles, HH=HH, HD=HD)
    return parts, info


def bed_layout(front, f, paint, nl, gap=0.4, axle=0.3, **kw):
    """Run a front builder sized for a bed of nl bales long; returns (parts, info, yc, Lo)."""
    Lo = bed_len(nl) + 2 * WALL_T
    rear_len = gap + Lo + 0.2
    hood_d = kw.get("hood_d", 3.0)
    k = kw.get("k", 1.4)
    cd = 4.0 if front is classic_front else 4.4
    yR = (hood_d * k + cd * k + rear_len) / 2
    parts, i = front(f, paint, rear_len=rear_len, rear_axles=[yR - Lo * axle], **kw)
    return parts, i, i["yc1"] + gap + Lo / 2, Lo


# ---------------------------------------------------------------- quest trucks

def old_bessie(f):
    """Old Bessie (quest): restored 1940s farm pickup, farm blue with cream hubs and steel trim,
    domed hood, pontoon fenders, wooden stake bed for 4 long x 3 wide bales (12). About 11 x 9 x 31."""
    wall_h = 2.8
    parts, i, yc, Lo = bed_layout(classic_front, f, "paint_blue", 4, k=1.5, wide=0.95, wheel_r=1.5, hood_d=3.0,
                                  hub="paint_cream", axle=0.32)
    bed, Lo, Wo = cargo_bed(f, "old_bessie", 4, 3, wall_h, yc, floor="handle", wall="handle")
    parts += bed + bed_support(f, i, yc, Lo) + plank_lines(f, "handle", Lo, Wo, yc, wall_h, n=3)
    # Blue rail caps and corner stakes.
    for x in (-1, 1):
        parts.append(flat(f, "paint_blue", (0.45, Lo, 0.2), (x * (Wo / 2 - 0.1), yc, FLOOR + wall_h + 0.1),
                          along="y"))
        for n in range(4):
            y = yc - Lo / 2 + 0.25 + n * (Lo - 0.5) / 3
            parts.append(B(f, "paint_blue", (0.3, 0.35, wall_h + 0.6), (x * (Wo / 2 + 0.15), y,
                                                                        FLOOR + wall_h / 2 - 0.1), along="z"))
    # Rear pontoon fenders on the bed sides over the axle, rear bumper, round taillights.
    ya = i["axles"][0]
    for x in (-1, 1):
        parts.append(half_ell(f, "paint_blue", 2.3, 1.9, 0.5, (x * (Wo / 2 + 0.05), ya, 1.6), axis="x"))
        parts.append(C(f, "paint_red", 0.3, 0.2, (x * (Wo / 2 - 0.6), yc + Lo / 2 + 0.1, FLOOR - 0.5), axis="y",
                       verts=8, rounded=False))
    parts.append(C(f, "steel", 0.3, Wo - 0.8, (0, i["yR"] + 0.1, i["fz"] - 0.2), axis="x", verts=10))
    return parts


def sandrunner(f):
    """Sandrunner (quest): lifted desert off-road pickup in sand yellow with dirt splashes,
    knobby tires, coil-over shocks, roll bar with lamps; bed 3 long x 3 wide bales. About 11 x 10 x 28."""
    wall_h = 3.2
    parts, i, yc, Lo = bed_layout(lifted_front, f, "paint_yellow", 3, gap=1.0, k=1.4, wide=1.0, hood_d=3.0,
                                  flare="dirt", shock="paint_red")
    bed, Lo, Wo = cargo_bed(f, "sandrunner", 3, 3, wall_h, yc, floor="metal", wall="paint_yellow")
    parts += bed + mud_flaps(f, i, Wo)
    # Dirt splash band along the lower bed and cab sides.
    for x in (-1, 1):
        parts.append(flat(f, "dirt", (0.08, Lo, 0.9), (x * (Wo / 2 + 0.04), yc, FLOOR + 0.45), along="y"))
        parts.append(flat(f, "dirt", (0.08, i["yc1"] - i["yc0"], 0.8), (x * (i["W"] / 2 + 0.04),
                                                                        (i["yc0"] + i["yc1"]) / 2,
                                                                        i["fz"] + 0.4), along="y"))
        parts.append(flat(f, "metal", (0.4, Lo, 0.15), (x * (Wo / 2 - 0.15), yc, FLOOR + wall_h + 0.07), along="y"))
    # Roll bar over the bed's front wall, with four lamps.
    yf = yc - Lo / 2 - 0.4
    top = FLOOR + wall_h + 2.0
    for x in (-1, 1):
        parts.append(C(f, "metal", 0.22, top - FLOOR + 0.3, (x * (Wo / 2 - 0.25), yf, (top + FLOOR) / 2 - 0.15),
                       verts=8, rounded=False))
        parts.append(beam(f, "metal", (x * (Wo / 2 - 0.25), yf, top - 0.4), (x * (Wo / 2 - 0.25), yf + 2.5,
                                                                             FLOOR + wall_h + 0.2), 0.3))
    parts.append(C(f, "metal", 0.22, Wo - 0.3, (0, yf, top), axis="x", verts=8, rounded=False))
    for n in range(4):
        x = (n - 1.5) * 1.6
        parts.append(B(f, "metal", (1.0, 0.5, 0.75), (x, yf - 0.1, top + 0.55), rounded=False))
        parts.append(B(f, "paint_cream", (0.8, 0.12, 0.55), (x, yf - 0.38, top + 0.55), rounded=False))
    parts.append(B(f, "metal", (Wo - 0.6, 0.5, 0.6), (0, i["yR"] - 0.1, i["fz"] - 0.2)))
    parts += taillights(f, dict(i, yR=yc + Lo / 2), FLOOR + 2.4, Wo)
    return parts


def ghost_hauler(f):
    """Ghost Hauler (quest, drives at night): pale washed-out hauler with glowing headlights, hubs
    and stack caps, tattered cloth hanging off the bed and glowing corner lanterns. Bed like the
    heavy hauler: 5 long x 3 wide x 2 high bales. About 12 x 10 x 36."""
    k, wall_h = 1.2, 5.4
    parts, i, yc = truck_with_bed(f, "ghost_hauler", "paint_cream", 5, wall_h, k=k, wide=1.35, wheel_r=1.5,
                                  gap=1.3, dual=True, stacks=True, tanks=True, axles=[2.2, 5.6], glow=True,
                                  trim="steel")
    bed, Lo, Wo = cargo_bed(f, "ghost_hauler", 5, 3, wall_h, yc, floor="handle", wall="paint_cream", layers=2)
    parts += bed + bed_support(f, i, yc, Lo) + mud_flaps(f, i, Wo) + plank_lines(f, "steel", Lo, Wo, yc, wall_h)
    # Tattered cloth strips of uneven length hanging from the top rails.
    lens = (2.4, 3.6, 1.6, 4.2, 2.8, 1.9, 3.9, 2.2, 3.1)
    top = FLOOR + wall_h
    for x in (-1, 1):
        parts.append(flat(f, "steel", (0.3, Lo + 0.2, 0.3), (x * (Wo / 2 + 0.1), yc, top + 0.15), along="y"))
        for n, ln in enumerate(lens):
            ln = lens[(n * 3 + (x > 0) * 4) % len(lens)]
            y = yc - Lo / 2 + 1.0 + n * (Lo - 2.0) / (len(lens) - 1)
            parts.append(flat(f, "cloth", (0.06, 1.7, ln), (x * (Wo / 2 + 0.3), y, top - ln / 2), along="z"))
    for ln, x in zip((2.0, 3.2, 1.4, 2.6), (-3.6, -1.2, 1.2, 3.6)):
        parts.append(flat(f, "cloth", (2.0, 0.06, ln), (x, yc + Lo / 2 + 0.25, top - ln / 2), along="z"))
    # Lanterns on posts at the four top corners.
    for x in (-1, 1):
        for y in (yc - Lo / 2, yc + Lo / 2):
            parts.append(B(f, "metal", (0.2, 0.2, 0.6), (x * (Wo / 2 + 0.1), y, top + 0.4), along="z",
                           rounded=False))
            parts.append(B(f, "metal", (0.6, 0.6, 0.12), (x * (Wo / 2 + 0.1), y, top + 0.95), rounded=False))
            parts.append(B(f, "glow", (0.45, 0.45, 0.6), (x * (Wo / 2 + 0.1), y, top + 1.3), rounded=False))
            parts.append(B(f, "metal", (0.6, 0.6, 0.12), (x * (Wo / 2 + 0.1), y, top + 1.65), rounded=False))
    # Ghostly glowing strip under the cab and a pale roof lamp.
    parts.append(B(f, "glow", (i["W"] - 1.0, 0.3, 0.3), (0, i["yc1"] - 0.6, i["fz"] + i["CH"] + 0.45),
                   rounded=False))
    parts.append(B(f, "metal", (i["W"], 0.5, 0.6), (0, i["yR"] - 0.1, i["fz"] - 0.3)))
    parts += taillights(f, dict(i, yR=yc + Lo / 2), FLOOR - 0.5, Wo)
    return parts


# ---------------------------------------------------------------- boats

def barge_hull(f, W, L, H, kind="metal", rake=0.9):
    """Box hull with raked ends under the waterline (studs), deck top at H."""
    hb = box(s(W, L, H), s(0, 0, H / 2))
    for v in hb.data.vertices:
        if v.co.z < 0:
            v.co.y *= rake
    return f.apply(f.shape(hb), kind, along="y")


def rail(f, kind, p0, p1, h=1.6, step=6.0, post="metal"):
    """Posts and two rails between two deck points (studs), rails along the segment."""
    parts = []
    a, b = Vector(p0), Vector(p1)
    n = max(1, round((b - a).length / step))
    for j in range(n + 1):
        p = a + (b - a) * (j / n)
        parts.append(B(f, post, (0.25, 0.25, h), (p.x, p.y, p.z + h / 2), along="z", rounded=False))
    for z in (h * 0.5, h):
        parts.append(beam(f, kind, (a.x, a.y, a.z + z), (b.x, b.y, b.z + z), 0.2))
    return parts


def ramp(f, name, width, height, y, z, d):
    """A stowed (upright) loading ramp at the bow (d=-1) or stern (d=+1): steel plate with yellow
    chevrons on the deck side and hinge knuckles at the bottom. Tagged `name`."""
    parts = [flat(f, "metal", (width, 0.6, height), (0, y, z + height / 2))]
    for n in range(4):
        parts.append(flat(f, "paint_yellow", (width - 1.0, 0.1, 0.35), (0, y - d * 0.33, z + 1.2 + n * height / 4.6)))
    for x in (-1, 1):
        parts.append(flat(f, "metal", (0.5, 0.8, height), (x * (width / 2 - 0.25), y, z + height / 2)))
        parts.append(C(f, "metal", 0.4, 1.2, (x * (width / 2 - 1.5), y, z + 0.3), axis="x", verts=8, rounded=False))
    return tag(parts, name)


def life_ring(f, x, y, z):
    o = ring(0.9 * STUD, 0.55 * STUD, 0.3 * STUD, n=12)
    return place([f.apply(f.shape(o, round_edges=False), "paint_red")], (x, y, z))


def helm(f, x, y, z):
    """Ship's wheel (decoration, not rigged): wooden rim, spokes and a post."""
    o = ring(0.8 * STUD, 0.62 * STUD, 0.15 * STUD, n=12)
    parts = [f.apply(f.shape(o, round_edges=False), "handle")]
    for j in range(4):
        parts.append(f.apply(f.shape(box(s(0.12, 0.12, 2.2), (0, 0, 0), rot=(PI * j / 4, 0, 0)),
                                     round_edges=False), "handle"))
    parts = place(parts, (x, y, z), rz=PI / 2)
    parts.append(B(f, "handle", (0.3, 0.3, 2.0), (x, y + 0.3, z - 1.0), along="z", rounded=False))
    return parts


def captains_barge(f):
    """Captain's Barge (quest): private ferry for 2 trucks side by side. Steel hull 26 x 80, a clear
    plank deck about 24 wide x 70 long with low rails, a small wheelhouse at the stern with a helm
    and flag, and a bow ramp (tagged Ramp, stowed upright). Deck top 3.0."""
    W, L, H = 26.0, 80.0, 3.0
    parts = [barge_hull(f, W, L, H, rake=0.86)]
    for x in (-1, 1):
        parts.append(B(f, "paint_blue", (0.1, L - 1.0, 0.7), (x * (W / 2 + 0.04), 0, H - 0.55), along="y",
                       rounded=False))
    parts.append(flat(f, "handle", (W - 1.0, L - 1.6, 0.12), (0, 0, H + 0.06), along="y"))
    # Low rails down the sides (open at the bow for the ramp) and around the stern.
    yb, ys = -L / 2 + 0.4, L / 2 - 0.4
    for x in (-1, 1):
        parts += rail(f, "metal", (x * (W / 2 - 0.3), yb + 1.5, H), (x * (W / 2 - 0.3), ys, H), h=1.6, step=8.0)
        for y in (-25, 0, 25):
            parts.append(C(f, "tire", 0.7, 0.7, (x * (W / 2 + 0.4), y, H - 1.2), axis="x", verts=10, rounded=False))
        for y in (yb + 3.0, ys - 12.0):
            parts.append(C(f, "metal", 0.4, 0.9, (x * (W / 2 - 1.3), y, H + 0.45), verts=8, rounded=False))
    parts += rail(f, "metal", (-(W / 2 - 0.3), ys, H), (W / 2 - 0.3, ys, H), h=1.6, step=6.5)
    # Wheelhouse at the stern (y 31..39), the deck ahead of it is clear (about 70 long).
    wy, wl, ww, wh = ys - 4.6, 8.0, 10.0, 6.0
    parts.append(B(f, "paint_cream", (ww, wl, wh), (0, wy, H + wh / 2), along="y"))
    parts.append(B(f, "paint_blue", (ww + 1.0, wl + 1.0, 0.4), (0, wy, H + wh + 0.2), along="y"))
    parts.append(B(f, "glass", (ww - 1.2, 0.12, 1.8), (0, wy - wl / 2 - 0.04, H + wh - 1.6), rounded=False))
    for x in (-1, 1):
        parts.append(B(f, "glass", (0.12, wl - 2.0, 1.6), (x * (ww / 2 + 0.04), wy, H + wh - 1.6), along="y",
                       rounded=False))
    parts.append(B(f, "handle", (2.4, 0.15, 4.4), (ww / 2 - 2.0, wy - wl / 2 - 0.05, H + 2.2), rounded=False))
    parts += helm(f, 0, wy - wl / 2 - 1.0, H + 2.8)
    parts.append(C(f, "metal", 0.6, 2.4, (2.5, wy + 2.0, H + wh + 1.4), verts=10))
    parts.append(C(f, "tire", 0.7, 0.3, (2.5, wy + 2.0, H + wh + 2.6), verts=10, rounded=False))
    parts.append(C(f, "handle", 0.15, 6.0, (-3.0, wy + 2.5, H + wh + 3.2), verts=6, rounded=False))
    parts.append(B(f, "paint_red", (0.08, 2.4, 1.5), (-3.0, wy + 3.8, H + wh + 5.3), along="y", rounded=False))
    parts.append(B(f, "paint_cream", (0.4, 0.4, 0.5), (-3.0, wy + 2.5, H + wh + 6.4), rounded=False))
    parts += life_ring(f, -(ww / 2 + 0.2), wy, H + 3.0)
    # Bow ramp, stowed upright.
    parts += ramp(f, "Ramp", W - 4.0, 8.0, -L / 2 + 0.3, H, -1)
    return parts


def public_ferry(f):
    """Public ferry for 6 trucks with trailers: hull 44 x 116, a 3-lane car deck (lanes 12 wide,
    about 42 x 110 overall with the side walkways) with yellow lane lines, raised side walkways
    with benches and rails, a wheelhouse on a gantry spanning the deck (13 studs of clearance),
    and bow and stern ramps (tagged Ramp and Ramp2, stowed upright). Deck top 4.0."""
    W, L, H = 44.0, 116.0, 4.0
    parts = [barge_hull(f, W, L, H, kind="paint_blue", rake=0.88)]
    parts.append(flat(f, "paint_cream", (0.1, L - 4.0, 1.0), (-(W / 2 + 0.04), 0, H - 0.7), along="y"))
    parts.append(flat(f, "paint_cream", (0.1, L - 4.0, 1.0), (W / 2 + 0.04, 0, H - 0.7), along="y"))
    parts.append(flat(f, "metal", (W - 1.0, L - 2.0, 0.12), (0, 0, H + 0.06), along="y"))
    for x in (-6, 6):
        parts.append(flat(f, "paint_cream", (0.4, L - 22.0, 0.04), (x, 0, H + 0.14), along="y"))
    # Side walkways with outer rails, curbs and benches.
    wx = 20.0
    for x in (-1, 1):
        parts.append(flat(f, "handle", (3.0, L - 14.0, 0.6), (x * wx, 0, H + 0.3), along="y"))
        parts += rail(f, "metal", (x * (W / 2 - 0.4), -L / 2 + 7.0, H + 0.6), (x * (W / 2 - 0.4), L / 2 - 7.0, H + 0.6),
                      h=2.0, step=12.0)
        for y in (-44, -30, -16, 16, 30, 44):
            bx = x * (wx + 0.6)
            parts.append(flat(f, "handle", (1.0, 3.2, 0.2), (bx, y, H + 1.6), along="y"))
            parts.append(flat(f, "handle", (0.15, 3.2, 0.9), (bx + x * 0.5, y, H + 2.15), along="y"))
            for d in (-1, 1):
                parts.append(flat(f, "metal", (0.9, 0.15, 1.0), (bx, y + d * 1.3, H + 1.0)))
        for y in (-36, 36):
            parts += life_ring(f, x * (W / 2 - 0.15), y, H + 2.0)
    # Gantry: two leg frames on the walkways (open between the legs), a bridge across, the wheelhouse.
    gz = H + 13.0
    for x in (-1, 1):
        for y in (-3.0, 3.0):
            parts.append(B(f, "metal", (1.0, 1.0, gz - H), (x * wx, y, (gz + H) / 2), along="z", rounded=False))
        parts.append(flat(f, "metal", (1.0, 7.0, 0.6), (x * wx, 0, H + 9.0), along="y"))
        for n in range(12):
            parts.append(flat(f, "metal", (0.9, 0.15, 0.15), (x * wx, -3.6, H + 1.0 + n * 1.0)))
    parts.append(flat(f, "metal", (W, 7.0, 0.8), (0, 0, gz + 0.4), along="y"))
    for y in (-3.4, 3.4):
        parts.append(beam(f, "metal", (-W / 2 + 0.3, y, gz + 2.0), (W / 2 - 0.3, y, gz + 2.0), 0.2))
    for x in (-21.5, -14, 14, 21.5):
        for y in (-3.4, 3.4):
            parts.append(flat(f, "metal", (0.2, 0.2, 1.2), (x, y, gz + 1.4)))
    cw, cd, ch = 14.0, 6.0, 5.5
    parts.append(B(f, "paint_cream", (cw, cd, ch), (0, 0, gz + 0.8 + ch / 2), along="y"))
    parts.append(flat(f, "paint_blue", (cw + 1.2, cd + 1.2, 0.4), (0, 0, gz + 0.8 + ch + 0.2), along="y"))
    for d in (-1, 1):
        parts.append(flat(f, "glass", (cw - 1.0, 0.12, 1.8), (0, d * (cd / 2 + 0.04), gz + ch - 0.6)))
    for x in (-1, 1):
        parts.append(flat(f, "glass", (0.12, cd - 1.4, 1.6), (x * (cw / 2 + 0.04), 0, gz + ch - 0.6), along="y"))
    parts.append(C(f, "paint_red", 0.9, 3.0, (4.0, 1.2, gz + ch + 2.4), verts=10, rounded=False))
    parts.append(C(f, "tire", 0.95, 0.3, (4.0, 1.2, gz + ch + 3.9), verts=10, rounded=False))
    # Bollards on deck corners.
    for x in (-1, 1):
        for y in (-L / 2 + 4.0, L / 2 - 4.0):
            parts.append(C(f, "metal", 0.45, 1.0, (x * (W / 2 - 2.0), y, H + 0.5), verts=8, rounded=False))
    # Ramps.
    parts += ramp(f, "Ramp", 36.0, 9.0, -L / 2 + 0.3, H, -1)
    parts += ramp(f, "Ramp2", 36.0, 9.0, L / 2 - 0.3, H, 1)
    return parts


def env_r(R, L2, y):
    return R * math.sqrt(max(0.0, 1 - (y / L2) ** 2))


def propeller(f, x, y, z, uid, r=2.4):
    """Three wooden blades and a steel hub, spinning about y. Tagged Propeller."""
    parts = [C(f, "steel", 0.4, 0.7, (x, y, z), axis="y", verts=8, rounded=False)]
    for j in range(3):
        o = box(s(0.6, 0.15, r), (0, 0, 0))
        M = Matrix.Translation(Vector(s(x, y, z))) @ Matrix.Rotation(2 * PI * j / 3, 4, "Y") @ \
            Matrix.Rotation(0.3, 4, "Z") @ Matrix.Translation(Vector(s(0, 0, r / 2 + 0.2)))
        parts.append(f.apply(f.shape(xform(o, M), round_edges=False), "handle", along="z"))
    return tag(parts, "Propeller", uid)


def zeppelin(f):
    """Sky island zeppelin: weathered cloth envelope 60 long x 18 across with red bands, nose cap
    and four tail fins, hung on ropes over a wooden gondola (8 x 18 x 5, windows, rear lookout deck,
    landing skids); two engine pods on outriggers with propellers (tagged Propeller). About 19 x 28 x 60."""
    parts = []
    R, L2, zc = 9.0, 30.0, 19.0
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=1.0, rotation=(PI / 2, 0, 0))
    env = bpy.context.active_object
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    for v in env.data.vertices:
        v.co = Vector(s(v.co.x * R, v.co.y * L2, v.co.z * R + zc))
    parts.append(f.apply(f.shape(env, round_edges=False), "cloth", along="y"))
    for y in (-18.0, 0.0, 18.0):
        r = env_r(R, L2, y) + 0.06
        o = ring(r * STUD, (r - 0.5) * STUD, 0.8 * STUD, n=16)
        parts += place([f.apply(f.shape(o, round_edges=False), "paint_red")], (0, y, zc), rz=PI / 2)
    parts.append(C(f, "steel", 0.9, 0.8, (0, -L2 + 0.1, zc), axis="y", verts=10, rounded=False))
    # Tail fins (top, bottom, sides) near the stern (+y).
    fy, fl = 24.0, 7.0
    er = env_r(R, L2, fy)
    parts.append(B(f, "paint_red", (0.3, fl, 4.5), (0, fy, zc + er + 1.6), along="y", rounded=False))
    parts.append(B(f, "paint_red", (0.3, fl, 4.0), (0, fy, zc - er - 1.3), along="y", rounded=False))
    for x in (-1, 1):
        parts.append(B(f, "paint_red", (4.5, fl, 0.3), (x * (er + 1.6), fy, zc), along="y", rounded=False))
    # Gondola with windows, roof and rear lookout deck, on skids.
    gz, gh, gw, gl, gy = 1.0, 5.0, 8.0, 18.0, -2.0
    parts.append(B(f, "handle", (gw, gl, gh), (0, gy, gz + gh / 2), along="y"))
    parts.append(B(f, "paint_cream", (gw + 0.6, gl + 0.6, 0.4), (0, gy, gz + gh + 0.2), along="y"))
    parts.append(C(f, "handle", gw / 2, gh, (0, gy - gl / 2, gz + gh / 2), verts=12))
    for x in (-1, 1):
        parts.append(B(f, "glass", (0.12, gl - 4.0, 1.4), (x * (gw / 2 + 0.04), gy - 0.5, gz + gh - 1.6), along="y",
                       rounded=False))
        for n in range(5):
            parts.append(B(f, "handle", (0.2, 0.3, 1.5), (x * (gw / 2 + 0.08), gy - gl / 2 + 2.0 + n * (gl - 4.0) / 4,
                                                          gz + gh - 1.6), along="z", rounded=False))
        parts.append(B(f, "metal", (0.4, gl + 4.0, 0.4), (x * (gw / 2 - 1.0), gy, 0.2), along="y"))
        for y in (gy - 5, gy + 5):
            parts.append(B(f, "metal", (0.3, 0.3, 0.8), (x * (gw / 2 - 1.0), y, 0.6), along="z", rounded=False))
    dy = gy + gl / 2 + 2.0
    parts.append(flat(f, "handle", (gw, 4.0, 0.3), (0, dy, gz + 0.15), along="y"))
    parts += rail(f, "handle", (-gw / 2 + 0.2, dy + 1.9, gz + 0.3), (gw / 2 - 0.2, dy + 1.9, gz + 0.3), h=1.6,
                  step=4.0, post="handle")
    for x in (-1, 1):
        parts += rail(f, "handle", (x * (gw / 2 - 0.2), dy - 1.9, gz + 0.3), (x * (gw / 2 - 0.2), dy + 1.9, gz + 0.3),
                      h=1.6, step=4.0, post="handle")
    # Suspension ropes from the gondola to the envelope.
    for x in (-1, 1):
        for y in (gy - gl / 2 + 1.0, gy, gy + gl / 2 - 1.0, dy + 1.5):
            zt = zc - env_r(R, L2, y) * 0.92
            parts.append(beam(f, "twine", (x * (gw / 2 - 0.3), y, gz + gh + 0.3 if y < dy else gz + 1.9),
                              (x * 3.0, y, zt), 0.15, along="z"))
    # Engine pods on outriggers with propellers at the front.
    py, pz = gy + 1.0, gz + 3.0
    for x in (-1, 1):
        px = x * (gw / 2 + 3.2)
        parts.append(beam(f, "metal", (x * gw / 2, py, pz), (px, py, pz), 0.4))
        parts.append(beam(f, "metal", (x * gw / 2, py, gz + 0.5), (px, py, pz - 0.6), 0.3))
        parts.append(C(f, "metal", 0.9, 3.4, (px, py, pz), axis="y", verts=10))
        parts.append(C(f, "metal", 0.5, 0.6, (px, py + 1.9, pz), axis="y", verts=8, rounded=False))
        parts += propeller(f, px, py - 2.0, pz, "L" if x < 0 else "R")
    # Mooring line coiled at the nose.
    parts.append(beam(f, "twine", (0, -L2 + 0.3, zc - 0.5), (0, -L2 + 3.0, zc - 6.0), 0.12))
    return parts


RIG_FLIP = True  # builders face -y; turn to +y so the glTF faces -Z
BEDS = BEDS  # shared with vehicles.cargo_bed(); the exporter reads it for rigs.json

PROPS = {
    "old_bessie": old_bessie,
    "sandrunner": sandrunner,
    "ghost_hauler": ghost_hauler,
    "captains_barge": captains_barge,
    "public_ferry": public_ferry,
    "zeppelin": zeppelin,
}

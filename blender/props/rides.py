"""Rides and promenade props in the house style (LT2 shapes, Rustic finish).

Built in studs (1 stud = 0.28 m), ground at z = 0. Builders face -y; RIG_FLIP turns them so the .glb faces -Z.
Builder y is the game's Z, so the positions below copy HayWagon.luau / Ferry.luau directly.

  hay_wagon          the free Hay Wagon ride: plank bed and rails, hay heap (HayFill) with a hay bench either side
                     (6 seat dips at x +-2.5), spoked wheels Wheel_L1..R2, "HAY RIDES" Board at the back
  farm_tractor       small vintage green tractor that pulls it; Wheel_L1/R1 front (steer), Wheel_L2/R2 rear
  ferry_snack_stand  ferry promenade snack counter under a striped awning tipped 12 deg; "SNACKS" Sign
  fishing_spot       bait bucket, a leaning rod and a tackle box

Run:
  python blender/props/rustic_props.py --out <dir> --category rides
"""
import math
import os
import sys

import bpy  # noqa: F401  (must be imported before bmesh/mathutils with the pip bpy module)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, HERE)
from rig import tag, wheel_uid  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
from style import box, cyl  # noqa: E402
from vehicles import B, C, PI, STUD, beam, place, ring, s  # noqa: E402
from hub import text  # noqa: E402

RIG_FLIP = True  # builders face -y; turn to +y so the glTF faces -Z


# ---------------------------------------------------------------- helpers (studs)

def wagon_wheel(f, x, y, r, w, kind="bark"):
    """Light wooden wagon wheel (one material): rim, 6 spokes, hub. Axle along x, on the ground."""
    parts = [f.apply(f.shape(ring(r * STUD, r * 0.8 * STUD, w * STUD, n=12), round_edges=False), kind, along="y")]
    for i in range(3):
        parts.append(f.apply(f.shape(box(s(w * 0.45, 0.24, r * 1.66), (0, 0, 0), rot=(PI * i / 3, 0, 0)),
                                     round_edges=False),
                             kind, along="z"))
    parts.append(f.apply(f.shape(cyl(r * 0.24 * STUD, (w + 0.1) * STUD, (0, 0, 0), verts=8, rot=(0, PI / 2, 0)),
                                 round_edges=False), kind, along="x"))
    return tag(place(parts, (x, y, r)), "wheel", wheel_uid(x, y))


def lug_tire(f, x, y, r, w, lugs=10, verts=14):
    """Tractor tire with chevron lugs and a hub disc (one material after export). Axle along x."""
    side = 1 if x >= 0 else -1
    parts = [C(f, "tire", r * 0.93, w, (x, y, r), axis="x", verts=verts, rounded=False),
             C(f, "tire", r * 0.5, w + 0.12, (x + side * 0.03, y, r), axis="x", verts=10, rounded=False)]
    for i in range(lugs):
        a = 2 * PI * (i + 0.5) / lugs
        for d in (-1, 1):
            o = box(s(w * 0.48, 0.32, 0.2), (0, 0, 0), rot=(0, 0, d * 0.45))
            o.location = s(d * w * 0.24, 0, 0)
            p = place([f.apply(f.shape(o, round_edges=False), "tire")], (0, 0, 0))
            # Lift onto the tread, then turn about the axle.
            M = (Matrix.Translation(Vector(s(x, y, r))) @ Matrix.Rotation(a, 4, "X")
                 @ Matrix.Translation(Vector(s(0, 0, r * 0.95))))
            p[0].data.transform(M)
            parts += p
    return tag(parts, "wheel", wheel_uid(x, y))


def rod(f, kind, p0, p1, th):
    """A square bar from p0 to p1 (studs), no bevel (vehicles.beam bevels, which costs triangles)."""
    a, b = Vector(s(*p0)), Vector(s(*p1))
    d = b - a
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler()
    o = box((th * STUD, th * STUD, d.length), (a + b) / 2, rot=tuple(rot))
    return f.apply(f.shape(o, round_edges=False), kind, along="xyz"[max(range(3), key=lambda i: abs(d[i]))])


def tilted_disc(f, kind, r, depth, loc, tilt, verts=10):
    """Cylinder whose axis leans tilt radians from z toward -y (steering wheels)."""
    return f.apply(f.shape(cyl(r * STUD, depth * STUD, s(*loc), verts=verts, rot=(tilt, 0, 0)),
                           round_edges=False), kind, along="z")


def letters(f, kind, words, loc, h, rz, depth=0.15):
    """Block letters (hub.text) turned by rz about z, then moved to loc. rz=0 faces -y, pi faces +y,
    -pi/2 faces -x."""
    return place(text(f, kind, words, 0, 0, 0, h, depth=depth), loc, rz=rz)


# ---------------------------------------------------------------- the hay wagon

def hay_wagon(f):
    """Free Hay Wagon, 9.2 wide x 5.5 tall x 16 long, laid out like HayWagon.luau with the bed centered (game bed
    center z=2 is the origin here): 8 x 14 plank bed at 2.4 (top 2.8), plank rails at x +-3.9 (top 4.2), four
    spoked wheels of radius 1.6 at x +-4.3, y -5 / +5. A 2.4 x 1.6 x 12 hay heap down the middle (HayFill, top 4.4)
    with a hay bench either side (top 3.6) dipped 2 x 2 to 3.25 at the six seats (x +-2.5, y -4/0/4). Tow tongue at
    the front (-y), a cream "HAY RIDES" Board at the back on two posts."""
    p = []
    bz = 2.4
    top = bz + 0.4
    # Bed and under-frame.
    p.append(B(f, "handle", (8.0, 14.0, 0.8), (0, 0, bz), along="y", rounded=False))
    for x in (-3.98, 3.98):
        p.append(B(f, "bark", (0.12, 14.2, 0.3), (x, 0, bz - 0.15), along="y", rounded=False))
    for x in (-2.6, 2.6):
        p.append(B(f, "bark", (0.6, 13.0, 0.5), (x, 0, bz - 0.65), along="y", rounded=False))
    for y in (-5.0, 5.0):
        p.append(B(f, "bark", (6.0, 0.6, 0.5), (0, y, bz - 0.65), rounded=False))
        p.append(C(f, "metal", 0.18, 8.6, (0, y, 1.6), axis="x", verts=6, rounded=False))
    # Plank rails: posts and two planks a side, a low rail across the front.
    for x in (-3.9, 3.9):
        for y in (-6.8, -2.0, 2.0, 6.8):
            p.append(B(f, "bark", (0.4, 0.4, 1.6), (x, y, top + 0.7), along="z", rounded=False))
        for z in (top + 0.45, top + 1.2):
            p.append(B(f, "handle", (0.3, 14.0, 0.4), (x, 0, z), along="y", rounded=False))
    for z in (top + 0.45, top + 1.2):
        p.append(B(f, "handle", (7.5, 0.3, 0.4), (0, -6.85, z), rounded=False))
    # Hay bench either side of the heap, dipped at the seats (riders face out).
    seats = (-4.0, 0.0, 4.0)
    for x in (-2.45, 2.45):
        edges = [-6.0]
        for y in seats:
            edges += [y - 1.0, y + 1.0]
        edges.append(6.0)
        for i in range(len(edges) - 1):
            y0, y1 = edges[i], edges[i + 1]
            dip = i % 2 == 1
            h = 0.45 if dip else 0.8
            p.append(B(f, "hay", (2.5, y1 - y0, h), (x, (y0 + y1) / 2, top + h / 2), along="y", rounded=False))
    # The hay heap (HayFill) the riders lean on.
    heap = [B(f, "hay", (2.4, 12.0, 1.2), (0, 0, top + 0.6), along="y", rounded=False),
            B(f, "hay", (1.8, 11.4, 0.4), (0, 0, top + 1.4), along="y", rounded=False)]
    p += tag(heap, "HayFill")
    # Tow tongue and hitch ring at the front.
    p.append(beam(f, "bark", (0, -6.8, bz - 0.7), (0, -8.3, 1.5), 0.45))
    p.append(B(f, "metal", (0.5, 0.6, 0.15), (0, -8.3, 1.45), rounded=False))
    # Wheels.
    for x in (-4.3, 4.3):
        for y in (-5.0, 5.0):
            p += wagon_wheel(f, x, y, 1.6, 0.6)
    # HAY RIDES board at the back (faces +y), on two posts.
    by, bzc = 7.2, 4.8
    for x in (-2.7, 2.7):
        p.append(B(f, "bark", (0.35, 0.35, 5.5 - top), (x, by - 0.3, (top + 5.5) / 2), along="z", rounded=False))
    p += tag([B(f, "paint_cream", (6.0, 0.25, 1.4), (0, by, bzc), rounded=False)], "Board")
    p += letters(f, "bark", "HAY RIDES", (0, by + 0.125, bzc), 0.8, PI, depth=0.12)
    return p


# ---------------------------------------------------------------- the tractor

def fender(f, kind, x, y, zc, R, w, a0, a1, n=4):
    """Curved fender over a wheel: n flat segments from angle a0 to a1 (0 = top, + toward +y)."""
    parts = []
    da = (a1 - a0) / n
    seg = 2 * R * math.sin(abs(da) / 2) + 0.05
    for i in range(n):
        a = a0 + da * (i + 0.5)
        parts.append(B(f, kind, (w, seg, 0.18), (x, y + R * math.sin(a), zc + R * math.cos(a)), along="y",
                       rot=(-a, 0, 0), rounded=False))
    return parts


def farm_tractor(f):
    """Small vintage tractor, 5 wide x 7 tall x 8.4 long, in weathered green with yellow trim. Origin is the
    game's tractor frame in HayWagon.luau: rear axle at y +1.5 (wheels radius 2.2, Wheel_L2/R2), front axle at
    y -3.5 (radius 1.2, Wheel_L1/R1, steering pivot at the hub). Narrow hood with a radiator grille, upright
    exhaust stack to 7, curved rear fenders, an open pan seat on a spring post and a tilted steering wheel; no
    driver (the game's NPC sits at y +1.5, seat top 4.3). Drawbar at the back (+y) at 1.4."""
    p = []
    ry, fy, R, r = 1.5, -3.5, 2.2, 1.2
    # Wheels.
    for x in (-1.98, 1.98):
        p += lug_tire(f, x, ry, R, 1.0, lugs=8)
    for x in (-1.45, 1.45):
        p += lug_tire(f, x, fy, r, 0.6, lugs=0, verts=12)
    # Axles and front axle beam.
    p.append(C(f, "metal", 0.22, 3.2, (0, ry, R), axis="x", verts=8, rounded=False))
    p.append(B(f, "metal", (2.6, 0.45, 0.45), (0, fy, r), rounded=False))
    p.append(B(f, "metal", (0.5, 0.5, 0.9), (0, fy, r + 0.6), along="z", rounded=False))
    # Engine, hood, grille.
    p.append(B(f, "metal", (1.3, 3.4, 1.1), (0, -2.2, 2.1), along="y", rounded=False))
    p.append(B(f, "paint_green", (1.9, 3.4, 1.4), (0, -2.6, 3.3), along="y"))
    p.append(B(f, "paint_green", (2.1, 0.5, 2.6), (0, -4.35, 2.75), rounded=False))
    p.append(B(f, "metal", (1.6, 0.1, 2.0), (0, -4.63, 2.75), rounded=False))
    for i in range(4):
        p.append(B(f, "paint_green", (1.6, 0.12, 0.1), (0, -4.66, 2.0 + 0.45 * i), rounded=False))
    p.append(B(f, "paint_yellow", (2.15, 0.55, 0.2), (0, -4.35, 4.15), rounded=False))
    for x in (-1.1, 1.1):
        p.append(C(f, "paint_yellow", 0.28, 0.3, (x, -4.0, 3.6), axis="y", verts=8, rounded=False))
    # Yellow side stripe along the hood.
    for x in (-0.96, 0.96):
        p.append(B(f, "paint_yellow", (0.05, 3.2, 0.18), (x, -2.6, 3.6), along="y", rounded=False))
    # Gearbox / rear body with the fuel tank in front of the seat.
    p.append(B(f, "paint_green", (2.1, 2.4, 2.0), (0, 0.6, 2.5), along="y"))
    p.append(C(f, "paint_green", 0.6, 1.6, (0, -0.4, 4.05), axis="y", verts=10, rounded=False))
    # Rear fenders and footplates.
    for x in (-1.98, 1.98):
        p += fender(f, "paint_green", x, ry, R, R + 0.35, 1.25, -1.2, 1.0)
        p.append(B(f, "metal", (0.9, 1.6, 0.15), (x * 0.62, -0.5, 1.75), along="y", rounded=False))
    # Steering column and wheel.
    p.append(rod(f, "metal", (0, -0.9, 4.2), (0, 0.35, 5.1), 0.18))
    p.append(tilted_disc(f, "tire", 0.7, 0.14, (0, 0.4, 5.15), 0.6, verts=12))
    # Open pan seat on a spring post.
    p.append(rod(f, "metal", (0, 1.6, 3.4), (0, 1.8, 4.0), 0.25))
    p.append(B(f, "paint_yellow", (1.3, 1.1, 0.25), (0, 1.75, 4.15), rounded=False))
    p.append(B(f, "paint_yellow", (1.3, 0.2, 0.7), (0, 2.25, 4.55), rounded=False))
    # Exhaust stack and air intake.
    p.append(C(f, "metal", 0.22, 3.0, (0.5, -3.7, 5.5), verts=8, rounded=False))
    p.append(C(f, "metal", 0.3, 0.4, (0.5, -3.7, 6.8), verts=8, rounded=False))
    p.append(C(f, "metal", 0.18, 1.1, (-0.5, -3.2, 4.5), verts=8, rounded=False))
    # Drawbar.
    p.append(B(f, "metal", (0.5, 1.5, 0.3), (0, 3.2, 1.4), along="y", rounded=False))
    return p


# ---------------------------------------------------------------- ferry promenade

def ferry_snack_stand(f):
    """Ferry promenade snack stand, 5 wide x 6.5 tall x 9 long, laid out like Ferry.luau: the service side faces
    -x here (+X in the game, toward the deck lanes), so it drops in at the game's stand frame offset by (-1, 0.4, 0)
    (origin under the awning's middle, on the promenade top). Cream plank counter 3 x 3.2 x 8 (x -1..2) with a
    plank top, red and cream striped awning 5 x 9 tipped 12 deg (high over the counter back, low at the front)
    on two front poles and two back posts, chalkboard menu, pretzel rack and a chowder pot on the counter, and a
    yellow "SNACKS" Sign on the counter front with red letters."""
    p = []
    cx0, cx1, ch = -1.0, 2.0, 3.2
    # Counter body, battens, trim and top.
    p.append(B(f, "paint_cream", (cx1 - cx0, 8.0, ch - 0.25), (0.5, 0, (ch - 0.25) / 2), along="z"))
    for y in (-3.6, -2.6, 2.6, 3.6):
        p.append(B(f, "paint_cream", (0.1, 0.18, ch - 0.45), (cx0 - 0.05, y, (ch - 0.25) / 2), along="z",
                   rounded=False))
    p.append(B(f, "paint_red", (0.1, 8.0, 0.35), (cx0 - 0.05, 0, 0.18), rounded=False))
    p.append(B(f, "handle", (3.4, 8.5, 0.25), (0.45, 0, ch - 0.125), along="y", rounded=False))
    # Awning: z at x is az + x * tan(12 deg); 7 stripes along y, a flap on each at the front edge.
    t, az = math.tan(math.radians(12)), 5.8
    n, L, W = 7, 9.0, 5.0
    w = L / n
    for i in range(n):
        kind = "paint_red" if i % 2 == 0 else "paint_cream"
        y = -L / 2 + w * (i + 0.5)
        p.append(B(f, kind, (W / math.cos(math.radians(12)), w, 0.25), (0, y, az), along="x",
                   rot=(0, -math.radians(12), 0), rounded=False))
        p.append(B(f, kind, (0.12, w, 0.6), (-W / 2 - 0.02, y, az - W / 2 * t - 0.38), rounded=False))
    # Poles at the front, posts at the back.
    for y in (-4.0, 4.0):
        p.append(B(f, "handle", (0.35, 0.35, az - 2.2 * t - 0.12), (-2.2, y, (az - 2.2 * t - 0.12) / 2),
                   along="z", rounded=False))
        p.append(B(f, "handle", (0.35, 0.35, az + 1.9 * t - ch), (1.9, y, (az + 1.9 * t + ch) / 2 - 0.12),
                   along="z", rounded=False))
    # Chalkboard menu standing at the back of the counter, facing the customers.
    p.append(B(f, "handle", (0.2, 2.3, 1.7), (1.75, 2.4, ch + 1.0), along="y", rounded=False))
    p.append(B(f, "tire", (0.1, 2.0, 1.4), (1.62, 2.4, ch + 1.0), rounded=False))
    for i, (ln, dz) in enumerate(((1.4, 0.4), (1.1, 0.05), (1.3, -0.3))):
        p.append(B(f, "paint_cream", (0.05, ln, 0.1), (1.55, 2.3 - (1.4 - ln) / 2, ch + 1.0 + dz), rounded=False))
    for dz in (0.05, -0.3):
        p.append(B(f, "paint_cream", (0.05, 0.25, 0.1), (1.55, 3.15, ch + 1.0 + dz), rounded=False))
    # Pretzel rack: iron post and crossbar with pretzels hanging toward the customers.
    ry = -2.4
    p.append(B(f, "tire", (0.8, 0.8, 0.1), (0.6, ry, ch + 0.05), rounded=False))
    p.append(B(f, "tire", (0.12, 0.12, 2.0), (0.6, ry, ch + 1.0), along="z", rounded=False))
    p.append(B(f, "tire", (0.1, 1.8, 0.1), (0.6, ry, ch + 1.95), along="y", rounded=False))
    for dy, z in ((-0.6, ch + 1.45), (0.6, ch + 1.45), (0.0, ch + 0.75)):
        pr = f.apply(f.shape(ring(0.38 * STUD, 0.24 * STUD, 0.16 * STUD, n=8), round_edges=False), "handle")
        pr.location = s(0.45, ry + dy, z)
        p.append(pr)
        p.append(B(f, "handle", (0.12, 0.6, 0.13), (0.45, ry + dy, z - 0.05), rot=(0.7, 0, 0), rounded=False))
        p.append(B(f, "handle", (0.12, 0.6, 0.13), (0.45, ry + dy, z - 0.05), rot=(-0.7, 0, 0), rounded=False))
    # Chowder pot with a ladle.
    py = -0.3
    p.append(C(f, "tire", 0.75, 0.95, (0.7, py, ch + 0.5), verts=12, rounded=False))
    p.append(C(f, "tire", 0.85, 0.12, (0.7, py, ch + 0.95), verts=12, rounded=False))
    p.append(C(f, "paint_cream", 0.66, 0.05, (0.7, py, ch + 0.97), verts=12, rounded=False))
    for y in (py - 0.85, py + 0.85):
        p.append(B(f, "tire", (0.15, 0.25, 0.15), (0.7, y, ch + 0.75), rounded=False))
    p.append(rod(f, "handle", (0.6, py + 0.2, ch + 0.8), (0.2, py + 0.7, ch + 1.9), 0.1))
    # SNACKS sign on the counter front (game SnackSign is 5 long x 1.2 tall).
    p += tag([B(f, "paint_yellow", (0.2, 5.0, 1.3), (cx0 - 0.2, 0, 2.1), along="y", rounded=False)], "Sign")
    p += letters(f, "paint_red", "SNACKS", (cx0 - 0.3, 0, 2.1), 0.85, -PI / 2, depth=0.1)
    return p


def fishing_spot(f):
    """Fishing spot, about 2 x 3 tall x 1.6: a galvanized bait bucket with a wire bail and bait inside, a red
    tackle box with a handle, and a rod leaning toward +x (the promenade rail is +x here, -X in the game) with
    a cork grip and a reel. Sits on the game's 2 x 2 FishingSpot pad."""
    p = []
    # Bait bucket.
    bx, by = -0.45, -0.3
    p.append(C(f, "steel", 0.42, 0.85, (bx, by, 0.425), verts=8, rounded=False))
    p.append(C(f, "dirt", 0.36, 0.05, (bx, by, 0.83), verts=8, rounded=False))
    for d in (-1, 1):
        p.append(rod(f, "steel", (bx + d * 0.42, by, 0.75), (bx + d * 0.2, by, 1.25), 0.05))
    p.append(B(f, "steel", (0.45, 0.05, 0.05), (bx, by, 1.25), rounded=False))
    # Tackle box.
    tx, ty = 0.45, -0.45
    p.append(B(f, "paint_red", (0.95, 0.6, 0.45), (tx, ty, 0.225), rounded=False))
    p.append(B(f, "paint_red", (1.0, 0.65, 0.1), (tx, ty, 0.5), rounded=False))
    p.append(B(f, "steel", (0.1, 0.05, 0.12), (tx, ty - 0.33, 0.42), rounded=False))
    p.append(B(f, "steel", (0.5, 0.07, 0.07), (tx, ty, 0.72), rounded=False))
    for x in (tx - 0.22, tx + 0.22):
        p.append(B(f, "steel", (0.07, 0.07, 0.17), (x, ty, 0.62), rounded=False))
    # Rod leaning on the rail: butt on the deck, tip at 3.
    a, b = (-0.75, 0.5, 0.0), (0.95, 0.5, 2.98)
    d = [b[i] - a[i] for i in range(3)]

    def at(k):
        return tuple(a[i] + d[i] * k for i in range(3))
    p.append(rod(f, "handle", at(0.0), at(0.28), 0.17))
    p.append(rod(f, "handle", at(0.28), at(0.65), 0.1))
    p.append(rod(f, "handle", at(0.65), at(1.0), 0.06))
    rx, ry_, rz = at(0.2)
    p.append(C(f, "steel", 0.16, 0.14, (rx + 0.12, ry_, rz - 0.08), axis="y", verts=8, rounded=False))
    return p


PROPS = {
    "hay_wagon": hay_wagon,
    "farm_tractor": farm_tractor,
    "ferry_snack_stand": ferry_snack_stand,
    "fishing_spot": fishing_spot,
}

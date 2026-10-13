"""Robux truck skins (MODEL_SPECS "Robux truck skins"): paint and trim swaps of the cash trucks.

Each skin calls the stock builder in vehicles.py with a finish whose apply() remaps part kinds to
the skin's own materials, so the geometry, size, bed and rig names (Wheel_*, Tailgate) are the
base truck's and the stats match. Additions are trim only: pinstripes, door crests, a roof light
bar, and the prairie_schooner's canvas `Cover` (its own mesh so the game can hide it to load).
Wheels get one textured material per wheel (whitewall / chunky tread are paint, same radius).

Every body is kept to 4 materials by the remap below (glass shares the dark slot, lenses and
taillights share a trim slot), so the exporter's limiter has nothing to merge.

Run through rustic_props.py:
  python blender/props/rustic_props.py --out <dir> --category truck_skins
"""
import math
import os
import sys

import bpy  # must be imported before bmesh/mathutils with the pip bpy module
import bmesh  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, HERE)
import common  # noqa: E402
import style  # noqa: E402
import vehicles  # noqa: E402
from rig import tag  # noqa: E402
from style import box, cyl  # noqa: E402

STUD = 0.28
PI = math.pi
FLOOR = vehicles.FLOOR
RIG_FLIP = True  # same as vehicles.py: builders face -y
BEDS = {}        # skin key -> the base truck's bed (filled when a skin is built)

# ---------------------------------------------------------------- skin materials
# Custom kinds live only in this module: name -> (texture, (light, mid, dark) sRGB, metallic).
KINDS = {
    "barn_red": ("weathered", ((0.66, 0.26, 0.20), (0.56, 0.20, 0.16), (0.38, 0.14, 0.11)), 0.0),
    "cream": ("weathered", ((0.95, 0.91, 0.79), (0.88, 0.83, 0.69), (0.70, 0.65, 0.52)), 0.0),
    "chrome": ("metal", ((0.88, 0.89, 0.90), (0.76, 0.77, 0.79), (0.58, 0.59, 0.61)), 0.6),
    "forest": ("weathered", ((0.30, 0.44, 0.28), (0.22, 0.35, 0.21), (0.14, 0.23, 0.14)), 0.0),
    "gunmetal": ("metal", ((0.44, 0.45, 0.46), (0.34, 0.35, 0.36), (0.25, 0.26, 0.27)), 0.5),
    "lamp": ("weathered", ((0.99, 0.95, 0.80), (0.95, 0.90, 0.70), (0.80, 0.74, 0.54)), 0.0),
    "navy": ("weathered", ((0.20, 0.25, 0.38), (0.14, 0.18, 0.30), (0.09, 0.11, 0.20)), 0.0),
    "pale_gold": ("weathered", ((0.96, 0.88, 0.62), (0.90, 0.79, 0.50), (0.70, 0.59, 0.34)), 0.3),
    "prairie_blue": ("weathered", ((0.54, 0.64, 0.72), (0.44, 0.54, 0.62), (0.31, 0.38, 0.45)), 0.0),
    "old_wood": ("plank", ((0.68, 0.64, 0.57), (0.55, 0.51, 0.45), (0.37, 0.34, 0.30)), 0.0),
    "canvas": ("weathered", ((0.94, 0.91, 0.81), (0.86, 0.82, 0.70), (0.69, 0.64, 0.53)), 0.0),
    "founders_green": ("weathered", ((0.21, 0.36, 0.27), (0.14, 0.27, 0.20), (0.08, 0.17, 0.12)), 0.0),
    "gold": ("weathered", ((0.97, 0.83, 0.44), (0.87, 0.70, 0.30), (0.62, 0.48, 0.18)), 0.4),
}


def bounds(o):
    """World-space (lo, hi) of a part in studs."""
    pts = [o.matrix_world @ v.co for v in o.data.vertices]
    lo = tuple(min(p[i] for p in pts) / STUD for i in range(3))
    hi = tuple(max(p[i] for p in pts) / STUD for i in range(3))
    return lo, hi


def dims(o):
    lo, hi = bounds(o)
    return tuple(h - l for l, h in zip(lo, hi))


def is_taillight(o):
    d = dims(o)
    return abs(d[0] - 0.6) < 0.1 and abs(d[1] - 0.15) < 0.1 and abs(d[2] - 0.35) < 0.1


def skin_finish(remap):
    """A Rustic finish whose apply() sends kind through remap(obj, kind) and builds this module's
    custom kinds itself (weathered paint / plank / metal textures from style.py)."""
    f = style.rustic()
    base_apply = f.apply
    mats = {}

    def material(kind):
        if kind not in mats:
            tex, pal, metallic = KINDS[kind]
            fn = {"weathered": lambda: style.weathered_texture(pal, f.contrast, 40 + list(KINDS).index(kind)),
                  "plank": lambda: style.plank_texture(pal, f.contrast),
                  "metal": lambda: style.metal_texture(pal, f.contrast, False)}[tex]()
            img = common.make_texture(f"rustic_{kind}", 128, fn)
            mats[kind] = common.texture_material(f"rustic_{kind}", img, roughness=0.6 if metallic else 0.9,
                                                 metallic=metallic)
        return mats[kind]

    def apply(obj, kind, along="x", uv="box"):
        k = remap(obj, kind)
        if k in KINDS:
            common.box_uv(obj, scale=1.6, along=along)
            common.assign(obj, material(k))
            return obj
        return base_apply(obj, k, along=along, uv=uv)

    f.apply = apply
    return f


# ---------------------------------------------------------------- wheels (one material each)

def wheel_texture(name, whitewall=False, tread=False, hub=(0.62, 0.63, 0.65)):
    """Left half: the sidewall seen side-on (a disc; hub inside 0.56 of the radius). Right half: one
    tread face (u around the tire, v across it)."""
    rubber = (0.13, 0.12, 0.11)
    white = (0.93, 0.91, 0.84)

    def fn(u, v):
        if u < 0.5:
            d = math.hypot((u - 0.25) / 0.25, (v - 0.5) / 0.5)
            if d < 0.18:
                return tuple(c * 0.75 for c in hub)          # axle cap
            if d < 0.5:
                return hub
            if d < 0.57:
                return tuple(c * 0.7 for c in hub)           # rim lip
            if whitewall and 0.64 < d < 0.84:
                return white
            return rubber
        t = (u - 0.5) * 2
        if tread:
            lug = (0.08 < t < 0.55) if v < 0.5 else (0.45 < t < 0.92)
            edge = v < 0.08 or v > 0.92
            return (0.20, 0.19, 0.17) if lug or edge else (0.06, 0.055, 0.05)
        return rubber

    img = common.make_texture(name, 128, fn)
    return common.texture_material(name, img, roughness=0.9)


def paint_wheels(parts, mat):
    """Give every wheel part (tire, hub, axle cap, dual tire) the one wheel material, with UVs:
    side faces planar onto the sidewall disc, tread faces one texture tile each."""
    groups = {}
    for o in parts:
        if o.get("rig") == "wheel":
            groups.setdefault(o["rig_uid"], []).append(o)
    for objs in groups.values():
        R = max(dims(o)[2] for o in objs) / 2 * STUD
        tire_r = R
        for o in objs:
            lo, hi = bounds(o)
            cy, cz = (lo[1] + hi[1]) / 2 * STUD, (lo[2] + hi[2]) / 2 * STUD
            x0, x1 = lo[0] * STUD, hi[0] * STUD
            is_tire = (hi[2] - lo[2]) / 2 * STUD > tire_r * 0.8
            mw = o.matrix_world
            mesh = o.data
            uvl = mesh.uv_layers.get("UVMap") or mesh.uv_layers.new(name="UVMap")
            for poly in mesh.polygons:
                n = (mw.to_3x3() @ poly.normal)
                cos = [mw @ mesh.vertices[mesh.loops[li].vertex_index].co for li in poly.loop_indices]
                if abs(n.x) > 0.7:
                    for li, p in zip(poly.loop_indices, cos):
                        uvl.data[li].uv = (0.25 + (p.y - cy) / tire_r * 0.25 * 0.98,
                                           0.5 + (p.z - cz) / tire_r * 0.5 * 0.98)
                elif not is_tire:
                    for li in poly.loop_indices:
                        uvl.data[li].uv = (0.25 + 0.1, 0.5)   # hub rim: hub grey
                else:
                    ac = math.atan2(sum(p.z - cz for p in cos), sum(p.y - cy for p in cos))
                    rel = [(math.atan2(p.z - cz, p.y - cy) - ac + PI) % (2 * PI) - PI for p in cos]
                    a0, a1 = min(rel), max(rel)
                    for li, p, a in zip(poly.loop_indices, cos, rel):
                        t = (a - a0) / (a1 - a0) if a1 - a0 > 1e-6 else 0.5
                        s = (p.x - x0) / (x1 - x0) if x1 - x0 > 1e-6 else 0.5
                        uvl.data[li].uv = (0.5 + 0.495 * t + 0.0025, 0.01 + 0.98 * s)
            common.assign(o, mat)


def strip(f, kind, size, loc, along="x"):
    """A thin flat trim piece in studs (no bevel, no lumps)."""
    return f.apply(box(tuple(v * STUD for v in size), tuple(v * STUD for v in loc)), kind, along=along)


def disc(f, kind, r, depth, loc, verts=14):
    """A thin disc facing x (door crest layers)."""
    o = cyl(r * STUD, depth * STUD, tuple(v * STUD for v in loc), verts=verts, rot=(0, PI / 2, 0))
    return f.apply(o, kind, along="x")


def shield(f, kind, w, h, depth, loc):
    """A small pointed heraldic shield facing x, in studs."""
    x, y, z = loc
    outline = [(-w / 2, h / 2), (w / 2, h / 2), (w / 2, -h * 0.1), (0, -h / 2), (-w / 2, -h * 0.1)]
    bm = bmesh.new()
    for sx in (-depth / 2, depth / 2):
        for oy, oz in outline:
            bm.verts.new(((x + sx) * STUD, (y + oy) * STUD, (z + oz) * STUD))
    bm.verts.ensure_lookup_table()
    n = len(outline)
    bm.faces.new([bm.verts[i] for i in range(n)][::-1])
    bm.faces.new([bm.verts[n + i] for i in range(n)])
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([bm.verts[i], bm.verts[j], bm.verts[n + j], bm.verts[n + i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("shield")
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new("shield", mesh)
    bpy.context.collection.objects.link(o)
    return f.apply(o, kind, along="x")


def build(key, base, remap, wheel_mat=None):
    """Build the base truck with the skin finish; returns (parts, finish)."""
    f = skin_finish(remap)
    parts = vehicles.PROPS[base](f)
    if base in vehicles.BEDS:
        BEDS[key] = vehicles.BEDS[base]
    if wheel_mat:
        paint_wheels(parts, wheel_mat)
    return parts, f


def by_kind0(parts, kind):
    return [o for o in parts if o.get("kind0") == kind]


def recording(remap):
    """Wrap a remap so every part remembers its stock kind (for the trim placement below)."""
    def fn(obj, kind):
        if kind not in KINDS:
            obj["kind0"] = kind
        return remap(obj, kind)
    return fn


# ---------------------------------------------------------------- skins

def homestead_classic(f):
    """Rusty pickup skin, 10.9 x 9.2 x 27.5 studs: cream cab over a barn-red body and bed, chrome-grey
    bumpers, grille bars and trim, whitewall tires (texture only)."""
    def remap(o, kind):
        if kind == "paint_red":
            return "barn_red" if is_taillight(o) or bounds(o)[1][2] < 7.5 else "cream"
        return {"metal": "chrome", "tire": "glass", "paint_cream": "cream"}.get(kind, kind)
    parts, _ = build("homestead_classic", "rusty_pickup", recording(remap),
                     wheel_texture("rustic_whitewall", whitewall=True, hub=(0.80, 0.81, 0.83)))
    return parts


def timber_wolf_4x4(f):
    """Farm flatbed skin (sold as the Flatbed tier, so it is cut on the flatbed: 24.5 long): forest green
    with a gunmetal stake bed and trim, tinted windows, a roof light bar and chunky-tread tires
    (texture only, same radius)."""
    def remap(o, kind):
        if kind == "paint_green":
            return "forest"
        return {"metal": "gunmetal", "handle": "gunmetal", "glass": "tire", "paint_cream": "lamp",
                "paint_red": "lamp", "paint_yellow": "lamp"}.get(kind, kind)
    parts, sf = build("timber_wolf_4x4", "farm_flatbed", recording(remap),
                      wheel_texture("rustic_tread", tread=True, hub=(0.36, 0.37, 0.38)))
    # Light bar across the front of the roof panel (the cab roof is the highest paint part).
    roof = max(by_kind0(parts, "paint_green"), key=lambda o: bounds(o)[1][2])
    lo, hi = bounds(roof)
    z, y = hi[2], lo[1] + 0.5
    w = (hi[0] - lo[0]) * 0.8
    for x in (-1, 1):
        parts.append(strip(sf, "tire", (0.25, 0.25, 0.35), (x * w * 0.4, y + 0.1, z + 0.17)))
    parts.append(strip(sf, "tire", (w, 0.55, 0.45), (0, y, z + 0.55)))
    for i in range(5):
        parts.append(strip(sf, "lamp", (w / 5 - 0.18, 0.08, 0.3), ((i - 2) * w / 5, y - 0.3, z + 0.55)))
    return parts


def midnight_express(f):
    """Box truck skin, 11.1 x 10.2 x 29.4 studs: deep navy cab and box with the side band in pale
    gold, pale-gold lamps, steel-plate floor. No glow."""
    def remap(o, kind):
        if kind in ("paint_cream", "paint_blue"):
            lens = kind == "paint_cream" and max(dims(o)) < 1.0
            return "pale_gold" if lens else "navy"
        if kind == "paint_red":
            return "pale_gold"
        return {"handle": "metal", "glass": "tire"}.get(kind, kind)
    parts, sf = build("midnight_express", "box_truck", recording(remap))
    # A thin pale-gold belt line on the cab doors to carry the box band forward.
    cab = max((o for o in by_kind0(parts, "paint_cream")), key=lambda o: dims(o)[2])
    lo, hi = bounds(cab)
    zc = lo[2] + (hi[2] - lo[2]) * 0.48
    for x in (-1, 1):
        parts.append(strip(sf, "pale_gold", (0.06, hi[1] - lo[1] - 0.3, 0.2), (x * (hi[0] + 0.03), (lo[1] + hi[1]) / 2,
                                                                               zc), along="y"))
    return parts


def cover(f, kind, Wo, y0, y1, z0, rise, hoops=4, n=12, t=0.12):
    """Canvas hoop cover: a half-ellipse shell over the bed with raised hoop bands, open at both ends."""
    a = Wo / 2 + 0.06
    bm = bmesh.new()

    def shell(r_add, ya, yb, thick):
        rows = []
        for ri, (ra, yy) in enumerate(((r_add, ya), (r_add, yb), (r_add + thick, yb), (r_add + thick, ya))):
            rows.append([bm.verts.new((((a + ra) * math.cos(PI * i / n)) * STUD, yy * STUD,
                                       (z0 + (rise + ra) * math.sin(PI * i / n)) * STUD)) for i in range(n + 1)])
        for r in range(4):
            A, B_ = rows[r], rows[(r + 1) % 4]
            for i in range(n):
                bm.faces.new([A[i], A[i + 1], B_[i + 1], B_[i]])
        for i in (0, n):  # close the bottom edges
            bm.faces.new([rows[0][i], rows[1][i], rows[2][i], rows[3][i]])

    shell(0.0, y0, y1, t)
    for h in range(hoops):
        yh = y0 + 0.25 + h * (y1 - y0 - 0.5) / (hoops - 1)
        shell(t - 0.02, yh - 0.18, yh + 0.18, 0.14)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("cover")
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new("cover", mesh)
    bpy.context.collection.objects.link(o)
    return f.apply(o, kind, along="y")


def prairie_schooner(f):
    """Heavy hauler skin (sold as the Heavy Hauler tier, so it is cut on the hauler: 36 long): faded
    prairie-blue cab and stakes, a sun-bleached plank tub (floor and walls), and a canvas hoop cover
    over the bed as its own `Cover` mesh."""
    def remap(o, kind):
        if kind == "metal" and bounds(o)[0][2] >= FLOOR - vehicles.WALL_T - 0.02 and max(dims(o)) > 8.0:
            return "old_wood"   # the tub's floor and walls
        if kind in ("paint_red", "paint_cream"):
            return "metal"      # taillights and lenses share the metal slot
        return {"paint_yellow": "prairie_blue", "paint_green": "prairie_blue", "glass": "tire"}.get(kind, kind)
    parts, sf = build("prairie_schooner", "heavy_hauler", recording(remap))
    Li, Wi, wall_h, _ = BEDS["prairie_schooner"]
    floor = max(by_kind0(parts, "metal"), key=lambda o: dims(o)[0] * dims(o)[1])
    lo, hi = bounds(floor)
    Wo = hi[0] - lo[0]
    c = cover(sf, "canvas", Wo, lo[1] + 0.5, hi[1] - 0.15, FLOOR + wall_h, rise=3.4)
    parts += tag([c], "Cover")
    return parts


def founders_semi(f):
    """Semi rig skin, ~9.8 x 10.1 x 25.3 studs: cream cab, sleeper and fairing over a dark green hood
    and fenders, a dark green rocker band with a gold pinstripe, gold hood pinstripes and a gold
    founders' crest on both doors; chrome-grey trim."""
    def remap(o, kind):
        if kind == "paint_blue":
            return "cream" if bounds(o)[1][2] > 6.0 else "founders_green"
        if kind == "paint_red":
            return "gold"
        return {"metal": "chrome", "glass": "founders_green", "tire": "founders_green",
                "paint_cream": "chrome"}.get(kind, kind)
    parts, sf = build("founders_semi", "semi_rig", recording(remap),
                      wheel_texture("rustic_founders_wheel", hub=(0.87, 0.70, 0.30)))
    paint = by_kind0(parts, "paint_blue")
    cab = max((o for o in paint if bounds(o)[1][2] > 6.0), key=lambda o: dims(o)[1] * dims(o)[2])
    hood = max((o for o in paint if bounds(o)[1][2] <= 6.0), key=lambda o: dims(o)[0] * dims(o)[1] * dims(o)[2])
    sleeper = [o for o in paint if bounds(o)[1][2] > 6.0 and o is not cab and dims(o)[2] > 3.0]
    clo, chi = bounds(cab)
    y_back = max(bounds(o)[1][1] for o in sleeper) if sleeper else chi[1]
    W, CH, z0 = chi[0], chi[2] - clo[2], clo[2]
    for x in (-1, 1):
        xs = x * (W + 0.025)
        yc, ln = (clo[1] + y_back) / 2, y_back - clo[1] - 0.1
        parts.append(strip(sf, "founders_green", (0.05, ln, CH * 0.18), (xs, yc, z0 + CH * 0.09), along="y"))
        parts.append(strip(sf, "gold", (0.06, ln, 0.1), (x * (W + 0.035), yc, z0 + CH * 0.18 + 0.12), along="y"))
        # Door crest: gold ring, green disc, gold shield.
        yd, zd = clo[1] + (chi[1] - clo[1]) * 0.42, z0 + CH * 0.4
        parts.append(disc(sf, "gold", 0.85, 0.04, (x * (W + 0.02), yd, zd)))
        parts.append(disc(sf, "founders_green", 0.72, 0.04, (x * (W + 0.05), yd, zd)))
        parts.append(shield(sf, "gold", 0.8, 1.0, 0.04, (x * (W + 0.08), yd, zd)))
    # Gold pinstripes along both hood sides.
    hlo, hhi = bounds(hood)
    for x in (-1, 1):
        parts.append(strip(sf, "gold", (0.06, hhi[1] - hlo[1] - 0.6, 0.1),
                           (x * (hhi[0] + 0.03), (hlo[1] + hhi[1]) / 2, hlo[2] + (hhi[2] - hlo[2]) * 0.75), along="y"))
    return parts


PROPS = {
    "homestead_classic": homestead_classic,
    "timber_wolf_4x4": timber_wolf_4x4,
    "midnight_express": midnight_express,
    "prairie_schooner": prairie_schooner,
    "founders_semi": founders_semi,
}

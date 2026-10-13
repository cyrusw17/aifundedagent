"""Every game prop in the house style (LT2 shapes, Rustic finish).

Hay and starter tools are built here; tools.py, vehicles.py, storage.py, buildings.py and
machines.py each add a category. Each prop is exported on its own to
<out>/<name>.glb, and each category gets a catalog render <out>/catalog_<category>.png.

Run:
  blender --background --python blender/props/rustic_props.py -- --out blender/exports/rustic
  ... [--category vehicles] [--only basic_shovel,log] [--no-catalog]
"""
import json
import math
import os
import sys

import bpy  # must be imported before bmesh/mathutils with the pip bpy module
import bmesh  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, HERE)
import common  # noqa: E402
import rig  # noqa: E402
import hay_bale  # noqa: E402
import style  # noqa: E402
from style import box, cap_uv, cyl  # noqa: E402

STUD = 0.28
GRASS = (0.42, 0.60, 0.28)


def handle(f, length, z0, r=0.018, sides=6, x=0.0, y=0.0, tilt=(0, 0, 0)):
    """A wooden pole from z0 upward (before tilt)."""
    h = cyl(r, length, (x, y, z0 + length / 2), verts=sides)
    if tilt != (0, 0, 0):
        h.rotation_euler = tilt
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return f.apply(f.shape(h, round_edges=False), "handle", along="z")


def d_grip(f, z):
    parts = [f.apply(f.shape(cyl(0.016, 0.12, (0, 0, z), verts=6, rot=(0, math.pi / 2, 0))), "handle", along="x")]
    for x in (-0.05, 0.05):
        parts.append(f.apply(f.shape(box((0.02, 0.02, 0.06), (x, 0, z - 0.035))), "handle", along="z"))
    return parts


# ---------------------------------------------------------------- hay

def hay_bale_prop(f):
    """4.6 x 3.2 x 2.6 studs like the game's bale part, flat top and bottom so bales stack."""
    hay_bale.BEVEL = max(f.bevel, 0.001)
    hay = f.apply(f.shape(hay_bale.build_hay(), round_edges=False), "hay")
    return [hay] + [f.apply(b, "twine") for b in hay_bale.build_twine()]


def round_bale(f):
    r, width = 0.5, 0.95
    body = f.apply(f.shape(cyl(r, width, (0, 0, r), verts=18, rot=(math.pi / 2, 0, 0))), "hay", along="x")
    parts = [body]
    for side in (-1, 1):
        cap = cyl(r * 0.96 - f.lumpy, 0.01, (0, side * (width / 2 + 0.002 + f.lumpy), r), verts=18,
                  rot=(math.pi / 2, 0, 0))
        cap_uv(cap, 1, r)
        parts.append(f.apply(cap, "hay", uv="rolled"))
    for y in (-0.25, 0.0, 0.25):
        parts.append(f.apply(cyl(r + 0.006 + f.lumpy, 0.025, (0, y, r), verts=18, rot=(math.pi / 2, 0, 0)), "twine"))
    return parts


# ---------------------------------------------------------------- hand tools

def rod(f, kind, p0, p1, r, verts=6, along=None):
    """A round bar from p0 to p1 (meters)."""
    from mathutils import Vector
    d = Vector(p1) - Vector(p0)
    o = cyl(r, d.length, tuple((Vector(p0) + Vector(p1)) / 2), verts=verts)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return f.apply(o, kind, along=along) if along else f.apply(o, kind)


def basic_shovel(f):
    """Small spade, about 2.7 studs tall. Mid detail: round ash shaft, a proper D grip, a riveted
    tapered socket, a dished blade with a pointed tip, a front strap and folded foot treads."""
    parts = [handle(f, 0.45, 0.23, r=0.017, sides=10)]
    # D grip: two cheeks rising from a split shaft to a round cross grip.
    for x in (-1, 1):
        parts.append(rod(f, "handle", (0, 0, 0.67), (x * 0.05, 0, 0.745), 0.012, verts=8, along="z"))
    parts.append(f.apply(f.shape(cyl(0.017, 0.13, (0, 0, 0.749), verts=10, rot=(0, math.pi / 2, 0)), round_edges=False),
                         "handle", along="x"))
    parts.append(f.apply(cyl(0.02, 0.025, (0, 0, 0.67), verts=10), "metal"))                 # grip ferrule
    # Tapered socket with two rivets.
    sock = cyl(0.024, 0.09, (0, 0, 0.225), verts=10)
    for v in sock.data.vertices:
        if v.co.z < 0:
            v.co.x *= 1.5
            v.co.y *= 0.8
    parts.append(f.apply(f.shape(sock, round_edges=False), "metal"))
    for z in (0.21, 0.25):
        parts.append(f.apply(cyl(0.006, 0.06, (0, 0, z), verts=6, rot=(math.pi / 2, 0, 0)), "metal"))
    # Dished blade: a 4 x 5 grid bent around the shaft, narrowing to a rounded point.
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=4, y_segments=5, size=0.5)
    for v in bm.verts:
        u, w = v.co.x * 2, v.co.y + 0.5                         # u -1..1 across, w 0 (tip)..1 (top)
        width = 0.085 * (0.55 + 0.45 * min(1.0, w * 1.6))
        tip = 0.03 * (1 - u * u) if w < 0.01 else 0.0
        v.co = (u * width, 0.018 * (u * u) - 0.01, 0.03 + 0.17 * w - tip)
    me = bpy.data.meshes.new("blade")
    bm.to_mesh(me)
    bm.free()
    blade = bpy.data.objects.new("blade", me)
    bpy.context.collection.objects.link(blade)
    m = blade.modifiers.new("solid", "SOLIDIFY")
    m.thickness = 0.008
    bpy.context.view_layer.objects.active = blade
    bpy.ops.object.modifier_apply(modifier=m.name)
    parts.append(f.apply(f.shape(blade, round_edges=False), "metal"))
    parts.append(f.apply(box((0.03, 0.01, 0.11), (0, -0.008, 0.15)), "metal"))                # front strap
    for x in (-1, 1):                                                                          # foot treads
        parts.append(f.apply(box((0.06, 0.03, 0.008), (x * 0.05, 0.0, 0.2)), "metal"))
    return parts


def wide_scoop(f):
    """Grain-scoop shovel: broad flat blade with raised sides, about 3 studs tall."""
    parts = [handle(f, 0.5, 0.3)] + d_grip(f, 0.84)
    base = box((0.3, 0.26, 0.015), (0, 0.05, 0.12), rot=(0.35, 0, 0))
    parts.append(f.apply(f.shape(base), "metal"))
    for x in (-0.15, 0.15):
        side = box((0.015, 0.26, 0.06), (x, 0.05, 0.15), rot=(0.35, 0, 0))
        parts.append(f.apply(f.shape(side), "metal"))
    back = box((0.3, 0.015, 0.1), (0, -0.07, 0.24), rot=(0.35, 0, 0))
    parts.append(f.apply(f.shape(back), "metal"))
    return parts


def garden_rake(f):
    """Long rake, about 5 studs: a round shaft, a wooden head with a steel ferrule and two bowed
    braces, and 14 tapered iron teeth that curve forward at the tips."""
    parts = [handle(f, 1.3, 0.08, r=0.018, sides=10)]
    parts.append(f.apply(f.shape(box((0.5, 0.045, 0.055), (0, 0, 0.06))), "handle", along="x"))
    parts.append(f.apply(cyl(0.024, 0.06, (0, 0, 0.11), verts=10), "metal"))                  # ferrule
    for x in (-1, 1):                                                                         # bowed braces
        parts.append(rod(f, "handle", (0, 0, 0.3), (x * 0.08, 0, 0.17), 0.009, verts=6, along="z"))
        parts.append(rod(f, "handle", (x * 0.08, 0, 0.17), (x * 0.16, 0, 0.085), 0.009, verts=6, along="z"))
        parts.append(f.apply(cyl(0.007, 0.05, (x * 0.23, 0, 0.06), verts=6, rot=(math.pi / 2, 0, 0)), "metal"))
    for i in range(14):
        x = -0.225 + i * 0.45 / 13
        tooth = cyl(0.007, 0.08, (x, 0.0, -0.005), verts=6)
        for v in tooth.data.vertices:
            if v.co.z < 0:
                v.co.x *= 0.5
                v.co.y = v.co.y * 0.5 - 0.012                                                 # tips curve forward
        parts.append(f.apply(tooth, "metal"))
    return parts


def pitchfork(f):
    """Four-tine fork, about 5 studs."""
    parts = [handle(f, 1.15, 0.32)]
    parts.append(f.apply(f.shape(box((0.06, 0.04, 0.08), (0, 0, 0.3))), "metal"))
    parts.append(f.apply(f.shape(box((0.2, 0.025, 0.03), (0, 0, 0.26))), "metal"))
    for i in range(4):
        x = -0.09 + i * 0.06
        tine = cyl(0.008, 0.26, (x, 0, 0.13), verts=5)
        for v in tine.data.vertices:
            if v.co.z < 0:
                v.co.x *= 0.4
                v.co.y *= 0.4  # pointed tips
        parts.append(f.apply(tine, "metal"))
    return parts


def hay_hook(f):
    """T handle with a curved iron hook, about 1.4 studs."""
    parts = [f.apply(f.shape(cyl(0.022, 0.16, (0, 0, 0.38), verts=6, rot=(0, math.pi / 2, 0))), "handle", along="x")]
    parts.append(f.apply(cyl(0.01, 0.16, (0, 0, 0.29), verts=6), "metal"))
    # Hook: a chain of short segments along a half circle.
    r, n = 0.08, 7
    for i in range(n):
        a0 = math.pi * i / n
        a1 = math.pi * (i + 1) / n
        p0 = (r * math.sin(a0), 0, 0.21 - r + r * math.cos(a0))
        p1 = (r * math.sin(a1), 0, 0.21 - r + r * math.cos(a1))
        mid = tuple((a + b) / 2 for a, b in zip(p0, p1))
        seg = cyl(0.01 * (1 - 0.5 * i / n), math.dist(p0, p1) * 1.15, mid, verts=6,
                  rot=(0, (a0 + a1) / 2 + math.pi / 2, 0))
        parts.append(f.apply(seg, "metal"))
    return parts


# ---------------------------------------------------------------- carriers and storage

def _wheelbarrow(f):
    """Shared body for wheelbarrow / wheelbarrow_loaded. Returns (parts, wheel_parts)."""
    parts = []
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    top = [face for face in bm.faces if face.normal.z > 0.9]
    bmesh.ops.delete(bm, geom=top, context="FACES")
    for v in bm.verts:
        v.co.x *= 0.75
        v.co.y *= 0.6
        v.co.z *= 0.3
        if v.co.z > 0:
            v.co.x *= 1.25
            v.co.y *= 1.25
            if v.co.x > 0:
                v.co.x += 0.12  # sloped front lip
    mesh = bpy.data.meshes.new("tray")
    bm.to_mesh(mesh)
    bm.free()
    tray = bpy.data.objects.new("tray", mesh)
    bpy.context.collection.objects.link(tray)
    tray.location = (0, 0, 0.45)
    bpy.context.view_layer.objects.active = tray
    bpy.ops.object.transform_apply(location=True)
    m = tray.modifiers.new("solid", "SOLIDIFY")
    m.thickness = 0.025
    bpy.ops.object.modifier_apply(modifier=m.name)
    parts.append(f.apply(f.shape(tray, round_edges=False), "handle", along="x"))
    # Rolled steel rim around the tray top (top corners: x -0.47..0.59, y +-0.375, z 0.6).
    x0, x1, yy, zt = -0.47, 0.59, 0.375, 0.6
    for y in (-yy, yy):
        parts.append(rod(f, "metal", (x0, y, zt), (x1, y, zt), 0.014, verts=6))
    for x in (x0, x1):
        parts.append(rod(f, "metal", (x, -yy, zt), (x, yy, zt), 0.014, verts=6))
    # Handles run from under the tray back past it, with rubber grips; steel legs with feet and a brace.
    for y in (-0.2, 0.2):
        parts.append(f.apply(f.shape(box((1.3, 0.04, 0.04), (-0.25, y, 0.27), rot=(0, 0.12, 0))), "handle", along="x"))
        parts.append(f.apply(cyl(0.026, 0.14, (-0.83, y, 0.34), verts=8, rot=(0, math.pi / 2 - 0.12, 0)), "tire"))
        parts.append(rod(f, "metal", (-0.3, y, 0.25), (-0.33, y * 1.15, 0.02), 0.014, verts=6))
        parts.append(f.apply(box((0.08, 0.05, 0.015), (-0.33, y * 1.15, 0.008)), "metal"))
        parts.append(rod(f, "metal", (-0.31, y, 0.15), (-0.05, y, 0.3), 0.01, verts=6))       # leg stay
        parts.append(f.apply(box((0.1, 0.012, 0.07), (0.44, y, 0.2), rot=(0, -0.4, 0)), "metal"))  # axle bracket
    parts.append(rod(f, "metal", (-0.32, -0.22, 0.12), (-0.32, 0.22, 0.12), 0.01, verts=6))
    # Wheel: rubber tyre, steel rim, six spokes, hub.
    c = (0.48, 0, 0.17)
    wheel = [f.apply(f.shape(cyl(0.17, 0.07, c, verts=18, rot=(math.pi / 2, 0, 0))), "tire", along="x"),
             f.apply(cyl(0.125, 0.075, c, verts=18, rot=(math.pi / 2, 0, 0)), "metal"),
             f.apply(cyl(0.04, 0.09, c, verts=8, rot=(math.pi / 2, 0, 0)), "metal")]
    for i in range(6):
        a = math.pi * i / 6
        wheel.append(f.apply(box((0.012, 0.012, 0.25), c, rot=(0, a, 0)), "metal"))
    return parts, wheel


def wheelbarrow(f):
    """About 5 x 2.5 x 2.5 studs: open wooden tray with a rolled rim, one spoked wheel at the front,
    two handles with rubber grips, steel legs."""
    parts, wheel = _wheelbarrow(f)
    return parts + wheel


def wheelbarrow_loaded(f):
    """Rigged wheelbarrow for carrying (art spec): the wheelbarrow scaled to the game's 5 x 3.6 tray and
    turned to face forward (wheel at the front, Roblox -Z), the wheel and hub as one Wheel_L1 mesh, and
    a loose-hay HayFill heap the game raises as it fills. Bales ride loose in game, so none are baked in."""
    from mathutils import Matrix
    parts, wheel = _wheelbarrow(f)
    hay = f.apply(f.shape(box((0.84, 0.62, 0.2), (0.02, 0, 0.52)), round_edges=False), "hay")
    rig.tag(wheel, "Wheel_L1")
    rig.tag([hay], "HayFill")
    parts += wheel + [hay]
    # Scale to the game's tray (Wheelbarrow.luau: 5 long x 3.6 wide inside); x and z scale together so
    # the wheel stays round.
    k = 5.0 / 3.4
    turn = Matrix.Rotation(math.pi / 2, 4, "Z") @ Matrix.Diagonal((k, 3.6 / 2.7, k, 1))
    for o in parts:
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
        o.data.transform(turn)
        o.data.update()
    return parts


def hay_crate(f):
    """Slatted crate, 3 x 3 x 2 studs. Spawned often, so the slats are unbevelled."""
    w, d, h = 3 * STUD, 3 * STUD, 2 * STUD
    parts = [f.apply(f.shape(box((w - 0.04, d - 0.04, 0.03), (0, 0, 0.03))), "handle", along="x")]
    slats = 3
    for i in range(slats):
        z = 0.08 + i * (h - 0.1) / slats + 0.05
        for sx, sy, size in ((0, -d / 2, (w, 0.025, 0.1)), (0, d / 2, (w, 0.025, 0.1)),
                             (-w / 2, 0, (0.025, d, 0.1)), (w / 2, 0, (0.025, d, 0.1))):
            along = "x" if size[0] > size[1] else "y"
            parts.append(f.apply(f.shape(box(size, (sx, sy, z)), round_edges=False), "handle", along=along))
    for x in (-w / 2, w / 2):
        for y in (-d / 2, d / 2):
            parts.append(f.apply(f.shape(box((0.06, 0.06, h), (x, y, h / 2)), round_edges=False), "handle", along="z"))
    # Some hay inside, heaped a little above the top.
    parts.append(f.apply(f.shape(box((w - 0.08, d - 0.08, h * 0.8), (0, 0, h * 0.45))), "hay"))
    return parts


def log(f):
    r, length = 0.24, 1.4
    parts = [f.apply(f.shape(cyl(r, length, (0, 0, r), verts=f.sides, rot=(0, math.pi / 2, 0))), "bark", along="x")]
    for side in (-1, 1):
        cap = cyl(r * 0.99, 0.01, (side * (length / 2 + 0.003), 0, r), verts=f.sides, rot=(0, math.pi / 2, 0))
        cap_uv(cap, 0, r)
        parts.append(f.apply(cap, "wood", uv="cap"))
    return parts


HAY_AND_TOOLS = {
    "hay_bale": hay_bale_prop,
    "round_bale": round_bale,
    "basic_shovel": basic_shovel,
    "wide_scoop": wide_scoop,
    "garden_rake": garden_rake,
    "pitchfork": pitchfork,
    "hay_hook": hay_hook,
    "wheelbarrow": wheelbarrow,
    "wheelbarrow_loaded": wheelbarrow_loaded,
    "hay_crate": hay_crate,
    "log": log,
}


GROUNDED = {"wide_scoop", "hay_hook", "garden_rake"}  # rest exactly on z=0 (art review P3)
MAX_TRIANGLES = 6000  # per prop by default; the body is decimated down to fit
# Mid-detail budgets per category (Cyrus 2026-10-13: "less low poly, more details, a good middle").
CATEGORY_TRIANGLES = {"vehicles": 12000, "special_vehicles": 12000, "truck_skins": 12000,
                      "buildings": 10000, "hub": 10000, "regions": 10000, "rides": 6000}
# Per-prop budgets that beat the category one (MODEL_SPECS "New triangle budgets": trailers <=6k).
KEY_TRIANGLES = {k: 6000 for k in ("wagon_trailer", "small_trailer", "medium_trailer", "large_trailer",
                                   "double_trailer", "bale_rack_trailer")}
MAX_MATERIALS = 4  # per mesh; Roblox imports one MeshPart per material (moving parts get 1)

CATEGORIES = ("scatter", "hay_and_tools", "tools", "gloves", "quest_gear", "finds", "needles", "vehicles", "special_vehicles", "storage",
              "buildings", "hub", "regions", "machines", "truck_skins", "rides")


def categories(wanted=CATEGORIES):
    """category name -> {prop key: builder}. Only the wanted category modules are imported."""
    cats = {"hay_and_tools": HAY_AND_TOOLS} if "hay_and_tools" in wanted else {}
    for name in wanted:
        if name == "hay_and_tools":
            continue
        try:
            mod = __import__(name)
        except ImportError:
            continue
        cats[name] = mod.PROPS
    return cats


def object_name(key):
    return "".join(w.capitalize() for w in key.split("_"))


def catalog(props, path):
    """Render a category: props laid out left to right in rows, small things in front."""
    common.reset_scene()
    f = style.rustic()
    objs = []
    for k, build in props.items():
        o = common.join(build(f), object_name(k))
        xs = [v.co.x + o.location.x for v in o.data.vertices]
        ys = [v.co.y + o.location.y for v in o.data.vertices]
        objs.append((o, max(xs) - min(xs), (max(xs) + min(xs)) / 2, max(ys) - min(ys), (max(ys) + min(ys)) / 2))
    # Biggest footprint at the back.
    objs.sort(key=lambda t: -(t[1] * t[3]))
    row_width = max(4.0, math.sqrt(sum(w * d for _, w, _, d, _ in objs)) * 1.6)
    gap = 0.3
    rows, row, used = [], [], 0.0
    for t in objs:
        if row and used + t[1] > row_width:
            rows.append(row)
            row, used = [], 0.0
        row.append(t)
        used += t[1] + gap
    rows.append(row)
    y = 0.0
    for row in rows:
        depth = max(t[3] for t in row)
        total = sum(t[1] for t in row) + gap * (len(row) - 1)
        x = -total / 2
        for o, w, cx, d, cy in row:
            o.location.x += x + w / 2 - cx
            o.location.y += y - depth / 2 - cy
            x += w + gap
        y -= depth + gap * 2
    common.render_preview(path, 1600, ground=GRASS)


def main():
    args = common.parse_args("rustic")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    cats = categories(argv[argv.index("--category") + 1].split(",") if "--category" in argv else CATEGORIES)
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else None
    out = args.out
    args.formats = "glb"

    rigs_path = os.path.join(out, "rigs.json")
    rigs = json.load(open(rigs_path)) if os.path.exists(rigs_path) else {}
    for cat, props in cats.items():
        for key, build in props.items():
            if only and key not in only:
                continue
            common.reset_scene()
            parts = build(style.rustic())
            flip = getattr(sys.modules.get(build.__module__), "RIG_FLIP", False)
            if flip or rig.is_rigged(parts):
                obj = rig.assemble(parts, object_name(key), common.join, flip=flip)
                objs = [obj] + list(obj.children)
            else:
                objs = [common.join(parts, object_name(key))]
            if key in GROUNDED:
                rig.ground(objs[0])
            rig.limit_materials(objs[0], MAX_MATERIALS)
            rig.limit_triangles(objs, KEY_TRIANGLES.get(key, CATEGORY_TRIANGLES.get(cat, MAX_TRIANGLES)))
            args.name = key
            common.export(objs, args)
            if len(objs) > 1:
                rigs[key] = rig.describe(objs, getattr(sys.modules.get(build.__module__), "BEDS", {}).get(key))
        if "--no-catalog" not in argv:
            catalog(props, os.path.join(out, f"catalog_{cat}.png"))
    with open(rigs_path, "w") as fh:
        json.dump(dict(sorted(rigs.items())), fh, indent=1)
        fh.write("\n")


if __name__ == "__main__":
    main()

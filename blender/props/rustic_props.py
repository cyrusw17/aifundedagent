"""Every game prop in the house style (LT2 shapes, Rustic finish).

Hay and starter tools are built here; tools.py, vehicles.py, storage.py, buildings.py and
machines.py each add a category. Each prop is exported on its own to
<out>/<name>.glb, and each category gets a catalog render <out>/catalog_<category>.png.

Run:
  blender --background --python blender/props/rustic_props.py -- --out blender/exports/rustic
  ... [--category vehicles] [--only basic_shovel,log] [--no-catalog]
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

def basic_shovel(f):
    """Small spade, about 2.7 studs tall."""
    parts = [handle(f, 0.48, 0.23)] + d_grip(f, 0.75)
    parts.append(f.apply(f.shape(box((0.05, 0.03, 0.06), (0, 0, 0.22))), "metal"))
    blade = box((0.17, 0.02, 0.2), (0, 0, 0.1))
    for v in blade.data.vertices:
        if v.co.z < 0:
            v.co.x *= 0.8
    parts.append(f.apply(f.shape(blade), "metal"))
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
    """Long rake, about 5 studs, with a wooden head and iron teeth."""
    parts = [handle(f, 1.3, 0.06)]
    parts.append(f.apply(f.shape(box((0.5, 0.05, 0.05), (0, 0, 0.06))), "handle", along="x"))
    for i in range(11):
        x = -0.22 + i * 0.044
        parts.append(f.apply(box((0.012, 0.012, 0.09), (x, 0.0, 0.0)), "metal"))
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

def wheelbarrow(f):
    """About 5 x 2.5 x 2.5 studs: open wooden tray, one wheel at the front, two handles."""
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
    # Handles run from under the tray back past it.
    for y in (-0.2, 0.2):
        parts.append(f.apply(f.shape(box((1.3, 0.04, 0.04), (-0.25, y, 0.27), rot=(0, 0.12, 0))), "handle", along="x"))
        parts.append(f.apply(f.shape(box((0.04, 0.04, 0.3), (-0.3, y, 0.15))), "handle", along="z"))
    wheel = cyl(0.17, 0.07, (0.48, 0, 0.17), verts=12, rot=(math.pi / 2, 0, 0))
    parts.append(f.apply(f.shape(wheel), "bark", along="x"))
    parts.append(f.apply(cyl(0.05, 0.08, (0.48, 0, 0.17), verts=8, rot=(math.pi / 2, 0, 0)), "metal"))
    return parts


def hay_crate(f):
    """Slatted crate, 3 x 3 x 2 studs."""
    w, d, h = 3 * STUD, 3 * STUD, 2 * STUD
    parts = [f.apply(f.shape(box((w - 0.04, d - 0.04, 0.03), (0, 0, 0.03))), "handle", along="x")]
    slats = 3
    for i in range(slats):
        z = 0.08 + i * (h - 0.1) / slats + 0.05
        for sx, sy, size in ((0, -d / 2, (w, 0.025, 0.1)), (0, d / 2, (w, 0.025, 0.1)),
                             (-w / 2, 0, (0.025, d, 0.1)), (w / 2, 0, (0.025, d, 0.1))):
            along = "x" if size[0] > size[1] else "y"
            parts.append(f.apply(f.shape(box(size, (sx, sy, z))), "handle", along=along))
    for x in (-w / 2, w / 2):
        for y in (-d / 2, d / 2):
            parts.append(f.apply(f.shape(box((0.06, 0.06, h), (x, y, h / 2))), "handle", along="z"))
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
    "hay_crate": hay_crate,
    "log": log,
}


CATEGORIES = ("hay_and_tools", "tools", "vehicles", "storage", "buildings", "machines")


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

    for cat, props in cats.items():
        for key, build in props.items():
            if only and key not in only:
                continue
            common.reset_scene()
            obj = common.join(build(style.rustic()), object_name(key))
            args.name = key
            common.export([obj], args)
        if "--no-catalog" not in argv:
            catalog(props, os.path.join(out, f"catalog_{cat}.png"))


if __name__ == "__main__":
    main()

"""Cosmetic skin explorations (Harvest Pass, Paint Studio, cosmetic shop; GAME_PLAN_V8 Part C 10).

Same Lumber Tycoon 2 shapes and Rustic finish as the game props; a skin only recolors the
palette (a copy of style.RUSTIC) and swaps some part kinds (e.g. metal -> steel, stitching -> glow),
plus optional thin trim strips (pinstripes, glowing rail edges) on top of the stock shapes.

Each skin renders one preview: rusty_pickup, leather_gloves (shown 3x size), hay bale and a
conveyor tile side by side on grass, labeled with the skin name.

Run:
  python blender/styles/skins.py [--out blender/exports/styles/skins] [--only autumn_harvest,gilded]
       [--res 1600] [--no-sheet]
Writes skin_<name>.png per skin and skins_overview.png (all six, 2 columns x 3 rows).
"""
import copy
import math
import os
import sys

import bpy  # must be imported before bmesh/mathutils with the pip bpy module

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, os.path.join(HERE, "..", "props"))
import common  # noqa: E402
import style  # noqa: E402
import gloves  # noqa: E402
import machines  # noqa: E402
import rustic_props  # noqa: E402
import vehicles  # noqa: E402
from style import box  # noqa: E402

STUD = 0.28
GRASS = rustic_props.GRASS
GLOVE_SCALE = 3.0

# ---------------------------------------------------------------- skins
# pal:      palette overrides (light, mid, dark) sRGB; spare kinds (paint_green, paint_blue,
#           paint_yellow, dirt, greywood...) are reused as extra color slots.
# map:      kind -> kind swaps for every prop.
# pickup:   body / upper (cab, above the bed rails) paint kinds.
# conveyor: rail (above the belt) / frame (below) kinds for the wooden boards.
# gloves, bale: per-prop kind swaps (take priority over map).
# trim:     kind for added pinstripes / rail edge strips, or None.

SKINS = {
    "autumn_harvest": dict(
        title="Autumn Harvest",
        pal={"paint_red": ((0.88, 0.52, 0.24), (0.78, 0.42, 0.17), (0.54, 0.27, 0.11)),     # burnt orange
             "paint_green": ((0.58, 0.20, 0.15), (0.48, 0.15, 0.11), (0.32, 0.10, 0.08)),   # deep red
             "cloth": ((0.92, 0.66, 0.22), (0.80, 0.42, 0.14), (0.52, 0.18, 0.10)),         # fallen leaves
             "leather": ((0.50, 0.33, 0.20), (0.40, 0.25, 0.15), (0.26, 0.16, 0.10)),
             "twine": ((0.58, 0.20, 0.15), (0.50, 0.16, 0.12), (0.34, 0.10, 0.08)),
             "hay": ((0.92, 0.80, 0.50), (0.82, 0.64, 0.34), (0.58, 0.42, 0.20)),
             "paint_yellow": ((0.90, 0.70, 0.30), (0.82, 0.58, 0.20), (0.60, 0.40, 0.12))},
        map={},
        pickup=dict(body="paint_red", upper="paint_green"),
        conveyor=dict(rail="paint_green", frame="leather"),
        gloves={"leather": "cloth", "twine": "paint_green", "paint_cream": "paint_yellow"},
        bale={},
        trim="paint_yellow"),
    "winter_frost": dict(
        title="Winter Frost",
        pal={"paint_red": ((0.76, 0.86, 0.94), (0.64, 0.77, 0.88), (0.46, 0.58, 0.70)),     # pale ice blue
             "paint_cream": ((0.97, 0.98, 1.00), (0.90, 0.93, 0.96), (0.72, 0.77, 0.82)),   # snow white
             "steel": ((0.90, 0.94, 0.98), (0.76, 0.82, 0.88), (0.58, 0.64, 0.70)),         # frosted steel
             "greywood": ((0.80, 0.84, 0.88), (0.66, 0.71, 0.76), (0.46, 0.50, 0.55)),      # frosted boards
             "twine": ((0.86, 0.92, 0.98), (0.80, 0.88, 0.96), (0.60, 0.70, 0.80)),
             "hay": ((0.92, 0.90, 0.80), (0.80, 0.76, 0.60), (0.60, 0.56, 0.42)),           # frost-dusted
             "glass": (None, (0.40, 0.55, 0.66), None)},
        map={"metal": "steel"},
        pickup=dict(body="paint_red", upper="paint_cream"),
        conveyor=dict(rail="paint_cream", frame="greywood"),
        gloves={"leather": "paint_red", "twine": "paint_cream"},
        bale={},
        trim="paint_cream"),
    "spring_bloom": dict(
        title="Spring Bloom",
        pal={"paint_green": ((0.70, 0.84, 0.62), (0.60, 0.76, 0.52), (0.42, 0.56, 0.36)),   # soft green
             "paint_cream": ((0.96, 0.93, 0.82), (0.90, 0.86, 0.72), (0.72, 0.68, 0.56)),   # cream
             "paint_yellow": ((0.96, 0.70, 0.78), (0.90, 0.58, 0.68), (0.70, 0.40, 0.50)),  # blossom pink
             "twine": ((0.94, 0.62, 0.72), (0.90, 0.56, 0.66), (0.70, 0.40, 0.50)),
             "hay": ((0.88, 0.86, 0.60), (0.76, 0.72, 0.44), (0.54, 0.52, 0.28))},           # fresh green-gold
        map={},
        pickup=dict(body="paint_green", upper="paint_cream"),
        conveyor=dict(rail="paint_cream", frame="paint_green"),
        gloves={"leather": "paint_green", "twine": "paint_cream", "paint_cream": "paint_yellow"},
        bale={},
        trim="paint_yellow"),
    "midnight_neon": dict(
        title="Midnight Neon",
        premium=True,
        pal={"paint_red": ((0.16, 0.17, 0.19), (0.11, 0.12, 0.14), (0.06, 0.06, 0.08)),     # near-black
             "steel": ((0.34, 0.36, 0.40), (0.26, 0.28, 0.31), (0.16, 0.17, 0.19)),         # gunmetal
             "greywood": ((0.22, 0.23, 0.25), (0.16, 0.17, 0.19), (0.10, 0.10, 0.12)),
             "glass": (None, (0.08, 0.16, 0.20), None),
             "twine": (None, (0.10, 0.11, 0.13), None),
             "glow": (None, (0.25, 0.95, 1.00), None)},                                     # cyan
        map={"metal": "steel", "paint_cream": "glow"},
        pickup=dict(body="paint_red", upper="paint_red"),
        conveyor=dict(rail="paint_red", frame="greywood"),
        gloves={"leather": "paint_red", "twine": "greywood"},
        bale={"twine": "glow"},
        trim="glow"),
    "gilded": dict(
        title="Gilded",
        premium=True,
        pal={"paint_cream": ((0.96, 0.92, 0.80), (0.90, 0.85, 0.70), (0.74, 0.68, 0.54)),   # cream paint
             "paint_yellow": ((1.00, 0.86, 0.42), (0.92, 0.72, 0.26), (0.66, 0.48, 0.14)),  # gold
             "steel": ((0.92, 0.92, 0.90), (0.80, 0.80, 0.78), (0.62, 0.62, 0.60)),         # bright steel
             "twine": (None, (0.92, 0.72, 0.26), None)},
        map={"metal": "steel"},
        pickup=dict(body="paint_cream", upper="paint_cream", lens="paint_yellow"),
        conveyor=dict(rail="paint_cream", frame="paint_cream"),
        gloves={"leather": "paint_cream", "twine": "paint_yellow", "paint_cream": "paint_yellow"},
        bale={},
        trim="paint_yellow"),
    "classic_two_tone": dict(
        title="Classic Two-Tone",
        pal={"paint_red": ((0.78, 0.26, 0.22), (0.68, 0.19, 0.16), (0.46, 0.12, 0.10)),     # classic red
             "paint_cream": ((0.95, 0.91, 0.78), (0.88, 0.83, 0.68), (0.70, 0.65, 0.52)),   # cream
             "twine": (None, (0.68, 0.19, 0.16), None)},
        map={"metal": "steel"},
        pickup=dict(body="paint_red", upper="paint_cream"),
        conveyor=dict(rail="paint_cream", frame="paint_red"),
        gloves={"leather": "paint_red", "twine": "paint_cream"},
        bale={},
        trim="paint_cream"),
}

ORDER = list(SKINS)


# ---------------------------------------------------------------- finish

def world_z(obj):
    zs = [obj.location.z + v.co.z for v in obj.data.vertices]
    return min(zs) / STUD, max(zs) / STUD


def skin_finish(name, ctx):
    """A Rustic finish with the skin's palette, and apply() swapping kinds per prop.
    ctx is a dict whose "prop" key names the prop being built (pickup, gloves, bale, conveyor)."""
    skin = SKINS[name]
    f = style.rustic()
    pal = copy.deepcopy(style.RUSTIC)
    pal.update(skin["pal"])
    f.pal = pal
    base_apply = f.apply

    def remap(obj, kind):
        prop = ctx["prop"]
        if prop == "pickup":
            p = skin["pickup"]
            if kind == "paint_red":
                return p["upper"] if world_z(obj)[1] > 7.0 else p["body"]
            if kind == "paint_cream" and "lens" in p:
                return p["lens"]
        if prop == "conveyor" and kind == "handle":
            c = skin["conveyor"]
            return c["rail"] if world_z(obj)[0] >= machines.BELT_Z - 0.01 else c["frame"]
        rules = skin.get(prop) if prop in ("gloves", "bale") else {}
        if kind in rules:
            return rules[kind]
        return skin["map"].get(kind, kind)

    def apply(obj, kind, along="x", uv="box"):
        return base_apply(obj, remap(obj, kind), along=along, uv=uv)

    f.apply = apply
    return f


def strip(f, kind, size, loc):
    """A thin flat trim strip in studs (no bevel)."""
    o = box(tuple(v * STUD for v in size), tuple(v * STUD for v in loc))
    return style.Finish.apply(f, o, kind)  # the stock apply: trim kinds are already final


# ---------------------------------------------------------------- props with trim

def pickup(f, skin):
    parts = vehicles.rusty_pickup(f)
    trim = skin["trim"]
    if trim:
        # Bed: outer width 10.8, rear end at the truck's back; a pinstripe along each side wall.
        ys = [o.location.y + v.co.y for o in parts for v in o.data.vertices]
        y_rear = max(ys) / STUD
        lo = vehicles.bed_len(3) + 2 * vehicles.WALL_T
        wo = vehicles.bed_wid(3) + 2 * vehicles.WALL_T
        yc = y_rear - lo / 2 - 0.1
        for x in (-1, 1):
            parts.append(strip(f, trim, (0.06, lo - 0.6, 0.22), (x * (wo / 2 + 0.06), yc, vehicles.FLOOR + 1.9)))
        # Cab belt line and a hood center stripe.
        W = 5.6 * 1.5 * 0.95
        cab = [o for o in parts if o.data.materials and abs((max(v.co.x for v in o.data.vertices)
                                                              - min(v.co.x for v in o.data.vertices)) / STUD - W) < 0.3]
        if cab:
            c = max(cab, key=lambda o: max(v.co.z for v in o.data.vertices) - min(v.co.z for v in o.data.vertices))
            y0 = (c.location.y + min(v.co.y for v in c.data.vertices)) / STUD
            y1 = (c.location.y + max(v.co.y for v in c.data.vertices)) / STUD
            zb = (c.location.z + min(v.co.z for v in c.data.vertices)) / STUD
            for x in (-1, 1):
                parts.append(strip(f, trim, (0.06, y1 - y0 - 0.2, 0.22), (x * (W / 2 + 0.06), (y0 + y1) / 2, zb + 2.6)))
    return parts


def conveyor(f, skin):
    parts = machines.PROPS["conveyor_straight"](f)
    trim = skin["trim"]
    if trim:
        z = machines.BELT_Z + machines.RAIL_H + 0.02
        for side in (-1, 1):
            y = side * (machines.BELT_W / 2 + machines.RAIL_T / 2)
            parts.append(strip(f, trim, (machines.TILE, machines.RAIL_T + 0.04, 0.08), (0, y, z + 0.04)))
    return parts


def label(text, x, y):
    bpy.ops.object.text_add(location=(x, y, 0.004))
    o = bpy.context.active_object
    o.data.body = text
    o.data.align_x = "CENTER"
    o.data.size = 3.2 * STUD
    o.data.extrude = 0.002
    bpy.ops.object.convert(target="MESH")
    o = bpy.context.active_object
    common.assign(o, common.material("Label", common.srgb((0.97, 0.95, 0.88)), roughness=0.7))
    return o


# ---------------------------------------------------------------- render

def render_skin(name, path, res):
    common.reset_scene()
    skin = SKINS[name]
    ctx = {"prop": None}
    f = skin_finish(name, ctx)
    objs = []
    for prop, build in (("pickup", lambda: pickup(f, skin)),
                        ("gloves", lambda: gloves.leather_gloves(f)),
                        ("bale", lambda: rustic_props.hay_bale_prop(f)),
                        ("conveyor", lambda: conveyor(f, skin))):
        ctx["prop"] = prop
        o = common.join(build(), f"{name}_{prop}")
        if prop == "pickup":
            o.rotation_euler = (0, 0, math.radians(-55))
        if prop == "gloves":
            o.scale = (GLOVE_SCALE,) * 3
        objs.append(o)
    bpy.context.view_layer.update()
    # Lay out left to right by world-space footprint, bottoms on the ground.
    x, gap = 0.0, 2.5 * STUD
    for o in objs:
        pts = [o.matrix_world @ v.co for v in o.data.vertices]
        x0, x1 = min(p.x for p in pts), max(p.x for p in pts)
        cy = (min(p.y for p in pts) + max(p.y for p in pts)) / 2
        o.location.x += x - x0
        o.location.y -= cy
        o.location.z -= min(p.z for p in pts)  # sit on the ground (the scaled glove dips below)
        x += (x1 - x0) + gap
        bpy.context.view_layer.update()
    title = skin["title"] + ("  (premium)" if skin.get("premium") else "")
    label(title, (x - gap) / 2, -12.0 * STUD)
    common.render_preview(path, res, ground=GRASS)
    print(f"[skins] wrote {path}")


def contact_sheet(paths, out, cell=(800, 400), cols=2):
    import numpy as np
    rows = (len(paths) + cols - 1) // cols
    W, H = cell[0] * cols, cell[1] * rows
    sheet = np.zeros((H, W, 4), dtype=np.float32)
    sheet[..., 3] = 1.0
    for i, p in enumerate(paths):
        img = bpy.data.images.load(p)
        img.scale(*cell)
        px = np.empty(cell[0] * cell[1] * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(cell[1], cell[0], 4)
        r, c = divmod(i, cols)
        y0 = (rows - 1 - r) * cell[1]  # image rows start at the bottom
        sheet[y0:y0 + cell[1], c * cell[0]:(c + 1) * cell[0]] = px
        bpy.data.images.remove(img)
    out_img = bpy.data.images.new("skins_overview", W, H)
    out_img.pixels.foreach_set(sheet.ravel())
    out_img.filepath_raw = out
    out_img.file_format = "PNG"
    out_img.save()
    print(f"[skins] wrote {out}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]

    def opt(name, default):
        return argv[argv.index(name) + 1] if name in argv else default

    out = os.path.abspath(opt("--out", os.path.join(HERE, "..", "exports", "styles", "skins")))
    only = opt("--only", None)
    res = int(opt("--res", 1600))
    os.makedirs(out, exist_ok=True)
    for name in (only.split(",") if only else ORDER):
        render_skin(name, os.path.join(out, f"skin_{name}.png"), res)
    if "--no-sheet" not in argv:
        paths = [os.path.join(out, f"skin_{n}.png") for n in ORDER]
        if all(os.path.exists(p) for p in paths):
            contact_sheet(paths, os.path.join(out, "skins_overview.png"))


if __name__ == "__main__":
    main()

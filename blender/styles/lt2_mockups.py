"""Lumber Tycoon 2 style mockups: simple part-built props, in two finishes.

  plain     - flat colors, like Roblox SmoothPlastic parts
  textured  - the same shapes with straw / bark / wood-grain textures,
              like Roblox Wood and Grass materials

Each scene shows a stack of square hay bales, a round hay bale, a small
shovel and a log.

Run:
  blender --background --python blender/styles/lt2_mockups.py -- --out blender/exports/styles
Writes lt2_plain.glb/.png and lt2_textured.glb/.png.
"""
import math
import os
import random
import sys

import bpy  # must be imported before bmesh/mathutils with the pip bpy module

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, os.path.join(HERE, "..", "props"))
import common  # noqa: E402
import hay_bale  # noqa: E402

GRASS = (0.42, 0.60, 0.28)

COLORS = {
    "hay": (0.89, 0.76, 0.40),
    "hay_end": (0.80, 0.66, 0.32),
    "twine": (0.55, 0.38, 0.22),
    "bark": (0.40, 0.28, 0.18),
    "wood": (0.85, 0.68, 0.45),
    "handle": (0.72, 0.52, 0.30),
    "metal": (0.62, 0.64, 0.68),
}


# ---------------------------------------------------------------- textures

def tileable_noise(seed, n=64):
    rng = random.Random(seed)
    return [rng.random() for _ in range(n)]


def lerp_row(rows, t):
    n = len(rows)
    x = t * n
    i = int(x) % n
    f = x - int(x)
    f = f * f * (3 - 2 * f)
    return rows[i] + (rows[(i + 1) % n] - rows[i]) * f


def straw_texture():
    rows = tileable_noise(1, 96)
    fine = tileable_noise(2, 256)
    lite, mid, dark = (0.98, 0.88, 0.55), (0.89, 0.75, 0.40), (0.70, 0.55, 0.25)

    def fn(u, v):
        t = lerp_row(rows, v)
        f = fine[int(v * 256) % 256]
        broken = 0.5 + 0.5 * math.sin(2 * math.pi * (3 * u + rows[int(v * 96) % 96] * 4))
        k = 0.55 * t + 0.25 * f + 0.2 * broken
        return common_mix(dark, common_mix(mid, lite, max(0, k - 0.5) * 2), min(1, k * 2))

    return common.make_texture("Straw", 256, fn)


def bark_texture():
    cols = tileable_noise(3, 48)
    fine = tileable_noise(4, 256)
    dark, mid = (0.24, 0.16, 0.10), (0.45, 0.32, 0.20)

    def fn(u, v):
        # Grooves run along u (the log's length).
        t = lerp_row(cols, v)
        g = 1 - abs(math.sin(math.pi * (v * 12 + t)))
        k = min(1, 0.6 * g ** 0.5 + 0.3 * fine[int(u * 256) % 256] * 0.5 + 0.2 * t)
        return common_mix(dark, mid, k)

    return common.make_texture("Bark", 256, fn)


def end_grain_texture():
    lite, dark = (0.92, 0.76, 0.52), (0.74, 0.55, 0.33)

    def fn(u, v):
        d = math.hypot(u - 0.5, v - 0.5) * 2
        if d > 0.92:
            return (0.40, 0.28, 0.18)  # bark rim
        ring = 0.5 + 0.5 * math.sin(d * 40 + math.sin(math.atan2(v - 0.5, u - 0.5) * 3) * 0.6)
        return common_mix(lite, dark, ring * 0.6 + d * 0.3)

    return common.make_texture("EndGrain", 128, fn)


def plank_texture():
    rows = tileable_noise(5, 32)
    lite, dark = (0.82, 0.62, 0.38), (0.64, 0.45, 0.26)

    def fn(u, v):
        t = lerp_row(rows, v)
        grain = 0.5 + 0.5 * math.sin(2 * math.pi * (v * 20 + math.sin(2 * math.pi * u) * 0.3 + t))
        return common_mix(dark, lite, 0.4 * grain + 0.6 * t)

    return common.make_texture("Plank", 128, fn)


def metal_texture():
    fine = tileable_noise(6, 128)
    return common.make_texture("Metal", 64, lambda u, v: tuple(
        c * (0.92 + 0.12 * fine[int((u * 7 + v * 3) * 128) % 128]) for c in COLORS["metal"]))


def common_mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


# ---------------------------------------------------------------- shapes

def cyl(r, depth, loc, verts=12, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return o


def box(size, loc, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return o


def cap_uv(obj, axis, r):
    """Planar UV across a log end, centered, so the ring texture lines up."""
    mesh = obj.data
    uv = mesh.uv_layers.get("UVMap") or mesh.uv_layers.new(name="UVMap")
    a, b = [i for i in range(3) if i != axis]
    for li, loop in enumerate(mesh.loops):
        co = mesh.vertices[loop.vertex_index].co
        uv.data[li].uv = (co[a] / (2 * r) + 0.5, co[b] / (2 * r) + 0.5)


class Finish:
    """Gives each part its material for the chosen finish."""

    def __init__(self, textured):
        self.textured = textured
        self.mats = {}
        if textured:
            self.tex = {"straw": straw_texture(), "bark": bark_texture(), "end": end_grain_texture(),
                        "plank": plank_texture(), "metal": metal_texture()}

    def _mat(self, key, make):
        if key not in self.mats:
            self.mats[key] = make()
        return self.mats[key]

    def apply(self, obj, kind, along="x"):
        if not self.textured:
            color = COLORS[kind]
            mat = self._mat(kind, lambda: common.material(kind, common.srgb(color), roughness=0.6,
                                                          metallic=0.5 if kind == "metal" else 0.0))
        else:
            tex_key = {"hay": "straw", "hay_end": "straw", "twine": "plank", "bark": "bark", "wood": "end",
                       "handle": "plank", "metal": "metal"}[kind]
            if kind == "twine":
                mat = self._mat("twine", lambda: common.material("twine", common.srgb(COLORS["twine"]), 0.9))
            else:
                mat = self._mat(tex_key, lambda: common.texture_material(
                    tex_key, self.tex[tex_key], metallic=0.5 if kind == "metal" else 0.0))
                if kind != "wood":
                    common.box_uv(obj, scale=1.6, along=along)
        common.assign(obj, mat)
        return obj


# ---------------------------------------------------------------- props

def square_bale(finish, loc, yaw=0.0):
    hay = hay_bale.build_hay()
    bands = hay_bale.build_twine()
    parts = [finish.apply(hay, "hay")] + [finish.apply(b, "twine") for b in bands]
    obj = common.join(parts, "SquareBale")
    obj.rotation_euler = (0, 0, yaw)
    obj.location = loc
    return obj


def round_bale(finish, loc):
    r, width = 0.5, 0.95
    body = cyl(r, width, (0, 0, r), verts=20, rot=(math.pi / 2, 0, 0))
    finish.apply(body, "hay", along="x")
    parts = [body]
    if finish.textured:
        # Ends show the rolled-up hay as rings.
        for side in (-1, 1):
            cap = cyl(r * 0.97, 0.01, (0, side * (width / 2 + 0.002), r), verts=20, rot=(math.pi / 2, 0, 0))
            cap_uv(cap, 1, r)
            common.assign(cap, finish._mat("straw_end", lambda: common.texture_material(
                "straw_end", common.make_texture("RolledHay", 128, lambda u, v: common_mix(
                    (0.95, 0.83, 0.48), (0.75, 0.60, 0.30),
                    0.5 + 0.5 * math.sin(math.hypot(u - 0.5, v - 0.5) * 70))))))
            parts.append(cap)
    for y in (-0.25, 0.0, 0.25):
        band = cyl(r + 0.004, 0.025, (0, y, r), verts=20, rot=(math.pi / 2, 0, 0))
        parts.append(finish.apply(band, "twine"))
    obj = common.join(parts, "RoundBale")
    obj.location = loc
    return obj


def small_shovel(finish, loc):
    """A short spade, about 2.7 studs tall: hand-tool size."""
    parts = []
    handle = cyl(0.018, 0.48, (0, 0, 0.47), verts=8)
    parts.append(finish.apply(handle, "handle", along="z"))
    grip = cyl(0.016, 0.12, (0, 0, 0.73), verts=8, rot=(0, math.pi / 2, 0))
    parts.append(finish.apply(grip, "handle", along="x"))
    for x in (-0.055, 0.055):
        post = box((0.02, 0.02, 0.06), (x * 0.9, 0, 0.70), rot=(0, x * 4, 0))
        parts.append(finish.apply(post, "handle", along="z"))
    neck = box((0.05, 0.03, 0.06), (0, 0, 0.22))
    parts.append(finish.apply(neck, "metal"))
    blade = box((0.17, 0.02, 0.2), (0, 0, 0.1))
    for v in blade.data.vertices:
        if v.co.z < 0:
            v.co.x *= 0.8
    parts.append(finish.apply(blade, "metal"))
    obj = common.join(parts, "SmallShovel")
    obj.location = loc
    return obj


def log(finish, loc):
    r, length = 0.24, 1.4
    body = cyl(r, length, (0, 0, r), verts=12, rot=(0, math.pi / 2, 0))
    finish.apply(body, "bark", along="x")
    parts = [body]
    for side in (-1, 1):
        cap = cyl(r * 0.995, 0.01, (side * (length / 2 + 0.003), 0, 0), verts=12, rot=(0, math.pi / 2, 0))
        cap_uv(cap, 0, r)
        cap.location.z = r
        finish.apply(cap, "wood")
        parts.append(cap)
    obj = common.join(parts, "Log")
    obj.location = loc
    return obj


def build_scene(textured):
    finish = Finish(textured)
    L, W, H = hay_bale.SIZE
    objs = [
        # Two bales side by side, one across the top: they stack because 2 x width = length.
        square_bale(finish, (0, -W / 2, 0)),
        square_bale(finish, (0, W / 2, 0)),
        square_bale(finish, (0, 0, H), yaw=math.pi / 2),
        round_bale(finish, (1.45, 0, 0)),
        small_shovel(finish, (2.35, -0.1, 0)),
        log(finish, (3.45, 0, 0)),
    ]
    return objs


def main():
    args = common.parse_args("lt2")
    args.formats = "glb"
    base, out = args.name, args.out
    for name, textured in (("plain", False), ("textured", True)):
        common.reset_scene()
        objs = build_scene(textured)
        args.name = f"{base}_{name}"
        common.export(objs, args)
        common.render_preview(os.path.join(out, f"{args.name}.png"), 1400, ground=GRASS)


if __name__ == "__main__":
    main()

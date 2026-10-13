"""House art style: Lumber Tycoon 2 shapes with a Rustic finish.

Chosen by Cyrus on 2026-10-13. Every prop builds its parts with cyl()/box(),
then calls RUSTIC_FINISH.shape(part) and .apply(part, kind) so materials,
bevels and the weathered unevenness stay consistent across the game.

Kinds: hay, bark, wood (end grain), handle (plank wood), metal (weathered grey), twine.
The other finishes (plain, textured, painted, faceted, soft) are kept for the
mockups in styles/lt2_mockups.py.
"""
import math
import random

import bpy

import common

# sRGB palettes. Each texture uses (light, mid, dark); flat finishes use mid.
BASE = {
    "hay": ((0.98, 0.88, 0.55), (0.89, 0.75, 0.40), (0.70, 0.55, 0.25)),
    "bark": ((0.45, 0.32, 0.20), (0.40, 0.28, 0.18), (0.24, 0.16, 0.10)),
    "wood": ((0.92, 0.76, 0.52), (0.85, 0.68, 0.45), (0.74, 0.55, 0.33)),
    "handle": ((0.82, 0.62, 0.38), (0.72, 0.52, 0.30), (0.64, 0.45, 0.26)),
    "metal": ((0.70, 0.72, 0.76), (0.62, 0.64, 0.68), (0.50, 0.52, 0.56)),
    "twine": ((0.60, 0.42, 0.25), (0.55, 0.38, 0.22), (0.45, 0.30, 0.18)),
}
PAINTED = {
    "hay": ((1.00, 0.90, 0.45), (0.98, 0.76, 0.22), (0.80, 0.50, 0.10)),
    "bark": ((0.55, 0.32, 0.16), (0.46, 0.26, 0.12), (0.26, 0.13, 0.06)),
    "wood": ((1.00, 0.82, 0.52), (0.95, 0.70, 0.40), (0.78, 0.48, 0.22)),
    "handle": ((0.92, 0.60, 0.30), (0.82, 0.50, 0.22), (0.66, 0.36, 0.14)),
    "metal": ((0.78, 0.82, 0.90), (0.62, 0.68, 0.78), (0.42, 0.46, 0.56)),
    "twine": ((0.85, 0.25, 0.20), (0.78, 0.20, 0.16), (0.60, 0.14, 0.10)),
}
RUSTIC = {
    "hay": ((0.86, 0.80, 0.60), (0.74, 0.66, 0.44), (0.52, 0.45, 0.28)),
    "bark": ((0.38, 0.33, 0.27), (0.30, 0.25, 0.20), (0.16, 0.13, 0.10)),
    "wood": ((0.80, 0.70, 0.55), (0.70, 0.60, 0.45), (0.52, 0.43, 0.32)),
    "handle": ((0.60, 0.50, 0.38), (0.50, 0.41, 0.30), (0.36, 0.29, 0.21)),
    "metal": ((0.58, 0.58, 0.57), (0.48, 0.48, 0.47), (0.40, 0.38, 0.35)),  # clean weathered grey iron, light wear
    "twine": ((0.45, 0.40, 0.32), (0.38, 0.33, 0.26), (0.28, 0.24, 0.18)),
    # Weathered paint, stone and cloth for vehicles, machines and buildings.
    "paint_red": ((0.62, 0.30, 0.24), (0.52, 0.24, 0.19), (0.36, 0.18, 0.14)),
    "paint_green": ((0.42, 0.50, 0.34), (0.34, 0.42, 0.28), (0.24, 0.30, 0.20)),
    "paint_blue": ((0.40, 0.48, 0.55), (0.32, 0.39, 0.46), (0.22, 0.27, 0.32)),
    "paint_cream": ((0.86, 0.82, 0.70), (0.78, 0.73, 0.60), (0.60, 0.55, 0.44)),
    "paint_yellow": ((0.82, 0.68, 0.34), (0.72, 0.58, 0.26), (0.52, 0.40, 0.18)),
    "stone": ((0.66, 0.63, 0.58), (0.56, 0.53, 0.49), (0.40, 0.38, 0.35)),
    "cloth": ((0.84, 0.80, 0.68), (0.74, 0.70, 0.58), (0.56, 0.52, 0.42)),
    "steel": ((0.78, 0.78, 0.76), (0.66, 0.66, 0.64), (0.50, 0.50, 0.48)),  # galvanized, unrusted
    "dirt": ((0.58, 0.48, 0.36), (0.48, 0.39, 0.29), (0.34, 0.27, 0.20)),
    "leather": ((0.56, 0.40, 0.27), (0.46, 0.32, 0.21), (0.32, 0.22, 0.15)),
    "greywood": ((0.55, 0.53, 0.49), (0.45, 0.43, 0.40), (0.30, 0.29, 0.27)),  # sun-bleached grey boards
    # Region scatter (STYLE.md "Regions" leaves / bark / ground, light-mid-dark).
    "leaf_oak": ((0.36, 0.46, 0.28), (0.30, 0.40, 0.23), (0.23, 0.31, 0.18)),     # Meadow
    "leaf_pine": ((0.24, 0.36, 0.28), (0.19, 0.30, 0.23), (0.13, 0.21, 0.16)),    # Pine Forest
    "leaf_snow": ((0.26, 0.36, 0.33), (0.21, 0.30, 0.28), (0.14, 0.21, 0.20)),    # Snow Peak
    "leaf_desert": ((0.50, 0.58, 0.42), (0.42, 0.50, 0.35), (0.30, 0.37, 0.26)),  # Desert (cactus)
    "leaf_swamp": ((0.36, 0.44, 0.26), (0.29, 0.36, 0.21), (0.20, 0.25, 0.15)),   # Swamp (reeds)
    "bark_pine": ((0.34, 0.27, 0.21), (0.26, 0.20, 0.15), (0.14, 0.11, 0.08)),
    "bark_swamp": ((0.30, 0.28, 0.24), (0.23, 0.21, 0.18), (0.12, 0.11, 0.10)),
    "snow": ((0.95, 0.96, 0.97), (0.92, 0.93, 0.94), (0.80, 0.82, 0.85)),         # #EBEDF0
    "sand": ((0.82, 0.73, 0.56), (0.76, 0.66, 0.49), (0.62, 0.52, 0.38)),         # Desert ground
    "lilac": ((0.70, 0.57, 0.78), (0.60, 0.47, 0.69), (0.44, 0.33, 0.52)),        # Epic needle tier #9A78B0
    "gold": ((0.90, 0.76, 0.42), (0.79, 0.65, 0.29), (0.58, 0.46, 0.18)),         # quest gold #C9A54A, no glow
    "coral": ((0.93, 0.62, 0.52), (0.85, 0.50, 0.42), (0.62, 0.34, 0.28)),        # Thimble Keys coral needle
    "brass": ((0.80, 0.66, 0.38), (0.66, 0.52, 0.26), (0.46, 0.35, 0.17)),        # Bobbin Rock brass needle
    # Flat, untextured.
    "tire": (None, (0.13, 0.12, 0.11), None),
    "glass": (None, (0.20, 0.26, 0.28), None),
    "glow": (None, (0.55, 0.95, 0.90), None),
    "lava": (None, (1.00, 0.45, 0.12), None),  # orange glow for fire and lava
    "firefly": (None, (0.70, 0.76, 0.36), None),  # Swamp accent glow
}
# Kinds that stay flat even in textured finishes, and their extra material settings.
FLAT = {"tire": {"roughness": 0.9}, "glass": {"roughness": 0.1, "metallic": 0.3},
        "glow": {"roughness": 0.4, "emission": 2.0}, "lava": {"roughness": 0.5, "emission": 2.5},
        "firefly": {"roughness": 0.4, "emission": 3.0}}
# Kinds that use the blotchy weathered texture.
WEATHERED = ("paint_red", "paint_green", "paint_blue", "paint_cream", "paint_yellow", "stone", "cloth", "steel", "dirt", "leather", "greywood",
             "leaf_oak", "leaf_pine", "leaf_snow", "leaf_desert", "leaf_swamp", "bark_pine", "bark_swamp", "snow", "sand", "lilac", "gold",
             "coral", "brass")
SOFT = {
    "hay": (None, (1.00, 0.86, 0.55), None),
    "bark": (None, (0.66, 0.45, 0.34), None),
    "wood": (None, (1.00, 0.84, 0.64), None),
    "handle": (None, (0.90, 0.64, 0.44), None),
    "metal": (None, (0.70, 0.80, 0.90), None),
    "twine": (None, (0.90, 0.48, 0.42), None),
}

VARIANTS = {
    #           palette   textures  contrast  bevel  sides  facets  lumpy
    "plain":    (BASE,    False,    1.0,      0.025, 12,    False,  0.0),
    "textured": (BASE,    True,     1.0,      0.025, 12,    False,  0.0),
    "painted":  (PAINTED, True,     1.4,      0.035, 12,    False,  0.0),
    "rustic":   (RUSTIC,  True,     1.2,      0.012, 10,    False,  0.012),
    "faceted":  (BASE,    False,    1.0,      0.0,   7,     True,   0.015),
    "soft":     (SOFT,    False,    1.0,      0.09,  24,    False,  0.0),
}


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


# ---------------------------------------------------------------- textures

def noise(seed, n=64):
    rng = random.Random(seed)
    return [rng.random() for _ in range(n)]


def smooth_lookup(vals, t):
    n = len(vals)
    x = t * n
    i = int(x) % n
    f = x - int(x)
    f = f * f * (3 - 2 * f)
    return vals[i] + (vals[(i + 1) % n] - vals[i]) * f


def contrast(k, c):
    return max(0.0, min(1.0, 0.5 + (k - 0.5) * c))


def straw_texture(pal, c):
    lite, mid, dark = pal
    rows, fine = noise(1, 96), noise(2, 256)

    def fn(u, v):
        t = smooth_lookup(rows, v)
        broken = 0.5 + 0.5 * math.sin(2 * math.pi * (3 * u + rows[int(v * 96) % 96] * 4))
        k = contrast(0.55 * t + 0.25 * fine[int(v * 256) % 256] + 0.2 * broken, c)
        return mix(dark, mid, k * 2) if k < 0.5 else mix(mid, lite, (k - 0.5) * 2)

    return fn


def bark_texture(pal, c):
    lite, mid, dark = pal
    cols, fine = noise(3, 48), noise(4, 256)

    def fn(u, v):
        t = smooth_lookup(cols, v)
        g = 1 - abs(math.sin(math.pi * (v * 12 + t)))
        k = contrast(min(1, 0.6 * g ** 0.5 + 0.15 * fine[int(u * 256) % 256] + 0.2 * t), c)
        return mix(dark, lite, k)

    return fn


def end_grain_texture(pal, c, rim):
    lite, mid, dark = pal

    def fn(u, v):
        d = math.hypot(u - 0.5, v - 0.5) * 2
        if d > 0.92:
            return rim
        ring = 0.5 + 0.5 * math.sin(d * 40 + math.sin(math.atan2(v - 0.5, u - 0.5) * 3) * 0.6)
        return mix(lite, dark, contrast(ring * 0.6 + d * 0.3, c))

    return fn


def plank_texture(pal, c):
    lite, mid, dark = pal
    rows = noise(5, 32)

    def fn(u, v):
        t = smooth_lookup(rows, v)
        grain = 0.5 + 0.5 * math.sin(2 * math.pi * (v * 20 + math.sin(2 * math.pi * u) * 0.3 + t))
        return mix(dark, lite, contrast(0.4 * grain + 0.6 * t, c))

    return fn


def metal_texture(pal, c, rusty):
    lite, mid, dark = pal
    fine = noise(6, 128)
    blotch = noise(7, 32)

    def fn(u, v):
        k = fine[int((u * 7 + v * 3) * 128) % 128]
        col = mix(mid, lite, k * 0.4)
        if rusty and smooth_lookup(blotch, (u * 3 + v) % 1) > 0.75:
            col = mix(col, dark, 0.45)  # light wear spots, not heavy rust
        return col

    return fn


def value_noise_2d(seed, n):
    """Tileable 2D value noise on an n x n grid, smoothly interpolated: fn(u, v) -> 0..1."""
    rng = random.Random(seed)
    grid = [[rng.random() for _ in range(n)] for _ in range(n)]

    def fn(u, v):
        x, y = (u % 1) * n, (v % 1) * n
        i, j = int(x), int(y)
        fx, fy = x - i, y - j
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        i1, j1 = (i + 1) % n, (j + 1) % n
        a = grid[j % n][i % n] + (grid[j % n][i1] - grid[j % n][i % n]) * fx
        b = grid[j1][i % n] + (grid[j1][i1] - grid[j1][i % n]) * fx
        return a + (b - a) * fy

    return fn


def weathered_texture(pal, c, seed, blotch=0.4):
    """Faded paint / stone / canvas: soft blotches, faint grain, a few chips and vertical streaks."""
    lite, mid, dark = pal
    big = value_noise_2d(seed, 4)
    fine = value_noise_2d(seed + 1, 32)
    chips = value_noise_2d(seed + 2, 12)
    streaks = noise(seed + 3, 24)

    def fn(u, v):
        k = 0.55 + (big(u, v) - 0.5) * blotch + (fine(u, v) - 0.5) * 0.12
        k -= 0.08 * max(0.0, smooth_lookup(streaks, u) - 0.6) * 2.5   # rain streaks run down (v)
        if chips(u, v) > 0.8:
            k -= 0.18                                                  # a few worn chips
        k = contrast(k, c)
        return mix(dark, mid, k * 2) if k < 0.5 else mix(mid, lite, (k - 0.5) * 2)

    return fn


def rolled_hay_texture(pal, c):
    lite, mid, dark = pal

    def fn(u, v):
        # A soft spiral wound from the center, at half contrast, instead of hard rings.
        du, dv = u - 0.5, v - 0.5
        r, a = math.hypot(du, dv), math.atan2(dv, du)
        k = 0.5 + 0.25 * math.sin(r * 55 - a)
        return mix(lite, dark, contrast(k, c * 0.5))

    return fn


# ---------------------------------------------------------------- finish

class Finish:
    """Turns a variant name into materials, bevels and shape tweaks for every part."""

    def __init__(self, variant):
        self.name = variant
        (self.pal, self.textured, self.contrast, self.bevel, self.sides,
         self.faceted, self.lumpy) = VARIANTS[variant]
        self.rng = random.Random(42)
        self.mats = {}

    def _mat(self, key, make):
        if key not in self.mats:
            self.mats[key] = make()
        return self.mats[key]

    def _texture(self, kind):
        pal, c = self.pal.get(kind), self.contrast
        rusty = self.name == "rustic"
        fn = {"hay": lambda: straw_texture(pal, c),
              "bark": lambda: bark_texture(pal, c),
              "wood": lambda: end_grain_texture(pal, c, self.pal["bark"][1]),
              "handle": lambda: plank_texture(pal, c),
              "metal": lambda: metal_texture(pal, c, rusty),
              "rolled": lambda: rolled_hay_texture(self.pal["hay"], c)}.get(kind)
        # Paint reads as solid color at driving distance: half the blotch of stone and cloth (art review B2-1).
        fn = fn() if fn else weathered_texture(pal, c, 10 + WEATHERED.index(kind),
                                               blotch=0.2 if kind.startswith("paint_") else 0.4)
        return common.make_texture(f"{self.name}_{kind}", 256 if kind in ("hay", "bark") else 128, fn)

    def shape(self, obj, round_edges=True):
        """Bevel, roughen and shade a part to match the variant."""
        if self.bevel and round_edges:
            m = obj.modifiers.new("bevel", "BEVEL")
            m.width = self.bevel
            m.segments = 3 if self.name == "soft" else 2
            m.limit_method = "ANGLE"
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.modifier_apply(modifier=m.name)
        if self.lumpy:
            # Scale the wobble to the part so small pieces (caps, tips) don't crumple.
            dims = [max(v.co[i] for v in obj.data.vertices) - min(v.co[i] for v in obj.data.vertices) for i in range(3)]
            amount = min(self.lumpy, min(dims) * 0.05)
            for v in obj.data.vertices:
                v.co += v.normal * self.rng.uniform(-amount, amount)
        for p in obj.data.polygons:
            p.use_smooth = self.name == "soft"
        return obj

    def apply(self, obj, kind, along="x", uv="box"):
        """Give a part its material. kind is one of the palette keys (hay, bark, wood, handle, metal,
        twine, paint_red/green/blue/cream/yellow, stone, cloth, steel, dirt, tire, glass, glow)."""
        metallic = 0.5 if kind in ("metal", "steel") else 0.0
        if kind in FLAT:
            opts = FLAT[kind]

            def make():
                m = common.material(kind, common.srgb(self.pal[kind][1]), roughness=opts["roughness"],
                                    metallic=opts.get("metallic", 0.0))
                if "emission" in opts:
                    bsdf = m.node_tree.nodes.get("Principled BSDF")
                    bsdf.inputs["Emission Color"].default_value = (*common.srgb(self.pal[kind][1]), 1)
                    bsdf.inputs["Emission Strength"].default_value = opts["emission"]
                return m

            common.assign(obj, self._mat(kind, make))
            return obj
        if self.textured and kind != "twine":
            key = "rolled" if uv == "rolled" else kind
            mat = self._mat(key, lambda: common.texture_material(f"{self.name}_{key}", self._texture(key),
                                                                 metallic=metallic))
            if uv == "box":
                common.box_uv(obj, scale=1.6, along=along)
        elif self.faceted:
            base = self.pal[kind][1]
            tones = {}

            def fn(p, c):
                if p.index not in tones:
                    k = 1 + self.rng.uniform(-0.07, 0.07) + max(0.0, p.normal.z) * 0.12
                    tones[p.index] = tuple(min(1.0, x * k) for x in base)
                return tones[p.index]

            common.paint(obj, fn)
            mat = self._mat("faceted", lambda: common.vertex_color_material("faceted", roughness=0.8))
        else:
            color = self.pal[kind][1]
            mat = self._mat(kind, lambda: common.material(kind, common.srgb(color),
                                                          roughness=0.5 if self.name == "soft" else 0.6,
                                                          metallic=metallic))
        common.assign(obj, mat)
        return obj


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


def rustic():
    """The house finish. Make one per scene (it caches materials)."""
    return Finish("rustic")

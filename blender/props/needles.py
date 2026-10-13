"""Needles, the bins and walls that hold them, and the region hay bales they come out of.

Sizes match the game (Needle.luau): a needle is 1.2 studs long and 0.15 thick, a bundle of ten is
1.3 x 0.55 x 0.55. Every needle lies flat on the ground along x, point toward +x, eye toward -x.

  needle_<tier>      common, uncommon, rare, epic, legendary: one 96-tri mesh, only the materials
                     differ (grey iron, sage, blue steel, lilac + glowing eye pin, gold + glowing spine)
  needle_<type>      one sorted needle per type (12), each <= 120 tris: steel, pine, sand, ice, bog,
                     obsidian, geode, cloud, phantom, cosmic, pearl, anchor
  needle_rainbow     mutation: painted stripes down the shaft
  needle_giant       mutation: a steel needle three times the size
  needle_glitch      mutation: stair-stepped blocky segments with a glow accent
  needle_bundle      3 x 0.6 x 0.6: ten grey needles, eyes at one end, two twine bands
  needle_bin         6 x 6 stud open wooden bin (one conveyor tile), iron corners; pile is "NeedleFill"
  bale_<region>      the standard 4.6 x 2.6 x 3.2 bale in each region's hay (9 regions)
  needle_display_wall 6 x 1 x 7.8 one-tile wall (Display.luau): 6 pegs on red velvet, brass plaques

Every prop uses 4 materials or fewer.
Region bales use the house straw texture with a region palette (a local material, not a new kind
in style.py), plus small flush surface details so they keep the exact bale size.

Run:
  python blender/props/rustic_props.py --out <dir> --category needles
"""
import math
import os
import random
import sys

import bpy  # noqa: F401  (must be imported before mathutils with the pip bpy module)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, HERE)
from mathutils import Matrix  # noqa: E402

import common  # noqa: E402
import hay_bale  # noqa: E402
import style  # noqa: E402
from rig import tag  # noqa: E402
from style import box, cyl  # noqa: E402

STUD = 0.28
NEEDLE_L, NEEDLE_T = 1.2, 0.15          # game needle part: 1.2 x 0.15 x 0.15 studs


def s(*v):
    return tuple(x * STUD for x in v)


def B(f, kind, size, loc, rot=(0, 0, 0), along="x", rounded=False):
    return f.apply(f.shape(box(s(*size), s(*loc), rot=rot), round_edges=rounded), kind, along=along)


def C(f, kind, r, depth, loc, axis="x", verts=8, rounded=False):
    rot = {"x": (0, math.pi / 2, 0), "y": (math.pi / 2, 0, 0), "z": (0, 0, 0)}[axis]
    return f.apply(f.shape(cyl(r * STUD, depth * STUD, s(*loc), verts=verts, rot=rot), round_edges=rounded),
                   kind, along=axis)


def move(parts, dx=0.0, dy=0.0, dz=0.0, rz=0.0, rx=0.0):
    """Turn parts about the origin (rx then rz) and shift them, in studs. Bakes into the mesh."""
    m = Matrix.Translation(s(dx, dy, dz)) @ Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(rx, 4, "X")
    for o in parts:
        o.data.transform(o.matrix_basis)
        o.matrix_basis = Matrix.Identity(4)
        o.data.transform(m)
    return parts


# ---------------------------------------------------------------- needle parts

def ring(f, kind, cx, outer, inner, n, z, h, phase=0.0):
    """A flat ring lying on the ground plane: an n-sided band between an outer and inner ellipse
    (radii in studs, x then y), centered at x = cx, h tall around height z. 8n triangles."""
    import bmesh
    bm = bmesh.new()
    rows = []
    for (rx, ry), zz in ((outer, z - h / 2), (outer, z + h / 2), (inner, z + h / 2), (inner, z - h / 2)):
        rows.append([bm.verts.new(s(cx + rx * math.cos(phase + 2 * math.pi * i / n),
                                    ry * math.sin(phase + 2 * math.pi * i / n), zz)) for i in range(n)])
    for r in range(4):
        a, b = rows[r], rows[(r + 1) % 4]
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("ring")
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new("ring", mesh)
    bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    return f.apply(f.shape(o, round_edges=False), kind, along="x")


def tip(f, kind, x0, x1, r, z, verts=6):
    """Tapered point from x0 to x1 (x1 is the sharp end)."""
    o = cyl(r * STUD, (x1 - x0) * STUD, s((x0 + x1) / 2, 0, z), verts=verts, rot=(0, math.pi / 2, 0))
    for v in o.data.vertices:
        if v.co.x > 0:
            v.co.y *= 0.06
            v.co.z *= 0.06
    return f.apply(f.shape(o, round_edges=False), kind, along="x")


EYE_LEN = {"slot": 0.2, "ring": 0.2, "diamond": 0.22, "bead": 0.16, "anchor": 0.2, "none": 0.04}


def needle(f, body, tip_kind=None, eye="slot", eye_kind=None, k=1.0, verts=6, shaft=True):
    """A needle k times game size (1.2 x 0.15 studs) along x, resting on z=0, point toward +x.
    Six-sided shaft and point (40 tris) plus the eye (slot 32, ring 48, diamond 32).
    Returns (parts, info): info gives the shaft span a..b, axis height z, radius r and the ends."""
    L, r = NEEDLE_L * k, NEEDLE_T / 2 * k
    z = r
    x0, x1 = -L / 2, L / 2
    a, b = x0 + EYE_LEN[eye] * k, x1 - 0.32 * k
    parts = []
    if shaft:
        parts.append(C(f, body, r, b - a + 0.04 * k, ((a + b) / 2, 0, z), verts=verts))
        parts.append(tip(f, tip_kind or body, b - 0.01 * k, x1, r, z, verts=verts))
    ek = eye_kind or body
    if eye == "slot":        # long eye: a rounded-rectangle band around an open slot
        parts.append(ring(f, ek, x0 + 0.11 * k, (0.155 * k, 0.117 * k), (0.085 * k, 0.045 * k), 4, z, 0.11 * k,
                          phase=math.pi / 4))
    elif eye == "ring":
        parts.append(ring(f, ek, x0 + 0.1 * k, (0.1 * k, 0.1 * k), (0.05 * k, 0.05 * k), 6, z, 0.1 * k))
    elif eye == "diamond":
        parts.append(ring(f, ek, x0 + 0.11 * k, (0.12 * k, 0.12 * k), (0.06 * k, 0.06 * k), 4, z, 0.11 * k))
    return parts, {"a": a, "b": b, "z": z, "r": r, "x0": x0, "x1": x1}


# ---------------------------------------------------------------- rarity tiers (one mesh, five materials)

RARITY = {   # tier: (base kind, eye insert kind, spine kind)
    "common": ("metal", "metal", "metal"),
    "uncommon": ("paint_green", "paint_green", "paint_green"),
    "rare": ("paint_blue", "paint_blue", "paint_blue"),
    "epic": ("lilac", "glow", "lilac"),
    "legendary": ("gold", "glow", "glow"),
}


def rarity_needle(f, tier):
    """1.2 x 0.23 x 0.15 studs, 96 tris, the same mesh for every tier: six-sided shaft and point, slot
    eye, a pin across the eye and a thin spine along the top. Only materials change by tier: Epic
    lights the eye pin, Legendary also lights the spine along the whole needle."""
    base, eye_k, spine_k = RARITY[tier]
    parts, n = needle(f, base)
    parts.append(B(f, eye_k, (0.05, 0.1, 0.06), (n["x0"] + 0.11, 0, n["z"])))                  # eye pin
    parts.append(B(f, spine_k, (n["x1"] - n["a"] - 0.12, 0.03, 0.02), ((n["a"] + n["x1"] - 0.12) / 2, 0,
                                                                         2 * n["r"] - 0.004)))   # spine
    return parts


def needle_common(f):
    """Common tier: matte grey iron (metal). 1.2 x 0.23 x 0.15 studs."""
    return rarity_needle(f, "common")


def needle_uncommon(f):
    """Uncommon tier: sage (paint_green). 1.2 x 0.23 x 0.15 studs."""
    return rarity_needle(f, "uncommon")


def needle_rare(f):
    """Rare tier: blue steel (paint_blue). 1.2 x 0.23 x 0.15 studs."""
    return rarity_needle(f, "rare")


def needle_epic(f):
    """Epic tier: lilac with a faint glow pin in the eye. 1.2 x 0.23 x 0.15 studs."""
    return rarity_needle(f, "epic")


def needle_legendary(f):
    """Legendary tier: gold with a glow pin in the eye and a glowing spine along the needle."""
    return rarity_needle(f, "legendary")


# ---------------------------------------------------------------- 12 sorted needles (each <= 120 tris)

def needle_steel(f):
    """1.2 x 0.23 x 0.15 studs: plain galvanized steel needle with a long slot eye."""
    return needle(f, "steel")[0]


def needle_pine(f):
    """1.25 x 0.23 x 0.15 studs: plank-grain wooden shaft, bark slot eye, green point that frays into
    a fan of pine needles."""
    parts, n = needle(f, "handle", tip_kind="paint_green", eye_kind="bark")
    for a in (-0.35, 0.0, 0.35):
        parts.append(B(f, "paint_green", (0.24, 0.022, 0.022), (n["b"] + 0.18 + 0.02 * abs(a), 0.1 * math.sin(a), n["z"]),
                       rot=(0, 0, a)))
    return parts


def needle_sand(f):
    """1.2 x 0.23 x 0.16 studs: sandstone needle, faded sand with a stone band and grit."""
    parts, n = needle(f, "sand", tip_kind="stone", eye_kind="stone")
    parts.append(C(f, "stone", n["r"] + 0.012, 0.05, (n["b"] - 0.06, 0, n["z"]), verts=6))
    for x, a in ((n["a"] + 0.15, 0.5), (n["a"] + 0.4, 2.0)):
        parts.append(B(f, "stone", (0.045, 0.045, 0.045), (x, 0.03, n["z"] + n["r"] * 0.85), rot=(a, a, 0)))
    return parts


def ice(f, obj):
    """Pale blue glassy ice (local material: the house glass kind is too dark to read as ice)."""
    def make():
        return common.material("ice", common.srgb((0.66, 0.82, 0.90)), roughness=0.15, metallic=0.1)
    common.assign(obj, f._mat("ice", make))
    return obj


def needle_ice(f):
    """1.2 x 0.2 x 0.15 studs: pale blue glassy ice needle with a round steel eye and snow frost on top."""
    parts, n = needle(f, "glass", eye="ring", eye_kind="steel")
    for o in parts[:2]:
        ice(f, o)
    parts.append(B(f, "snow", (0.12, 0.06, 0.02), (n["a"] + 0.15, 0, n["z"] + n["r"] - 0.005), rot=(0, 0, 0.3)))
    parts.append(B(f, "snow", (0.12, 0.03, 0.02), (n["b"] + 0.08, 0, n["z"] + n["r"] * 0.55)))      # frosted point
    return parts


def needle_bog(f):
    """1.2 x 0.23 x 0.2 studs: mossy green needle with moss clumps, a mud spot and a muddy eye."""
    parts, n = needle(f, "paint_green", tip_kind="metal", eye_kind="dirt")
    for x, y, a in ((n["a"] + 0.1, 0.03, 0.3), (n["a"] + 0.42, -0.03, -0.4)):
        parts.append(B(f, "paint_green", (0.14, 0.12, 0.09), (x, y, n["z"] + 0.04), rot=(0.4, 0, a)))
    parts.append(B(f, "dirt", (0.1, 0.09, 0.07), (n["a"] + 0.27, -0.02, n["z"] + 0.05), rot=(0, 0, 0.6)))
    return parts


def needle_obsidian(f):
    """1.2 x 0.23 x 0.15 studs: knapped black volcanic glass, five-sided, with glossy chipped facets."""
    parts, n = needle(f, "tire", tip_kind="glass", eye_kind="tire", verts=5)
    for i in range(4):
        x = n["a"] + 0.08 + i * 0.15
        a = 0.6 + i * 0.6
        parts.append(B(f, "glass", (0.11, 0.06, 0.012), (x, n["r"] * 0.75 * math.cos(a), n["z"] + n["r"] * 0.75 * math.sin(a)),
                       rot=(a, 0, 0.2)))
    return parts


def needle_geode(f):
    """1.2 x 0.25 x 0.21 studs: stone needle with a band of glass crystal facets and a diamond eye."""
    parts, n = needle(f, "stone", tip_kind="glass", eye="diamond", eye_kind="glass")
    mid = (n["a"] + n["b"]) / 2
    for i in range(3):
        a = 0.5 + i * 1.05
        parts.append(B(f, "glass", (0.09, 0.055, 0.055), (mid + (i % 2) * 0.05 - 0.02, (n["r"] + 0.01) * math.cos(a),
                                                       n["z"] + (n["r"] + 0.01) * math.sin(a)), rot=(a + 0.785, 0.785, 0)))
    return parts


def needle_cloud(f):
    """1.2 x 0.24 x 0.2 studs: puffy white cloud needle, cloth shaft with a snow-white puff, round eye
    with a faint glow at its middle, silver point."""
    parts, n = needle(f, "cloth", tip_kind="steel", eye="ring", eye_kind="snow")
    for i, (x, sc) in enumerate(((n["a"] + 0.17, 0.16),)):
        parts.append(B(f, "snow", (sc * 1.4, sc, sc * 0.9), (x, 0.01 * i, n["z"] + 0.05), rot=(0.5, 0.4, 0.785)))
    parts.append(B(f, "glow", (0.05, 0.05, 0.02), (n["x0"] + 0.1, 0, n["z"])))
    return parts


def needle_phantom(f):
    """1.2 x 0.2 x 0.15 studs: pale ghostly needle, cloth shaft with a glowing core line, glowing
    point, round eye and a trailing wisp."""
    parts, n = needle(f, "cloth", tip_kind="glow", eye="ring", eye_kind="paint_cream")
    parts.append(B(f, "glow", (n["b"] - n["a"] - 0.04, 0.03, 0.02), ((n["a"] + n["b"]) / 2, 0, n["z"] + n["r"] - 0.004)))
    parts.append(B(f, "paint_cream", (0.16, 0.02, 0.02), (n["a"] + 0.2, 0.09, n["z"]), rot=(0, 0, 0.5)))
    return parts


def needle_cosmic(f):
    """1.2 x 0.23 x 0.17 studs: night-dark needle with a blue band and two glowing star sparkles."""
    parts, n = needle(f, "tire", tip_kind="steel", eye_kind="paint_blue")
    parts.append(C(f, "paint_blue", n["r"] + 0.01, 0.05, (n["b"] - 0.04, 0, n["z"]), verts=6))
    for i, (x, y) in enumerate(((n["a"] + 0.15, 0.02), (n["a"] + 0.4, -0.03))):
        parts.append(B(f, "glow", (0.035, 0.035, 0.035), (x, y, n["z"] + n["r"]), rot=(0.785, 0.785, i)))
    return parts


def needle_pearl(f):
    """1.25 x 0.24 x 0.24 studs: cream needle with a round pearl bead for an eye, set in a steel collar."""
    parts, n = needle(f, "paint_cream", tip_kind="steel", eye="bead")
    bpy.ops.mesh.primitive_uv_sphere_add(segments=6, ring_count=4, radius=0.12 * STUD, location=s(n["x0"] + 0.06, 0, 0.12))
    parts.append(f.apply(f.shape(bpy.context.active_object, round_edges=False), "cloth"))
    parts.append(C(f, "steel", n["r"] + 0.015, 0.04, (n["a"] + 0.01, 0, n["z"]), verts=6))
    return parts


def needle_anchor(f):
    """1.2 x 0.36 x 0.15 studs: grey iron needle whose eye is a tiny ship's anchor: ring, stock bar,
    and two arms swept back toward the point."""
    parts, n = needle(f, "metal", eye="anchor", verts=5)
    z, x0 = n["z"], n["x0"]
    parts.append(ring(f, "metal", n["a"] - 0.02, (0.06, 0.06), (0.03, 0.03), 5, z, 0.06))       # ring
    parts.append(B(f, "metal", (0.035, 0.32, 0.06), (n["a"] + 0.07, 0, z)))                    # stock bar
    for side in (-1, 1):                                                                         # arms + flukes
        parts.append(B(f, "metal", (0.2, 0.05, 0.07), (x0 + 0.1, side * 0.09, z), rot=(0, 0, side * 0.9)))
    return parts


def needle_coral(f):
    """1.2 x 0.26 x 0.2 studs: Thimble Keys needle grown from coral: a coral-pink shaft and point with
    little knobbly cream polyps along it and a ring eye."""
    parts, n = needle(f, "coral", eye="ring")
    rng = random.Random(41)
    for i in range(5):
        x = n["a"] + 0.08 + i * (n["b"] - n["a"] - 0.1) / 4
        side = (-1, 1)[i % 2]
        parts.append(B(f, "paint_cream", (0.05, 0.05, 0.05), (x, side * (n["r"] + 0.01), n["z"] + rng.uniform(0, 0.03)),
                       rot=(0.6, 0.6, i)))
    parts.append(B(f, "coral", (0.12, 0.035, 0.035), (n["a"] + 0.3, 0.07, n["z"] + 0.03), rot=(0, 0, 0.9)))  # branch
    return parts


def needle_brass(f):
    """1.2 x 0.23 x 0.15 studs: Bobbin Rock needle in old brass (181, 148, 72), brass to the point, with a
    couple of dark thread turns under the slot eye."""
    parts, n = needle(f, "brass")
    for i in range(2):
        parts.append(C(f, "twine", n["r"] + 0.008, 0.02, (n["a"] + 0.05 + i * 0.03, 0, n["z"]), verts=6))
    return parts


# ---------------------------------------------------------------- mutations

def needle_rainbow(f):
    """1.2 x 0.23 x 0.15 studs: mutated needle painted in red, yellow, green and blue stripes."""
    parts, n = needle(f, "paint_blue", shaft=False)
    paints = ("paint_red", "paint_yellow", "paint_green", "paint_blue")
    seg = (n["b"] - n["a"] + 0.04) / len(paints)
    for i, p in enumerate(paints):
        parts.append(C(f, p, n["r"], seg + 0.002, (n["a"] - 0.02 + seg * (i + 0.5), 0, n["z"]), verts=5))
    parts.append(tip(f, "paint_red", n["b"] - 0.01, n["x1"], n["r"], n["z"], verts=5))
    return parts


def needle_giant(f):
    """3.6 x 0.7 x 0.45 studs: mutated steel needle, three times game size."""
    return needle(f, "steel", k=3.0, verts=8)[0]


def needle_glitch(f):
    """1.2 x 0.28 x 0.24 studs: mutated needle broken into stair-stepped offset blocks, alternating
    steel and black, with a glowing glitch block."""
    t = NEEDLE_T
    parts = []
    n_seg, x0 = 7, -NEEDLE_L / 2
    seg = NEEDLE_L / n_seg
    offs = (0.0, 0.04, 0.07, 0.03, -0.03, -0.06, -0.02)
    for i in range(n_seg):
        x = x0 + seg * (i + 0.5)
        size = t * (1.0 - 0.13 * max(0, i - 4) * 2) if i >= 5 else t
        kind = "glow" if i == 3 else ("steel" if i % 2 == 0 else "tire")
        dz = 0.03 if i in (2, 5) else 0.0
        parts.append(B(f, kind, (seg * 0.94, size, size), (x, offs[i], size / 2 + dz)))
    parts.append(B(f, "tire", (0.06, 0.06, 0.05), (x0 + seg * 0.5, 0, t + 0.025)))              # stuck pixel
    parts.append(B(f, "glow", (0.04, 0.04, 0.04), (x0 + seg * 5.6, 0.1, 0.02)))
    return parts


# ---------------------------------------------------------------- bundle, bin, display

def thin_needle(f, kind, length, t, x, y, z):
    """Cheap needle for bundles: a square shaft tapering to the point (+x) and a flat eye block
    at -x. 24 tris."""
    o = box(s(length - 0.15, t, t), s(x + 0.075, y, z))
    for v in o.data.vertices:
        if v.co.x > 0:
            v.co.y *= 0.15
            v.co.z *= 0.15
    return [f.apply(f.shape(o, round_edges=False), kind),
            B(f, kind, (0.16, t * 1.1, t * 0.7), (x - length / 2 + 0.08, y, z))]


def needle_bundle(f):
    """1.3 x 0.55 x 0.55 studs (the game's bundle part), 296 tris: ten grey needles packed 2-3-3-2, eyes all at the
    -x end, tied with two twine bands."""
    parts = []
    t = 0.15
    rows = (2, 3, 3, 2)
    for row, count in enumerate(rows):
        for i in range(count):
            y = (i - (count - 1) / 2) * t
            parts += thin_needle(f, "metal", 1.24 + 0.02 * ((row + i) % 3), t, 0.0, y, t / 2 + row * t * 0.87)
    zc = t / 2 + 1.5 * t * 0.87
    for x in (-0.3, 0.25):
        band = cyl(0.27 * STUD, 0.1 * STUD, s(x, 0, zc), verts=8, rot=(0, math.pi / 2, 0))
        parts.append(f.apply(band, "twine", along="x"))
    return parts


def needle_bin(f):
    """6 x 4 x 6 studs (one conveyor tile): sturdy open-top plank bin on skids with iron corner
    angles and rim bands. The needle pile inside (a packed steel floor with loose needles heaped on
    it) is its own one-material mesh tagged "NeedleFill" so the game can raise it as the bin fills."""
    W, H, T = 5.78, 4.0, 0.35   # iron fittings bring the footprint to 6 x 6
    parts = []
    for y in (-2.2, 0.0, 2.2):                                                                   # skids
        parts.append(B(f, "handle", (W, 0.5, 0.3), (0, y, 0.15), rounded=True))
    parts.append(B(f, "handle", (W - 0.1, W - 0.1, 0.25), (0, 0, 0.42), rounded=True))          # floor
    planks = 4
    ph = (H - 0.55) / planks
    for i in range(planks):
        z = 0.55 + ph * (i + 0.5)
        for side in (-1, 1):
            parts.append(B(f, "handle", (W - 0.08, T, ph - 0.05), (0, side * (W - T) / 2, z), rounded=True))
            parts.append(B(f, "handle", (T, W - 2 * T, ph - 0.05), (side * (W - T) / 2, 0, z), along="y", rounded=True))
    for sx in (-1, 1):                                                                           # iron corners
        for sy in (-1, 1):
            parts.append(B(f, "metal", (0.5, 0.08, H - 0.2), (sx * (W / 2 - 0.25), sy * (W / 2 + 0.03), H / 2 + 0.1), along="z"))
            parts.append(B(f, "metal", (0.08, 0.5, H - 0.2), (sx * (W / 2 + 0.03), sy * (W / 2 - 0.25), H / 2 + 0.1), along="z"))
            for z in (1.0, H - 0.6):
                parts.append(C(f, "steel", 0.06, 0.06, (sx * (W / 2 - 0.25), sy * (W / 2 + 0.08), z), axis="y", verts=6))
    for side in (-1, 1):                                                                         # rim bands
        parts.append(B(f, "metal", (W + 0.1, 0.06, 0.16), (0, side * (W / 2 + 0.02), H - 0.12)))
        parts.append(B(f, "metal", (0.06, W + 0.1, 0.16), (side * (W / 2 + 0.02), 0, H - 0.12), along="y"))
    # Needle pile: packed floor near the top and a loose heap on it, one steel mesh.
    fill = H - 0.75
    pile = [B(f, "steel", (W - 2 * T - 0.02, W - 2 * T - 0.02, 0.2), (0, 0, fill - 0.1))]
    rng = random.Random(9)
    for i in range(34):
        p, _ = needle(f, "steel")
        r = math.sqrt(rng.random()) * 2.0
        a = rng.uniform(0, 2 * math.pi)
        dz = fill + 0.15 * (1 - r / 2.0) * 2 + rng.uniform(0, 0.08)
        pile += move(p, dx=r * math.cos(a), dy=r * math.sin(a), dz=dz, rz=rng.uniform(0, math.pi),
                     rx=rng.uniform(-0.25, 0.25))
    return parts + tag(pile, "NeedleFill")


def needle_display_wall(f):
    """6 wide x 1 deep x 7.8 tall, under 2k tris: one plot tile, built like Display.luau (TileSize 6,
    HEIGHT 7). A 5.6 x 7 plank board between two round wooden posts 7.6 tall, a grey iron cap
    (6.2 x 1 x 0.4, top at 7.8) and a red name board under it. Six iron pegs (0.9 x 0.3 x 0.3) in two
    rows of 3 at x -1.8/0/1.8, z 5 and 2, stand 0.15 proud of the board on dark red velvet backs
    (paint_red), each with a brass plaque (paint_yellow) below. The display side faces -y. Wood is
    one kind (planks) so the wall stays at 4 kinds."""
    T, HEIGHT = 6.0, 7.0
    y0 = -0.25                       # Display.luau's board face plane (its local z 0), centered for depth
    parts = []
    nb = 6
    bh = HEIGHT / nb
    for i in range(nb):                                                                     # board planks
        parts.append(B(f, "handle", (T - 0.4, 0.4, bh - 0.06), (0, y0 + 0.2, bh * (i + 0.5))))
    for x in (-1, 1):                                                                       # posts
        parts.append(C(f, "handle", 0.3, HEIGHT + 0.6, (x * (T / 2 - 0.25), y0 + 0.3, (HEIGHT + 0.6) / 2),
                       axis="z", verts=8))
    parts.append(B(f, "metal", (T + 0.2, 1.0, 0.4), (0, y0 + 0.3, HEIGHT + 0.6), rounded=True))   # iron cap
    parts.append(B(f, "paint_red", (3.6, 0.12, 0.6), (0, y0 - 0.06, HEIGHT - 0.35)))                # name board
    for z in (HEIGHT - 0.7, HEIGHT):
        parts.append(B(f, "metal", (3.8, 0.16, 0.12), (0, y0 - 0.08, z)))                           # its iron trim
    for row in range(2):
        pz = HEIGHT - 2 - row * 3                                                           # peg heights 5, 2
        for col in range(3):
            x = (col - 1) * 1.8
            parts.append(B(f, "paint_red", (1.55, 0.06, 2.2), (x, y0 - 0.03, pz + 0.1)))          # velvet back
            parts.append(B(f, "metal", (0.9, 0.3, 0.3), (x, y0 - 0.15, pz)))                     # peg
            parts.append(B(f, "paint_yellow", (0.9, 0.06, 0.32), (x, y0 - 0.09, pz - 0.65)))       # brass plaque
    return parts


# ---------------------------------------------------------------- region bales

L2, D2, H = hay_bale.SIZE[0] / STUD / 2, hay_bale.SIZE[1] / STUD / 2, hay_bale.SIZE[2] / STUD
PROUD = 0.045   # studs: just above the hay's rustic wobble (0.043), inside the stock bale's 4.63 x 3.25 x 2.64 bounds

REGION_HAY = {   # sRGB (light, mid, dark) for the straw texture
    "pine": ((0.70, 0.70, 0.46), (0.55, 0.56, 0.34), (0.36, 0.38, 0.22)),
    "desert": ((0.94, 0.89, 0.74), (0.85, 0.78, 0.60), (0.66, 0.59, 0.42)),
    "snow": ((0.72, 0.70, 0.60), (0.58, 0.56, 0.44), (0.40, 0.39, 0.30)),
    "swamp": ((0.52, 0.50, 0.32), (0.41, 0.39, 0.24), (0.25, 0.24, 0.15)),
    "volcano": ((0.50, 0.42, 0.30), (0.35, 0.28, 0.20), (0.17, 0.13, 0.10)),
    "cave": ((0.66, 0.69, 0.72), (0.52, 0.56, 0.60), (0.34, 0.37, 0.42)),
    "sky": ((0.90, 0.88, 0.80), (0.78, 0.76, 0.66), (0.60, 0.58, 0.50)),
    "haunted": ((0.62, 0.58, 0.66), (0.48, 0.45, 0.53), (0.31, 0.29, 0.36)),
    "star": ((0.36, 0.36, 0.46), (0.25, 0.25, 0.35), (0.13, 0.13, 0.21)),
    "seagrass": ((0.66, 0.74, 0.58), (0.50, 0.60, 0.46), (0.30, 0.40, 0.32)),   # Thimble Keys sea grass
    "thread": ((0.86, 0.76, 0.66), (0.74, 0.62, 0.52), (0.52, 0.42, 0.36)),     # Bobbin Rock thread grass
}


def region_hay(f, obj, region):
    """Straw texture in the region's palette, cached per scene like the house kinds."""
    key = f"hay_{region}"
    mat = f._mat(key, lambda: common.texture_material(
        f"rustic_{key}", common.make_texture(f"rustic_{key}", 256, style.straw_texture(REGION_HAY[region], f.contrast))))
    common.box_uv(obj, scale=1.6, along="x")
    common.assign(obj, mat)
    return obj


def ember(f, obj):
    """Small orange emissive material for volcano embers (the house glow kind is cyan)."""
    def make():
        m = common.material("ember", common.srgb((0.95, 0.45, 0.15)), roughness=0.5)
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Emission Color"].default_value = (*common.srgb((1.0, 0.45, 0.12)), 1)
        bsdf.inputs["Emission Strength"].default_value = 2.0
        return m
    common.assign(obj, f._mat("ember", make))
    return obj


def bale(f, region):
    hay_bale.BEVEL = max(f.bevel, 0.001)
    hay = region_hay(f, f.shape(hay_bale.build_hay(), round_edges=False), region)
    return [hay] + [f.apply(b, "twine") for b in hay_bale.build_twine()]


def patch(f, kind, face, u, v, w, h, a=0.0, t=0.03, round_=False):
    """A thin flat detail on a bale face, its outer side PROUD above the hay. u, v are face
    coordinates in studs from the face center (u along x for front/back/top, along y for the ends);
    a turns it in the face plane."""
    out = PROUD * (0.8 + 0.2 * (abs(u * 7.31 + v * 13.17 + w * 3.71) % 1))   # overlaps never share a plane
    if round_:      # soft oval: a flat 8-sided disc squashed to w x h, facing out of the face
        o = cyl(STUD / 2, t * STUD, (0, 0, 0), verts=8)
        o.scale = (w, h, 1)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        rot, loc = {"top": ((0, 0, a), (u, v, H + out - t / 2)),
                    "front": ((math.pi / 2, a, 0), (u, -(D2 + out - t / 2), H / 2 + v)),
                    "back": ((math.pi / 2, a, 0), (u, D2 + out - t / 2, H / 2 + v)),
                    "left": ((a, math.pi / 2, math.pi / 2), (-(L2 + out - t / 2), u, H / 2 + v)),
                    "right": ((a, math.pi / 2, math.pi / 2), (L2 + out - t / 2, u, H / 2 + v))}[face]
        o.rotation_mode = "ZYX" if face in ("left", "right") else "XYZ"   # ends: w along y, h up
        o.rotation_euler = rot
        o.location = s(*loc)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    elif face == "top":
        o = box(s(w, h, t), s(u, v, H + out - t / 2), rot=(0, 0, a))
    elif face in ("front", "back"):
        sy = -1 if face == "front" else 1
        o = box(s(w, t, h), s(u, sy * (D2 + out - t / 2), H / 2 + v), rot=(0, a, 0))
    else:
        sx = -1 if face == "left" else 1
        o = box(s(t, w, h), s(sx * (L2 + out - t / 2), u, H / 2 + v), rot=(a, 0, 0))
    lim = (L2 + PROUD, D2 + PROUD, H + PROUD)
    for vt in o.data.vertices:                      # keep the bale's exact size: clip overhangs
        w = vt.co + o.location
        w.x = max(-lim[0] * STUD, min(lim[0] * STUD, w.x))
        w.y = max(-lim[1] * STUD, min(lim[1] * STUD, w.y))
        w.z = max(0.0, min(lim[2] * STUD, w.z))
        vt.co = w - o.location
    if kind == "ember":
        return ember(f, o)
    return f.apply(o, kind, along="x")


def scatter(f, kinds, faces, n, size, seed, aspect=1.0, margin=0.25):
    """n patches of the given kinds spread over faces, size studs across (aspect = length / width)."""
    rng = random.Random(seed)
    parts = []
    for i in range(n):
        face = faces[i % len(faces)]
        hu = (L2 if face in ("top", "front", "back") else D2) - margin
        hv = (D2 if face == "top" else H / 2) - margin
        w = size * rng.uniform(0.7, 1.3)
        parts.append(patch(f, kinds[i % len(kinds)], face, rng.uniform(-hu, hu), rng.uniform(-hv, hv),
                           w * aspect, w, a=rng.uniform(-1.2, 1.2)))
    return parts


SIDES = ("front", "top", "back", "left", "right")


def bale_pine(f):
    """4.6 x 2.6 x 3.2 studs: green-brown forest hay with fallen pine needles and bits of bark."""
    return bale(f, "pine") + scatter(f, ["paint_green", "bark"], SIDES, 40, 0.08, 1, aspect=7) + \
        scatter(f, ["bark"], ("front", "top", "right"), 5, 0.12, 2, aspect=1.6)


def bale_desert(f):
    """4.6 x 2.6 x 3.2 studs: pale, sun-bleached dry hay with sand dusted along the bottom."""
    parts = bale(f, "desert")
    rng = random.Random(3)
    for face in ("front", "back", "left", "right"):
        span = L2 if face in ("front", "back") else D2
        for i in range(3):
            u = -span + 0.5 + i * (2 * span - 1) / 2 + rng.uniform(-0.3, 0.3)
            parts.append(patch(f, "sand", face, u, -H / 2 + 0.2, rng.uniform(0.9, 1.4), 0.35))
    return parts + scatter(f, ["sand", "dirt"], ("front", "top", "left", "back"), 10, 0.12, 4, aspect=3)


def bale_snow(f):
    """4.6 x 2.6 x 3.2 studs: cold pale hay with a frosted top: snow patches and icicle drips."""
    parts = bale(f, "snow")
    rng = random.Random(6)
    for i in range(10):
        parts.append(patch(f, "snow" if i % 2 else "cloth", "top", rng.uniform(-1.6, 1.6), rng.uniform(-1.0, 1.0),
                           rng.uniform(1.2, 2.0), rng.uniform(0.9, 1.4), a=rng.uniform(-0.5, 0.5)))
    for face in ("front", "back", "left", "right"):
        span = L2 if face in ("front", "back") else D2
        for i in range(4):
            u = -span + 0.4 + i * (2 * span - 0.8) / 3
            ln = rng.uniform(0.2, 0.55)
            parts.append(patch(f, "snow", face, u, H / 2 - ln / 2 - 0.02, rng.uniform(0.25, 0.45), ln))
    return parts


def bale_swamp(f):
    """4.6 x 2.6 x 3.2 studs: dark, wet green-brown hay, moss creeping up from the bottom and mud spots."""
    parts = bale(f, "swamp")
    rng = random.Random(7)
    for face in ("front", "back", "left", "right"):
        span = L2 if face in ("front", "back") else D2
        for i in range(3):
            u = rng.uniform(-span + 0.4, span - 0.4)
            hh = rng.uniform(0.4, 0.8)
            parts.append(patch(f, "paint_green", face, u, -H / 2 + hh / 2 + 0.03, rng.uniform(0.8, 1.3), hh))
    return parts + scatter(f, ["dirt"], SIDES, 10, 0.3, 8) + scatter(f, ["paint_green"], ("top",), 4, 0.6, 9)


def bale_volcano(f):
    """4.6 x 2.6 x 3.2 studs: scorched dark hay with charred patches and a few glowing ember flecks."""
    return bale(f, "volcano") + scatter(f, ["tire"], SIDES, 12, 0.6, 10, aspect=1.4) + \
        scatter(f, ["ember"], SIDES, 18, 0.11, 11, aspect=1.5)


def bale_cave(f):
    """4.6 x 2.6 x 3.2 studs: grey-blue cave hay studded with glassy crystal bits and stone grit."""
    return bale(f, "cave") + scatter(f, ["glass", "steel"], SIDES, 16, 0.2, 12, aspect=1.6) + \
        scatter(f, ["steel"], SIDES, 8, 0.25, 13)


def bale_sky(f):
    """4.6 x 2.6 x 3.2 studs: light airy cream hay with soft white cloud tufts."""
    parts = bale(f, "sky")
    rng = random.Random(14)
    for face in ("top", "front", "right", "back"):
        for _ in range(2):
            hu = (L2 if face in ("top", "front", "back") else D2) - 0.8
            hv = (D2 if face == "top" else H / 2) - 0.6
            u, v = rng.uniform(-hu, hu), rng.uniform(-hv, hv)
            for du, dv, r in ((0, 0, 0.55), (0.35, 0.12, 0.4), (-0.35, 0.08, 0.38), (0.1, -0.2, 0.35)):
                parts.append(patch(f, "snow" if du else "cloth", face, u + du, v + dv, r * 1.3, r, round_=True))
    return parts


def bale_haunted(f):
    """4.6 x 2.6 x 3.2 studs: grey-violet hay with blue-grey blotches, dirt, and cobweb strands."""
    parts = bale(f, "haunted") + scatter(f, ["paint_blue"], SIDES, 8, 0.4, 15)
    rng = random.Random(16)
    for face in ("front", "left", "top"):           # cobwebs fanned across the corners
        hu = L2 if face in ("front", "top") else D2
        hv = D2 if face == "top" else H / 2
        for cu, cv in ((-1, 1), (1, 1)) if face != "top" else ((-1, -1),):
            for i in range(4):
                a = (0.2 + i * 0.4) * (1 if cu < 0 else -1)
                ln = rng.uniform(0.8, 1.2)
                parts.append(patch(f, "cloth", face, cu * (hu - 0.3) - cu * ln * 0.35, cv * (hv - 0.3) - cv * 0.2,
                                   ln, 0.025, a=a, t=0.02))
    return parts


def bale_star(f):
    """4.6 x 2.6 x 3.2 studs: night-dark starry hay with small glowing sparkles."""
    return bale(f, "star") + scatter(f, ["glow"], SIDES, 22, 0.11, 17) + \
        scatter(f, ["paint_blue"], SIDES, 6, 0.4, 18)


def bale_seagrass(f):
    """4.6 x 2.6 x 3.2 studs: Thimble Keys sea grass hay, sea-green with dark kelp strands, a dusting
    of sand on the bottom and a couple of small shells."""
    parts = bale(f, "seagrass") + scatter(f, ["paint_green"], SIDES, 16, 0.1, 21, aspect=8)
    for face, u in (("front", -1.2), ("back", 0.8), ("left", 0.0)):
        parts.append(patch(f, "sand", face, u, -H / 2 + 0.2, 1.3, 0.3))
    for kind, face, u, v in (("paint_cream", "front", 1.1, 0.3), ("coral", "top", -0.9, 0.4),
                             ("paint_cream", "right", 0.2, -0.2)):
        parts.append(patch(f, kind, face, u, v, 0.28, 0.22, round_=True))
    return parts


def bale_thread(f):
    """4.6 x 2.6 x 3.2 studs: Bobbin Rock thread grass, a pale linen hay wrapped with loose strands of
    red, blue and cream thread."""
    parts = bale(f, "thread")
    rng = random.Random(23)
    for i, kind in enumerate(("paint_red", "paint_blue", "paint_cream", "paint_red", "paint_blue")):
        for face in ("front", "top", "back"):
            parts.append(patch(f, kind, face, rng.uniform(-L2 + 0.4, L2 - 0.4), rng.uniform(-0.5, 0.5),
                               rng.uniform(1.2, 2.4), 0.05, a=rng.uniform(-0.6, 0.6), t=0.02))
    return parts


PROPS = {
    "needle_common": needle_common,
    "rarity_needle": needle_common,  # the name Config/Props registers; tiers recolor it in game
    "needle_uncommon": needle_uncommon,
    "needle_rare": needle_rare,
    "needle_epic": needle_epic,
    "needle_legendary": needle_legendary,
    "needle_steel": needle_steel,
    "needle_pine": needle_pine,
    "needle_sand": needle_sand,
    "needle_ice": needle_ice,
    "needle_bog": needle_bog,
    "needle_obsidian": needle_obsidian,
    "needle_geode": needle_geode,
    "needle_cloud": needle_cloud,
    "needle_phantom": needle_phantom,
    "needle_cosmic": needle_cosmic,
    "needle_pearl": needle_pearl,
    "needle_anchor": needle_anchor,
    "needle_coral": needle_coral,
    "needle_brass": needle_brass,
    "needle_rainbow": needle_rainbow,
    "needle_giant": needle_giant,
    "needle_glitch": needle_glitch,
    "needle_bundle": needle_bundle,
    "needle_bin": needle_bin,
    "needle_display_wall": needle_display_wall,
    "bale_pine": bale_pine,
    "bale_desert": bale_desert,
    "bale_snow": bale_snow,
    "bale_swamp": bale_swamp,
    "bale_volcano": bale_volcano,
    "bale_cave": bale_cave,
    "bale_sky": bale_sky,
    "bale_haunted": bale_haunted,
    "bale_star": bale_star,
    "bale_seagrass": bale_seagrass,
    "bale_thread": bale_thread,
}

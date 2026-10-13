"""Square hay bale in the Lumber Tycoon 2 look: a simple block of hay tied with
two twine bands. Flat top and bottom and exact stud sizes so bales stack.

Exports two meshes:
  HayBale_Hay    - the bale (physics body; set Roblox material to Grass or Fabric)
  HayBale_Twine  - the two bands (weld to the hay; Fabric or SmoothPlastic)

Run:
  blender --background --python blender/props/hay_bale.py -- --out blender/exports
"""
import os
import sys

import bpy  # must be imported before bmesh/mathutils with the pip bpy module

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import common  # noqa: E402

STUD = 0.28
# 4 x 2 x 2 studs: two bales side by side match one bale lengthwise, so they stack in bonds.
SIZE = (4 * STUD, 2 * STUD, 2 * STUD)
BEVEL = 0.025
TWINE_X = (-0.3, 0.3)        # band positions along the length, as a fraction of the length
TWINE_WIDTH = 0.025
TWINE_PROUD = 0.004          # how far bands stand off the hay

HAY = (0.89, 0.76, 0.40)      # sRGB
HAY_END = (0.80, 0.66, 0.32)  # cut ends read a little darker
TWINE = (0.55, 0.38, 0.22)


def build_hay(color=HAY, end_color=HAY_END):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, SIZE[2] / 2))
    bale = bpy.context.active_object
    bale.scale = SIZE
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = bale.modifiers.new("bevel", "BEVEL")
    mod.width = BEVEL
    mod.segments = 2
    bpy.ops.object.modifier_apply(modifier=mod.name)
    common.paint(bale, lambda p, c: end_color if abs(p.normal.x) > 0.7 else color)
    bale.name = "HayBale_Hay"
    return bale


def build_twine(color=TWINE):
    bands = []
    for fx in TWINE_X:
        bpy.ops.mesh.primitive_cube_add(size=1, location=(fx * SIZE[0], 0, SIZE[2] / 2))
        band = bpy.context.active_object
        band.scale = (TWINE_WIDTH, SIZE[1] + 2 * TWINE_PROUD, SIZE[2] + 2 * TWINE_PROUD)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        common.paint(band, lambda p, c: color)
        bands.append(band)
    return bands


def build():
    hay_mat = common.vertex_color_material("Hay", roughness=0.95)
    twine_mat = common.vertex_color_material("Twine", roughness=0.9)
    hay = build_hay()
    common.assign(hay, hay_mat)
    bands = build_twine()
    for b in bands:
        common.assign(b, twine_mat)
    twine = common.join(bands, "HayBale_Twine")
    return [hay, twine]


def main():
    args = common.parse_args("hay_bale")
    common.reset_scene()
    common.export(build(), args)


if __name__ == "__main__":
    main()

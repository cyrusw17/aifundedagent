"""Render a quick PNG preview of an exported .glb (CPU Cycles, works headless).

Run:
  blender --background --python blender/tools/render_preview.py -- blender/exports/hay_barrel.glb blender/exports/hay_barrel.png [size]
"""
import os
import sys

import bpy

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import common  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
glb, out = argv[0], argv[1]
res = int(argv[2]) if len(argv) > 2 else 600

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
common.render_preview(out, res)

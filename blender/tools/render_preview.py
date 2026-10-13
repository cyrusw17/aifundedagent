"""Render a quick PNG preview of an exported .glb (CPU Cycles, works headless).

Run:
  blender --background --python blender/tools/render_preview.py -- blender/exports/hay_barrel.glb blender/exports/hay_barrel.png
"""
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
glb, out = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)

# Frame the imported objects.
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
zs = [(o.matrix_world @ v.co).z for o in objs for v in o.data.vertices]
mid, size = (min(zs) + max(zs)) / 2, max(zs) - min(zs)

target = bpy.data.objects.new("target", None)
target.location = (0, 0, mid)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.location = (size * 1.6, -size * 1.6, mid + size * 0.9)
cam.constraints.new("TRACK_TO").target = target
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.rotation_euler = (0.7, 0.2, 0.8)
sun.data.energy = 4
for o in (target, cam, sun):
    bpy.context.collection.objects.link(o)

scene = bpy.context.scene
scene.camera = cam
scene.world = bpy.data.worlds.new("world")
scene.world.color = (0.6, 0.65, 0.7)
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16
scene.render.resolution_x = scene.render.resolution_y = 600
scene.render.filepath = out
bpy.ops.render.render(write_still=True)

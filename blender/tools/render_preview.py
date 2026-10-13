"""Render a quick PNG preview of an exported .glb (CPU Cycles, works headless).

Run:
  blender --background --python blender/tools/render_preview.py -- blender/exports/hay_barrel.glb blender/exports/hay_barrel.png
"""
import sys

import bpy
from mathutils import Vector  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
glb, out = argv[0], argv[1]
res = int(argv[2]) if len(argv) > 2 else 600

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)

# Frame the imported objects with an orthographic three-quarter view.
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
pts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
lo = Vector([min(p[i] for p in pts) for i in range(3)])
hi = Vector([max(p[i] for p in pts) for i in range(3)])
center, size = (lo + hi) / 2, max(hi - lo)

target = bpy.data.objects.new("target", None)
target.location = center
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.type = "ORTHO"
view = Vector((0.3, -1.0, 0.6)).normalized()
cam.location = center + view * size * 3
w, h = hi.x - lo.x, max(hi.y - lo.y, hi.z - lo.z)
wide = w > 1.5 * h  # a row of props: render a 2:1 frame
aspect = 2 if wide else 1
cam.data.ortho_scale = max(w, h * aspect) * 1.25
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
scene.render.resolution_x = res
scene.render.resolution_y = res // 2 if wide else res
scene.render.filepath = out
bpy.ops.render.render(write_still=True)

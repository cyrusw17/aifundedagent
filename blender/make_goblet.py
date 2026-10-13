"""Builds a goblet via a lathe profile, then exports GLB and a preview PNG.

Run: python blender/make_goblet.py   (uses the `bpy` pip module)
"""
import math
import os

import bpy

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)

# Profile (radius, height) from base up, revolved around Z.
profile = [(0.0, 0.0), (0.55, 0.0), (0.55, 0.06), (0.2, 0.15), (0.09, 0.3),
           (0.09, 0.9), (0.2, 1.0), (0.3, 1.1), (0.55, 1.35), (0.7, 1.8),
           (0.7, 2.2), (0.66, 2.2), (0.66, 1.8), (0.5, 1.4), (0.0, 1.3)]
mesh = bpy.data.meshes.new("Goblet")
mesh.from_pydata([(r, 0, z) for r, z in profile], [(i, i + 1) for i in range(len(profile) - 1)], [])
obj = bpy.data.objects.new("Goblet", mesh)
bpy.context.scene.collection.objects.link(obj)
bpy.context.view_layer.objects.active = obj
obj.select_set(True)

screw = obj.modifiers.new("Lathe", "SCREW")
screw.angle = math.tau
screw.steps = screw.render_steps = 64
screw.axis = "Z"
screw.use_merge_vertices = True
bpy.ops.object.modifier_apply(modifier="Lathe")
bpy.ops.object.shade_smooth()
bevel = obj.modifiers.new("Subsurf", "SUBSURF")
bevel.levels = 1
bpy.ops.object.modifier_apply(modifier="Subsurf")

gold = bpy.data.materials.new("Gold")
gold.use_nodes = True
bsdf = gold.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (1.0, 0.77, 0.25, 1)
bsdf.inputs["Metallic"].default_value = 1.0
bsdf.inputs["Roughness"].default_value = 0.25
obj.data.materials.append(gold)

# Floor, lights, camera.
bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, -0.001))
floor = bpy.context.object
mat = bpy.data.materials.new("Floor")
mat.diffuse_color = (0.15, 0.15, 0.18, 1)
floor.data.materials.append(mat)
for loc, energy in [((3, -3, 4), 600), ((-4, 2, 3), 250)]:
    bpy.ops.object.light_add(type="AREA", location=loc)
    light = bpy.context.object
    light.data.energy, light.data.size = energy, 3
    light.rotation_euler = (math.radians(55), 0, math.radians(45 if loc[0] > 0 else -60))
bpy.ops.object.camera_add(location=(3.6, -4.2, 2.4))
cam = bpy.context.object
cam.rotation_euler = (math.radians(75), 0, math.radians(40))
cam.data.lens = 50
bpy.context.scene.camera = cam
world = bpy.data.worlds.new("World")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.5, 0.55, 0.65, 1)
bpy.context.scene.world = world

sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 48
sc.cycles.device = "CPU"
sc.render.resolution_x, sc.render.resolution_y = 800, 800
sc.render.filepath = os.path.join(OUT, "goblet.png")
bpy.ops.render.render(write_still=True)

bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "goblet.glb"), use_selection=True)
print("done")

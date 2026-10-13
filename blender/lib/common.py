"""Shared helpers for prop build scripts.

Works both inside Blender (blender --background --python ...) and with the
standalone `bpy` pip module (python ...).
"""
import argparse
import os
import sys

import bpy


def parse_args(default_name):
    """Parse args after `--` (Blender passes its own args before it)."""
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "exports"),
                        help="Folder to write exports into")
    parser.add_argument("--name", default=default_name, help="Base file name for exports")
    parser.add_argument("--formats", default="glb,obj", help="Comma list of: glb, obj, fbx, blend")
    return parser.parse_args(argv)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def material(name, color, roughness=0.8, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def join(objs, name):
    """Join objects into one mesh with the given name and apply transforms."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj


def shade_smooth(obj, angle_deg=40):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_auto_smooth(angle=__import__("math").radians(angle_deg))


def triangle_count(objs):
    total = 0
    for o in objs:
        total += sum(len(p.vertices) - 2 for p in o.data.polygons)
    return total


def export(objs, args):
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    written = []
    for fmt in [f.strip() for f in args.formats.split(",") if f.strip()]:
        path = os.path.join(out, f"{args.name}.{fmt}")
        if fmt == "glb":
            bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                                      export_apply=True, export_yup=True)
        elif fmt == "obj":
            bpy.ops.wm.obj_export(filepath=path, export_selected_objects=True,
                                  export_materials=True, forward_axis="NEGATIVE_Z", up_axis="Y")
        elif fmt == "fbx":
            bpy.ops.export_scene.fbx(filepath=path, use_selection=True, apply_unit_scale=True,
                                     axis_forward="-Z", axis_up="Y")
        elif fmt == "blend":
            bpy.ops.wm.save_as_mainfile(filepath=path)
        else:
            raise SystemExit(f"Unknown format: {fmt}")
        written.append(path)
    print(f"[{args.name}] {triangle_count(objs)} triangles")
    for p in written:
        print(f"[{args.name}] wrote {p}")
    return written

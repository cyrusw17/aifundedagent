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


def vertex_color_material(name, roughness=0.9, metallic=0.0):
    """Material whose base color comes from the mesh's "Col" color attribute.

    Exports to glTF as COLOR_0, which Roblox's 3D importer reads as vertex color.
    """
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    attr = nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    mat.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def paint(obj, color_fn):
    """Fill obj's "Col" attribute: color_fn(poly, vertex_co) -> sRGB (r, g, b) per face corner."""
    mesh = obj.data
    attr = mesh.color_attributes.get("Col") or mesh.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            co = mesh.vertices[mesh.loops[li].vertex_index].co
            attr.data[li].color_srgb = (*color_fn(poly, co), 1.0)


def flat(obj):
    for p in obj.data.polygons:
        p.use_smooth = False


def render_preview(out, res=600, ground=None):
    """Render every mesh in the scene with an orthographic three-quarter view (CPU Cycles).

    ground: optional sRGB color for a floor plane under the props.
    """
    from mathutils import Vector

    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    pts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    center, size = (lo + hi) / 2, max(hi - lo)

    if ground:
        bpy.ops.mesh.primitive_plane_add(size=size * 6, location=(center.x, center.y, lo.z))
        assign(bpy.context.active_object, material("Ground", srgb(ground), roughness=1.0))

    view = Vector((0.3, -1.0, 0.6)).normalized()
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.location = center + view * size * 3
    cam.rotation_euler = view.to_track_quat("Z", "Y").to_euler()
    # Fit the frame to the props as the camera sees them.
    right = view.cross(Vector((0, 0, 1))).normalized()
    up = right.cross(view).normalized()
    xs = [(p - center).dot(right) for p in pts]
    ys = [(p - center).dot(up) for p in pts]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    wide = w > 1.5 * h  # a row of props: render a 2:1 frame
    aspect = 2 if wide else 1
    cam.data.ortho_scale = max(w, h * aspect) * 1.15
    cam.data.shift_x = -(max(xs) + min(xs)) / 2 / cam.data.ortho_scale
    cam.data.shift_y = (max(ys) + min(ys)) / 2 / cam.data.ortho_scale / aspect
    target = None
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.rotation_euler = (0.7, 0.2, 0.8)
    sun.data.energy = 4
    for o in (cam, sun):
        bpy.context.collection.objects.link(o)

    scene = bpy.context.scene
    scene.camera = cam
    scene.world = bpy.data.worlds.new("world")
    scene.world.color = (0.6, 0.65, 0.7)
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.render.resolution_x = res
    scene.render.resolution_y = res // 2 if wide else res
    scene.render.filepath = os.path.abspath(out)
    bpy.ops.render.render(write_still=True)


def srgb(c):
    """sRGB 0-1 color to linear, for material base colors."""
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def make_texture(name, size, fn):
    """Create an image texture: fn(u, v) -> sRGB (r, g, b) for u, v in [0, 1)."""
    img = bpy.data.images.new(name, size, size)
    px = []
    for j in range(size):
        for i in range(size):
            px.extend((*fn(i / size, j / size), 1.0))
    img.pixels = px
    # Round-trip through a PNG so the pixels are kept (packing a generated image resets it)
    # and the glTF exporter embeds a real image.
    import tempfile
    path = os.path.join(tempfile.mkdtemp(), f"{name}.png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    img = bpy.data.images.load(path)
    img.name = name
    img.pack()
    return img


def texture_material(name, image, roughness=0.9, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def box_uv(obj, scale=1.0, along="x"):
    """Planar UVs per face from world-space size, so texture density matches across props.

    along: the axis the texture's u direction (its grain) follows on side faces.
    """
    mesh = obj.data
    uv = mesh.uv_layers.get("UVMap") or mesh.uv_layers.new(name="UVMap")
    ax = "xyz".index(along)
    for poly in mesh.polygons:
        n = [abs(c) for c in poly.normal]
        dominant = n.index(max(n))
        if dominant == ax:
            # End faces: use the other two axes.
            a, b = [i for i in range(3) if i != ax]
        else:
            a = ax
            b = [i for i in range(3) if i not in (ax, dominant)][0]
        for li in poly.loop_indices:
            co = mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv = (co[a] * scale, co[b] * scale)

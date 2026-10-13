"""Rigging for props with moving parts (vehicles, trailers, belts, machines).

Builders tag the parts that move with tag(parts, name, uid). assemble() then joins each tagged group
into its own mesh, parented under the body mesh, so Studio's Import 3D gives one model whose moving
pieces are separate, named MeshParts the game can turn or slide:

  RustyPickup              the body; keeps the prop's name so Props.luau still finds the prop
    Wheel_L1, Wheel_R1     wheels, numbered front to back; L/R as seen from the driver's seat
    Wheel_L2, Wheel_R2     (a dual rear wheel is one mesh: both tires on that hub)
    Tailgate               origin on its hinge (the bottom edge)
    Ramp, Lever, Head      origin at the bottom center too; Gate at the top center; Door on its left
                           (hinge) edge; ArmL/ArmR at the shoulder (inner end)
    Coupler                trailer hitch coupler; origin at the hitch point
    Belt, Roller, Drum ... conveyor and machine parts that move

Every wheel's mesh is symmetric about its axle, so its bounding box center (where Roblox puts a
MeshPart's position) is the axle point. Vehicles are turned to face +y in Blender, which the glTF
exporter writes as -Z forward, +Y up: Roblox's forward (LookVector) and up.
"""
import math

import bpy  # noqa: F401
from mathutils import Matrix, Vector

STUD = 0.28
# Pivot rules by part name (default: bounds center). Builder coordinates face -y, so "left" is low x
# before the flip. bottom = bottom center; top = top center; door = vertical hinge on the builder-left
# edge; shoulder = the inner end (nearest the body's center line).
PIVOTS = {"Tailgate": "bottom", "Ramp": "bottom", "Lever": "bottom", "Head": "bottom",
          "Gate": "top", "Door": "door", "ArmL": "shoulder", "ArmR": "shoulder"}


def tag(objs, name, uid=""):
    """Mark parts as one moving piece. Parts with the same name and uid join into one mesh."""
    for o in objs:
        o["rig"] = name
        o["rig_uid"] = str(uid)
    return objs


def wheel_uid(x, y):
    return f"{x:.2f}:{y:.2f}"


def is_rigged(parts):
    return any("rig" in o for o in parts)


def _bake(o):
    """Move the object's transform into its mesh so it sits at the origin."""
    o.data.transform(o.matrix_basis)
    o.matrix_basis = Matrix.Identity(4)


def _bounds(objs):
    pts = [v.co for o in objs for v in o.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def _set_origin(o, p):
    o.data.transform(Matrix.Translation(-p))
    o.location = p


def _kind(mat):
    return mat.name.split(".")[0].replace("rustic_", "").replace("rolled", "hay")


def limit_materials(o, n, palette=None):
    """Keep the n materials covering the most area (glow and lava are kept when present) and repaint the
    other faces with the kept material nearest in color. Roblox makes one MeshPart per material."""
    import style
    palette = palette or style.RUSTIC
    mats = [sl.material for sl in o.material_slots]
    if len(mats) <= n:
        return o
    area = [0.0] * len(mats)
    for p in o.data.polygons:
        area[p.material_index] += p.area
    order = sorted(range(len(mats)), key=lambda i: -area[i])
    keep = [i for i in order if _kind(mats[i]) in ("glow", "lava")][:2]
    keep += [i for i in order if i not in keep][:max(0, n - len(keep))]

    def color(i):
        pal = palette.get(_kind(mats[i]))
        return Vector(pal[1]) if pal else Vector((0.5, 0.5, 0.5))
    remap = {i: (i if i in keep else min(keep, key=lambda k: (color(k) - color(i)).length))
             for i in range(len(mats))}
    for p in o.data.polygons:
        p.material_index = remap[p.material_index]
    # Drop the unused slots, highest index first. pop() itself shifts the faces' indices down.
    for i in sorted(set(range(len(mats))) - set(keep), reverse=True):
        o.data.materials.pop(index=i)
    return o


def _roblox(v):
    """Blender meters (z up, front +y after the flip) to Roblox studs (y up, front -Z)."""
    return [round(v.x / STUD, 2), round(v.z / STUD, 2), round(-v.y / STUD, 2)]


def describe(objs, bed=None):
    """Sidecar entry for rigs.json: each moving part's pivot and size in Roblox studs, wheel radii,
    and the bed. The body's origin is the model's ground center."""
    body = objs[0]
    pts = [o.matrix_world @ v.co for o in [body] + list(body.children_recursive) for v in o.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    info = {"forward": "-Z", "up": "+Y", "size": _roblox(hi - lo), "parts": {}}
    info["size"] = [abs(x) for x in info["size"]]
    for o in objs[1:]:
        olo, ohi = _bounds([o])
        size = [abs(x) for x in _roblox(ohi - olo)]
        entry = {"pivot": _roblox(o.location), "size": size}
        if o.name.startswith("Wheel_"):
            entry["radius"] = round(size[1] / 2, 2)
        info["parts"][o.name] = entry
    if bed:
        info["bed"] = {"inside_length": round(bed[0], 2), "inside_width": round(bed[1], 2),
                       "wall": round(bed[2], 2), "floor_top": 3.5, "bales": list(bed[3])}
    return info


def ground(o):
    """Shift a single mesh so its lowest point sits on z=0."""
    lo = min(v.co.z for v in o.data.vertices)
    o.data.transform(Matrix.Translation((0, 0, -lo)))


def triangles(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def limit_triangles(objs, budget):
    """Decimate the body (objs[0]) so the whole prop fits the triangle budget. Collapse decimation
    mostly eats the tiny bevel faces, so silhouettes and UVs hold up."""
    total = sum(triangles(o) for o in objs)
    body = objs[0]
    if total <= budget:
        return
    rest = total - triangles(body)
    ratio = max(0.2, (budget - rest) / triangles(body) * 0.97)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    m = body.modifiers.new("budget", "DECIMATE")
    m.ratio = ratio
    m.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=m.name)


def assemble(parts, name, join, flip=False):
    """Join a rigged prop. join(objs, name) is common.join. Returns the body; moving parts are its
    children. flip turns the prop 180 degrees about z first (builders face -y; Roblox wants -Z)."""
    for o in parts:
        _bake(o)
    if flip:
        turn = Matrix.Rotation(math.pi, 4, "Z")
        for o in parts:
            o.data.transform(turn)

    body, groups = [], {}
    for o in parts:
        if "rig" in o:
            groups.setdefault((o["rig"], o["rig_uid"]), []).append(o)
        else:
            body.append(o)

    # Name the groups: wheels by axle and side, everything else numbered front to back when repeated.
    named = []
    wheels = [(k, g) for k, g in groups.items() if k[0] == "wheel"]
    others = [(k, g) for k, g in groups.items() if k[0] != "wheel"]
    if wheels:
        centers = {k: sum(_bounds(g), Vector()) / 2 for k, g in wheels}
        # Group wheel centers into axles front (+y) to back, within 0.3 studs (lumpy tires differ a bit).
        axles = []
        for y in sorted((c.y / STUD for c in centers.values()), reverse=True):
            if not axles or axles[-1] - y > 0.3:
                axles.append(y)

        def axle_of(y):
            return min(range(len(axles)), key=lambda i: abs(axles[i] - y)) + 1
        for k, g in wheels:
            c = centers[k]
            side = "L" if c.x < 0 else "R"
            named.append((f"Wheel_{side}{axle_of(c.y / STUD)}", g, "center"))
    by_name = {}
    for k, g in others:
        by_name.setdefault(k[0], []).append(g)
    for base, gs in by_name.items():
        def order(g):
            c = sum(_bounds(g), Vector()) / 2
            return (round(-c.y / STUD, 1), round(c.x / STUD, 1))  # front to back, then left to right
        gs.sort(key=order)
        for i, g in enumerate(gs):
            named.append((base if i == 0 else f"{base}{i + 1}", g, PIVOTS.get(base, "center")))

    root = join(body, name)
    for child_name, g, pivot in named:
        lo, hi = _bounds(g)
        c = (lo + hi) / 2
        p = c
        if pivot == "bottom":
            p = Vector((c.x, c.y, lo.z))
        elif pivot == "top":
            p = Vector((c.x, c.y, hi.z))
        elif pivot == "door":
            p = Vector((hi.x if flip else lo.x, c.y, c.z))
        elif pivot == "shoulder":
            p = Vector((lo.x if abs(lo.x) < abs(hi.x) else hi.x, c.y, c.z))
        o = join(g, child_name)
        limit_materials(o, 1)  # one material per moving part: Roblox imports one MeshPart per material
        _set_origin(o, p)
        o.parent = root
        o.matrix_parent_inverse = Matrix.Identity(4)
    return root

"""Rigging for props with moving parts (vehicles, trailers, belts, machines).

Builders tag the parts that move with tag(parts, name, uid). assemble() then joins each tagged group
into its own mesh, parented under the body mesh, so Studio's Import 3D gives one model whose moving
pieces are separate, named MeshParts the game can turn or slide:

  RustyPickup              the body; keeps the prop's name so Props.luau still finds the prop
    Wheel_L1, Wheel_R1     wheels, numbered front to back; L/R as seen from the driver's seat
    Wheel_L2, Wheel_R2     (a dual rear wheel is one mesh: both tires on that hub)
    Tailgate               origin on its hinge (the bottom edge)
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
        axles = sorted({round(c.y / STUD, 1) for c in centers.values()}, reverse=True)  # front (+y) first
        for k, g in wheels:
            c = centers[k]
            side = "L" if c.x < 0 else "R"
            named.append((f"Wheel_{side}{axles.index(round(c.y / STUD, 1)) + 1}", g, "center"))
    by_name = {}
    for k, g in others:
        by_name.setdefault(k[0], []).append(g)
    for base, gs in by_name.items():
        def order(g):
            c = sum(_bounds(g), Vector()) / 2
            return (round(-c.y / STUD, 1), round(c.x / STUD, 1))  # front to back, then left to right
        gs.sort(key=order)
        for i, g in enumerate(gs):
            named.append((base if i == 0 else f"{base}{i + 1}", g, "hinge" if base == "Tailgate" else "center"))

    root = join(body, name)
    for child_name, g, pivot in named:
        lo, hi = _bounds(g)
        c = (lo + hi) / 2
        p = Vector((c.x, c.y, lo.z)) if pivot == "hinge" else c
        o = join(g, child_name)
        _set_origin(o, p)
        o.parent = root
        o.matrix_parent_inverse = Matrix.Identity(4)
    return root

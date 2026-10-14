"""An R15-style Roblox avatar for the launch art: fifteen rounded parts on a joint hierarchy, so it can be posed
(shoulders, elbows, wrists, hips, knees, ankles, waist, neck) and an expressive face. Units are studs; about
5.6 studs tall standing. The avatar faces -y; pose angles are in degrees.

    a = avatar.R15(outfit="farmer", face="grin")
    a.pose(r_shoulder=(-150, 0, 10), r_elbow=(-20, 0, 0))
    a.place((0, 0, 0), yaw_deg=20)
"""
import math

import bpy
import mathutils

import scene as S

OUTFITS = {
    # shirt, shirt stripe, pants/overalls, boots, gloves, hat (None = hair only), hair
    "farmer": dict(shirt=(178, 66, 52), stripe=(120, 40, 34), pants=(66, 92, 140), boots=(84, 58, 40),
                   gloves=(150, 106, 70), hat=(214, 186, 112), hair=(92, 60, 38), skin=(234, 184, 146), overalls=True),
    "rancher": dict(shirt=(70, 120, 160), stripe=(46, 84, 118), pants=(96, 80, 62), boots=(60, 44, 32),
                    gloves=(150, 106, 70), hat=(120, 84, 54), hair=(40, 30, 24), skin=(160, 112, 80), overalls=False),
    "kid": dict(shirt=(240, 196, 70), stripe=(210, 150, 40), pants=(70, 120, 90), boots=(200, 70, 60),
                gloves=None, hat=None, hair=(200, 120, 60), skin=(250, 210, 170), overalls=False, cap=(200, 70, 60)),
    "girl": dict(shirt=(150, 90, 170), stripe=(110, 60, 130), pants=(60, 80, 120), boots=(90, 60, 40),
                 gloves=(150, 106, 70), hat=None, hair=(130, 70, 40), skin=(214, 160, 120), overalls=True, ponytail=True),
    "starlight": dict(shirt=(60, 70, 120), stripe=(40, 46, 90), pants=(40, 44, 70), boots=(40, 40, 50),
                      gloves=(150, 175, 255), hat=None, hair=(236, 196, 104), skin=(234, 184, 146), overalls=False,
                      glove_glow=2.0),
}

# joint name -> (parent, offset from parent joint)
JOINTS = {
    "root": (None, (0, 0, 2.55)),
    "waist": ("root", (0, 0, 0.25)),
    "neck": ("waist", (0, 0, 1.75)),
    "l_shoulder": ("waist", (-1.25, 0, 1.45)),
    "r_shoulder": ("waist", (1.25, 0, 1.45)),
    "l_elbow": ("l_shoulder", (0, 0, -1.15)),
    "r_elbow": ("r_shoulder", (0, 0, -1.15)),
    "l_wrist": ("l_elbow", (0, 0, -1.0)),
    "r_wrist": ("r_elbow", (0, 0, -1.0)),
    "l_hip": ("root", (-0.5, 0, -0.1)),
    "r_hip": ("root", (0.5, 0, -0.1)),
    "l_knee": ("l_hip", (0, 0, -1.15)),
    "r_knee": ("r_hip", (0, 0, -1.15)),
    "l_ankle": ("l_knee", (0, 0, -1.1)),
    "r_ankle": ("r_knee", (0, 0, -1.1)),
}


def rbox(size, loc, m, bevel=0.18, segs=3, parent=None, name="part"):
    o = S.box(size, loc, m, bevel=0, name=name)
    mod = o.modifiers.new("round", "BEVEL")
    mod.width = min(bevel, min(size) * 0.45)
    mod.segments = segs
    mod.limit_method = "NONE"
    bpy.ops.object.shade_smooth()
    if parent:
        o.parent = parent
    return o


class R15:
    def __init__(self, outfit="farmer", face="grin"):
        self.o = OUTFITS[outfit]
        self.j = {}
        for name, (parent, off) in JOINTS.items():
            e = bpy.data.objects.new(name, None)
            bpy.context.scene.collection.objects.link(e)
            e.rotation_mode = "XYZ"
            e.location = off
            if parent:
                e.parent = self.j[parent]
            self.j[name] = e
        self._build(face)

    # ---------------------------------------------------------------- body
    def _m(self, key, rgb, rough=0.75, metal=0.0, emit=0.0):
        return S.mat("av_%s_%d_%d_%d" % (key, *rgb), rgb, rough, metal, emit)

    def _build(self, face):
        o = self.o
        skin = self._m("skin", o["skin"], 0.6)
        shirt = self._m("shirt", o["shirt"], 0.85)
        stripe = self._m("stripe", o["stripe"], 0.85)
        pants = self._m("pants", o["pants"], 0.85)
        boots = self._m("boots", o["boots"], 0.7)
        hands = self._m("glove", o["gloves"], 0.7, 0, o.get("glove_glow", 0)) if o["gloves"] else skin
        J = self.j
        # torso: upper (shirt or overall bib) and lower
        rbox((2.0, 1.0, 1.6), (0, 0, 0.85), shirt, 0.22, parent=J["waist"])
        for z in (0.35, 0.85, 1.35):  # plaid bands
            rbox((2.04, 1.04, 0.14), (0, 0, z), stripe, 0.05, 1, parent=J["waist"])
        for x in (-0.55, -0.05, 0.45):
            rbox((0.14, 1.04, 1.5), (x + 0.05, 0, 0.85), stripe, 0.05, 1, parent=J["waist"])
        if o.get("overalls"):
            rbox((1.5, 1.06, 1.0), (0, 0, 0.55), pants, 0.15, parent=J["waist"])
            for x in (-0.55, 0.55):
                rbox((0.3, 1.08, 0.7), (x, 0, 1.3), pants, 0.08, parent=J["waist"])
                S.cyl(0.08, 0.05, (x, -0.55, 1.05), self._m("brass", (210, 170, 80), 0.3, 0.8), verts=10,
                      rot=(math.pi / 2, 0, 0)).parent = J["waist"]
        rbox((2.0, 1.0, 0.5), (0, 0, 0.0), pants, 0.15, parent=J["root"])
        rbox((2.04, 1.04, 0.16), (0, 0, 0.18), self._m("belt", (70, 50, 36), 0.6), 0.05, 1, parent=J["root"])
        # arms
        for s in ("l", "r"):
            rbox((0.95, 0.95, 1.25), (0, 0, -0.5), shirt, 0.3, parent=J[s + "_shoulder"])
            rbox((0.9, 0.9, 1.1), (0, 0, -0.5), shirt, 0.3, parent=J[s + "_elbow"])
            rbox((0.92, 0.92, 0.12), (0, 0, -0.95), stripe, 0.04, 1, parent=J[s + "_elbow"])
            rbox((0.85, 0.85, 0.75), (0, 0, -0.3), hands, 0.3, parent=J[s + "_wrist"])
            # legs
            rbox((0.98, 0.98, 1.25), (0, 0, -0.55), pants, 0.25, parent=J[s + "_hip"])
            rbox((0.94, 0.94, 1.15), (0, 0, -0.5), pants, 0.25, parent=J[s + "_knee"])
            rbox((1.0, 1.35, 0.55), (0, -0.15, -0.3), boots, 0.22, parent=J[s + "_ankle"])
        # head
        J_n = J["neck"]
        rbox((1.0, 0.9, 0.3), (0, 0, 0.1), skin, 0.1, parent=J_n)
        head = rbox((1.6, 1.42, 1.5), (0, 0, 0.95), skin, 0.45, 4, parent=J_n)
        self.head = head
        self._face(face)
        hair = self._m("hair", o["hair"], 0.8)
        rbox((1.62, 1.46, 0.5), (0, 0.04, 1.55), hair, 0.22, parent=J_n)
        rbox((1.62, 0.5, 1.1), (0, 0.5, 1.15), hair, 0.22, parent=J_n)
        for x in (-0.55, -0.15, 0.25):
            rbox((0.42, 0.3, 0.42), (x, -0.62, 1.55), hair, 0.12, parent=J_n)
        if o.get("ponytail"):
            rbox((0.5, 0.5, 1.2), (0, 0.85, 0.9), hair, 0.22, parent=J_n)
        if o.get("hat"):
            hat = self._m("hat", o["hat"], 0.85)
            S.cyl(1.6, 0.14, (0, 0, 1.75), hat, verts=28).parent = J_n
            S.cyl(0.9, 0.75, (0, 0, 2.1), hat, verts=24).parent = J_n
            S.cyl(0.92, 0.18, (0, 0, 1.9), self._m("hatband", (130, 60, 44), 0.8), verts=24).parent = J_n
        if o.get("cap"):
            cap = self._m("cap", o["cap"], 0.8)
            rbox((1.66, 1.5, 0.55), (0, 0.02, 1.7), cap, 0.25, parent=J_n)
            rbox((1.3, 0.9, 0.12), (0, -0.95, 1.5), cap, 0.06, parent=J_n)

    def _face(self, face):
        J_n = self.j["neck"]
        ink = self._m("ink", (30, 24, 20), 0.4)
        white = self._m("eyewhite", (250, 250, 250), 0.3)
        mouth = self._m("mouth", (90, 30, 30), 0.6)
        teeth = self._m("teeth", (250, 248, 240), 0.4)
        fy = -0.71
        eye_h = {"grin": 0.42, "wow": 0.5, "determined": 0.3}.get(face, 0.42)
        for x in (-0.33, 0.33):
            e = S.cyl(0.17, 0.05, (x, fy, 1.1), white, verts=16, rot=(math.pi / 2, 0, 0))
            e.scale = (1, eye_h / 0.34, 1)
            e.parent = J_n
            p = S.cyl(0.1, 0.06, (x + 0.02, fy - 0.02, 1.08), ink, verts=14, rot=(math.pi / 2, 0, 0))
            p.scale = (1, eye_h / 0.3, 1)
            p.parent = J_n
            hl = S.cyl(0.035, 0.07, (x + 0.06, fy - 0.035, 1.15), white, verts=8, rot=(math.pi / 2, 0, 0))
            hl.parent = J_n
            brow_rot = {"grin": 0.0, "wow": 0.0, "determined": 0.35}.get(face, 0) * (1 if x > 0 else -1)
            b = S.box((0.36, 0.05, 0.08), (x, fy - 0.01, 1.4 + (0.06 if face == "wow" else 0)), ink,
                      rot=(0, brow_rot, 0), bevel=0)
            b.parent = J_n
        if face == "wow":
            m = S.cyl(0.2, 0.05, (0, fy, 0.6), mouth, verts=16, rot=(math.pi / 2, 0, 0))
            m.scale = (0.9, 1.3, 1)
            m.parent = J_n
        else:
            # open grin: a half-disc of mouth with a strip of teeth
            bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.36, depth=0.05, location=(0, fy, 0.72),
                                                rotation=(math.pi / 2, 0, 0))
            m = bpy.context.active_object
            m.data.materials.append(mouth)
            m.scale = (1, 0.75 if face == "grin" else 0.4, 1)
            bpy.ops.mesh.primitive_cube_add(size=1, location=(0, fy, 0.9))
            cut = bpy.context.active_object
            cut.scale = (1, 0.5, 0.36)
            mod = m.modifiers.new("half", "BOOLEAN")
            mod.object = cut
            mod.operation = "DIFFERENCE"
            cut.hide_render = True
            cut.hide_viewport = True
            m.parent = J_n
            t = S.box((0.5, 0.06, 0.09), (0, fy - 0.005, 0.67), teeth, bevel=0)
            t.parent = J_n
        cheek = self._m("cheek", (240, 140, 130), 0.6)
        for x in (-0.55, 0.55):
            c = S.cyl(0.12, 0.03, (x, fy + 0.01, 0.78), cheek, verts=12, rot=(math.pi / 2, 0, 0))
            c.parent = J_n

    # ---------------------------------------------------------------- posing
    def pose(self, **angles):
        """Joint rotations in degrees, (x, y, z). x swings a limb forward (-) or back (+); z turns it."""
        for k, v in angles.items():
            self.j[k].rotation_euler = tuple(math.radians(a) for a in v)
        return self

    def place(self, loc, yaw_deg=0.0, scale=1.0):
        r = self.j["root"]
        r.location = (loc[0], loc[1], loc[2] + 2.55 * scale)
        r.rotation_euler = (r.rotation_euler[0], r.rotation_euler[1], math.radians(yaw_deg))
        r.scale = (scale,) * 3
        return self

    def hold(self, obj, side="r", offset=(0, 0, -0.65), rot=(0, 0, 0)):
        """Parent a prop root to a hand."""
        obj.parent = self.j[side + "_wrist"]
        obj.location = offset
        obj.rotation_euler = tuple(math.radians(a) for a in rot)
        return obj

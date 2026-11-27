"""Galaughxy roster generator — 20 smooth vinyl-toy characters, exported as .glb.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/generate_roster.py -- godot/assets/models/characters

Every character shares one joint layout (empties), so the Godot Puppet can drive any of them:
  Root > Hips > Spine > Head, Arm_L, Arm_R, Leg_L, Leg_R
  Head > Eye_L, Eye_R, Brow_L, Brow_R (optional), Jaw or Mouth (lip-sync)
Optional gag joints, animated by name in Godot: Toast, Steam, Rotor_*, Tentacle_*, Wheel_*,
Ear_L/Ear_R, Ball_*, Cheek_L/Cheek_R, Mustache, Flame, Tail, Antenna_*.

Perfect style (CLAUDE.md section 17): smooth primitives only (high-segment spheres, bevelled boxes
and cylinders, shade smooth + weighted normals), every left/right part mirrored from one
definition, nothing cuts into the floor. Blender axes: Z up, characters face -Y (exports to +Z
forward in Godot).
"""

import math
import os
import sys

import bpy
from mathutils import Vector

# Mac Studio palette + a few natural accents
SILVER = "#E5E7EB"
GRAY = "#2C2E33"
CREAM = "#F5F2EB"
BLUE = "#4A90E2"
CORAL = "#FF5F56"
AMBER = "#FFBD2E"
MINT = "#27C93F"
DARK = "#16181D"
WHITE = "#FFFFFF"
PINK = "#F7A8B8"
INK = "#101114"


def segs(r):
    """Sphere segments scaled to size: big shapes stay perfectly round, tiny ones stay light."""
    return max(16, min(48, int(r * 420)))


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb(hexc):
    h = hexc.lstrip("#")
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


class Char:
    def __init__(self, cid):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        self.id = cid
        self.mats = {}
        self.joints = {}
        self.wpos = {}
        self.joint("Root", None, (0, 0, 0))

    # ── materials ──────────────────────────────────────────────────────────────
    def mat(self, hexc, emit=0.0, alpha=1.0, rough=0.42):
        key = (hexc, emit, alpha, rough)
        if key in self.mats:
            return self.mats[key]
        name = "M_%s%s%s" % (hexc.lstrip("#"), "_glow" if emit else "", "_glass" if alpha < 1 else "")
        m = bpy.data.materials.new(name)
        try:
            m.use_nodes = True
        except Exception:
            pass
        b = m.node_tree.nodes.get("Principled BSDF")
        c = rgb(hexc)
        b.inputs["Base Color"].default_value = (*c, 1.0)
        b.inputs["Roughness"].default_value = rough
        if emit:
            b.inputs["Emission Color"].default_value = (*c, 1.0)
            b.inputs["Emission Strength"].default_value = emit
        if alpha < 1.0:
            b.inputs["Alpha"].default_value = alpha
            b.inputs["Roughness"].default_value = 0.08
            for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
                try:
                    setattr(m, attr, val)
                except Exception:
                    pass
        self.mats[key] = m
        return m

    # ── joints ─────────────────────────────────────────────────────────────────
    def joint(self, name, parent, pos):
        e = bpy.data.objects.new(name, None)
        e.empty_display_size = 0.03
        bpy.context.scene.collection.objects.link(e)
        p = Vector(pos)
        if parent:
            e.parent = self.joints[parent]
            e.location = p - self.wpos[parent]
        else:
            e.location = p
        self.joints[name] = e
        self.wpos[name] = p
        return name

    def std(self, hips, spine, head, arm, leg):
        """Standard joint layout. arm/leg are the left-side positions; the right side mirrors x."""
        self.joint("Hips", "Root", hips)
        self.joint("Spine", "Hips", spine)
        self.joint("Head", "Spine", head)
        self.joint("Arm_L", "Spine", arm)
        self.joint("Arm_R", "Spine", (-arm[0], arm[1], arm[2]))
        self.joint("Leg_L", "Hips", leg)
        self.joint("Leg_R", "Hips", (-leg[0], leg[1], leg[2]))

    # ── parts ──────────────────────────────────────────────────────────────────
    def _new(self):
        o = bpy.context.active_object
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        return o

    def _place(self, o, joint, name, center, rot, hexc, emit, alpha, hard):
        o.name = name
        o.data.name = name
        for p in o.data.polygons:
            p.use_smooth = True
        if hard:
            wn = o.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
            wn.keep_sharp = True
        o.data.materials.append(self.mat(hexc, emit, alpha))
        o.parent = self.joints[joint]
        o.location = Vector(center) - self.wpos[joint]
        if rot is not None:
            if len(rot) == 4:
                o.rotation_mode = "QUATERNION"
                o.rotation_quaternion = rot
            else:
                o.rotation_euler = rot
        return o

    def _apply_scale(self, o, s):
        o.scale = s
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    def ell(self, joint, name, c, r, hexc, rot=None, emit=0.0, alpha=1.0):
        n = segs(max(r))
        bpy.ops.mesh.primitive_uv_sphere_add(segments=n, ring_count=n // 2, radius=1.0)
        o = self._new()
        self._apply_scale(o, r)
        return self._place(o, joint, name, c, rot, hexc, emit, alpha, False)

    def box(self, joint, name, c, half, rad, hexc, rot=None, emit=0.0, alpha=1.0):
        bpy.ops.mesh.primitive_cube_add(size=2.0)
        o = self._new()
        self._apply_scale(o, half)
        bv = o.modifiers.new("Bevel", "BEVEL")
        bv.width = min(rad, min(half) * 0.98)
        bv.segments = 6
        bv.limit_method = "NONE"
        bv.use_clamp_overlap = True
        return self._place(o, joint, name, c, rot, hexc, emit, alpha, True)

    def cyl(self, joint, name, c, radius, half_h, hexc, rot=None, bevel=0.012, emit=0.0, alpha=1.0, verts=64):
        bpy.ops.mesh.primitive_cylinder_add(vertices=min(verts, max(20, segs(radius * 1.6))), radius=1.0, depth=2.0)
        o = self._new()
        self._apply_scale(o, (radius, radius, half_h))
        if bevel > 0:
            bv = o.modifiers.new("Bevel", "BEVEL")
            bv.width = min(bevel, radius * 0.9, half_h * 0.9)
            bv.segments = 6
            bv.limit_method = "ANGLE"
            bv.angle_limit = math.radians(40)
            bv.use_clamp_overlap = True
        return self._place(o, joint, name, c, rot, hexc, emit, alpha, True)

    def cone(self, joint, name, c, r1, r2, half_h, hexc, rot=None, emit=0.0):
        bpy.ops.mesh.primitive_cone_add(vertices=max(20, segs(max(r1, r2) * 1.6)), radius1=r1, radius2=r2, depth=2.0 * half_h)
        o = self._new()
        bv = o.modifiers.new("Bevel", "BEVEL")
        bv.width = min(0.008, half_h * 0.4, max(r1, r2) * 0.4)
        bv.segments = 5
        bv.limit_method = "ANGLE"
        bv.angle_limit = math.radians(40)
        return self._place(o, joint, name, c, rot, hexc, emit, 1.0, True)

    def torus(self, joint, name, c, major, minor, hexc, rot=None, emit=0.0):
        bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=segs(major * 1.5), minor_segments=max(10, segs(minor * 3) // 2))
        o = self._new()
        return self._place(o, joint, name, c, rot, hexc, emit, 1.0, False)

    def cap(self, joint, name, a, b, r, hexc, emit=0.0):
        """Capsule from a to b (one smooth mesh: cylinder plus two hemispherical ends)."""
        a = Vector(a)
        b = Vector(b)
        d = b - a
        length = d.length
        n = segs(r * 2.5)
        bpy.ops.mesh.primitive_cylinder_add(vertices=n, radius=r, depth=length)
        body = self._new()
        parts = [body]
        for z in (-length / 2, length / 2):
            bpy.ops.mesh.primitive_uv_sphere_add(segments=n, ring_count=n // 2, radius=r, location=(0, 0, z))
            parts.append(bpy.context.active_object)
        bpy.ops.object.select_all(action="DESELECT")
        for p in parts:
            p.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.join()
        o = bpy.context.active_object
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        return self._place(o, joint, name, (a + b) / 2, (q.w, q.x, q.y, q.z), hexc, emit, 1.0, False)

    def pair(self, fn):
        """Builds a left/right pair from one definition: fn(s, side) with s = +1 (left) or -1 (right)."""
        for s, side in ((1, "L"), (-1, "R")):
            fn(s, side)

    # ── faces ──────────────────────────────────────────────────────────────────
    def animal_eyes(self, center, spacing, r, iris=INK, sclera=WHITE, pupil_r=0.55, head="Head"):
        cx, cy, cz = center

        def eye(s, side):
            j = self.joint("Eye_" + side, head, (cx + s * spacing, cy, cz))
            self.ell(j, "EyeWhite_" + side, (cx + s * spacing, cy, cz), (r, r * 0.8, r), sclera)
            self.ell(j, "Pupil_" + side, (cx + s * spacing, cy - r * 0.72, cz), (r * pupil_r, r * 0.3, r * pupil_r), iris)
            self.ell(j, "Glint_" + side, (cx + s * spacing + s * r * 0.18, cy - r * 0.86, cz + r * 0.2), (r * 0.14, r * 0.08, r * 0.14), WHITE, emit=0.6)
        self.pair(eye)

    def screen_eyes(self, center, spacing, w, h, hexc=MINT, head="Head"):
        cx, cy, cz = center

        def eye(s, side):
            j = self.joint("Eye_" + side, head, (cx + s * spacing, cy, cz))
            self.ell(j, "EyeGlow_" + side, (cx + s * spacing, cy, cz), (w, 0.006, h), hexc, emit=3.0)
        self.pair(eye)

    def brows(self, center, spacing, length, hexc=GRAY, tilt=0.0, head="Head", thick=0.008):
        cx, cy, cz = center

        def brow(s, side):
            j = self.joint("Brow_" + side, head, (cx + s * spacing, cy, cz))
            half = length / 2
            self.cap(j, "BrowBar_" + side, (cx + s * spacing - half, cy, cz + s * tilt), (cx + s * spacing + half, cy, cz - s * tilt), thick, hexc)
        self.pair(brow)

    def screen_mouth(self, center, w, h, hexc=MINT, head="Head"):
        j = self.joint("Mouth", head, center)
        self.ell(j, "MouthGlow", center, (w, 0.006, h), hexc, emit=3.0)

    # ── export ─────────────────────────────────────────────────────────────────
    def export(self, out_dir):
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, self.id + ".glb")
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True, export_animations=False)
        print("[roster] wrote", path)


# ── the cast ─────────────────────────────────────────────────────────────────────

def robo_bear(c):
    c.std((0, 0, 0.16), (0, 0, 0.2), (0, 0, 0.46), (0.17, 0, 0.32), (0.08, 0, 0.12))
    c.box("Spine", "Chassis", (0, 0, 0.3), (0.15, 0.11, 0.13), 0.05, BLUE)
    c.ell("Spine", "ChestLight", (0, -0.112, 0.31), (0.025, 0.008, 0.025), AMBER, emit=2.5)
    c.box("Head", "CRT", (0, 0, 0.58), (0.17, 0.14, 0.13), 0.05, BLUE)
    c.box("Head", "Bezel", (0, -0.13, 0.58), (0.135, 0.018, 0.1), 0.03, CREAM)
    c.box("Head", "Screen", (0, -0.145, 0.58), (0.115, 0.008, 0.08), 0.025, DARK)
    c.screen_eyes((0, -0.155, 0.6), 0.05, 0.018, 0.024, MINT)
    c.screen_mouth((0, -0.155, 0.545), 0.03, 0.007, MINT)

    def ear(s, side):
        c.joint("Ear_" + side, "Head", (s * 0.13, 0, 0.7))
        c.ell("Ear_" + side, "EarOuter_" + side, (s * 0.13, 0, 0.71), (0.05, 0.035, 0.05), BLUE)
        c.ell("Ear_" + side, "EarInner_" + side, (s * 0.13, -0.025, 0.71), (0.03, 0.012, 0.03), CREAM)
    c.pair(ear)
    c.joint("Antenna_1", "Head", (0, 0, 0.71))
    c.cap("Antenna_1", "Mast", (0, 0, 0.71), (0, 0, 0.8), 0.008, SILVER)
    c.ell("Antenna_1", "Bobble", (0, 0, 0.82), (0.022, 0.022, 0.022), CORAL, emit=2.0)

    def limbs(s, side):
        c.cap("Arm_" + side, "Arm_" + side + "_Mesh", (s * 0.17, 0, 0.36), (s * 0.2, 0, 0.24), 0.03, BLUE)
        c.ell("Arm_" + side, "Hand_" + side, (s * 0.2, 0, 0.22), (0.035, 0.035, 0.035), SILVER)
        c.cap("Leg_" + side, "Leg_" + side + "_Mesh", (s * 0.08, 0, 0.16), (s * 0.08, 0, 0.07), 0.032, GRAY)
        c.box("Leg_" + side, "Foot_" + side, (s * 0.08, -0.02, 0.035), (0.045, 0.06, 0.03), 0.02, GRAY)
    c.pair(limbs)


def robo_fish(c):
    c.std((0, 0, 0.12), (0, 0, 0.3), (0, -0.12, 0.32), (0.11, -0.02, 0.3), (0.06, 0, 0.05))
    c.cyl("Hips", "Base", (0, 0, 0.025), 0.12, 0.025, SILVER, bevel=0.01)
    for i in range(4):
        c.torus("Hips", "Spring_%d" % i, (0, 0, 0.07 + i * 0.04), 0.035, 0.009, SILVER)
    c.ell("Spine", "FishBody", (0, 0, 0.3), (0.1, 0.2, 0.12), GRAY)
    c.ell("Spine", "FishBelly", (0, -0.02, 0.26), (0.085, 0.16, 0.07), SILVER)
    c.joint("Tail", "Spine", (0, 0.19, 0.3))
    c.ell("Tail", "TailFinUp", (0, 0.27, 0.35), (0.012, 0.07, 0.06), CORAL, rot=(math.radians(-35), 0, 0))
    c.ell("Tail", "TailFinDown", (0, 0.27, 0.25), (0.012, 0.07, 0.06), CORAL, rot=(math.radians(35), 0, 0))
    c.ell("Spine", "DorsalFin", (0, 0.02, 0.42), (0.01, 0.08, 0.04), CORAL)
    c.joint("Rotor_Key", "Spine", (0, 0.04, 0.42))
    c.cyl("Rotor_Key", "KeyStem", (0, 0.04, 0.45), 0.008, 0.03, SILVER, bevel=0.003)
    c.torus("Rotor_Key", "KeyLoop_L", (0.03, 0.04, 0.49), 0.022, 0.006, SILVER, rot=(0, math.radians(90), 0))
    c.torus("Rotor_Key", "KeyLoop_R", (-0.03, 0.04, 0.49), 0.022, 0.006, SILVER, rot=(0, math.radians(90), 0))
    c.animal_eyes((0, -0.13, 0.35), 0.065, 0.035)
    c.joint("Jaw", "Head", (0, -0.17, 0.28))
    c.ell("Jaw", "Lips", (0, -0.19, 0.29), (0.04, 0.02, 0.018), CORAL)

    def fin(s, side):
        c.ell("Arm_" + side, "SideFin_" + side, (s * 0.12, 0.0, 0.27), (0.05, 0.035, 0.012), CORAL, rot=(0, s * math.radians(-30), 0))
    c.pair(fin)


def toaster_bot(c):
    c.std((0, 0, 0.1), (0, 0, 0.12), (0, 0, 0.25), (0.19, 0, 0.22), (0.09, 0, 0.06))
    c.box("Spine", "Toaster", (0, 0, 0.25), (0.17, 0.12, 0.14), 0.05, SILVER)
    c.box("Spine", "Band", (0, 0, 0.17), (0.172, 0.122, 0.02), 0.015, GRAY)

    def slot(s, side):
        c.box("Spine", "Slot_" + side, (s * 0.06, 0, 0.385), (0.03, 0.09, 0.008), 0.006, DARK)
    c.pair(slot)
    c.joint("Toast", "Spine", (0, 0, 0.36))

    def toast(s, side):
        c.box("Toast", "Toast_" + side, (s * 0.06, 0, 0.39), (0.022, 0.08, 0.06), 0.02, "#D9A05B")
        c.box("Toast", "Crust_" + side, (s * 0.06, 0, 0.445), (0.023, 0.081, 0.012), 0.01, "#A8692E")
    c.pair(toast)
    c.box("Head", "Face", (0, -0.12, 0.27), (0.11, 0.006, 0.06), 0.02, DARK)
    c.screen_eyes((0, -0.128, 0.285), 0.045, 0.016, 0.02, AMBER)
    c.screen_mouth((0, -0.128, 0.245), 0.028, 0.006, AMBER)
    c.ell("Arm_L", "Lever", (0.19, 0, 0.27), (0.02, 0.03, 0.02), GRAY)
    c.cyl("Arm_R", "Dial", (-0.18, -0.03, 0.22), 0.025, 0.01, CORAL, rot=(0, math.radians(90), 0), bevel=0.004)

    def leg(s, side):
        c.cap("Leg_" + side, "Leg_" + side + "_Mesh", (s * 0.09, 0, 0.1), (s * 0.09, 0, 0.045), 0.022, GRAY)
        c.box("Leg_" + side, "Foot_" + side, (s * 0.09, -0.015, 0.025), (0.035, 0.045, 0.02), 0.015, GRAY)
    c.pair(leg)


def coffee_bot(c):
    c.std((0, 0, 0.08), (0, 0, 0.1), (0, 0, 0.3), (0.14, 0, 0.22), (0.07, 0, 0.04))
    c.cyl("Spine", "Base", (0, 0, 0.1), 0.13, 0.05, GRAY, bevel=0.02)
    c.cyl("Spine", "Body", (0, 0, 0.23), 0.11, 0.08, SILVER, bevel=0.02)
    c.box("Head", "Face", (0, -0.105, 0.24), (0.07, 0.008, 0.045), 0.02, DARK)
    c.screen_eyes((0, -0.115, 0.25), 0.03, 0.013, 0.016, AMBER)
    c.screen_mouth((0, -0.115, 0.222), 0.02, 0.005, AMBER)
    c.ell("Head", "Dome", (0, 0, 0.33), (0.1, 0.1, 0.1), "#CFE8FF", alpha=0.35)
    c.ell("Head", "Coffee", (0, 0, 0.32), (0.075, 0.075, 0.045), "#6B3E1F")
    c.cyl("Head", "Lid", (0, 0, 0.43), 0.03, 0.012, GRAY, bevel=0.006)
    c.joint("Steam", "Head", (0, 0, 0.47))
    for i, (x, z, r) in enumerate(((0, 0.48, 0.025), (0.02, 0.52, 0.02), (-0.015, 0.555, 0.016))):
        c.ell("Steam", "Puff_%d" % i, (x, 0, z), (r, r, r), WHITE)
    c.cap("Arm_R", "Spout", (-0.11, -0.02, 0.2), (-0.17, -0.05, 0.17), 0.015, SILVER)
    c.torus("Arm_L", "Handle", (0.13, 0, 0.23), 0.04, 0.011, GRAY, rot=(math.radians(90), 0, 0))

    def foot(s, side):
        c.ell("Leg_" + side, "Foot_" + side, (s * 0.07, -0.02, 0.025), (0.04, 0.05, 0.022), GRAY)
    c.pair(foot)


def roomba_dog(c):
    c.std((0, 0, 0.05), (0, 0, 0.06), (0, -0.14, 0.08), (0.15, -0.05, 0.05), (0.1, 0.05, 0.02))
    c.cyl("Spine", "Disc", (0, 0, 0.055), 0.22, 0.035, GRAY, bevel=0.02)
    c.torus("Spine", "Rim", (0, 0, 0.09), 0.17, 0.01, SILVER)
    c.cyl("Spine", "TopPlate", (0, 0, 0.09), 0.16, 0.006, SILVER, bevel=0.004)
    c.cyl("Spine", "Button", (0, 0.03, 0.1), 0.03, 0.008, MINT, bevel=0.004, emit=1.2)
    c.screen_eyes((0, -0.215, 0.07), 0.05, 0.016, 0.014, MINT)
    c.ell("Head", "Nose", (0, -0.222, 0.05), (0.02, 0.012, 0.014), INK)

    def ear(s, side):
        c.joint("Ear_" + side, "Head", (s * 0.12, -0.12, 0.09))
        c.ell("Ear_" + side, "FloppyEar_" + side, (s * 0.19, -0.1, 0.06), (0.03, 0.06, 0.012), CORAL, rot=(0, s * math.radians(55), 0))
    c.pair(ear)
    c.joint("Tail", "Spine", (0, 0.2, 0.08))
    c.cap("Tail", "TailMast", (0, 0.2, 0.08), (0, 0.24, 0.15), 0.009, SILVER)
    c.ell("Tail", "TailTip", (0, 0.245, 0.16), (0.016, 0.016, 0.016), CORAL, emit=1.5)


def tv_head(c):
    c.std((0, 0, 0.2), (0, 0, 0.24), (0, 0, 0.44), (0.12, 0, 0.36), (0.06, 0, 0.18))
    c.box("Spine", "Torso", (0, 0, 0.32), (0.1, 0.08, 0.1), 0.04, GRAY)
    c.box("Head", "Monitor", (0, 0, 0.58), (0.15, 0.14, 0.15), 0.035, CREAM)
    c.box("Head", "ScreenFrame", (0, -0.137, 0.61), (0.11, 0.008, 0.09), 0.02, "#E4DFD2")
    c.box("Head", "Screen", (0, -0.145, 0.61), (0.095, 0.006, 0.075), 0.03, DARK)
    c.box("Head", "DiskSlot", (0, -0.142, 0.48), (0.045, 0.004, 0.006), 0.003, GRAY)
    c.screen_eyes((0, -0.152, 0.63), 0.042, 0.015, 0.02, MINT)
    c.screen_mouth((0, -0.152, 0.585), 0.028, 0.006, MINT)

    def ears(s, side):
        j = c.joint("Antenna_" + side, "Head", (s * 0.04, 0, 0.73))
        c.cap(j, "Rabbit_" + side, (s * 0.04, 0, 0.73), (s * 0.13, 0, 0.88), 0.007, SILVER)
        c.ell(j, "RabbitTip_" + side, (s * 0.133, 0, 0.885), (0.014, 0.014, 0.014), CORAL)

        c.cap("Arm_" + side, "Arm_" + side + "_Mesh", (s * 0.12, 0, 0.38), (s * 0.15, 0, 0.26), 0.018, GRAY)
        c.ell("Arm_" + side, "Hand_" + side, (s * 0.152, 0, 0.245), (0.028, 0.028, 0.028), SILVER)
        c.cap("Leg_" + side, "Leg_" + side + "_Mesh", (s * 0.06, 0, 0.22), (s * 0.06, 0, 0.05), 0.02, GRAY)
        c.box("Leg_" + side, "Shoe_" + side, (s * 0.06, -0.02, 0.025), (0.035, 0.055, 0.022), 0.018, CORAL)
    c.pair(ears)
    c.cyl("Head", "Neck", (0, 0, 0.44), 0.03, 0.025, SILVER, bevel=0.006)


def gumball_bot(c):
    c.std((0, 0, 0.1), (0, 0, 0.12), (0, 0, 0.35), (0.14, 0, 0.2), (0.07, 0, 0.06))
    c.cyl("Spine", "Base", (0, 0, 0.19), 0.12, 0.09, CORAL, bevel=0.035)
    c.box("Spine", "CoinPlate", (0, -0.112, 0.15), (0.04, 0.01, 0.03), 0.01, SILVER)
    c.box("Spine", "Face", (0, -0.112, 0.23), (0.07, 0.006, 0.03), 0.015, DARK)
    c.screen_eyes((0, -0.12, 0.235), 0.032, 0.012, 0.014, AMBER, head="Spine")
    c.screen_mouth((0, -0.12, 0.165), 0.018, 0.005, AMBER, head="Spine")
    c.ell("Head", "Dome", (0, 0, 0.38), (0.11, 0.11, 0.11), "#DDF2FF", alpha=0.3)
    c.cyl("Head", "Collar", (0, 0, 0.285), 0.085, 0.012, SILVER, bevel=0.006)
    c.cyl("Head", "Cap", (0, 0, 0.49), 0.04, 0.014, CORAL, bevel=0.008)
    c.ell("Head", "Knob", (0, 0, 0.515), (0.018, 0.018, 0.018), SILVER)
    balls = ((0.045, 0.02, 0.33, CORAL), (-0.045, -0.02, 0.33, AMBER), (0.0, 0.05, 0.34, MINT),
             (0.03, -0.045, 0.385, MINT), (-0.035, 0.04, 0.39, CORAL), (0.0, 0.0, 0.43, AMBER))
    for i, (x, y, z, col) in enumerate(balls):
        j = c.joint("Ball_%d" % i, "Head", (x, y, z))
        c.ell(j, "Gum_%d" % i, (x, y, z), (0.028, 0.028, 0.028), col)

    def limbs(s, side):
        c.cap("Arm_" + side, "Arm_" + side + "_Mesh", (s * 0.12, 0, 0.22), (s * 0.16, 0, 0.14), 0.018, SILVER)
        c.ell("Arm_" + side, "Hand_" + side, (s * 0.165, 0, 0.13), (0.025, 0.025, 0.025), CORAL)
        c.ell("Leg_" + side, "Foot_" + side, (s * 0.07, -0.02, 0.05), (0.04, 0.055, 0.045), GRAY)
    c.pair(limbs)


def chaotic_frog(c):
    c.std((0, 0, 0.1), (0, 0, 0.12), (0, -0.06, 0.2), (0.13, -0.12, 0.1), (0.15, 0.08, 0.08))
    lime = "#9BCB3C"
    avocado = "#5E8C1F"
    c.ell("Spine", "Body", (0, 0, 0.14), (0.2, 0.18, 0.12), lime)
    c.ell("Spine", "Back", (0, 0.05, 0.17), (0.17, 0.12, 0.08), avocado)
    c.ell("Spine", "Belly", (0, -0.08, 0.1), (0.15, 0.1, 0.07), "#E9F2C9")
    c.animal_eyes((0, -0.06, 0.28), 0.09, 0.06, iris=INK, pupil_r=0.45)

    def dome(s, side):
        c.ell("Eye_" + side, "Dome_" + side, (s * 0.09, -0.04, 0.27), (0.068, 0.06, 0.06), lime)
    c.pair(dome)
    c.joint("Jaw", "Head", (0, 0.02, 0.15))
    c.ell("Jaw", "Chin", (0, -0.1, 0.11), (0.16, 0.09, 0.04), "#C8E39A")
    c.ell("Jaw", "MouthLine", (0, -0.165, 0.135), (0.12, 0.012, 0.008), INK)

    def legs(s, side):
        c.ell("Leg_" + side, "Thigh_" + side, (s * 0.17, 0.08, 0.08), (0.07, 0.1, 0.06), lime)
        c.ell("Leg_" + side, "Foot_" + side, (s * 0.2, 0.0, 0.015), (0.06, 0.08, 0.015), avocado)
        c.cap("Arm_" + side, "Arm_" + side + "_Mesh", (s * 0.13, -0.12, 0.1), (s * 0.15, -0.16, 0.03), 0.025, lime)
        c.ell("Arm_" + side, "Hand_" + side, (s * 0.155, -0.18, 0.015), (0.035, 0.04, 0.012), avocado)
    c.pair(legs)


def grumpy_duck(c):
    c.std((0, 0, 0.12), (0, 0, 0.16), (0, -0.04, 0.38), (0.15, 0, 0.2), (0.06, 0, 0.06))
    c.ell("Spine", "Body", (0, 0.02, 0.2), (0.16, 0.19, 0.14), CREAM)
    c.cone("Spine", "TailTuft", (0, 0.21, 0.25), 0.05, 0.0, 0.05, CREAM, rot=(math.radians(-60), 0, 0))
    c.ell("Head", "HeadBall", (0, -0.05, 0.42), (0.11, 0.1, 0.1), CREAM)
    c.ell("Head", "BeakTop", (0, -0.18, 0.41), (0.075, 0.07, 0.022), AMBER)
    c.joint("Jaw", "Head", (0, -0.12, 0.39))
    c.ell("Jaw", "BeakBottom", (0, -0.17, 0.385), (0.065, 0.06, 0.016), "#E9A515")
    c.animal_eyes((0, -0.13, 0.455), 0.05, 0.02, pupil_r=0.7)
    c.brows((0, -0.145, 0.485), 0.05, 0.04, GRAY, tilt=-0.01)
    c.ell("Head", "Beret", (0.015, 0.0, 0.52), (0.09, 0.085, 0.025), CORAL, rot=(0, math.radians(-14), 0))
    c.ell("Head", "BeretStalk", (0.03, 0.0, 0.548), (0.008, 0.008, 0.012), CORAL)

    def parts(s, side):
        c.ell("Arm_" + side, "Wing_" + side, (s * 0.15, 0.03, 0.21), (0.035, 0.12, 0.08), "#ECE5D6", rot=(math.radians(-12), 0, 0))
        c.cap("Leg_" + side, "Leg_" + side + "_Mesh", (s * 0.06, 0, 0.08), (s * 0.06, 0, 0.03), 0.012, AMBER)
        c.ell("Leg_" + side, "Foot_" + side, (s * 0.06, -0.04, 0.012), (0.045, 0.06, 0.012), AMBER)
    c.pair(parts)


def chonk_cat(c):
    c.std((0, 0, 0.1), (0, 0, 0.12), (0, -0.16, 0.2), (0.08, -0.15, 0.05), (0.12, 0.14, 0.05))
    c.ell("Spine", "Loaf", (0, 0.03, 0.15), (0.2, 0.25, 0.14), GRAY)
    c.ell("Spine", "Chest", (0, -0.12, 0.12), (0.12, 0.08, 0.09), "#4A4D55")
    c.ell("Head", "Head", (0, -0.16, 0.24), (0.14, 0.11, 0.11), GRAY)
    c.ell("Head", "Muzzle", (0, -0.255, 0.21), (0.055, 0.03, 0.035), "#D9D9DE")
    c.ell("Head", "Nose", (0, -0.282, 0.228), (0.014, 0.008, 0.01), PINK)

    def ear(s, side):
        c.joint("Ear_" + side, "Head", (s * 0.08, -0.16, 0.32))
        c.cone("Ear_" + side, "EarCone_" + side, (s * 0.085, -0.16, 0.35), 0.045, 0.004, 0.045, GRAY, rot=(0, s * math.radians(-15), 0))
        c.cone("Ear_" + side, "EarPink_" + side, (s * 0.085, -0.176, 0.345), 0.026, 0.002, 0.03, PINK, rot=(0, s * math.radians(-15), 0))
    c.pair(ear)
    c.animal_eyes((0, -0.245, 0.265), 0.055, 0.026, iris=INK, sclera=MINT, pupil_r=0.35)
    c.joint("Jaw", "Head", (0, -0.25, 0.19))
    c.ell("Jaw", "Mouth", (0, -0.276, 0.19), (0.02, 0.006, 0.006), INK)

    def paws(s, side):
        c.ell("Arm_" + side, "FrontPaw_" + side, (s * 0.08, -0.15, 0.03), (0.045, 0.055, 0.03), "#D9D9DE")
        c.ell("Leg_" + side, "BackPaw_" + side, (s * 0.14, 0.17, 0.03), (0.06, 0.06, 0.03), GRAY)
    c.pair(paws)
    c.joint("Tail", "Spine", (0.12, 0.24, 0.08))
    c.cap("Tail", "TailMesh", (0.12, 0.24, 0.06), (0.22, 0.05, 0.035), 0.03, GRAY)


def pigeon_chef(c):
    c.std((0, 0, 0.12), (0, 0, 0.16), (0, -0.06, 0.36), (0.13, 0, 0.22), (0.05, 0, 0.06))
    slate = "#6B7A8F"
    c.ell("Spine", "Body", (0, 0.02, 0.21), (0.14, 0.17, 0.15), slate)
    c.ell("Spine", "Chest", (0, -0.08, 0.23), (0.11, 0.08, 0.12), "#8794A6")
    c.torus("Spine", "NeckSheen", (0, -0.04, 0.32), 0.07, 0.022, "#5EC4B6")
    c.ell("Head", "HeadBall", (0, -0.06, 0.4), (0.08, 0.08, 0.08), slate)
    c.cone("Head", "BeakTop", (0, -0.15, 0.4), 0.018, 0.004, 0.025, "#3A3D44", rot=(math.radians(90), 0, 0))
    c.joint("Jaw", "Head", (0, -0.13, 0.392))
    c.cone("Jaw", "BeakBottom", (0, -0.145, 0.388), 0.012, 0.003, 0.018, "#3A3D44", rot=(math.radians(90), 0, 0))
    c.animal_eyes((0, -0.115, 0.42), 0.04, 0.018, iris=INK, sclera=AMBER, pupil_r=0.5)
    c.cyl("Head", "ToqueBand", (0.01, -0.04, 0.475), 0.06, 0.025, WHITE, rot=(0, math.radians(-12), 0), bevel=0.008)
    c.ell("Head", "ToquePuff", (0.025, -0.04, 0.53), (0.085, 0.075, 0.05), WHITE, rot=(0, math.radians(-12), 0))

    def parts(s, side):
        c.ell("Arm_" + side, "Wing_" + side, (s * 0.135, 0.03, 0.22), (0.035, 0.12, 0.09), "#56637A", rot=(math.radians(-10), 0, 0))
        c.cap("Leg_" + side, "Leg_" + side + "_Mesh", (s * 0.05, 0, 0.07), (s * 0.05, 0, 0.025), 0.01, CORAL)
        c.ell("Leg_" + side, "Foot_" + side, (s * 0.05, -0.03, 0.01), (0.03, 0.04, 0.01), CORAL)
    c.pair(parts)


def panic_hamster(c):
    c.std((0, 0, 0.08), (0, 0, 0.1), (0, -0.03, 0.18), (0.09, -0.08, 0.1), (0.06, 0.02, 0.03))
    tan = "#E0A060"
    c.ell("Spine", "Body", (0, 0, 0.12), (0.13, 0.12, 0.12), tan)
    c.ell("Spine", "Belly", (0, -0.07, 0.1), (0.09, 0.06, 0.08), CREAM)
    c.ell("Head", "Face", (0, -0.06, 0.2), (0.1, 0.085, 0.085), tan)

    def cheek(s, side):
        c.joint("Cheek_" + side, "Head", (s * 0.075, -0.09, 0.17))
        c.ell("Cheek_" + side, "CheekPuff_" + side, (s * 0.075, -0.09, 0.17), (0.05, 0.045, 0.045), "#F2C48E")
        c.joint("Ear_" + side, "Head", (s * 0.06, -0.03, 0.275))
        c.ell("Ear_" + side, "Ear_" + side + "_Mesh", (s * 0.065, -0.03, 0.28), (0.028, 0.012, 0.028), tan)
        c.ell("Ear_" + side, "EarPink_" + side, (s * 0.065, -0.042, 0.28), (0.018, 0.006, 0.018), PINK)
    c.pair(cheek)
    c.animal_eyes((0, -0.13, 0.225), 0.035, 0.016, pupil_r=0.85)
    c.ell("Head", "Nose", (0, -0.145, 0.195), (0.012, 0.008, 0.009), PINK)
    c.joint("Jaw", "Head", (0, -0.13, 0.17))
    c.box("Jaw", "Teeth", (0, -0.14, 0.165), (0.012, 0.004, 0.01), 0.003, WHITE)

    def paws(s, side):
        c.ell("Arm_" + side, "Paw_" + side, (s * 0.07, -0.1, 0.1), (0.022, 0.022, 0.03), PINK)
        c.ell("Leg_" + side, "Foot_" + side, (s * 0.06, -0.04, 0.012), (0.028, 0.04, 0.012), PINK)
    c.pair(paws)


def long_dachshund(c):
    c.std((0, 0.12, 0.12), (0, 0, 0.14), (0, -0.3, 0.2), (0.06, -0.18, 0.1), (0.06, 0.18, 0.1))
    brown = "#8B5A2B"
    c.cap("Spine", "LongBody", (0, -0.2, 0.15), (0, 0.2, 0.15), 0.075, brown)
    for i, y in enumerate((-0.1, 0.0, 0.1)):
        c.torus("Spine", "Fold_%d" % i, (0, y, 0.15), 0.07, 0.009, "#7A4C22", rot=(math.radians(90), 0, 0))
    c.ell("Head", "Head", (0, -0.3, 0.22), (0.065, 0.08, 0.065), brown)
    c.ell("Head", "Snout", (0, -0.39, 0.2), (0.035, 0.06, 0.03), "#9C6A38")
    c.ell("Head", "Nose", (0, -0.45, 0.205), (0.015, 0.01, 0.012), INK)
    c.animal_eyes((0, -0.355, 0.245), 0.035, 0.014, pupil_r=0.8)
    c.joint("Jaw", "Head", (0, -0.36, 0.18))
    c.ell("Jaw", "Chin", (0, -0.4, 0.178), (0.028, 0.045, 0.012), "#9C6A38")

    def parts(s, side):
        c.joint("Ear_" + side, "Head", (s * 0.055, -0.29, 0.25))
        c.ell("Ear_" + side, "Flop_" + side, (s * 0.075, -0.28, 0.19), (0.018, 0.04, 0.07), "#6B421E", rot=(0, s * math.radians(-12), 0))
        c.cap("Arm_" + side, "FrontLeg_" + side, (s * 0.05, -0.17, 0.1), (s * 0.05, -0.17, 0.03), 0.022, brown)
        c.ell("Arm_" + side, "FrontPaw_" + side, (s * 0.05, -0.185, 0.015), (0.028, 0.035, 0.015), "#6B421E")
        c.cap("Leg_" + side, "BackLeg_" + side, (s * 0.05, 0.17, 0.1), (s * 0.05, 0.17, 0.03), 0.022, brown)
        c.ell("Leg_" + side, "BackPaw_" + side, (s * 0.05, 0.155, 0.015), (0.028, 0.035, 0.015), "#6B421E")
    c.pair(parts)
    c.joint("Tail", "Spine", (0, 0.27, 0.17))
    c.cap("Tail", "TailMesh", (0, 0.27, 0.17), (0, 0.33, 0.24), 0.014, brown)


def grumpy_landlord(c):
    c.std((0, 0, 0.2), (0, 0, 0.24), (0, -0.02, 0.5), (0.15, 0, 0.42), (0.06, 0, 0.2))
    hide = "#A47551"
    c.ell("Spine", "Bean", (0, 0, 0.42), (0.16, 0.13, 0.24), hide)
    c.ell("Spine", "Vest", (0, -0.02, 0.36), (0.165, 0.135, 0.12), CORAL)
    c.ell("Head", "Brow", (0, -0.08, 0.56), (0.12, 0.06, 0.04), "#8E6342")

    def face(s, side):
        c.ell("Head", "Muzzle_" + side, (s * 0.045, -0.12, 0.49), (0.055, 0.04, 0.045), "#E4C9A8")
    c.pair(face)
    c.animal_eyes((0, -0.13, 0.55), 0.045, 0.016, pupil_r=0.8)
    c.brows((0, -0.15, 0.575), 0.045, 0.045, GRAY, tilt=0.008, thick=0.009)
    c.joint("Mustache", "Head", (0, -0.15, 0.5))
    c.pair(lambda s, side: c.ell("Mustache", "Whisk_" + side, (s * 0.05, -0.155, 0.5), (0.06, 0.02, 0.025), "#3B2A1E", rot=(0, s * math.radians(12), 0)))
    c.joint("Jaw", "Head", (0, -0.12, 0.46))

    def tusk(s, side):
        c.cone("Jaw", "Tusk_" + side, (s * 0.03, -0.135, 0.42), 0.012, 0.002, 0.04, WHITE)
    c.pair(tusk)

    def limbs(s, side):
        c.cap("Arm_" + side, "Noodle_" + side, (s * 0.15, 0, 0.42), (s * 0.21, -0.02, 0.28), 0.014, hide)
        c.ell("Arm_" + side, "Hand_" + side, (s * 0.215, -0.022, 0.27), (0.022, 0.022, 0.022), "#E4C9A8")
        c.cap("Leg_" + side, "NoodleLeg_" + side, (s * 0.06, 0, 0.2), (s * 0.06, 0, 0.04), 0.014, hide)
        c.box("Leg_" + side, "Shoe_" + side, (s * 0.06, -0.025, 0.02), (0.03, 0.05, 0.018), 0.015, INK)
    c.pair(limbs)


def cyber_penguin(c):
    c.std((0, 0, 0.1), (0, 0, 0.14), (0, -0.02, 0.38), (0.14, 0, 0.26), (0.05, 0, 0.05))
    c.ell("Spine", "Body", (0, 0, 0.22), (0.14, 0.12, 0.18), GRAY)
    c.ell("Spine", "Belly", (0, -0.06, 0.2), (0.1, 0.07, 0.14), WHITE)
    c.ell("Head", "HeadBall", (0, -0.01, 0.42), (0.1, 0.095, 0.09), GRAY)
    c.box("Head", "Visor", (0, -0.085, 0.435), (0.075, 0.015, 0.025), 0.014, DARK)
    c.screen_eyes((0, -0.1, 0.437), 0.035, 0.016, 0.01, BLUE)
    c.cone("Head", "BeakTop", (0, -0.115, 0.4), 0.018, 0.004, 0.025, AMBER, rot=(math.radians(90), 0, 0))
    c.joint("Jaw", "Head", (0, -0.1, 0.39))
    c.cone("Jaw", "BeakBottom", (0, -0.112, 0.388), 0.012, 0.003, 0.018, "#E9A515", rot=(math.radians(90), 0, 0))
    c.box("Spine", "Jetpack", (0, 0.13, 0.25), (0.08, 0.035, 0.08), 0.025, SILVER)
    c.joint("Flame", "Spine", (0, 0.14, 0.15))

    def side(s, sd):
        c.cyl("Spine", "Thruster_" + sd, (s * 0.04, 0.15, 0.17), 0.022, 0.03, GRAY, bevel=0.006)
        c.cone("Flame", "FlameCone_" + sd, (s * 0.04, 0.15, 0.115), 0.016, 0.0, 0.03, CORAL, rot=(math.radians(180), 0, 0), emit=3.0)
        c.ell("Arm_" + sd, "Flipper_" + sd, (s * 0.15, 0, 0.23), (0.025, 0.05, 0.1), GRAY, rot=(0, s * math.radians(-15), 0))
        c.ell("Arm_" + sd, "FlipperBand_" + sd, (s * 0.158, 0, 0.2), (0.022, 0.045, 0.014), SILVER)
        c.ell("Leg_" + sd, "Foot_" + sd, (s * 0.05, -0.05, 0.015), (0.035, 0.05, 0.014), AMBER)
    c.pair(side)


def mecha_bunny(c):
    c.std((0, 0, 0.1), (0, 0, 0.14), (0, -0.02, 0.3), (0.12, -0.04, 0.18), (0.06, 0, 0.05))
    c.ell("Spine", "Body", (0, 0.01, 0.17), (0.12, 0.11, 0.13), CREAM)
    c.ell("Head", "Head", (0, -0.03, 0.33), (0.1, 0.09, 0.085), CREAM)
    c.ell("Head", "Muzzle", (0, -0.105, 0.31), (0.04, 0.02, 0.03), WHITE)
    c.ell("Head", "Nose", (0, -0.122, 0.322), (0.012, 0.007, 0.009), PINK)
    c.animal_eyes((0, -0.095, 0.35), 0.042, 0.018, pupil_r=0.85)
    c.joint("Jaw", "Head", (0, -0.11, 0.29))
    c.box("Jaw", "Teeth", (0, -0.12, 0.288), (0.011, 0.004, 0.012), 0.003, WHITE)

    def ear(s, side):
        j = c.joint("Ear_" + side, "Head", (s * 0.045, -0.02, 0.41))
        for i in range(5):
            c.torus(j, "Coil_%s_%d" % (side, i), (s * (0.045 + i * 0.006), -0.02, 0.42 + i * 0.022), 0.02, 0.006, SILVER)
        c.ell(j, "EarTip_" + side, (s * 0.08, -0.02, 0.56), (0.025, 0.012, 0.05), CREAM)
        c.ell(j, "EarTipPink_" + side, (s * 0.08, -0.032, 0.56), (0.014, 0.005, 0.035), PINK)
    c.pair(ear)
    c.box("Spine", "Battery", (0, 0.11, 0.2), (0.065, 0.03, 0.08), 0.02, MINT)
    c.cyl("Spine", "Terminal", (0, 0.11, 0.29), 0.018, 0.012, SILVER, bevel=0.005)
    for i in range(3):
        c.box("Spine", "Charge_%d" % i, (0, 0.142, 0.16 + i * 0.03), (0.035, 0.003, 0.009), 0.003, MINT, emit=2.5)

    def limbs(s, side):
        c.ell("Arm_" + side, "Paw_" + side, (s * 0.11, -0.07, 0.15), (0.025, 0.025, 0.035), CREAM)
        c.ell("Leg_" + side, "Foot_" + side, (s * 0.06, -0.05, 0.02), (0.035, 0.07, 0.02), CREAM)
    c.pair(limbs)


def bot_octopus(c):
    c.std((0, 0, 0.12), (0, 0, 0.16), (0, 0, 0.28), (0.1, -0.05, 0.12), (0.06, 0.05, 0.08))
    c.ell("Head", "Mantle", (0, 0.02, 0.3), (0.15, 0.15, 0.17), CORAL)
    c.ell("Head", "Spots", (0.06, 0.06, 0.4), (0.03, 0.02, 0.03), "#E84A42")

    def goggle(s, side):
        c.torus("Head", "Goggle_" + side, (s * 0.06, -0.12, 0.29), 0.035, 0.009, SILVER, rot=(math.radians(90), 0, 0))
    c.pair(goggle)
    c.animal_eyes((0, -0.115, 0.29), 0.06, 0.03, pupil_r=0.55)
    c.screen_mouth((0, -0.142, 0.22), 0.02, 0.006, INK)
    for i in range(6):
        a = math.radians(30 + i * 60)
        x0, y0 = math.sin(a) * 0.09, -math.cos(a) * 0.09
        x1, y1 = math.sin(a) * 0.2, -math.cos(a) * 0.2
        j = c.joint("Tentacle_%d" % i, "Hips", (x0, y0, 0.14))
        c.cap(j, "Arm_%d" % i, (x0, y0, 0.14), ((x0 + x1) / 2, (y0 + y1) / 2, 0.07), 0.02, SILVER)
        c.cap(j, "Forearm_%d" % i, ((x0 + x1) / 2, (y0 + y1) / 2, 0.07), (x1, y1, 0.03), 0.017, SILVER)
        c.ell(j, "Joint_%d" % i, ((x0 + x1) / 2, (y0 + y1) / 2, 0.07), (0.024, 0.024, 0.024), GRAY)
        c.cone(j, "ClawA_%d" % i, (x1 + math.cos(a) * 0.012, y1 + math.sin(a) * 0.012, 0.015), 0.009, 0.002, 0.018, GRAY)
        c.cone(j, "ClawB_%d" % i, (x1 - math.cos(a) * 0.012, y1 - math.sin(a) * 0.012, 0.015), 0.009, 0.002, 0.018, GRAY)


def turbo_turtle(c):
    c.std((0, 0, 0.08), (0, 0, 0.1), (0, -0.25, 0.12), (0.13, -0.12, 0.05), (0.13, 0.12, 0.05))
    skin = "#8FBF6A"
    c.ell("Spine", "Shell", (0, 0, 0.13), (0.2, 0.24, 0.11), SILVER)
    c.torus("Spine", "ShellRim", (0, 0, 0.08), 0.2, 0.018, BLUE, rot=None)
    for i, (x, y) in enumerate(((0, 0), (0.08, 0.08), (-0.08, 0.08), (0.08, -0.08), (-0.08, -0.08))):
        c.ell("Spine", "Plate_%d" % i, (x, y, 0.22 - (0.025 if i else 0)), (0.05, 0.05, 0.018), "#C9CED6")
    c.ell("Spine", "Underbelly", (0, 0, 0.06), (0.17, 0.21, 0.04), "#D9E4B0")
    c.cap("Head", "Neck", (0, -0.17, 0.09), (0, -0.24, 0.12), 0.035, skin)
    c.ell("Head", "Head", (0, -0.27, 0.13), (0.06, 0.07, 0.05), skin)
    c.animal_eyes((0, -0.315, 0.15), 0.03, 0.014, pupil_r=0.8)

    def lid(s, side):
        c.ell("Eye_" + side, "SleepyLid_" + side, (s * 0.03, -0.318, 0.157), (0.016, 0.012, 0.009), skin)
    c.pair(lid)
    c.joint("Jaw", "Head", (0, -0.31, 0.115))
    c.ell("Jaw", "Smile", (0, -0.33, 0.115), (0.025, 0.006, 0.004), INK)

    def legs(s, side):
        c.ell("Arm_" + side, "FrontFlipper_" + side, (s * 0.15, -0.14, 0.04), (0.05, 0.04, 0.025), skin)
        c.ell("Leg_" + side, "BackFlipper_" + side, (s * 0.15, 0.15, 0.04), (0.045, 0.04, 0.025), skin)
    c.pair(legs)
    for i, (x, y) in enumerate(((0.2, -0.1), (-0.2, -0.1), (0.2, 0.12), (-0.2, 0.12))):
        j = c.joint("Wheel_%d" % i, "Spine", (x, y, 0.045))
        c.torus(j, "Tyre_%d" % i, (x, y, 0.045), 0.03, 0.014, GRAY, rot=(0, math.radians(90), 0))
        c.cyl(j, "Hub_%d" % i, (x, y, 0.045), 0.02, 0.01, AMBER, rot=(0, math.radians(90), 0), bevel=0.004)
    c.joint("Tail", "Spine", (0, 0.23, 0.07))
    c.cone("Tail", "TailCone", (0, 0.26, 0.07), 0.02, 0.003, 0.03, skin, rot=(math.radians(-90), 0, 0))


def owl_drone(c):
    c.std((0, 0, 0.12), (0, 0, 0.14), (0, -0.02, 0.24), (0.15, 0, 0.2), (0.05, -0.02, 0.06))
    feather = "#B07A4A"
    c.ell("Spine", "Body", (0, 0, 0.22), (0.15, 0.14, 0.15), feather)
    c.ell("Spine", "Breast", (0, -0.08, 0.18), (0.1, 0.07, 0.1), "#D9B48A")
    c.ell("Head", "FaceDisc", (0, -0.1, 0.26), (0.12, 0.04, 0.09), CREAM)

    def lens(s, side):
        j = c.joint("Eye_" + side, "Head", (s * 0.055, -0.13, 0.27))
        c.cyl(j, "Barrel_" + side, (s * 0.055, -0.13, 0.27), 0.04, 0.025, SILVER, rot=(math.radians(90), 0, 0), bevel=0.008)
        c.cyl(j, "Glass_" + side, (s * 0.055, -0.156, 0.27), 0.03, 0.004, DARK, rot=(math.radians(90), 0, 0), bevel=0.003)
        c.ell(j, "Iris_" + side, (s * 0.055, -0.161, 0.27), (0.012, 0.004, 0.012), BLUE, emit=3.0)
        c.joint("Ear_" + side, "Head", (s * 0.09, -0.02, 0.35))
        c.cone("Ear_" + side, "Tuft_" + side, (s * 0.095, -0.02, 0.38), 0.03, 0.003, 0.035, feather, rot=(0, s * math.radians(-20), 0))
    c.pair(lens)
    c.cone("Head", "Beak", (0, -0.15, 0.22), 0.016, 0.0, 0.022, AMBER, rot=(math.radians(180), 0, 0))
    c.joint("Jaw", "Head", (0, -0.14, 0.205))
    c.ell("Jaw", "BeakTip", (0, -0.145, 0.198), (0.008, 0.006, 0.006), "#E9A515")
    for i, (x, y) in enumerate(((0.16, 0.12), (-0.16, 0.12), (0.16, -0.12), (-0.16, -0.12))):
        c.cap("Spine", "Strut_%d" % i, (x * 0.4, y * 0.4, 0.33), (x, y, 0.36), 0.008, SILVER)
        j = c.joint("Rotor_%d" % i, "Spine", (x, y, 0.37))
        c.cyl(j, "Motor_%d" % i, (x, y, 0.365), 0.014, 0.012, GRAY, bevel=0.004)
        c.box(j, "Blade_%d" % i, (x, y, 0.38), (0.07, 0.008, 0.003), 0.003, GRAY)

    def talon(s, side):
        c.ell("Leg_" + side, "Talon_" + side, (s * 0.05, -0.04, 0.03), (0.025, 0.035, 0.012), AMBER)
        c.cap("Leg_" + side, "Shin_" + side, (s * 0.05, -0.02, 0.08), (s * 0.05, -0.035, 0.035), 0.01, AMBER)
        c.ell("Arm_" + side, "Wing_" + side, (s * 0.15, 0.02, 0.21), (0.03, 0.09, 0.09), "#94633A")
    c.pair(talon)


def dino_mech(c):
    c.std((0, 0.04, 0.16), (0, 0, 0.2), (0, -0.16, 0.36), (0.07, -0.1, 0.26), (0.08, 0.06, 0.12))
    green = "#4FBF5C"
    c.ell("Spine", "Body", (0, 0.02, 0.24), (0.12, 0.16, 0.13), green, rot=(math.radians(-15), 0, 0))
    c.ell("Spine", "LEDBelly", (0, -0.09, 0.2), (0.07, 0.03, 0.08), AMBER, emit=2.0)
    c.box("Head", "Skull", (0, -0.18, 0.39), (0.08, 0.1, 0.07), 0.05, green)
    c.animal_eyes((0, -0.21, 0.43), 0.06, 0.018, pupil_r=0.8)
    c.brows((0, -0.225, 0.455), 0.06, 0.035, "#2E7D3A", tilt=-0.006)
    c.joint("Jaw", "Head", (0, -0.13, 0.33))
    c.box("Jaw", "LowerJaw", (0, -0.2, 0.325), (0.07, 0.085, 0.022), 0.02, "#6FD07A")
    for i in range(4):
        x = -0.045 + i * 0.03
        c.cone("Head", "Tooth_%d" % i, (x, -0.27, 0.338), 0.008, 0.0, 0.012, WHITE, rot=(math.radians(180), 0, 0))

    def limbs(s, side):
        c.cap("Arm_" + side, "Clamp_" + side, (s * 0.07, -0.1, 0.26), (s * 0.08, -0.15, 0.22), 0.014, SILVER)
        c.cone("Arm_" + side, "PinchA_" + side, (s * 0.085, -0.17, 0.215), 0.008, 0.002, 0.015, GRAY, rot=(math.radians(100), 0, 0))
        c.cone("Arm_" + side, "PinchB_" + side, (s * 0.07, -0.17, 0.215), 0.008, 0.002, 0.015, GRAY, rot=(math.radians(100), 0, 0))
        c.ell("Leg_" + side, "Thigh_" + side, (s * 0.08, 0.06, 0.11), (0.05, 0.07, 0.07), green)
        c.ell("Leg_" + side, "Foot_" + side, (s * 0.08, 0.0, 0.02), (0.04, 0.07, 0.02), "#2E7D3A")
    c.pair(limbs)
    c.joint("Tail", "Spine", (0, 0.16, 0.22))
    c.cone("Tail", "TailCone", (0, 0.3, 0.16), 0.06, 0.012, 0.13, green, rot=(math.radians(-70), 0, 0))


ROSTER = [
    ("robo_bear", robo_bear), ("robo_fish", robo_fish), ("toaster_bot", toaster_bot), ("coffee_bot", coffee_bot),
    ("roomba_dog", roomba_dog), ("tv_head", tv_head), ("gumball_bot", gumball_bot), ("chaotic_frog", chaotic_frog),
    ("grumpy_duck", grumpy_duck), ("chonk_cat", chonk_cat), ("pigeon_chef", pigeon_chef), ("panic_hamster", panic_hamster),
    ("long_dachshund", long_dachshund), ("grumpy_landlord", grumpy_landlord), ("cyber_penguin", cyber_penguin),
    ("mecha_bunny", mecha_bunny), ("bot_octopus", bot_octopus), ("turbo_turtle", turbo_turtle), ("owl_drone", owl_drone),
    ("dino_mech", dino_mech),
]


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = argv[0] if argv else os.path.join(os.path.dirname(__file__), "..", "godot", "assets", "models", "characters")
    only = set(argv[1:])
    for cid, build in ROSTER:
        if only and cid not in only:
            continue
        c = Char(cid)
        build(c)
        c.export(out_dir)


if __name__ == "__main__":
    main()

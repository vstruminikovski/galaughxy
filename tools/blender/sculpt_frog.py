"""Sculpts 'Bog', the original pond frog protagonist, and exports public/models/frog.glb.

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/sculpt_frog.py
Each articulated part is its own object with its origin at the joint pivot, so the engine
animates it deterministically without a skeleton:
  Frog_Body, Frog_Jaw, Frog_Mouth, Frog_Eye_L/R, Frog_Lid_L/R, Frog_Arm_L/R, Frog_Leg_L/R
"""
import os
import sys

sys.path.append(os.path.dirname(__file__))
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
from common import (activate, export_glb, fbm, link, metablob, mix, paint, sculpt, set_material,  # noqa: E402
                    set_origin, smoothstep, srgb, tri_count, vc_material)

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../public/models/frog.glb'))

reset_ok = bpy.ops.wm.read_factory_settings(use_empty=True)

TOP = srgb('#6f9a35')
SIDE = srgb('#557f27')
BELLY = srgb('#e3dba4')
SPOT = srgb('#2f4a17')
WART = srgb('#8fb24a')
LIP = srgb('#c9c27f')


def skin(p, n):
    spots = fbm(p * 11.0)
    warts = fbm(p * 38.0 + Vector((3, 1, 2)))
    belly = smoothstep(-0.05, -0.55, n.z) * 0.9 + smoothstep(0.08, 0.02, p.z) * 0.3
    mottle = fbm(p * 4.0 + Vector((7, 2, 5)))
    c = mix(SIDE, TOP, smoothstep(0.1, 0.9, n.z))
    c = mix(c, srgb('#8a9a2c'), smoothstep(0.0, 0.35, mottle) * 0.5)
    c = mix(c, SPOT, smoothstep(0.06, 0.16, spots) * (1 - belly))
    c = mix(c, WART, smoothstep(0.28, 0.4, warts) * 0.6 * (1 - belly))
    c = mix(c, BELLY, belly)
    return c


SKIN_PASSES = (
    ('CLOUDS', 0.035, 0.007, {}),
    ('VORONOI', 0.018, 0.0035, {}),
)

mat_skin = vc_material('FrogSkin', roughness=0.38)
parts = []


def part(name, elements, pivot, voxel=0.0055, passes=SKIN_PASSES, color=skin, mat=mat_skin, dec=0.2, smooth=2):
    o = metablob(name, elements, resolution=0.008)
    sculpt(o, voxel=voxel, passes=passes, smooth=smooth, decimate=dec)
    paint(o, color)
    set_material(o, mat)
    set_origin(o, pivot)
    parts.append(o)
    return o


# ── body + head (one sculpt so the neck blends) ──
part('Frog_Body', [
    {'co': (0, 0.05, 0.15), 'r': 0.2, 'size': (0.85, 1.1, 0.68), 'rot': (-0.4, 0, 0)},
    {'co': (0, -0.12, 0.24), 'r': 0.16, 'size': (1.02, 0.78, 0.52)},
    {'co': (0.085, -0.15, 0.3), 'r': 0.06},   # eye sockets
    {'co': (-0.085, -0.15, 0.3), 'r': 0.06},
    {'co': (0, -0.24, 0.23), 'r': 0.07, 'size': (1.2, 0.8, 0.6)},  # snout
    {'co': (0, -0.17, 0.19), 'r': 0.13, 'size': (1.1, 0.8, 0.25), 'neg': True},  # mouth cavity carve
], pivot=(0, 0, 0))

# ── lower jaw (hinged at the back of the mouth) ──
part('Frog_Jaw', [
    {'co': (0, -0.16, 0.195), 'r': 0.15, 'size': (1.0, 0.78, 0.22)},
    {'co': (0, -0.25, 0.2), 'r': 0.06, 'size': (1.2, 0.7, 0.4)},
], pivot=(0, -0.05, 0.215), color=lambda p, n: mix(skin(p, n), LIP, smoothstep(0.3, 0.9, n.z) * 0.6))

# ── mouth interior (visible when the jaw drops) ──
mouth = part('Frog_Mouth', [
    {'co': (0, -0.15, 0.2), 'r': 0.12, 'size': (0.95, 0.75, 0.28)},
], pivot=(0, -0.05, 0.215), passes=(), color=lambda p, n: mix(srgb('#5a1a22'), srgb('#d46a7a'), smoothstep(0.3, 0.9, n.z) * 0.5),
    mat=vc_material('FrogMouth', roughness=0.25), dec=0.5, smooth=0)

# ── eyes: glossy golden iris with a horizontal pupil ──
mat_eye = vc_material('FrogEye', roughness=0.05)
for side, sx in (('L', 1), ('R', -1)):
    c = Vector((0.085 * sx, -0.16, 0.335))
    look = Vector((0.35 * sx, -0.9, 0.25)).normalized()

    def eye_col(p, n, c=c, look=look):
        d = n.dot(look)
        vert = abs((n - look * d).z)
        if d > 0.9 and vert < 0.11:
            return srgb('#050505')
        if d > 0.55:
            return mix(srgb('#7a4d0a'), srgb('#e8b52a'), fbm((p - c) * 90) * 0.8 + 0.5)
        return srgb('#2a2e10')

    part(f'Frog_Eye_{side}', [{'co': tuple(c), 'r': 0.046}], pivot=tuple(c), voxel=0.003, passes=(), color=eye_col,
         mat=mat_eye, dec=0.4, smooth=1)

    # eyelid: upper hemisphere shell; rotating +X closes it
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=28, v_segments=16, radius=0.0505)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.004], context='VERTS')
    me = bpy.data.meshes.new(f'Frog_Lid_{side}')
    bm.to_mesh(me)
    lid = link(bpy.data.objects.new(f'Frog_Lid_{side}', me))
    lid.location = c
    activate(lid)
    bpy.ops.object.transform_apply(location=True)
    solid = lid.modifiers.new('s', 'SOLIDIFY')
    solid.thickness = 0.006
    from common import apply_modifiers
    apply_modifiers(lid)
    for p in lid.data.polygons:
        p.use_smooth = True
    paint(lid, lambda p, n: mix(skin(p, n), srgb('#9fbf5a'), 0.25))
    set_material(lid, mat_skin)
    set_origin(lid, tuple(c))
    parts.append(lid)

    # ── front leg (shoulder pivot) ──
    part(f'Frog_Arm_{side}', [
        {'co': (0.13 * sx, -0.12, 0.11), 'r': 0.05, 'size': (0.7, 0.7, 1.7)},
        {'co': (0.14 * sx, -0.17, 0.018), 'r': 0.05, 'size': (1.0, 1.2, 0.3)},
        {'co': (0.17 * sx, -0.22, 0.012), 'r': 0.018},
        {'co': (0.13 * sx, -0.225, 0.012), 'r': 0.018},
        {'co': (0.1 * sx, -0.2, 0.012), 'r': 0.017},
    ], pivot=(0.11 * sx, -0.09, 0.19))

    # ── hind leg folded under the body (hip pivot) ──
    part(f'Frog_Leg_{side}', [
        {'co': (0.16 * sx, 0.12, 0.1), 'r': 0.1, 'size': (0.7, 1.25, 0.62), 'rot': (0.3, 0, 0)},
        {'co': (0.19 * sx, 0.0, 0.05), 'r': 0.07, 'size': (0.6, 1.35, 0.5)},
        {'co': (0.21 * sx, -0.08, 0.016), 'r': 0.075, 'size': (1.0, 1.3, 0.22)},
        {'co': (0.25 * sx, -0.15, 0.012), 'r': 0.02},
        {'co': (0.2 * sx, -0.165, 0.012), 'r': 0.02},
        {'co': (0.16 * sx, -0.15, 0.012), 'r': 0.019},
    ], pivot=(0.13 * sx, 0.14, 0.13))

print(f'[frog] parts={len(parts)} tris={tri_count(parts)}')
os.makedirs(os.path.dirname(OUT), exist_ok=True)
export_glb(OUT)
print('[frog] wrote', OUT)

"""Sculpts the 'Pond Life' habitat and exports public/models/pond.glb + pond_height.json.

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/sculpt_pond.py
Area: Blender x -6..6, y -5..5 (camera sits at -Y). Water rest level WL.
"""
import json
import math
import os
import random
import sys

sys.path.append(os.path.dirname(__file__))
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
from common import (fbm, link, metablob, mix, paint, sculpt, set_material, smoothstep, srgb,  # noqa: E402
                    tri_count, vc_material)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../..'))
OUT = os.path.join(ROOT, 'public/models/pond.glb')
OUT_H = os.path.join(ROOT, 'public/models/pond_height.json')
WL = -0.12
X0, X1, Y0, Y1 = -6.0, 6.0, -5.0, 5.0
random.seed(7)
bpy.ops.wm.read_factory_settings(use_empty=True)
objs = []


def height(x, y):
    p = Vector((x, y, 0.0))
    h = fbm(p * 0.22) * 0.38 + fbm(p * 0.9 + Vector((4, 4, 0))) * 0.06
    h += smoothstep(1.8, 5.0, y) * 1.5                 # back hill
    h += smoothstep(-3.0, -6.0, x) * 0.45               # left bank
    h += smoothstep(3.5, 6.0, x) * 0.35                 # right bank
    d = math.sqrt(((x - 0.6) / 3.1) ** 2 + ((y - 1.5) / 1.7) ** 2)
    h -= 0.62 * smoothstep(1.05, 0.25, d)               # pond basin
    h *= 1.0 - 0.75 * smoothstep(1.4, 0.0, math.hypot(x + 0.3, y + 1.2))  # flat 'stage' for the actors
    return h


# ───────────────────────── terrain ─────────────────────────
bm = bmesh.new()
NX, NY = 150, 125
bmesh.ops.create_grid(bm, x_segments=NX, y_segments=NY, size=1.0)
for v in bm.verts:
    x = (v.co.x + 1) / 2 * (X1 - X0) + X0
    y = (v.co.y + 1) / 2 * (Y1 - Y0) + Y0
    v.co = Vector((x, y, height(x, y)))
me = bpy.data.meshes.new('Terrain')
bm.to_mesh(me)
terrain = link(bpy.data.objects.new('Terrain', me))
for p in terrain.data.polygons:
    p.use_smooth = True

MUD_DEEP, MUD, SAND = srgb('#2e2618'), srgb('#4d3d27'), srgb('#7a6744')
GRASS_A, GRASS_B, GRASS_C = srgb('#3f5f22'), srgb('#6b8834'), srgb('#8f9145')
MOSS, DIRT = srgb('#2f4a1c'), srgb('#6a5236')


def ground_col(p, n):
    z = p.z
    if z < WL - 0.02:
        return mix(MUD, MUD_DEEP, smoothstep(WL, WL - 0.4, z))
    shore = smoothstep(WL + 0.12, WL, z)
    g = mix(GRASS_A, GRASS_B, smoothstep(-0.2, 0.3, fbm(p * 0.8)))
    g = mix(g, GRASS_C, smoothstep(0.15, 0.4, fbm(p * 2.3 + Vector((9, 1, 0)))) * 0.6)
    g = mix(g, MOSS, smoothstep(0.1, 0.35, fbm(p * 1.6 + Vector((2, 7, 0)))) * 0.5)
    g = mix(g, DIRT, smoothstep(0.25, 0.45, fbm(p * 0.6 + Vector((5, 3, 0)))) * 0.8)
    g = mix(g, DIRT, smoothstep(0.75, 0.5, n.z))  # steep slopes go earthy
    return mix(g, mix(SAND, MUD, 0.4), shore)


paint(terrain, ground_col)
set_material(terrain, vc_material('Ground', roughness=0.95))
objs.append(terrain)

# ───────────────────────── rocks ─────────────────────────
mat_rock = vc_material('Rock', roughness=0.85)
ROCK, ROCK_D, LICHEN = srgb('#80796c'), srgb('#4d4942'), srgb('#b3ad72')


def rock_col(p, n):
    c = mix(ROCK_D, ROCK, smoothstep(-0.3, 0.4, fbm(p * 3.0)))
    c = mix(c, LICHEN, smoothstep(0.32, 0.42, fbm(p * 9.0 + Vector((1, 9, 3)))) * 0.7)
    moss = smoothstep(0.45, 0.85, n.z) * smoothstep(-0.1, 0.25, fbm(p * 2.0 + Vector((5, 5, 5))))
    return mix(c, MOSS, moss)


def rock(name, x, y, s, squash=0.65, sink=0.35):
    z = height(x, y)
    els = [{'co': (x, y, z + s * (squash - sink)), 'r': s, 'size': (1.0, 0.85, squash), 'rot': (0, 0, random.random() * 3)}]
    for _ in range(2):
        els.append({'co': (x + random.uniform(-.5, .5) * s, y + random.uniform(-.5, .5) * s, z + s * (squash - sink) * 0.7),
                    'r': s * random.uniform(0.5, 0.75), 'size': (1, 1, squash)})
    o = metablob(name, els)
    sculpt(o, voxel=s * 0.045, passes=(
        ('VORONOI', 0.35 * s, 0.18 * s, {}),
        ('CLOUDS', 0.25 * s, 0.08 * s, {}),
        ('VORONOI', 0.08 * s, 0.025 * s, {}),
    ), smooth=1, decimate=0.18)
    paint(o, rock_col)
    set_material(o, mat_rock)
    objs.append(o)


for i, (x, y, s) in enumerate([(-2.6, 0.6, 0.45), (-2.0, 1.2, 0.25), (3.4, 0.9, 0.55), (3.9, 1.7, 0.3), (2.2, 3.0, 0.4),
                               (-1.0, 3.1, 0.6), (4.6, -1.5, 0.35), (-4.4, -1.0, 0.5), (1.5, -3.2, 0.2), (-3.2, -3.0, 0.25),
                               (-0.6, 2.95, 0.2), (0.4, 3.2, 0.28)]):
    rock(f'Rock_{i}', x, y, s)

# ───────────────────────── fallen log ─────────────────────────
BARK, BARK_D, WOOD = srgb('#5b4431'), srgb('#2d2118'), srgb('#c09a6a')


def bark_col(p, n):
    groove = fbm(Vector((p.x * 2.0, p.y * 28.0, p.z * 28.0)))
    c = mix(BARK, BARK_D, smoothstep(0.0, 0.25, groove))
    c = mix(c, WOOD, smoothstep(0.85, 0.97, abs(n.x)) * 0.8)  # cut ends
    return mix(c, MOSS, smoothstep(0.35, 0.8, n.z) * smoothstep(-0.15, 0.2, fbm(p * 2.5)))


lx, ly = -1.9, -0.2
lz = height(lx, ly) + 0.16
els = [{'co': (lx + i * 0.32, ly + i * 0.08, lz + 0.02 * math.sin(i)), 'r': 0.22 - abs(i) * 0.008, 'size': (1.3, 1, 1)}
       for i in range(-4, 5)]
els.append({'co': (lx + 0.5, ly + 0.25, lz + 0.18), 'r': 0.08, 'size': (0.8, 0.8, 2.2), 'rot': (0.5, 0.3, 0)})  # branch stub
log = metablob('Log', els)
sculpt(log, voxel=0.018, passes=(('CLOUDS', 0.04, 0.03, {}), ('VORONOI', 0.12, 0.03, {})), smooth=1, decimate=0.2)
paint(log, bark_col)
set_material(log, vc_material('Bark', roughness=0.9))
objs.append(log)

# ───────────────────────── trees + bushes ─────────────────────────
LEAF_A, LEAF_B, LEAF_D = srgb('#3e6b23'), srgb('#7a9a3a'), srgb('#1d3312')


def leaf_col(p, n):
    c = mix(LEAF_A, LEAF_B, smoothstep(-0.2, 0.4, fbm(p * 1.4)) * smoothstep(-0.4, 0.8, n.z))
    return mix(c, LEAF_D, smoothstep(0.0, -0.8, n.z) * 0.8)


mat_leaf = vc_material('Foliage', roughness=0.8)
mat_bark = vc_material('Bark', roughness=0.9)


def tree(name, x, y, hgt):
    z = height(x, y)
    trunk = [{'co': (x, y, z + t * hgt * 0.7), 'r': 0.22 * (1 - t * 0.55), 'size': (1, 1, 1.6)} for t in [i / 8 for i in range(9)]]
    trunk += [{'co': (x + math.cos(a) * 0.22, y + math.sin(a) * 0.22, z + 0.05), 'r': 0.12, 'size': (1.6, 0.8, 0.6),
               'rot': (0, 0, a)} for a in [k * 2.1 for k in range(3)]]  # root flare
    t = metablob(name + '_Trunk', trunk)
    sculpt(t, voxel=0.03, passes=(('CLOUDS', 0.05, 0.03, {}),), smooth=1, decimate=0.2)
    paint(t, bark_col)
    set_material(t, mat_bark)
    objs.append(t)
    crown = []
    for _ in range(12):
        a, r = random.random() * 6.28, random.uniform(0, 1.0)
        crown.append({'co': (x + math.cos(a) * r, y + math.sin(a) * r, z + hgt * random.uniform(0.7, 1.0)),
                      'r': random.uniform(0.55, 0.9), 'size': (1, 1, 0.75)})
    c = metablob(name + '_Crown', crown)
    sculpt(c, voxel=0.06, passes=(('CLOUDS', 0.35, 0.35, {}), ('CLOUDS', 0.1, 0.12, {})), smooth=1, decimate=0.15)
    paint(c, leaf_col)
    set_material(c, mat_leaf)
    objs.append(c)


for i, (x, y, hgt) in enumerate([(-4.6, 3.6, 4.2), (-1.8, 4.4, 5.0), (1.2, 4.6, 4.4), (3.9, 4.0, 5.2), (5.4, 2.0, 3.6),
                                 (-5.4, 0.6, 3.4)]):
    tree(f'Tree_{i}', x, y, hgt)


def bush(name, x, y, s):
    z = height(x, y)
    els = [{'co': (x + random.uniform(-.6, .6) * s, y + random.uniform(-.6, .6) * s, z + s * random.uniform(0.2, 0.6)),
            'r': s * random.uniform(0.45, 0.7), 'size': (1, 1, 0.8)} for _ in range(6)]
    o = metablob(name, els)
    sculpt(o, voxel=s * 0.06, passes=(('CLOUDS', 0.18 * s, 0.22 * s, {}),), smooth=1, decimate=0.2)
    paint(o, leaf_col)
    set_material(o, mat_leaf)
    objs.append(o)


for i, (x, y, s) in enumerate([(-3.6, 2.2, 0.6), (-0.2, 2.9, 0.45), (2.9, 2.6, 0.55), (4.8, 0.2, 0.6), (-4.9, -2.2, 0.55),
                               (4.2, -3.2, 0.5)]):
    bush(f'Bush_{i}', x, y, s)

# ───────────────────────── mushrooms ─────────────────────────
for i, (x, y) in enumerate([(-1.3, -0.45), (-1.15, -0.5), (-2.5, -0.55)]):
    z = height(x, y)
    s = 0.05 + i * 0.012
    m = metablob(f'Mushroom_{i}', [
        {'co': (x, y, z + s * 1.2), 'r': s * 0.35, 'size': (1, 1, 3.4)},
        {'co': (x, y, z + s * 2.4), 'r': s, 'size': (1, 1, 0.55)},
    ])
    sculpt(m, voxel=s * 0.12, smooth=1, decimate=0.3)
    paint(m, lambda p, n, s=s, z=z: srgb('#efe3c8') if p.z < z + s * 2.1 else mix(srgb('#b8452a'), srgb('#f2e6c9'),
                                                                                  smoothstep(0.3, 0.42, fbm(p * 160))))
    set_material(m, vc_material('Mushroom', roughness=0.5))
    objs.append(m)

# ───────────────────────── lily pads ─────────────────────────
pads = bmesh.new()
for i in range(14):
    a, r = random.random() * 6.28, random.uniform(0.2, 1.0)
    cx, cy = 0.6 + math.cos(a) * 2.4 * r, 1.5 + math.sin(a) * 1.3 * r
    rad = random.uniform(0.12, 0.22)
    rot = random.random() * 6.28
    verts = [pads.verts.new((cx, cy, WL + 0.006))]
    steps = 20
    for k in range(steps + 1):
        t = rot + 0.35 + k / steps * (6.28 - 0.7)  # notch
        verts.append(pads.verts.new((cx + math.cos(t) * rad, cy + math.sin(t) * rad, WL + 0.006 + 0.004 * math.sin(k))))
    for k in range(1, steps + 1):
        pads.faces.new((verts[0], verts[k], verts[k + 1]))
pme = bpy.data.meshes.new('LilyPads')
pads.to_mesh(pme)
pad_obj = link(bpy.data.objects.new('LilyPads', pme))
paint(pad_obj, lambda p, n: mix(srgb('#3c6e2a'), srgb('#7aa344'), smoothstep(-0.3, 0.4, fbm(p * 6))))
set_material(pad_obj, vc_material('LilyPad', roughness=0.35))
objs.append(pad_obj)

for i, (x, y) in enumerate([(-0.4, 1.0), (1.9, 2.0)]):
    fl = metablob(f'LilyFlower_{i}', [{'co': (x + math.cos(a) * 0.04, y + math.sin(a) * 0.04, WL + 0.04), 'r': 0.04,
                                       'size': (1.3, 0.6, 0.7), 'rot': (0, 0.6, a)} for a in [k * 1.05 for k in range(6)]]
                  + [{'co': (x, y, WL + 0.05), 'r': 0.022}])
    sculpt(fl, voxel=0.006, smooth=1, decimate=0.35)
    paint(fl, lambda p, n, x=x, y=y: srgb('#ffd23a') if math.hypot(p.x - x, p.y - y) < 0.022 else
          mix(srgb('#f7c6d6'), srgb('#e0608a'), smoothstep(0.03, 0.08, math.hypot(p.x - x, p.y - y))))
    set_material(fl, vc_material('Flower', roughness=0.5))
    objs.append(fl)

# ───────────────────────── grass + reeds (one wind-animated mesh, uv.y = 0 base → 1 tip) ─────────────────────────
gb = bmesh.new()
uvl = gb.loops.layers.uv.new('UVMap')
col_base, col_tip, reed_tip = srgb('#2b4417'), srgb('#a3ad52'), srgb('#9b9a55')
blade_cols = []
reed_tips = []


def blade(x, y, h, w, lean, reed=False):
    z = height(x, y) - 0.01
    a = random.random() * 6.28
    dx, dy = math.cos(a) * w, math.sin(a) * w
    lx_, ly_ = math.cos(a + 1.57) * lean, math.sin(a + 1.57) * lean
    v0 = gb.verts.new((x - dx, y - dy, z))
    v1 = gb.verts.new((x + dx, y + dy, z))
    v2 = gb.verts.new((x + lx_ * 0.4 + dx * 0.5, y + ly_ * 0.4 + dy * 0.5, z + h * 0.55))
    v3 = gb.verts.new((x + lx_ * 0.4 - dx * 0.5, y + ly_ * 0.4 - dy * 0.5, z + h * 0.55))
    v4 = gb.verts.new((x + lx_, y + ly_, z + h))
    f1 = gb.faces.new((v0, v1, v2, v3))
    f2 = gb.faces.new((v3, v2, v4))
    for f in (f1, f2):
        for loop in f.loops:
            loop[uvl].uv = (0.5, (loop.vert.co.z - z) / h)
    blade_cols.append(reed)
    if reed:
        reed_tips.append((x + lx_, y + ly_, z + h))


count = 0
while count < 16000:
    x, y = random.uniform(X0 + 0.1, X1 - 0.1), random.uniform(Y0 + 0.1, Y1 - 0.1)
    z = height(x, y)
    if z < WL + 0.04:
        continue
    dens = smoothstep(-0.3, 0.2, fbm(Vector((x, y, 0)) * 0.7)) * (0.35 if math.hypot(x + 0.3, y + 1.2) < 1.2 else 1.0)
    # keep the lens corridor between the camera and the actor stage low and sparse
    if y < -0.9 and abs(x + 0.3 - (y + 1.2) * -0.15) < 1.3:
        dens *= 0.12
    if random.random() > dens:
        continue
    blade(x, y, random.uniform(0.08, 0.26), random.uniform(0.008, 0.014), random.uniform(0.02, 0.09))
    count += 1
reeds = 0
while reeds < 420:  # cattail reeds in the shallows / shoreline
    a, r = random.random() * 6.28, random.uniform(0.85, 1.1)
    x, y = 0.6 + math.cos(a) * 3.1 * r, 1.5 + math.sin(a) * 1.7 * r
    if y < 0.3 and abs(x) < 1.8:  # keep the front of the pond open to camera
        continue
    blade(x, y, random.uniform(0.6, 1.25), 0.012, random.uniform(0.03, 0.12), reed=True)
    reeds += 1

gme = bpy.data.meshes.new('Grass')
gb.to_mesh(gme)
grass = link(bpy.data.objects.new('Grass', gme))
attr = gme.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
gme.color_attributes.active_color = attr
uv = gme.uv_layers[0].data
for poly in gme.polygons:
    for li in poly.loop_indices:
        vi = gme.loops[li].vertex_index
        t = max(0.0, min(1.0, uv[li].uv[1]))
        c = mix(col_base, col_tip, t ** 0.8)
        c = tuple(ci * (0.8 + 0.4 * ((vi * 2654435761 % 1000) / 1000)) for ci in c)
        attr.data[vi].color = (*c, 1)
set_material(grass, vc_material('Grass', roughness=0.7))
objs.append(grass)

# cattail heads (static)
heads = [{'co': (tx, ty, tz - 0.06), 'r': 0.022, 'size': (1, 1, 3.4)} for tx, ty, tz in reed_tips[::5]]
ct = metablob('Cattails', heads)
sculpt(ct, voxel=0.008, smooth=0, decimate=0.25)
paint(ct, lambda p, n: srgb('#5a3a1e'))
set_material(ct, vc_material('Cattail', roughness=0.9))
objs.append(ct)

print(f'[pond] objects={len(objs)} tris={tri_count(objs)} grass={count} reeds={reeds}')
from common import export_glb  # noqa: E402
export_glb(OUT)

# Heightmap for actor ground-following (Three coords: x, z = -blenderY), 0.1 m grid
step = 0.1
xs = [round(X0 + i * step, 3) for i in range(int((X1 - X0) / step) + 1)]
ys = [round(Y0 + j * step, 3) for j in range(int((Y1 - Y0) / step) + 1)]
grid = [[round(height(x, y), 3) for x in xs] for y in ys]
with open(OUT_H, 'w') as f:
    json.dump({'x0': X0, 'y0': Y0, 'step': step, 'nx': len(xs), 'ny': len(ys), 'waterLevel': WL, 'h': grid}, f,
              separators=(',', ':'))
print('[pond] wrote', OUT, OUT_H)

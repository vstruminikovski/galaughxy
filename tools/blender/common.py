"""Shared helpers for the headless Blender sculpting pipeline.

Everything is generated procedurally (metaball forms -> voxel remesh -> displacement
"sculpt" passes -> smoothing -> decimation -> vertex paint), so every asset is 100% original
and reproducible from code. Blender is Z-up; the glTF exporter converts to Three.js Y-up
(Blender -Y = Three +Z = toward the camera).
"""
import bpy
import math
from mathutils import Vector, noise


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def activate(obj):
    for o in list(bpy.context.scene.objects):
        if o is not None:
            o.select_set(False)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)


def apply_modifiers(obj):
    activate(obj)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def _ellipsoid_mesh(elements):
    import bmesh
    from mathutils import Euler, Matrix
    bm = bmesh.new()
    for el in elements:
        sx, sy, sz = el.get('size', (1, 1, 1))
        r = el['r']
        m = (Matrix.Translation(Vector(el['co'])) @ Euler(el.get('rot', (0, 0, 0))).to_matrix().to_4x4()
             @ Matrix.Diagonal((r * sx, r * sy, r * sz, 1)))
        bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=20, radius=1.0, matrix=m)
    return bm


def metablob(name, elements, resolution=None, threshold=None):
    """Additive ellipsoid 'clay' forms + optional negative (carving) forms.
    elements: dicts {co, r, size?(x,y,z), rot?(euler), neg?}. Positives are fused later by the
    voxel remesh in sculpt(); negatives are subtracted with an exact boolean."""
    pos = [e for e in elements if not e.get('neg')]
    neg = [e for e in elements if e.get('neg')]
    me = bpy.data.meshes.new(name)
    _ellipsoid_mesh(pos).to_mesh(me)
    obj = link(bpy.data.objects.new(name, me))
    obj['carve'] = 1 if neg else 0
    if neg:
        nme = bpy.data.meshes.new(name + '_carve')
        _ellipsoid_mesh(neg).to_mesh(nme)
        cutter = link(bpy.data.objects.new(name + '_carve', nme))
        cutter.hide_render = True
        obj['_cutter'] = cutter.name
    return obj


_tex_count = [0]


def texture(kind, size, **kw):
    _tex_count[0] += 1
    t = bpy.data.textures.new(f'tex{_tex_count[0]}', type=kind)
    t.noise_scale = size
    for k, v in kw.items():
        setattr(t, k, v)
    return t


def sculpt(obj, voxel=0.01, passes=(), smooth=0, decimate=None):
    """Voxel remesh, then layered displacement 'brush' passes, smoothing and decimation.
    passes: (texture_kind, noise_scale, strength, extra_kw) tuples."""
    m = obj.modifiers.new('remesh', 'REMESH')
    m.mode = 'VOXEL'
    m.voxel_size = voxel
    m.adaptivity = 0.0
    apply_modifiers(obj)  # fuses overlapping clay forms into one watertight volume
    cutter_name = obj.get('_cutter')
    if cutter_name:
        cutter = bpy.data.objects[cutter_name]
        b = obj.modifiers.new('carve', 'BOOLEAN')
        b.operation = 'DIFFERENCE'
        b.object = cutter
        b.solver = 'EXACT'
        apply_modifiers(obj)
        bpy.data.objects.remove(cutter, do_unlink=True)
        m = obj.modifiers.new('remesh2', 'REMESH')
        m.mode = 'VOXEL'
        m.voxel_size = voxel
        apply_modifiers(obj)
    # 'Smooth brush' pass to blend the joins between forms like hand-sculpted clay
    blend = obj.modifiers.new('blend', 'CORRECTIVE_SMOOTH')
    blend.iterations = 12
    blend.factor = 0.8
    blend.use_only_smooth = True
    apply_modifiers(obj)
    for kind, size, strength, kw in passes:
        d = obj.modifiers.new('disp', 'DISPLACE')
        d.texture = texture(kind, size, **kw)
        d.strength = strength
        d.mid_level = 0.5
        d.texture_coords = 'GLOBAL'
    if smooth:
        s = obj.modifiers.new('smooth', 'SMOOTH')
        s.iterations = smooth
        s.factor = 0.5
    if decimate:
        dm = obj.modifiers.new('dec', 'DECIMATE')
        dm.ratio = decimate
    apply_modifiers(obj)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def srgb(c):
    """hex -> linear float rgb"""
    c = c.lstrip('#')
    return tuple((int(c[i:i + 2], 16) / 255) ** 2.2 for i in (0, 2, 4))


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def fbm(p, octaves=4):
    v, a, f = 0.0, 0.5, 1.0
    for _ in range(octaves):
        v += a * noise.noise(p * f)
        a *= 0.5
        f *= 2.0
    return v


def paint(obj, fn):
    """Per-vertex colour: fn(world_co, world_normal) -> linear rgb."""
    me = obj.data
    attr = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    me.color_attributes.active_color = attr
    try:
        me.color_attributes.render_color_index = me.color_attributes.active_color_index
    except Exception:
        pass
    mw = obj.matrix_world
    nm = mw.to_3x3()
    for v in me.vertices:
        c = fn(mw @ v.co, (nm @ v.normal).normalized())
        attr.data[v.index].color = (c[0], c[1], c[2], 1.0)


def vc_material(name, roughness=0.7, specular=0.4, sheen=0.0):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except Exception:
        pass
    nodes = mat.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    vc = nodes.new('ShaderNodeVertexColor')
    vc.layer_name = 'Col'
    mat.node_tree.links.new(vc.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = roughness
    return mat


def set_material(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def set_origin(obj, point):
    bpy.context.scene.cursor.location = Vector(point)
    activate(obj)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')


def tri_count(objs):
    total = 0
    for o in objs:
        o.data.calc_loop_triangles()
        total += len(o.data.loop_triangles)
    return total


def export_glb(path):
    kw = dict(filepath=path, export_format='GLB', export_apply=True, export_yup=True, use_selection=False)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color='MATERIAL', **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)

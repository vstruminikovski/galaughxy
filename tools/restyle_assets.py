"""Normalizes a fetched CC0 model (Kenney, Poly Pizza, Poly Haven, ...) into the studio style.

  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \\
      --python tools/restyle_assets.py -- <in.glb|.gltf|.obj|.fbx> <out.glb> [--height 0.5] [--character]

What it does:
  - imports the file and joins nothing (parts stay separate so they can be posed)
  - scales it to --height metres (default 0.5) and puts its feet on the floor, facing -Y
  - shade smooth + weighted normals on every mesh (perfect style, CLAUDE.md section 17)
  - replaces every material and texture with the nearest Mac Studio palette colour
    (no bitmaps: the project contains no image textures)
  - with --character, adds the shared joint layout (Root > Hips > Spine > Head, Arm_L/R, Leg_L/R,
    Eye_L/R, Jaw) as empties at proportional heights, parenting each mesh to the nearest joint, so
    the Godot Puppet can animate it
  - exports a .glb
"""

import math
import sys

import bpy
from mathutils import Matrix, Vector

PALETTE = {
    "silver": "#E5E7EB", "space_gray": "#2C2E33", "cream": "#F5F2EB", "bondi_blue": "#4A90E2",
    "coral": "#FF5F56", "amber": "#FFBD2E", "mint": "#27C93F",
}


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c):
    return c * 12.92 if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def nearest(rgb):
    best, best_d = None, 9.0
    for name, h in PALETTE.items():
        p = hex_rgb(h)
        d = sum((a - b) ** 2 for a, b in zip(rgb, p))
        if d < best_d:
            best, best_d = name, d
    return best


def material_colour(mat):
    """sRGB base colour of a material (Principled base colour, or its viewport colour)."""
    if mat and mat.node_tree:
        for node in mat.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                c = node.inputs["Base Color"].default_value
                return tuple(linear_to_srgb(c[i]) for i in range(3))
    if mat:
        return tuple(mat.diffuse_color[:3])
    return hex_rgb(PALETTE["silver"])


def palette_material(name, cache):
    if name in cache:
        return cache[name]
    m = bpy.data.materials.new("M_" + name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    b = m.node_tree.nodes.get("Principled BSDF")
    c = hex_rgb(PALETTE[name])
    b.inputs["Base Color"].default_value = (*[srgb_to_linear(v) for v in c], 1.0)
    b.inputs["Roughness"].default_value = 0.42
    cache[name] = m
    return m


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    src, out = argv[0], argv[1]
    height = float(argv[argv.index("--height") + 1]) if "--height" in argv else 0.5
    character = "--character" in argv

    bpy.ops.wm.read_factory_settings(use_empty=True)
    ext = src.lower().rsplit(".", 1)[-1]
    if ext in ("glb", "gltf"):
        bpy.ops.import_scene.gltf(filepath=src)
    elif ext == "obj":
        bpy.ops.wm.obj_import(filepath=src)
    elif ext == "fbx":
        bpy.ops.import_scene.fbx(filepath=src)
    else:
        raise SystemExit("unsupported format: " + ext)

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit("no meshes in " + src)
    bpy.context.view_layer.update()

    # bounds, scale to height, feet on the floor, centred
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        for corner in o.bound_box:
            w = o.matrix_world @ Vector(corner)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    s = height / max(1e-6, hi.z - lo.z)
    pivot = bpy.data.objects.new("Normalize", None)
    bpy.context.scene.collection.objects.link(pivot)
    for o in bpy.data.objects:
        if o.parent is None and o != pivot:
            o.parent = pivot
    pivot.scale = (s, s, s)
    pivot.location = (-(lo.x + hi.x) / 2 * s, -(lo.y + hi.y) / 2 * s, -lo.z * s)
    bpy.context.view_layer.update()
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    bpy.data.objects.remove(pivot)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    # palette materials, smooth shading, weighted normals, no textures
    cache = {}
    for o in meshes:
        for i, slot in enumerate(o.material_slots):
            slot.material = palette_material(nearest(material_colour(slot.material)), cache)
        if not o.material_slots:
            o.data.materials.append(palette_material("silver", cache))
        for p in o.data.polygons:
            p.use_smooth = True
        if not any(m.type == "WEIGHTED_NORMAL" for m in o.modifiers):
            wn = o.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
            wn.keep_sharp = True
    for img in list(bpy.data.images):
        bpy.data.images.remove(img)

    if character:
        h = height
        joints = {"Root": (None, 0.0), "Hips": ("Root", 0.35), "Spine": ("Hips", 0.45), "Head": ("Spine", 0.8),
                  "Arm_L": ("Spine", 0.6), "Arm_R": ("Spine", 0.6), "Leg_L": ("Hips", 0.3), "Leg_R": ("Hips", 0.3),
                  "Eye_L": ("Head", 0.86), "Eye_R": ("Head", 0.86), "Jaw": ("Head", 0.74)}
        side = {"Arm_L": 0.3, "Arm_R": -0.3, "Leg_L": 0.12, "Leg_R": -0.12, "Eye_L": 0.08, "Eye_R": -0.08}
        made = {}
        for name, (parent, frac) in joints.items():
            e = bpy.data.objects.new(name, None)
            bpy.context.scene.collection.objects.link(e)
            e.location = (side.get(name, 0.0) * h, -0.1 * h if name in ("Eye_L", "Eye_R", "Jaw") else 0.0, frac * h)
            made[name] = e
        world = {name: made[name].location.copy() for name in made}
        for name, (parent, _) in joints.items():
            if parent:
                made[name].parent = made[parent]
                bpy.context.view_layer.update()
                made[name].matrix_world = Matrix.Translation(world[name])
        bpy.context.view_layer.update()
        body_joints = ["Head", "Arm_L", "Arm_R", "Leg_L", "Leg_R", "Spine", "Hips"]
        for o in meshes:
            c = sum((o.matrix_world @ Vector(b) for b in o.bound_box), Vector()) / 8
            best = min(body_joints, key=lambda j: (made[j].matrix_world.translation - c).length)
            mw = o.matrix_world.copy()
            o.parent = made[best]
            o.matrix_world = mw

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True, export_yup=True, export_animations=False)
    print("[restyle] wrote", out, "scale %.3f" % s)


main()

"""Turntable-style still of a .glb for quick art review.
Blender -b -P tools/blender/preview.py -- <in.glb> <out.png> [cam_x cam_y cam_z tgt_x tgt_y tgt_z]"""
import sys, math, bpy
from mathutils import Vector
argv = sys.argv[sys.argv.index('--') + 1:]
src, out = argv[0], argv[1]
cam_p = Vector(map(float, argv[2:5])) if len(argv) >= 5 else Vector((0.55, -0.9, 0.45))
tgt = Vector(map(float, argv[5:8])) if len(argv) >= 8 else Vector((0, -0.05, 0.18))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE' if 'BLENDER_EEVEE' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE_NEXT'
sc.render.resolution_x, sc.render.resolution_y = 900, 600
sc.render.filepath = out
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam)
cam.location = cam_p
cam.rotation_euler = (tgt - cam_p).to_track_quat('-Z', 'Y').to_euler()
cam.data.lens = 50
sc.camera = cam
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sc.collection.objects.link(sun)
sun.data.energy = 4; sun.rotation_euler = (math.radians(50), 0, math.radians(30))
w = bpy.data.worlds.new('w'); sc.world = w
try:
    w.use_nodes = True
except Exception: pass
bg = w.node_tree.nodes.get('Background')
if bg: bg.inputs[0].default_value = (0.55, 0.65, 0.75, 1); bg.inputs[1].default_value = 0.8
bpy.ops.render.render(write_still=True)

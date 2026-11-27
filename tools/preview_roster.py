"""Contact sheet of every roster .glb (front three-quarter view), for checking the designs.

  Blender --background --python tools/preview_roster.py -- <glb dir> <out.png>
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
files = sorted(f for f in os.listdir(src) if f.endswith(".glb"))
cols = 5
for i, f in enumerate(files):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(src, f))
    new = [o for o in bpy.data.objects if o not in before]
    x = (i % cols) * 0.75
    y = -(i // cols) * 0.0
    z = -(i // cols) * 1.0
    for o in new:
        if o.parent is None:
            o.location = (x, 0, z)
    bpy.ops.object.text_add(location=(x - 0.2, -0.3, z - 0.12))
    t = bpy.context.active_object
    t.data.body = f[:-4]
    t.data.size = 0.06
    t.rotation_euler = (math.radians(90), 0, 0)
scene = bpy.context.scene
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scene.collection.objects.link(cam)
cam.data.type = "ORTHO"
cam.data.ortho_scale = 4.1
cam.location = (1.5 + 3.0, -6.0, -1.1 + 1.6)
direction = Vector((1.5, 0, -1.1)) - cam.location
cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
scene.collection.objects.link(sun)
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_cavity = False
scene.render.resolution_x = 2000
scene.render.resolution_y = 1700
scene.render.filepath = out
bpy.ops.render.render(write_still=True)

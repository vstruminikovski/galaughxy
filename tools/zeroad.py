"""0 A.D. buildings for history maps (CLAUDE.md section 27).

0 A.D. art is (C) Wildfire Games, CC-BY-SA 3.0 (https://creativecommons.org/licenses/by-sa/3.0/,
https://www.wildfiregames.com/). Converted pieces stay CC-BY-SA: see godot/assets/history/LICENSE.md.

What this module does:
  - resolve(actor): reads an actor XML from the 0 A.D. repository and its root-attached prop actors,
    and returns the parts [(mesh path, base texture path, player-colour?)].
  - fetch(path): downloads a file once (Git LFS objects through Gitea's media endpoint) into
    tools/.cache/0ad/ (git-ignored).
  - import_actor(...)  [Blender only]: imports the parts (COLLADA), bakes every face to ONE flat colour
    sampled from its texture, snapped to the 21 Mac Studio swatches (so the Godot restyle shows it in
    the Illustrated Ink palette), joins them into one object named Lowpoly_<label>, scales and seats it.

The converted buildings are faceted on purpose: hard-edged low-poly architecture. Godot inks them with
crease and silhouette edges (InkEdges.gd) rather than the smooth-surface contour ink.
"""

import os
import urllib.request
import xml.etree.ElementTree as ET

REPO = "https://gitea.wildfiregames.com/0ad/0ad"
ART = "binaries/data/mods/public/art"
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache", "0ad")

# the 21 Mac Studio swatches (base, light 42 % toward white, shade 32 % darker), like Style.gd
BASES = ["#E5E7EB", "#2C2E33", "#F5F2EB", "#4A90E2", "#FF5F56", "#FFBD2E", "#27C93F"]


def _hex(c):
    return "#%02X%02X%02X" % tuple(max(0, min(255, int(round(v)))) for v in c)


def _rgb(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def swatches():
    out = []
    for b in BASES:
        c = _rgb(b)
        out.append(_hex(c))
        out.append(_hex([v + (255 - v) * 0.42 for v in c]))
        out.append(_hex([v * 0.68 for v in c]))
    return out


SWATCHES = swatches()
SW_RGB = [[v / 255.0 for v in _rgb(s)] for s in SWATCHES]


def snap(c):
    """Nearest swatch (redmean distance) for an sRGB colour in 0..1."""
    best, best_d = 0, 1e9
    for i, s in enumerate(SW_RGB):
        rm = (c[0] + s[0]) * 0.5
        dr, dg, db = c[0] - s[0], c[1] - s[1], c[2] - s[2]
        d = (2.0 + rm) * dr * dr + 4.0 * dg * dg + (3.0 - rm) * db * db
        if d < best_d:
            best, best_d = i, d
    return SWATCHES[best]


def fetch(path):
    """art-relative path -> local file (cached). XML actors come raw; meshes and textures via LFS media."""
    local = os.path.join(CACHE, path)
    if os.path.exists(local) and os.path.getsize(local) > 0:
        return local
    os.makedirs(os.path.dirname(local), exist_ok=True)
    kind = "raw" if path.endswith(".xml") else "media"
    url = "%s/%s/branch/main/%s/%s" % (REPO, kind, ART, path)
    req = urllib.request.Request(url, headers={"User-Agent": "galaughxy-asset-tool"})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
    if data.startswith(b"Not found"):
        raise FileNotFoundError(url)
    with open(local, "wb") as f:
        f.write(data)
    return local


def resolve(actor, depth=0):
    """Parts of an actor: [(mesh, base texture, player_colour)], following props attached at root."""
    if depth > 4:
        return []
    root = ET.parse(fetch("actors/" + actor)).getroot()
    mesh, tex, props = None, None, []
    material = (root.findtext("material") or "").lower()
    for group in root.findall("group"):
        # skip pure includes (<variant file="..."/> with nothing of its own, e.g. destruction FX)
        variants = [v for v in group.findall("variant") if v.get("file") is None or len(list(v)) > 0]
        if not variants:
            continue
        v = variants[0]
        if mesh is None and v.findtext("mesh"):
            mesh = v.findtext("mesh").strip()
        for t in v.findall("textures/texture"):
            if t.get("name") == "baseTex" and tex is None:
                tex = t.get("file")
        for p in v.findall("props/prop"):
            if p.get("attachpoint", "root") == "root" and p.get("actor"):
                props.append(p.get("actor"))
    parts = []
    if mesh and tex:
        parts.append(("meshes/" + mesh, "textures/skins/" + tex, "player" in material))
    for p in props:
        if "garrison" in p or "destruction" in p or "flag" in p:
            continue
        try:
            parts.extend(resolve(p, depth + 1))
        except Exception as e:   # a missing prop is skipped, the building still converts
            print("[0ad] skip prop", p, e)
    return parts


# ── Blender side ──────────────────────────────────────────────────────────────────

def _image_pixels(path):
    import bpy
    import numpy as np
    img = bpy.data.images.load(path, check_existing=True)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    return px.reshape(h, w, 4), w, h


def _bake_faces(obj, tex_path, player, mat_for):
    """One flat swatch colour per face, sampled (5 points) from the texture under the face."""
    import numpy as np
    px, w, h = _image_pixels(tex_path)
    me = obj.data
    uv = me.uv_layers.active
    if uv is None:
        return
    slots = {}
    for poly in me.polygons:
        uvs = [uv.data[li].uv for li in poly.loop_indices]
        cu = sum(u[0] for u in uvs) / len(uvs)
        cv = sum(u[1] for u in uvs) / len(uvs)
        pts = [(cu, cv)] + [((cu + u[0]) * 0.5, (cv + u[1]) * 0.5) for u in uvs[:4]]
        acc = np.zeros(4)
        for (u, v) in pts:
            x = int((u % 1.0) * (w - 1))
            y = int((v % 1.0) * (h - 1))
            acc += px[y, x]
        c = acc / len(pts)
        rgb = c[:3]
        if player and c[3] < 0.5:
            hexc = "#4A90E2"   # player-colour areas (banners, trims): Bondi blue
        else:
            hexc = snap(rgb)
        if hexc not in slots:
            me.materials.append(mat_for(hexc))
            slots[hexc] = len(me.materials) - 1
        poly.material_index = slots[hexc]
        poly.use_smooth = False


NS = {"c": "http://www.collada.org/2005/11/COLLADASchema"}


def _floats(el):
    return [float(x) for x in el.text.split()] if el is not None and el.text else []


def _node_matrix(node):
    """A COLLADA node's local transform (matrix, or translate / rotate / scale in order)."""
    from mathutils import Matrix, Vector
    m = Matrix.Identity(4)
    for el in node:
        tag = el.tag.split("}")[1]
        v = _floats(el)
        if tag == "matrix" and len(v) == 16:
            m = m @ Matrix([v[0:4], v[4:8], v[8:12], v[12:16]])
        elif tag == "translate" and len(v) == 3:
            m = m @ Matrix.Translation(Vector(v))
        elif tag == "rotate" and len(v) == 4:
            import math
            m = m @ Matrix.Rotation(math.radians(v[3]), 4, Vector(v[:3]))
        elif tag == "scale" and len(v) == 3:
            m = m @ Matrix.Diagonal((v[0], v[1], v[2], 1.0))
    return m


def read_dae(path):
    """Minimal COLLADA reader (Blender 5 has no importer): triangles with UVs, placed by the visual
    scene's node transforms, converted to Blender's Z-up metres. Returns [(p0, p1, p2), (uv0, uv1, uv2)]."""
    from mathutils import Matrix, Vector
    import math
    root = ET.parse(path).getroot()
    up = root.findtext("c:asset/c:up_axis", default="Y_UP", namespaces=NS).strip()
    unit_el = root.find("c:asset/c:unit", NS)
    unit = 1.0   # the game ignores the unit tag (some files say centimetres for metre data)
    geoms = {}
    for g in root.findall("c:library_geometries/c:geometry", NS):
        mesh = g.find("c:mesh", NS)
        if mesh is None:
            continue
        sources = {}
        for s in mesh.findall("c:source", NS):
            acc = s.find("c:technique_common/c:accessor", NS)
            stride = int(acc.get("stride", "1")) if acc is not None else 1
            vals = _floats(s.find("c:float_array", NS))
            sources[s.get("id")] = [vals[i:i + stride] for i in range(0, len(vals), stride)]
        vert = mesh.find("c:vertices", NS)
        vpos = vert.find("c:input[@semantic='POSITION']", NS).get("source").lstrip("#")
        tris = []
        for prim in list(mesh):
            tag = prim.tag.split("}")[1]
            if tag not in ("triangles", "polylist", "polygons"):
                continue
            inputs = prim.findall("c:input", NS)
            stride = max(int(i.get("offset")) for i in inputs) + 1
            offs = {}
            for i in inputs:
                sem, src, off = i.get("semantic"), i.get("source").lstrip("#"), int(i.get("offset"))
                if sem == "VERTEX":
                    offs["P"] = (off, vpos)
                elif sem == "TEXCOORD" and ("T" not in offs or i.get("set", "0") in ("0", "1")):
                    if "T" not in offs:
                        offs["T"] = (off, src)
            if "P" not in offs:
                continue
            polys = []
            if tag == "triangles":
                p = [int(x) for x in prim.find("c:p", NS).text.split()]
                polys = [(p, [3] * (len(p) // (3 * stride)))]
            elif tag == "polylist":
                p = [int(x) for x in prim.find("c:p", NS).text.split()]
                polys = [(p, [int(x) for x in prim.find("c:vcount", NS).text.split()])]
            else:
                for pe in prim.findall("c:p", NS):
                    p = [int(x) for x in pe.text.split()]
                    polys.append((p, [len(p) // stride]))
            for p, counts in polys:
                idx = 0
                for n in counts:
                    vs = []
                    for k in range(n):
                        b = (idx + k) * stride
                        pos = sources[offs["P"][1]][p[b + offs["P"][0]]]
                        uv = (0.0, 0.0)
                        if "T" in offs:
                            t = sources[offs["T"][1]][p[b + offs["T"][0]]]
                            uv = (t[0], t[1])
                        vs.append((Vector(pos[:3]), uv))
                    idx += n
                    for k in range(1, n - 1):
                        tris.append((vs[0], vs[k], vs[k + 1]))
        geoms[g.get("id")] = tris
    axis = Matrix.Rotation(math.radians(90), 4, "X") if up == "Y_UP" else Matrix.Identity(4)
    if up == "X_UP":
        axis = Matrix.Rotation(math.radians(-90), 4, "Y")
    out = []

    def walk(node, m):
        m2 = m @ _node_matrix(node)
        for ig in node.findall("c:instance_geometry", NS):
            for tri in geoms.get(ig.get("url").lstrip("#"), []):
                out.append(([(axis @ m2 @ v[0]) * unit for v in tri], [v[1] for v in tri]))
        for child in node.findall("c:node", NS):
            walk(child, m2)

    for vs in root.findall("c:library_visual_scenes/c:visual_scene", NS):
        for node in vs.findall("c:node", NS):
            walk(node, Matrix.Identity(4))
    return out


def _mesh_from_tris(name, tris):
    import bpy
    verts, faces, uvs = [], [], []
    for ps, ts in tris:
        b = len(verts)
        verts.extend([tuple(p) for p in ps])
        faces.append((b, b + 1, b + 2))
        uvs.extend(ts)
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    layer = me.uv_layers.new(name="UVMap")
    for i, loop in enumerate(me.loops):
        layer.data[i].uv = uvs[loop.vertex_index]
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def import_actor(actor, label, mat_for, scale=0.45):
    """Imports an actor's parts, bakes flat colours, joins them into Lowpoly_<label>, seated at z = 0
    with its footprint centred on the origin. Returns the object."""
    import bpy
    parts = resolve(actor)
    objs = []
    for mesh, tex, player in parts:
        try:
            dae = fetch(mesh)
            img = fetch(tex)
            tris = read_dae(dae)
        except Exception as e:
            print("[0ad] skip part", mesh, e)
            continue
        if not tris:
            continue
        o = _mesh_from_tris("part", tris)
        _bake_faces(o, img, player, mat_for)
        objs.append(o)
    if not objs:
        raise RuntimeError("no parts for " + actor)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = "Lowpoly_" + label
    o.data.name = o.name
    for v in o.data.vertices:
        v.co *= scale
    # weld duplicates per face colour so edges are shared (cleaner ink and colliders)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    bm.to_mesh(o.data)
    bm.free()
    for poly in o.data.polygons:
        poly.use_smooth = False
    xs = [v.co.x for v in o.data.vertices]
    ys = [v.co.y for v in o.data.vertices]
    zs = [v.co.z for v in o.data.vertices]
    cx, cy, z0 = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs)
    for v in o.data.vertices:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= z0
    o.location = (0, 0, 0)
    print("[0ad] %s: %d faces, %.1f x %.1f x %.1f m" % (label, len(o.data.polygons), max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)))
    return o

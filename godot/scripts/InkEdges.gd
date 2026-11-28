class_name InkEdges
extends MeshInstance3D

## Ink for hard-edged, faceted meshes (the converted 0 A.D. buildings, named Lowpoly_*).
## The smooth contour ink (InkStroke.gd) finds silhouettes inside triangles from varying vertex
## normals, so it can't see a faceted mesh, whose silhouettes run along its edges. This builds one quad
## per candidate edge instead. Each quad carries the edge's two ends and the normals of its two faces,
## and shaders/ink_edges.gdshader decides every frame whether the edge is a silhouette, a crease or
## an open border. Coplanar edges (inside flat walls) are dropped at setup, so flat areas cost nothing.

const FLAT_COS := 0.9995     # faces closer than ~1.8 degrees: no line possible
const CREASE_COS := 0.82     # folds sharper than ~35 degrees are creases

static var _material: ShaderMaterial

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/ink_edges.gdshader")
		if Look.illustrated():
			_material.set_shader_parameter("use_global_ink", 1.0)
			_material.set_shader_parameter("light_weight", 1.0)
		else:
			_material.set_shader_parameter("ink_color", Color(0.48, 0.12, 0.12, 1.0))
			_material.set_shader_parameter("use_global_ink", 0.0)
			_material.set_shader_parameter("light_weight", 0.0)
	return _material

static func reset() -> void:
	_material = null

static func make(src: ArrayMesh) -> InkEdges:
	var e := InkEdges.new()
	e.setup(src)
	e.material_override = material()
	return e

func setup(src: ArrayMesh) -> void:
	var ids := {}
	var pts := PackedVector3Array()
	var edges := {}
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := idx.size() if idx.size() > 0 else verts.size()
		var k := 0
		while k + 2 < count:
			var p := [verts[idx[k] if idx.size() > 0 else k], verts[idx[k + 1] if idx.size() > 0 else k + 1], verts[idx[k + 2] if idx.size() > 0 else k + 2]]
			k += 3
			var n: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
			if n.length_squared() < 1e-14:
				continue
			n = n.normalized()
			var vid := []
			for q: Vector3 in p:
				var key := Vector3i(roundi(q.x * 2000.0), roundi(q.y * 2000.0), roundi(q.z * 2000.0))
				if not ids.has(key):
					ids[key] = pts.size()
					pts.append(q)
				vid.append(ids[key])
			for e in [[vid[0], vid[1]], [vid[1], vid[2]], [vid[2], vid[0]]]:
				if e[0] == e[1]:
					continue
				var ek := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
				if edges.has(ek):
					(edges[ek] as Array).append(n)
				else:
					edges[ek] = [n]
	var v := PackedVector3Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var c2 := PackedFloat32Array()
	var uv := PackedVector2Array()
	var ix := PackedInt32Array()
	var corners := [Vector2(0, -1), Vector2(0, 1), Vector2(1, -1), Vector2(1, 1)]
	for ek: Vector2i in edges:
		var ns: Array = edges[ek]
		var na: Vector3 = ns[0]
		var nb: Vector3 = ns[1] if ns.size() > 1 else ns[0]
		var two := ns.size() > 1
		if two and na.dot(nb) > FLAT_COS:
			continue
		var crease := 1.0 if (two and na.dot(nb) < CREASE_COS) else 0.0
		var a: Vector3 = pts[ek.x]
		var b: Vector3 = pts[ek.y]
		var base := v.size()
		for corner in corners:
			v.append(a)
			c0.append_array([b.x, b.y, b.z, crease])
			c1.append_array([na.x, na.y, na.z, 1.0 if two else 0.0])
			c2.append_array([nb.x, nb.y, nb.z, 0.0])
			uv.append(corner)
		ix.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var m := ArrayMesh.new()
	if not v.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_CUSTOM0] = c0
		arr[Mesh.ARRAY_CUSTOM1] = c1
		arr[Mesh.ARRAY_CUSTOM2] = c2
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_INDEX] = ix
		var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	mesh = m
	custom_aabb = src.get_aabb().grow(0.1)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

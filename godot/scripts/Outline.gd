class_name Outline
extends RefCounted

## Rounded outline by inverted hull: a copy of the mesh pushed out along smoothed vertex
## normals and drawn with front faces culled, so only its rim shows. Geometry, not pixels,
## so it stays exact at any resolution and from every angle.

static func hull(src: ArrayMesh, thickness: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		# average the face normals meeting at each corner, so the shell stays closed
		var sum := {}
		var key_of := PackedStringArray()
		key_of.resize(verts.size())
		var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in verts.size():
			var k := "%d,%d,%d" % [roundi(verts[i].x * 1e4), roundi(verts[i].y * 1e4), roundi(verts[i].z * 1e4)]
			key_of[i] = k
			sum[k] = sum.get(k, Vector3.ZERO) + nrm[i]
		var moved := PackedVector3Array()
		moved.resize(verts.size())
		for i in verts.size():
			var n: Vector3 = (sum[key_of[i]] as Vector3).normalized()
			moved[i] = verts[i] + n * thickness
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = moved
		if idx.size() > 0:
			a[Mesh.ARRAY_INDEX] = idx
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return out

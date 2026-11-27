class_name Outline
extends RefCounted

## Rounded outline by inverted hull: a copy of the mesh pushed out along smoothed normals and
## drawn with front faces culled, so only its rim shows. Geometry, not pixels, so it stays exact
## at any resolution and from every angle.
##
## Normals are averaged over a neighbourhood (not just identical corners) so the rim follows the
## surface as one smooth curve instead of kinking at every mesh cell.

static func hull(src: ArrayMesh, thickness: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	var radius := thickness * 8.0
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		# 1. merge corners that share a position: one unique point with its summed normal
		var slot := {}
		var pts := PackedVector3Array()
		var sums := PackedVector3Array()
		var key_of := PackedInt32Array()
		key_of.resize(verts.size())
		for i in verts.size():
			var k := "%d,%d,%d" % [roundi(verts[i].x * 1e4), roundi(verts[i].y * 1e4), roundi(verts[i].z * 1e4)]
			if not slot.has(k):
				slot[k] = pts.size()
				pts.append(verts[i])
				sums.append(Vector3.ZERO)
			key_of[i] = slot[k]
			sums[slot[k]] += nrm[i]
		# 2. spatial grid over unique points, so each point can average its close neighbours
		var grid := {}
		for u in pts.size():
			var c := _cell(pts[u], radius)
			if grid.has(c):
				grid[c].append(u)
			else:
				grid[c] = [u]
		var smooth := PackedVector3Array()
		smooth.resize(pts.size())
		var r2 := radius * radius
		for u in pts.size():
			var acc := Vector3.ZERO
			var base := _cell(pts[u], radius)
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						var c := Vector3i(base.x + dx, base.y + dy, base.z + dz)
						if not grid.has(c):
							continue
						for v in grid[c]:
							var d := pts[v].distance_squared_to(pts[u])
							if d < r2:
								acc += sums[v] * (1.0 - d / r2)
			smooth[u] = acc.normalized() if acc.length_squared() > 0.0 else sums[u].normalized()
		# 3. push every corner out along its smoothed normal
		var moved := PackedVector3Array()
		moved.resize(verts.size())
		for i in verts.size():
			moved[i] = verts[i] + smooth[key_of[i]] * thickness
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = moved
		if idx.size() > 0:
			a[Mesh.ARRAY_INDEX] = idx
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return out

static func _cell(p: Vector3, size: float) -> Vector3i:
	return Vector3i(floori(p.x / size), floori(p.y / size), floori(p.z / size))

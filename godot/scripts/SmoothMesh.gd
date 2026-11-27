class_name SmoothMesh
extends RefCounted

## Smooth surfaces from signed-distance fields (surface nets).
## Replaces the cube builders: every shape is sampled on a grid, the surface is placed
## between inside and outside samples, and normals come from the field gradient.
## f(p) < 0 is inside. color(p) -> Color for each surface vertex.

## shift: the mesh is returned relative to this point (the part's pivot), so the node can sit on the joint.
static func build(f: Callable, lo: Vector3, hi: Vector3, step: float, color: Callable, shift := Vector3.ZERO) -> ArrayMesh:
	var nx := int(ceil((hi.x - lo.x) / step)) + 1
	var ny := int(ceil((hi.y - lo.y) / step)) + 1
	var nz := int(ceil((hi.z - lo.z) / step)) + 1
	var field := PackedFloat32Array()
	field.resize(nx * ny * nz)
	for i in nx:
		for j in ny:
			for k in nz:
				var p := lo + Vector3(i, j, k) * step
				field[_idx(i, j, k, ny, nz)] = f.call(p)
	# one vertex per cell that the surface passes through
	var vert_of := PackedInt32Array()
	vert_of.resize((nx - 1) * (ny - 1) * (nz - 1))
	vert_of.fill(-1)
	var pos := PackedVector3Array()
	var cells := [
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
		Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1),
	]
	var edges := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	for i in nx - 1:
		for j in ny - 1:
			for k in nz - 1:
				var v := PackedFloat32Array()
				v.resize(8)
				var inside := false
				var outside := false
				for c in 8:
					var o: Vector3i = cells[c]
					v[c] = field[_idx(i + o.x, j + o.y, k + o.z, ny, nz)]
					if v[c] < 0.0: inside = true
					else: outside = true
				if not (inside and outside):
					continue
				var acc := Vector3.ZERO
				var n := 0
				for e: Array in edges:
					var a: float = v[e[0]]
					var b: float = v[e[1]]
					if (a < 0.0) == (b < 0.0):
						continue
					var t := a / (a - b)
					var pa := Vector3(cells[e[0]]) 
					var pb := Vector3(cells[e[1]])
					acc += pa.lerp(pb, t)
					n += 1
				var local := Vector3(i, j, k) + acc / float(n)
				vert_of[_cidx(i, j, k, ny - 1, nz - 1)] = pos.size()
				pos.append(_snap(f, lo + local * step, step))
	# connect neighbouring cells across every grid edge that changes sign
	var tris := PackedVector3Array()
	var dims := [nx, ny, nz]
	for i in nx:
		for j in ny:
			for k in nz:
				var s0: float = field[_idx(i, j, k, ny, nz)]
				for a in 3:
					var sv := [i, j, k]
					if sv[a] >= dims[a] - 1:
						continue
					var sv2 := sv.duplicate()
					sv2[a] += 1
					var s1: float = field[_idx(sv2[0], sv2[1], sv2[2], ny, nz)]
					if (s0 < 0.0) == (s1 < 0.0):
						continue
					var b := (a + 1) % 3
					var c := (a + 2) % 3
					if sv[b] < 1 or sv[c] < 1 or sv[b] > dims[b] - 1 or sv[c] > dims[c] - 1:
						continue
					var quad := []
					for d: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(0, 0), Vector2i(-1, 0)]:
						var cc := [0, 0, 0]
						cc[a] = sv[a]
						cc[b] = sv[b] + d.x
						cc[c] = sv[c] + d.y
						if cc[0] < 0 or cc[1] < 0 or cc[2] < 0 or cc[0] > dims[0] - 2 or cc[1] > dims[1] - 2 or cc[2] > dims[2] - 2:
							quad = []
							break
						var vi: int = vert_of[_cidx(cc[0], cc[1], cc[2], ny - 1, nz - 1)]
						if vi < 0:
							quad = []
							break
						quad.append(vi)
					if quad.size() != 4:
						continue
					var q0: Vector3 = pos[quad[0]]
					var q1: Vector3 = pos[quad[1]]
					var q2: Vector3 = pos[quad[2]]
					var q3: Vector3 = pos[quad[3]]
					var ta := [q0, q1, q2, q0, q2, q3]
					for t in ta:
						tris.append(t)
	# normals from the field gradient, colours from the caller
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_c := PackedColorArray()
	var eps := step * 0.5
	for p in tris:
		var g := Vector3(
			f.call(p + Vector3(eps, 0, 0)) - f.call(p - Vector3(eps, 0, 0)),
			f.call(p + Vector3(0, eps, 0)) - f.call(p - Vector3(0, eps, 0)),
			f.call(p + Vector3(0, 0, eps)) - f.call(p - Vector3(0, 0, eps)))
		out_v.append(p - shift)
		out_n.append(g.normalized() if g.length_squared() > 1e-12 else Vector3.UP)
		out_c.append(color.call(p))
	# make every triangle wind outward (Godot: clockwise is front, so flip to match the normal)
	for t in range(0, out_v.size(), 3):
		var geo := (out_v[t + 1] - out_v[t]).cross(out_v[t + 2] - out_v[t])
		var avg := (out_n[t] + out_n[t + 1] + out_n[t + 2])
		if geo.dot(avg) > 0.0:
			var tmp := out_v[t + 1]
			out_v[t + 1] = out_v[t + 2]
			out_v[t + 2] = tmp
			tmp = out_n[t + 1]
			out_n[t + 1] = out_n[t + 2]
			out_n[t + 2] = tmp
			var tc := out_c[t + 1]
			out_c[t + 1] = out_c[t + 2]
			out_c[t + 2] = tc
	var mesh := ArrayMesh.new()
	if out_v.size() == 0:
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = out_n
	arrays[Mesh.ARRAY_COLOR] = out_c
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Moves a point exactly onto the surface (f = 0) with a few Newton steps along the gradient,
## never further than one cell, so flat faces stay flat and curves stay round.
static func _snap(f: Callable, p: Vector3, step: float) -> Vector3:
	var start := p
	var eps := step * 0.25
	for it in 3:
		var d: float = f.call(p)
		if absf(d) < step * 1e-4:
			break
		var g := Vector3(
			f.call(p + Vector3(eps, 0, 0)) - f.call(p - Vector3(eps, 0, 0)),
			f.call(p + Vector3(0, eps, 0)) - f.call(p - Vector3(0, eps, 0)),
			f.call(p + Vector3(0, 0, eps)) - f.call(p - Vector3(0, 0, eps))) / (2.0 * eps)
		var gl := g.length_squared()
		if gl < 1e-12:
			break
		p -= g * (d / gl)
	if p.distance_to(start) > step:
		return start
	return p

static func _idx(i: int, j: int, k: int, ny: int, nz: int) -> int:
	return (i * ny + j) * nz + k

static func _cidx(i: int, j: int, k: int, cy: int, cz: int) -> int:
	return (i * cy + j) * cz + k

## Solid colour helper.
static func solid(c: Color) -> Callable:
	return func(_p: Vector3) -> Color: return c

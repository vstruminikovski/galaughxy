class_name PondWorld
extends RefCounted

## Pond Life, smooth stylised habitat (metres). The ground is a smooth height field; rocks,
## trees, reeds, lily pads and flowers are rounded shapes. Layout matches the earlier version.

const WATER_LEVEL := -0.06
const GRASS := [Color("#3f5f22"), Color("#6b8834"), Color("#8f9145"), Color("#2f4a1c")]
const DIRT := Color("#6a5236")
const MUD := [Color("#4d3d27"), Color("#2e2618")]
const ROCK := [Color("#80796c"), Color("#4d4942"), Color("#6d6a60")]
const LICHEN := Color("#b3ad72")
const BARK := Color("#5b4431")
const LEAF := [Color("#3e6b23"), Color("#7a9a3a"), Color("#1d3312")]
const PAD := Color("#3c6e2a")
const PINK := Color("#f7c6d6")
const REED := Color("#9b9a55")
const CATTAIL := Color("#5a3a1e")

static func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func _vnoise(x: float, y: float) -> float:
	var xi := floorf(x)
	var yi := floorf(y)
	var xf := x - xi
	var yf := y - yi
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := yf * yf * (3.0 - 2.0 * yf)
	var a := Sdf.hash3(xi, yi, 17)
	var b := Sdf.hash3(xi + 1, yi, 17)
	var c := Sdf.hash3(xi, yi + 1, 17)
	var d := Sdf.hash3(xi + 1, yi + 1, 17)
	return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v - 0.5

static func _fbm(x: float, y: float, o := 4) -> float:
	var v := 0.0
	var a := 0.5
	var f := 1.0
	for i in o:
		v += a * _vnoise(x * f, y * f)
		a *= 0.5
		f *= 2.0
	return v

## Height in metres at world (x, z). Same layout as the voxel version.
static func height(x: float, z: float) -> float:
	var y := -z
	var h := _fbm(x * 0.22 + 3.1, y * 0.22) * 0.32 + _fbm(x * 0.9 + 4.0, y * 0.9 + 4.0) * 0.05
	h += _smooth(1.8, 5.0, y) * 1.5
	h += _smooth(-3.0, -6.0, x) * 0.45
	h += _smooth(3.5, 6.0, x) * 0.35
	var d := sqrt(pow((x - 0.6) / 3.1, 2) + pow((y - 1.5) / 1.7, 2))
	h -= 0.62 * _smooth(1.05, 0.25, d)
	h *= 1.0 - 0.75 * _smooth(1.4, 0.0, Vector2(x + 0.3, y + 1.2).length())
	return h

## Metres to stand at above world (x, z). Smooth height, so the frog can sit on the bank.
func ground(x: float, z: float) -> float:
	return height(x, z)

func build() -> Node3D:
	var root := Node3D.new()
	root.add_child(_terrain())
	# rocks
	for r in [[-2.6, 0.6, 0.45], [-2.0, 1.2, 0.25], [3.4, 0.9, 0.55], [3.9, 1.7, 0.3], [2.2, 3.0, 0.4], [-1.0, 3.1, 0.6], [4.6, -1.5, 0.35], [-4.4, -1.0, 0.5]]:
		var c := Vector3(r[0], height(r[0], -r[1]), -r[1])
		var rad: float = r[2]
		var f := Sdf.ellipsoid(c + Vector3(0, rad * 0.3, 0), Vector3(rad, rad * 0.7, rad))
		root.add_child(Builders.sdf_piece(f, c - Vector3.ONE * (rad + 0.1), c + Vector3.ONE * (rad + 0.1), 0.025,
			func(p: Vector3) -> Color: return LICHEN if Sdf.hash3(p.x * 9.0, p.y * 9.0, p.z * 9.0) > 0.85 else ROCK[int(Sdf.hash3(p.x, p.z, 0.0) * 3.0) % 3]))
	# fallen log along the bank
	var log_a := Vector3(-3.6, height(-3.6, 0.2) + 0.12, 0.2)
	var log_b := Vector3(-0.4, height(-0.4, 0.2) + 0.12, 0.2)
	root.add_child(Builders.sdf_piece(Sdf.capsule(log_a, log_b, 0.14), log_a - Vector3.ONE * 0.3, log_b + Vector3.ONE * 0.3, 0.03, SmoothMesh.solid(BARK)))
	# trees
	for t in [[-4.6, 3.6, 4.2], [-1.8, 4.4, 5.0], [1.2, 4.6, 4.4], [3.9, 4.0, 5.2], [5.4, 2.0, 3.6], [-5.4, 0.6, 3.4]]:
		root.add_child(_tree(Vector3(t[0], 0, -t[1]), t[2] * 0.6))
	# reeds and cattail heads on the shore; lily pads and pink flowers on the water
	var reeds: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	var pads: Array[Transform3D] = []
	var flowers: Array[Transform3D] = []
	for ix in range(-60, 61, 2):
		for iz in range(-50, 51, 2):
			var x := ix * 0.1
			var z := iz * 0.1
			var h := height(x, z)
			var hs := Sdf.hash3(ix, 1, iz)
			if h > -0.05 and h < 0.12 and hs > 0.7 and _near_water(x, z):
				var hgt := 0.5 + hs * 0.4
				reeds.append(Transform3D(Basis().scaled(Vector3(1, hgt, 1)), Vector3(x, h, z) + Vector3(0, hgt * 0.5, 0)))
				heads.append(Transform3D(Basis(), Vector3(x, h + hgt, z) + Vector3(0, 0.05, 0)))
			elif h < -0.12 and hs > 0.94:
				pads.append(Transform3D(Basis().scaled(Vector3(0.22, 0.012, 0.22)), Vector3(x, WATER_LEVEL + 0.01, z)))
				if Sdf.hash3(iz, 4, ix) > 0.5:
					flowers.append(Transform3D(Basis().scaled(Vector3(0.05, 0.05, 0.05)), Vector3(x, WATER_LEVEL + 0.05, z)))
	root.add_child(Builders.scatter(_cyl_mesh(0.02, 1.0), reeds, REED))
	root.add_child(Builders.scatter(_sphere_mesh(0.035), heads, CATTAIL))
	root.add_child(Builders.scatter(_cyl_mesh(0.5, 1.0), pads, PAD))
	root.add_child(Builders.scatter(_sphere_mesh(1.0), flowers, PINK))
	# water surface (translucent) over the basin
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(11.4, 9.4)
	water.mesh = plane
	water.position = Vector3(0, WATER_LEVEL, 0)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.18, 0.44, 0.52, 0.55)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.05
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	water.material_override = wm
	root.add_child(water)
	return root

func _near_water(x: float, z: float) -> bool:
	for d in [Vector2(0.3, 0), Vector2(-0.3, 0), Vector2(0, 0.3), Vector2(0, -0.3)]:
		if height(x + d.x, z + d.y) < -0.08:
			return true
	return false

func _terrain() -> MeshInstance3D:
	var nx := 121
	var nz := 101
	var step := 0.1
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var grid := []
	grid.resize(nx * nz)
	for i in nx:
		for j in nz:
			var x := -6.0 + i * step
			var z := -5.0 + j * step
			grid[i * nz + j] = Vector3(x, height(x, z), z)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_c := PackedColorArray()
	for i in nx - 1:
		for j in nz - 1:
			var a: Vector3 = grid[i * nz + j]
			var b: Vector3 = grid[(i + 1) * nz + j]
			var c: Vector3 = grid[(i + 1) * nz + j + 1]
			var d: Vector3 = grid[i * nz + j + 1]
			for tri in [[a, c, b], [a, d, c]]:
				var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				if n.y < 0.0:
					n = -n
				for v: Vector3 in tri:
					out_v.append(v)
					out_n.append(n)
					out_c.append(_ground_color(v, n))
	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = out_n
	arrays[Mesh.ARRAY_COLOR] = out_c
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi

func _ground_color(v: Vector3, n: Vector3) -> Color:
	if v.y < -0.1:
		return MUD[0].lerp(MUD[1], _smooth(-0.1, -0.5, v.y))
	var g: Color = GRASS[int(absf(sin(v.x * 7.0 + v.z * 3.0)) * 4.0) % 4]
	var dirt := _smooth(0.62, 0.8, _fbm(v.x * 0.6 + 5.0, -v.z * 0.6) + 0.5)
	var c := g.lerp(DIRT, dirt)
	var steep := _smooth(0.8, 0.95, n.y)
	c = c.lerp(DIRT, 1.0 - steep)
	return MUD[0].lerp(c, _smooth(-0.1, -0.02, v.y))

func _tree(base: Vector3, height_m: float) -> Node3D:
	var root := Node3D.new()
	root.position = base
	var top := Vector3(0, height_m, 0)
	root.add_child(Builders.sdf_piece(Sdf.capsule(Vector3.ZERO, top, 0.12), Vector3(-0.3, -0.1, -0.3), top + Vector3(0.3, 0.3, 0.3), 0.025, SmoothMesh.solid(BARK)))
	var blobs := []
	for k in 9:
		var a := Sdf.hash3(base.x, k, base.z) * TAU
		var rr := 0.2 + Sdf.hash3(k, base.z, base.x) * 0.5
		blobs.append(Sdf.sphere(top + Vector3(cos(a) * rr, 0.2 + Sdf.hash3(base.z, k, 3.0) * 0.4, sin(a) * rr), 0.32 + Sdf.hash3(k, 7.0, base.x) * 0.15))
	var crown := Sdf.union(blobs)
	root.add_child(Builders.sdf_piece(crown, top - Vector3.ONE * 0.9, top + Vector3(0.9, 1.0, 0.9), 0.05,
		func(p: Vector3) -> Color: return LEAF[int(Sdf.hash3(p.x * 4.0, p.y * 4.0, p.z * 4.0) * 3.0) % 3]))
	return root

func _cyl_mesh(radius: float, h: float) -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = h
	c.radial_segments = 12
	return c

func _sphere_mesh(r: float) -> Mesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s

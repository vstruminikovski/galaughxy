class_name GardenWorld
extends RefCounted

## Backyard Garden, smooth stylised scene (metres): lawn, picket fence, flower beds,
## stepping stones, a rounded tree, bushes and a garden table with a glowing lantern.

const LAWN := [Color("#4f7a2a"), Color("#5d8a33"), Color("#466f25")]
const SOIL := Color("#5a4228")
const WOOD := Color("#a6743f")
const WOOD_DARK := Color("#7a5230")
const BARK := Color("#5b4431")
const LEAF := [Color("#3e6b23"), Color("#4f8030"), Color("#2f5a1c")]
const FLOWERS := [Color("#ff5f87"), Color("#ffd23a"), Color("#9b6bff"), Color("#ffffff"), Color("#ff8a3d")]
const STONE := Color("#9a9790")
const TABLE := Color("#c79a5e")

static func build() -> Node3D:
	var root := Node3D.new()
	# lawn with soft mown stripes
	var lawn_col := func(p: Vector3) -> Color:
		var stripe := (int(floorf((p.x + 6.0) / 1.2)) + int(floorf((p.z + 6.0) / 1.2))) % 2
		return LAWN[0] if stripe == 1 else LAWN[int(absf(sin(p.x * 12.9 + p.z * 7.1)) * 3.0) % 3]
	root.add_child(Builders.sdf_piece(Sdf.rbox(Vector3(0, -0.12, 0), Vector3(5.6, 0.12, 4.6), 0.06),
		Vector3(-5.8, -0.4, -4.8), Vector3(5.8, 0.1, 4.8), 0.07, lawn_col, false))
	# picket fence around the lawn: rounded posts and rails
	var fence := Node3D.new()
	root.add_child(fence)
	for x in range(-11, 12):
		var fx := x * 0.5
		fence.add_child(_cyl(Vector3(fx, 0.5, -4.5), 0.035, 0.5, WOOD_DARK))
		fence.add_child(_cyl(Vector3(fx, 0.5, 4.5), 0.035, 0.5, WOOD_DARK))
	for z in range(-9, 10):
		var fz := z * 0.5
		fence.add_child(_cyl(Vector3(-5.5, 0.5, fz), 0.035, 0.5, WOOD_DARK))
		fence.add_child(_cyl(Vector3(5.5, 0.5, fz), 0.035, 0.5, WOOD_DARK))
	for h in [0.35, 0.7]:
		fence.add_child(_rail(Vector3(0, h, -4.5), Vector3(11.0, 0, 0), WOOD))
		fence.add_child(_rail(Vector3(0, h, 4.5), Vector3(11.0, 0, 0), WOOD))
		fence.add_child(_rail(Vector3(-5.5, h, 0), Vector3(0, 0, 9.0), WOOD))
		fence.add_child(_rail(Vector3(5.5, h, 0), Vector3(0, 0, 9.0), WOOD))
	# stepping stones
	var stones: Array[Transform3D] = []
	for z in range(-4, 3):
		stones.append(Transform3D(Basis(), Vector3(0, 0.01, z * 0.6)))
	root.add_child(Builders.scatter(_stone_mesh(), stones, STONE))
	# flower beds with blooms
	root.add_child(Builders.sdf_piece(Sdf.rbox(Vector3(-3.7, 0.03, -2.5), Vector3(0.9, 0.05, 0.6), 0.1), Vector3(-4.8, -0.1, -3.3), Vector3(-2.7, 0.2, -1.6), 0.03, SmoothMesh.solid(SOIL)))
	var blooms: Array[Transform3D] = []
	for i in 12:
		var bx := -4.4 + (i % 4) * 0.45
		var bz := -2.9 + (i / 4) * 0.35
		blooms.append(Transform3D(Basis().scaled(Vector3(0.09, 0.09, 0.09)), Vector3(bx, 0.12, bz)))
	root.add_child(Builders.scatter(_sphere_mesh(), blooms, FLOWERS[0]))
	# tree at the back left
	var tree := Node3D.new()
	tree.position = Vector3(-3.6, 0, -0.6)
	root.add_child(tree)
	tree.add_child(_trunk(Vector3.ZERO, 2.2))
	tree.add_child(_crown(Vector3(0, 2.4, 0), 1.7))
	# bushes near the fence
	for b in [Vector3(4.0, 0.0, -3.6), Vector3(-4.0, 0.0, 3.6), Vector3(4.4, 0.0, 2.0)]:
		root.add_child(_bush(b))
	# garden table with a mug and a glowing lantern
	root.add_child(Builders.sdf_piece(Sdf.rbox(Vector3(2.0, 0.6, -1.0), Vector3(0.6, 0.04, 0.4), 0.03), Vector3(1.3, 0.5, -1.5), Vector3(2.7, 0.7, -0.5), 0.02, SmoothMesh.solid(TABLE)))
	for lx in [1.5, 2.5]:
		for lz in [-1.3, -0.7]:
			root.add_child(_cyl(Vector3(lx, 0.29, lz), 0.03, 0.29, WOOD_DARK))
	root.add_child(Builders.sdf_piece(Sdf.cyl(Vector3(2.2, 0.66, -1.0), 0.05, 0.05), Vector3(2.1, 0.55, -1.1), Vector3(2.3, 0.8, -0.9), 0.01, SmoothMesh.solid(Color("#e2574c"))))
	root.add_child(Builders.glow_piece(Sdf.sphere(Vector3(1.6, 0.7, -1.0), 0.05), Vector3(1.5, 0.6, -1.1), Vector3(1.7, 0.8, -0.9), 0.01, Color("#ffd23a")))
	return root

static func _cyl(c: Vector3, r: float, h: float, col: Color) -> Node3D:
	return Builders.sdf_piece(Sdf.cyl(c, r, h), c - Vector3(r, h, r), c + Vector3(r, h, r), 0.015, SmoothMesh.solid(col), false)

static func _rail(c: Vector3, size: Vector3, col: Color) -> Node3D:
	var half := size * 0.5 + Vector3(0.03, 0.03, 0.03)
	var rail := Builders.sdf_piece(Sdf.rbox(c, half, 0.02), c - half - Vector3.ONE * 0.05, c + half + Vector3.ONE * 0.05, 0.04, SmoothMesh.solid(col), false)
	return rail

static func _trunk(base: Vector3, height: float) -> Node3D:
	var top := base + Vector3(0, height, 0)
	var f := Sdf.capsule(base, top, 0.14)
	return Builders.sdf_piece(f, base - Vector3(0.3, 0.2, 0.3), top + Vector3(0.3, 0.2, 0.3), 0.03, SmoothMesh.solid(BARK))

static func _crown(c: Vector3, radius: float) -> Node3D:
	var blobs := []
	for k in 8:
		var a := k * TAU / 8.0
		blobs.append(Sdf.sphere(c + Vector3(cos(a) * radius * 0.5, sin(k * 1.7) * 0.25, sin(a) * radius * 0.5), radius * 0.6))
	blobs.append(Sdf.sphere(c, radius * 0.8))
	var f := Sdf.union(blobs)
	return Builders.sdf_piece(f, c - Vector3.ONE * (radius + 0.4), c + Vector3.ONE * (radius + 0.4), 0.06,
		func(p: Vector3) -> Color: return LEAF[int(absf(sin(p.x * 9.0 + p.z * 5.0)) * 3.0) % 3])

static func _bush(at: Vector3) -> Node3D:
	var f := Sdf.union([Sdf.sphere(at + Vector3(0, 0.35, 0), 0.4), Sdf.sphere(at + Vector3(0.35, 0.3, 0.1), 0.3), Sdf.sphere(at + Vector3(-0.3, 0.3, -0.1), 0.32)])
	return Builders.sdf_piece(f, at - Vector3(0.6, 0, 0.6), at + Vector3(0.7, 0.9, 0.7), 0.05,
		func(p: Vector3) -> Color: return LEAF[int(absf(sin(p.x * 13.0 + p.z * 3.0)) * 3.0) % 3])

static func _stone_mesh() -> Mesh:
	var b := BoxMesh.new()
	b.size = Vector3(0.22, 0.02, 0.2)
	return b

static func _sphere_mesh() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	return s

class_name KitchenWorld
extends RefCounted

## The Overflowing Kitchen, smooth stylised room (metres). Same layout as before.

const TEAL := Color("#4A90E2")
const GREEN := Color("#F5F2EB")
const YELLOW := Color("#FFD986")
const CREAM := Color("#F5F2EB")
const TAN := Color("#96BFEE")
const WHITE := Color("#E5E7EB")
const WOOD := Color("#FF5F56")
const FRIDGE := Color("#E5E7EB")
const TRIM := Color("#4A90E2")

static func build() -> Node3D:
	var root := Node3D.new()
	# floor: soft checker tiles from vertex colour
	var floor_col := func(p: Vector3) -> Color:
		return CREAM if (int(floorf(p.x / 0.5)) + int(floorf(p.z / 0.5))) % 2 == 0 else TAN
	root.add_child(Builders.sdf_piece(Sdf.rbox(Vector3(0, -0.05, 0), Vector3(3.1, 0.05, 2.6), 0.02),
		Vector3(-3.3, -0.2, -2.8), Vector3(3.3, 0.1, 2.8), 0.04, floor_col))
	# back wall with a window cut-out, and a left wall
	var back := Sdf.minus(Sdf.rbox(Vector3(0, 1.5, -2.65), Vector3(3.15, 1.5, 0.08), 0.05), Sdf.rbox(Vector3(0.15, 1.85, -2.65), Vector3(0.6, 0.45, 0.3), 0.04))
	root.add_child(Builders.sdf_piece(back, Vector3(-3.3, -0.1, -2.8), Vector3(3.3, 3.1, -2.5), 0.03,
		func(p: Vector3) -> Color: return TEAL if p.y < 1.1 else GREEN))
	root.add_child(Builders.sdf_piece(Sdf.rbox(Vector3(-3.1, 1.5, 0), Vector3(0.08, 1.5, 2.6), 0.05),
		Vector3(-3.3, -0.1, -2.8), Vector3(-2.9, 3.1, 2.8), 0.03,
		func(p: Vector3) -> Color: return TEAL if p.y < 1.1 else YELLOW))
	# neon trim along the back wall
	root.add_child(Builders.glow_piece(Sdf.rbox(Vector3(0, 1.1, -2.55), Vector3(3.15, 0.03, 0.02), 0.01), Vector3(-3.3, 1.0, -2.6), Vector3(3.3, 1.2, -2.5), 0.02, TRIM))
	# counter with a white worktop, stove, fridge, plant, bucket, duck
	root.add_child(_piece(Sdf.rbox(Vector3(0.2, 0.4, -2.1), Vector3(1.15, 0.4, 0.3), 0.04), Vector3(-1.0, 0, -2.5), Vector3(1.3, 0.9, -1.7), WOOD))
	root.add_child(_piece(Sdf.rbox(Vector3(0.2, 0.84, -2.1), Vector3(1.2, 0.04, 0.33), 0.02), Vector3(-1.0, 0.7, -2.5), Vector3(1.3, 0.95, -1.7), WHITE))
	root.add_child(_piece(Sdf.rbox(Vector3(-1.45, 0.45, -2.1), Vector3(0.35, 0.45, 0.3), 0.04), Vector3(-1.9, 0, -2.5), Vector3(-1.0, 1.0, -1.7), WHITE))
	root.add_child(_piece(Sdf.rbox(Vector3(-1.45, 0.92, -2.1), Vector3(0.36, 0.03, 0.31), 0.02), Vector3(-1.9, 0.85, -2.5), Vector3(-1.0, 0.98, -1.7), Color("#26262b")))
	root.add_child(_piece(Sdf.rbox(Vector3(-2.45, 0.95, -2.1), Vector3(0.35, 0.95, 0.3), 0.07), Vector3(-2.9, 0, -2.5), Vector3(-2.0, 2.0, -1.7), FRIDGE))
	root.add_child(Builders.glow_piece(Sdf.sphere(Vector3(-2.3, 1.5, -1.78), 0.03), Vector3(-2.4, 1.4, -1.85), Vector3(-2.2, 1.6, -1.7), 0.01, Color("#ff5f87")))
	root.add_child(_piece(Sdf.cyl(Vector3(2.6, 0.12, -2.1), 0.15, 0.12), Vector3(2.3, 0, -2.4), Vector3(2.9, 0.3, -1.8), Color("#c8643b")))
	root.add_child(_piece(Sdf.union([Sdf.sphere(Vector3(2.6, 0.42, -2.1), 0.2), Sdf.sphere(Vector3(2.48, 0.56, -2.1), 0.14), Sdf.sphere(Vector3(2.72, 0.58, -2.1), 0.14)]),
		Vector3(2.2, 0.2, -2.5), Vector3(3.0, 0.8, -1.7), Color("#5bbf5b")))
	root.add_child(_piece(Sdf.cyl(Vector3(1.9, 0.3, -0.6), 0.2, 0.3), Vector3(1.6, 0, -0.9), Vector3(2.2, 0.7, -0.3), Color("#3d8bd4")))
	root.add_child(_piece(Sdf.union([Sdf.ellipsoid(Vector3(-0.9, 0.14, 0.9), Vector3(0.22, 0.14, 0.2)), Sdf.sphere(Vector3(-0.7, 0.3, 0.9), 0.12)]),
		Vector3(-1.2, 0, 0.6), Vector3(-0.5, 0.5, 1.2), Color("#ffd23f")))
	return root

static func _piece(f: Callable, lo: Vector3, hi: Vector3, c: Color) -> Node3D:
	return Builders.sdf_piece(f, lo, hi, 0.02, SmoothMesh.solid(c))

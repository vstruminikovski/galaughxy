extends MapBase

## The Overflowing Kitchen, with the Backyard Patio expansion on its open right side.

const DECK_A := Color("#C99A6B")
const DECK_B := Color("#B8875A")
const WHITE := Color("#F5F2EB")
const CORAL := Color("#FF5F56")
const GRAY := Color("#2C2E33")

func build() -> void:
	add_child(KitchenWorld.build())

func build_expansion(id: String) -> Node3D:
	if id != "backyard_patio":
		return null
	var z := Node3D.new()
	var planks := func(p: Vector3) -> Color: return DECK_A if int(floorf(p.z / 0.2)) % 2 == 0 else DECK_B
	z.add_child(Builders.sdf_piece(Sdf.rbox(Vector3(4.6, -0.04, 0), Vector3(1.45, 0.04, 2.5), 0.03),
		Vector3(3.0, -0.15, -2.6), Vector3(6.2, 0.05, 2.6), 0.04, planks))
	# round table with a parasol
	z.add_child(Builders.sdf_piece(Sdf.cyl(Vector3(4.6, 0.72, 0), 0.45, 0.025), Vector3(4.1, 0.66, -0.5), Vector3(5.1, 0.78, 0.5), 0.02, SmoothMesh.solid(WHITE)))
	z.add_child(Builders.sdf_piece(Sdf.cyl(Vector3(4.6, 1.2, 0), 0.025, 1.2), Vector3(4.5, 0.0, -0.1), Vector3(4.7, 2.45, 0.1), 0.012, SmoothMesh.solid(GRAY)))
	z.add_child(Builders.sdf_piece(Sdf.cyl(Vector3(4.6, 0.03, 0), 0.25, 0.03), Vector3(4.3, -0.02, -0.3), Vector3(4.9, 0.1, 0.3), 0.02, SmoothMesh.solid(GRAY)))
	var dome := Sdf.minus(Sdf.ellipsoid(Vector3(4.6, 1.95, 0), Vector3(0.95, 0.28, 0.95)), Sdf.box(Vector3(4.6, 1.75, 0), Vector3(1.2, 0.2, 1.2)))
	z.add_child(Builders.sdf_piece(dome, Vector3(3.55, 1.85, -1.05), Vector3(5.65, 2.3, 1.05), 0.025,
		func(p: Vector3) -> Color: return CORAL if int(floorf((atan2(p.z, p.x - 4.6) + PI) / (PI / 4.0))) % 2 == 0 else WHITE))
	# two chairs, mirrored across the table
	for s in [1.0, -1.0]:
		var c := Vector3(4.6, 0.42, 0.85 * s)
		z.add_child(Builders.sdf_piece(Sdf.rbox(c, Vector3(0.24, 0.04, 0.22), 0.03), c - Vector3(0.3, 0.1, 0.3), c + Vector3(0.3, 0.1, 0.3), 0.02, SmoothMesh.solid(WHITE)))
		var back := c + Vector3(0, 0.28, 0.2 * s)
		z.add_child(Builders.sdf_piece(Sdf.rbox(back, Vector3(0.24, 0.24, 0.03), 0.03), back - Vector3(0.3, 0.3, 0.1), back + Vector3(0.3, 0.3, 0.1), 0.02, SmoothMesh.solid(WHITE)))
		for lx in [-0.18, 0.18]:
			for lz in [-0.16, 0.16]:
				var leg := Vector3(4.6 + lx, 0.2, c.z + lz)
				z.add_child(Builders.sdf_piece(Sdf.cyl(leg, 0.02, 0.2), leg - Vector3(0.05, 0.25, 0.05), leg + Vector3(0.05, 0.25, 0.05), 0.01, SmoothMesh.solid(GRAY), false))
	return z

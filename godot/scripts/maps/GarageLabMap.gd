extends MapBase

## The Mac Garage Lab: a clean studio workshop. Giant monitor backdrop, workbench, three test
## pedestals and a launch ramp. Expansion: Basement Server Room (racks with blinking LEDs).

const SILVER := Color("#E5E7EB")
const GRAY := Color("#2C2E33")
const CREAM := Color("#F5F2EB")
const BLUE := Color("#4A90E2")
const CORAL := Color("#FF5F56")
const AMBER := Color("#FFBD2E")
const MINT := Color("#27C93F")
const TILE := Color("#D5D8DE")

func build() -> void:
	# floor: light tiles with a soft grid
	var floor_col := func(p: Vector3) -> Color:
		var gx := absf(fposmod(p.x, 1.0) - 0.5) > 0.48
		var gz := absf(fposmod(p.z, 1.0) - 0.5) > 0.48
		return TILE if (gx or gz) else SILVER
	add_child(Builders.sdf_piece(Sdf.rbox(Vector3(0, -0.06, 0), Vector3(4.0, 0.06, 3.5), 0.05),
		Vector3(-4.1, -0.2, -3.6), Vector3(4.1, 0.05, 3.6), 0.05, floor_col))
	# walls: back and two mirrored sides
	add_child(Builders.sdf_piece(Sdf.rbox(Vector3(0, 1.6, -3.56), Vector3(4.05, 1.6, 0.06), 0.05),
		Vector3(-4.2, -0.1, -3.7), Vector3(4.2, 3.3, -3.4), 0.05, SmoothMesh.solid(CREAM)))
	for s in [1.0, -1.0]:
		add_child(Builders.sdf_piece(Sdf.rbox(Vector3(4.06 * s, 1.6, 0), Vector3(0.06, 1.6, 3.5), 0.05),
			Vector3(4.06 * s - 0.15, -0.1, -3.7), Vector3(4.06 * s + 0.15, 3.3, 3.7), 0.05, SmoothMesh.solid(CREAM)))
	# light strip along the top of the back wall
	add_child(Builders.glow_piece(Sdf.rbox(Vector3(0, 3.02, -3.48), Vector3(3.9, 0.025, 0.02), 0.015),
		Vector3(-4.0, 2.95, -3.55), Vector3(4.0, 3.1, -3.4), 0.015, Color("#F4FAFF")))
	_monitor()
	_workbench()
	_pedestals()
	_ramp()

func _monitor() -> void:
	var frame := Vector3(0, 1.8, -3.36)
	add_child(Builders.sdf_piece(Sdf.rbox(frame, Vector3(2.2, 1.12, 0.07), 0.1), frame - Vector3(2.35, 1.25, 0.15), frame + Vector3(2.35, 1.25, 0.15), 0.04, SmoothMesh.solid(GRAY)))
	# the screen: a glowing slab thick enough for the sample grid, standing 3 cm proud of the frame
	add_child(Builders.glow_piece(Sdf.rbox(frame + Vector3(0, 0.04, 0.07), Vector3(2.0, 0.95, 0.035), 0.03),
		frame + Vector3(-2.1, -1.0, 0.0), frame + Vector3(2.1, 1.1, 0.14), 0.025, BLUE))
	add_child(Builders.sdf_piece(Sdf.rbox(Vector3(0, 0.36, -3.45), Vector3(0.28, 0.36, 0.05), 0.04), Vector3(-0.4, -0.05, -3.55), Vector3(0.4, 0.8, -3.35), 0.025, SmoothMesh.solid(SILVER)))
	add_child(Builders.sdf_piece(Sdf.rbox(Vector3(0, 0.035, -3.2), Vector3(0.65, 0.035, 0.28), 0.03), Vector3(-0.75, -0.05, -3.55), Vector3(0.75, 0.12, -2.85), 0.025, SmoothMesh.solid(SILVER)))

func _workbench() -> void:
	var top := Vector3(-2.6, 0.9, -1.4)
	add_child(Builders.sdf_piece(Sdf.rbox(top, Vector3(0.9, 0.04, 0.45), 0.03), top - Vector3(1.0, 0.1, 0.55), top + Vector3(1.0, 0.1, 0.55), 0.025, SmoothMesh.solid(SILVER)))
	for lx in [-0.8, 0.8]:
		for lz in [-0.35, 0.35]:
			var leg := Vector3(top.x + lx, 0.43, top.z + lz)
			add_child(Builders.sdf_piece(Sdf.cyl(leg, 0.035, 0.43), leg - Vector3(0.08, 0.48, 0.08), leg + Vector3(0.08, 0.48, 0.08), 0.015, SmoothMesh.solid(GRAY), false))
	# a mug and a parts box on top
	add_child(Builders.sdf_piece(Sdf.cyl(top + Vector3(0.45, 0.11, 0.1), 0.06, 0.07), top + Vector3(0.35, 0.02, 0.0), top + Vector3(0.55, 0.22, 0.2), 0.012, SmoothMesh.solid(CORAL)))
	add_child(Builders.sdf_piece(Sdf.rbox(top + Vector3(-0.4, 0.1, -0.05), Vector3(0.18, 0.06, 0.12), 0.03), top + Vector3(-0.65, 0.0, -0.25), top + Vector3(-0.15, 0.2, 0.15), 0.015, SmoothMesh.solid(MINT)))

func _pedestals() -> void:
	var cols := [MINT, AMBER, CORAL]
	for i in 3:
		var c := Vector3(2.5, 0.12, -1.8 + i * 1.2)
		add_child(Builders.sdf_piece(Sdf.cyl(c, 0.38, 0.12), c - Vector3(0.45, 0.18, 0.45), c + Vector3(0.45, 0.18, 0.45), 0.025, SmoothMesh.solid(GRAY)))
		add_child(Builders.glow_torus(c + Vector3(0, 0.125, 0), 0.3, 0.016, cols[i]))

func _ramp() -> void:
	# a wedge rising toward the back, with rounded edges, and two amber guide stripes
	var box := Sdf.rbox(Vector3(-1.4, 0.25, 1.7), Vector3(0.6, 0.25, 0.9), 0.05)
	var slope := Sdf.plane(Vector3(-1.4, 0.0, 2.6), Vector3(0, 1.8, 0.5))
	var wedge := Sdf.smax(box, slope, 0.06)
	add_child(Builders.sdf_piece(wedge, Vector3(-2.1, -0.05, 0.7), Vector3(-0.7, 0.6, 2.7), 0.03,
		func(p: Vector3) -> Color: return AMBER if absf(absf(p.x + 1.4) - 0.42) < 0.06 else SILVER))

func build_expansion(id: String) -> Node3D:
	if id != "basement_server_room":
		return null
	var z := Node3D.new()
	for i in 2:
		var c := Vector3(3.55, 1.0, 1.6 + i * 1.0)
		z.add_child(Builders.sdf_piece(Sdf.rbox(c, Vector3(0.32, 1.0, 0.42), 0.05), c - Vector3(0.4, 1.1, 0.5), c + Vector3(0.4, 1.1, 0.5), 0.04, SmoothMesh.solid(GRAY)))
		for row in 6:
			var led := Vector3(3.22, 0.4 + row * 0.26, c.z)
			var col: Color = [MINT, AMBER, MINT, BLUE, MINT, CORAL][row]
			z.add_child(Builders.glow_piece(Sdf.rbox(led, Vector3(0.012, 0.02, 0.3), 0.01), led - Vector3(0.03, 0.04, 0.32), led + Vector3(0.03, 0.04, 0.32), 0.01, col))
	# floor hatch down to the basement
	var hatch := Vector3(2.6, 0.005, 2.2)
	z.add_child(Builders.sdf_piece(Sdf.rbox(hatch, Vector3(0.45, 0.01, 0.35), 0.008), hatch - Vector3(0.5, 0.03, 0.4), hatch + Vector3(0.5, 0.03, 0.4), 0.01, SmoothMesh.solid(Color("#1B1E24")), false))
	z.add_child(Builders.glow_torus(hatch + Vector3(0, 0.014, 0), 0.4, 0.012, MINT))
	return z

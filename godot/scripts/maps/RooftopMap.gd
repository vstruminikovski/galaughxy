extends MapBase

## Skyline Rooftop Terrace at golden hour: tiled deck, parapet, a raised pool (the flood gag
## spills it over), a fountain, loungers, planters, string lights and a city skyline.
## Expansion: Helipad.

const TILE_A := Color("#EADFCB")
const TILE_B := Color("#DCCDB4")
const WALL := Color("#D2BFA3")
const POOL := Color("#BFE6E0")
const WATER := Color(0.29, 0.62, 0.89, 0.7)
const WHITE := Color("#F5F2EB")
const GRAY := Color("#2C2E33")
const CORAL := Color("#FF5F56")
const AMBER := Color("#FFBD2E")
const LEAF := Color("#5E9E4F")
const CITY := [Color("#8E8AA3"), Color("#9FA4B8"), Color("#B39C9A"), Color("#7F879C")]

func build() -> void:
	var tiles := func(p: Vector3) -> Color:
		return TILE_A if (int(floorf(p.x / 0.8)) + int(floorf(p.z / 0.8))) % 2 == 0 else TILE_B
	add_child(Builders.sdf_piece(Sdf.rbox(Vector3(0, -0.1, 0), Vector3(6.0, 0.1, 5.0), 0.06),
		Vector3(-6.1, -0.3, -5.1), Vector3(6.1, 0.05, 5.1), 0.06, tiles))
	add_child(Builders.sdf_piece(Sdf.rbox(Vector3(0, 0.4, -5.08), Vector3(6.1, 0.4, 0.1), 0.06),
		Vector3(-6.3, -0.1, -5.3), Vector3(6.3, 0.9, -4.9), 0.05, SmoothMesh.solid(WALL)))
	for s in [1.0, -1.0]:
		add_child(Builders.sdf_piece(Sdf.rbox(Vector3(6.08 * s, 0.4, 0), Vector3(0.1, 0.4, 5.1), 0.06),
			Vector3(6.08 * s - 0.2, -0.1, -5.3), Vector3(6.08 * s + 0.2, 0.9, 5.3), 0.05, SmoothMesh.solid(WALL)))
	_pool(Vector3(2.4, 0, 1.0))
	_fountain(Vector3(-2.4, 0, 1.0))
	for s in [1.0, -1.0]:
		_lounger(Vector3(4.7 * s, 0, 3.0))
		_planter(Vector3(5.3 * s, 0, -4.3))
	_lights()
	_skyline()

func _pool(c: Vector3) -> void:
	var tub := Sdf.minus(Sdf.rbox(c + Vector3(0, 0.2, 0), Vector3(1.4, 0.2, 0.95), 0.1), Sdf.rbox(c + Vector3(0, 0.36, 0), Vector3(1.25, 0.3, 0.8), 0.08))
	add_child(Builders.sdf_piece(tub, c - Vector3(1.5, 0.05, 1.05), c + Vector3(1.5, 0.5, 1.05), 0.035, SmoothMesh.solid(POOL)))
	add_child(_water(c + Vector3(0, 0.3, 0), Vector2(2.4, 1.5)))

func _fountain(c: Vector3) -> void:
	var basin := Sdf.minus(Sdf.cyl(c + Vector3(0, 0.15, 0), 0.75, 0.15), Sdf.cyl(c + Vector3(0, 0.3, 0), 0.62, 0.15))
	add_child(Builders.sdf_piece(basin, c - Vector3(0.85, 0.05, 0.85), c + Vector3(0.85, 0.4, 0.85), 0.02, SmoothMesh.solid(WHITE)))
	add_child(Builders.sdf_piece(Sdf.cyl(c + Vector3(0, 0.45, 0), 0.07, 0.3), c + Vector3(-0.15, 0.1, -0.15), c + Vector3(0.15, 0.8, 0.15), 0.015, SmoothMesh.solid(WHITE)))
	var bowl := Sdf.minus(Sdf.ellipsoid(c + Vector3(0, 0.78, 0), Vector3(0.34, 0.12, 0.34)), Sdf.ellipsoid(c + Vector3(0, 0.87, 0), Vector3(0.25, 0.07, 0.25)))
	add_child(Builders.sdf_piece(bowl, c + Vector3(-0.42, 0.6, -0.42), c + Vector3(0.42, 0.95, 0.42), 0.012, SmoothMesh.solid(WHITE)))
	add_child(_pool_disc(c + Vector3(0, 0.25, 0), 0.6))
	add_child(_pool_disc(c + Vector3(0, 0.86, 0), 0.22))

## Round water surface (Godot's cylinder: exactly round).
func _pool_disc(at: Vector3, radius: float) -> MeshInstance3D:
	var m := _water(at, Vector2.ONE)
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.01
	disc.radial_segments = 64
	m.mesh = disc
	return m

func _water(at: Vector3, size: Vector2) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	m.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WATER
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	m.material_override = mat
	m.position = at
	return m

func _lounger(c: Vector3) -> void:
	var seat := c + Vector3(0, 0.3, 0)
	add_child(Builders.sdf_piece(Sdf.rbox(seat, Vector3(0.32, 0.05, 0.75), 0.04), seat - Vector3(0.4, 0.1, 0.85), seat + Vector3(0.4, 0.1, 0.85), 0.02, SmoothMesh.solid(WHITE)))
	var back := Sdf.rbox(c + Vector3(0, 0.55, -0.62), Vector3(0.32, 0.25, 0.05), 0.04)
	add_child(Builders.sdf_piece(back, c + Vector3(-0.4, 0.25, -0.75), c + Vector3(0.4, 0.85, -0.5), 0.02, SmoothMesh.solid(WHITE)))
	add_child(Builders.sdf_piece(Sdf.rbox(seat + Vector3(0, 0.07, 0.15), Vector3(0.28, 0.025, 0.5), 0.025), seat + Vector3(-0.35, 0.0, -0.4), seat + Vector3(0.35, 0.15, 0.7), 0.015, SmoothMesh.solid(CORAL)))
	for lx in [-0.26, 0.26]:
		for lz in [-0.6, 0.6]:
			var leg := Vector3(c.x + lx, 0.13, c.z + lz)
			add_child(Builders.sdf_piece(Sdf.cyl(leg, 0.025, 0.13), leg - Vector3(0.05, 0.16, 0.05), leg + Vector3(0.05, 0.16, 0.05), 0.012, SmoothMesh.solid(GRAY), false))

func _planter(c: Vector3) -> void:
	add_child(Builders.sdf_piece(Sdf.rbox(c + Vector3(0, 0.3, 0), Vector3(0.45, 0.3, 0.45), 0.06), c - Vector3(0.55, 0.05, 0.55), c + Vector3(0.55, 0.7, 0.55), 0.03, SmoothMesh.solid(WALL)))
	var bush := Sdf.smin(Sdf.sphere(c + Vector3(0, 0.85, 0), 0.38), Sdf.smin(Sdf.sphere(c + Vector3(0.22, 0.75, 0), 0.26), Sdf.sphere(c + Vector3(-0.22, 0.75, 0), 0.26), 0.1), 0.12)
	add_child(Builders.sdf_piece(bush, c + Vector3(-0.6, 0.4, -0.5), c + Vector3(0.6, 1.3, 0.5), 0.03, SmoothMesh.solid(LEAF)))

func _lights() -> void:
	# poles at the back corners, a sagging string of warm bulbs between them
	for s in [1.0, -1.0]:
		var pole := Vector3(5.75 * s, 1.25, -4.75)
		add_child(Builders.sdf_piece(Sdf.cyl(pole, 0.04, 1.25), pole - Vector3(0.1, 1.3, 0.1), pole + Vector3(0.1, 1.3, 0.1), 0.02, SmoothMesh.solid(GRAY), false))
	var bulbs := []
	for i in 25:
		var x := -5.7 + i * (11.4 / 24.0)
		var sag := 0.45 * (1.0 - pow(x / 5.7, 2.0))
		bulbs.append(Transform3D(Basis().scaled(Vector3.ONE * 0.08), Vector3(x, 2.42 - sag, -4.75)))
	var sphere := SphereMesh.new()
	sphere.radial_segments = 24
	sphere.rings = 12
	var mm := Builders.scatter(sphere, bulbs, AMBER)
	var m := mm.material_override as StandardMaterial3D
	m.emission_enabled = true
	m.emission = AMBER
	m.emission_energy_multiplier = 2.5
	add_child(mm)

func _skyline() -> void:
	# mirrored blocks of towers far behind the terrace
	var towers := [[2.0, 7.5, 1.6], [4.8, 10.0, 2.0], [7.6, 6.0, 1.8], [10.4, 12.0, 2.2], [13.6, 8.0, 2.0]]
	for s in [1.0, -1.0]:
		for i in towers.size():
			var tw: Array = towers[i]
			var c := Vector3(tw[0] * s * 1.6, tw[1] * 0.5 - 7.0, -30.0 - (i % 2) * 4.0)
			var half := Vector3(tw[2] * 0.5, tw[1] * 0.5, 1.2)
			add_child(Builders.sdf_piece(Sdf.rbox(c, half, 0.25), c - half - Vector3.ONE * 0.3, c + half + Vector3.ONE * 0.3, 0.2,
				SmoothMesh.solid(CITY[i % CITY.size()]), false))
	add_child(Builders.sdf_piece(Sdf.rbox(Vector3(0, -0.5, -36.0), Vector3(1.4, 6.5, 1.4), 0.3), Vector3(-1.8, -7.2, -37.8), Vector3(1.8, 6.3, -34.2), 0.2, SmoothMesh.solid(CITY[1]), false))

func build_expansion(id: String) -> Node3D:
	if id != "helipad":
		return null
	var z := Node3D.new()
	var c := Vector3(-3.6, 0.0, -2.7)
	z.add_child(Builders.sdf_piece(Sdf.cyl(c + Vector3(0, 0.03, 0), 1.25, 0.03), c - Vector3(1.35, 0.05, 1.35), c + Vector3(1.35, 0.12, 1.35), 0.025, SmoothMesh.solid(GRAY)))
	# the H, built from three bars
	for s in [1.0, -1.0]:
		var bar := c + Vector3(0.32 * s, 0.065, 0)
		z.add_child(Builders.sdf_piece(Sdf.rbox(bar, Vector3(0.07, 0.008, 0.48), 0.007), bar - Vector3(0.12, 0.03, 0.55), bar + Vector3(0.12, 0.03, 0.55), 0.01, SmoothMesh.solid(WHITE), false))
	z.add_child(Builders.sdf_piece(Sdf.rbox(c + Vector3(0, 0.065, 0), Vector3(0.3, 0.008, 0.07), 0.007), c + Vector3(-0.35, 0.04, -0.12), c + Vector3(0.35, 0.09, 0.12), 0.01, SmoothMesh.solid(WHITE), false))
	z.add_child(Builders.glow_torus(c + Vector3(0, 0.07, 0), 1.12, 0.02, AMBER))
	return z

extends Node3D

## Entry point. Builds the garden room + robo as voxel meshes with rounded outlines,
## frames a static camera, and can save a screenshot for checking (--shot <path>).

const CELL := 0.1
const SKY := Color("#a9d3ea")

func _ready() -> void:
	RenderingServer.set_default_clear_color(SKY)
	_light()
	_camera()
	_world()
	_maybe_shot()

func _light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = false # no shadow artefacts
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#dff1ff")
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

func _camera() -> void:
	var cam := Camera3D.new()
	cam.name = "Static"
	cam.fov = 38
	cam.position = Vector3(0, 1.6, 5.5)
	add_child(cam)
	cam.look_at(Vector3(0, 0.7, 0), Vector3.UP)
	cam.current = true

func _world() -> void:
	_add_voxels(GardenWorld.build(), CELL, Vector3.ZERO, Color("#7a1f1f"))
	_add_voxels(RoboParts.assembled(Color("#4aa3df")), CELL * 0.7, Vector3(0, 0, 0.3), Color("#7a1f1f"))

func _add_voxels(voxels: Dictionary, size: float, at: Vector3, ink: Color) -> void:
	var mesh := VoxelMesh.build(voxels, size)
	var hull := Outline.hull(mesh, size * 0.18)
	var root := Node3D.new()
	root.position = at
	add_child(root)

	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = _lit_material()
	root.add_child(body)

	var rim := MeshInstance3D.new()
	rim.mesh = hull
	rim.material_override = _ink_material(ink)
	root.add_child(rim)

func _lit_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	return m

func _ink_material(ink: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = ink
	m.cull_mode = BaseMaterial3D.CULL_FRONT # draw only the rim of the shell
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _maybe_shot() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i < 0 or i + 1 >= args.size():
		return
	var path: String = args[i + 1]
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[shot] saved ", path)
	get_tree().quit()

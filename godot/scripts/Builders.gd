class_name Builders
extends RefCounted

## Node helpers for smooth stylised scenery (surfaces from signed distance fields, plus
## MultiMesh scatter for small repeated pieces such as reeds, pads and flowers).

static func lit_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.7
	return m

static func ink_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

## A smooth SDF surface with its rounded ink rim. Returns a Node3D positioned at origin.
static func sdf_piece(f: Callable, lo: Vector3, hi: Vector3, step: float, color: Callable, ink := true, thick := 0.012) -> Node3D:
	var mesh := SmoothMesh.build(f, lo - Vector3.ONE * 0.1, hi + Vector3.ONE * 0.1, step, color)
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = lit_material()
	n.add_child(body)
	if ink and mesh.get_surface_count() > 0:
		var rim := MeshInstance3D.new()
		rim.mesh = Outline.hull(mesh, thick)
		rim.material_override = ink_material(Color("#7a1f1f"))
		n.add_child(rim)
	return n

## A glowing SDF surface (emissive, no ink).
static func glow_piece(f: Callable, lo: Vector3, hi: Vector3, step: float, color: Color) -> Node3D:
	var mesh := SmoothMesh.build(f, lo - Vector3.ONE * 0.1, hi + Vector3.ONE * 0.1, step, SmoothMesh.solid(color))
	var n := MeshInstance3D.new()
	n.mesh = mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.4
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	n.material_override = m
	return n

## Scatter one mesh many times (reeds, pads, flowers). transforms: Array[Transform3D].
static func scatter(mesh: Mesh, transforms: Array, color: Color) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	inst.material_override = m
	return inst

static func box_bounds(c: Vector3, half: Vector3, pad := 0.05) -> Array:
	return [c - half - Vector3(pad, pad, pad), c + half + Vector3(pad, pad, pad)]

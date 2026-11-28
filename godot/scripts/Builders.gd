class_name Builders
extends RefCounted

## Node helpers for smooth stylised scenery (surfaces from signed distance fields, plus
## MultiMesh scatter for small repeated pieces such as reeds, pads and flowers).

static func lit_material() -> Material:
	return Style.toon(Color.WHITE, true, {"kind": "set"})

static func ink_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

## A smooth SDF surface with its rounded ink rim. Returns a Node3D positioned at origin.
static func sdf_piece(f: Callable, lo: Vector3, hi: Vector3, step: float, color: Callable, ink := true, thick := 0.009) -> Node3D:
	var mesh := SmoothMesh.build(f, lo - Vector3.ONE * 0.1, hi + Vector3.ONE * 0.1, step, color)
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = lit_material()
	n.add_child(body)
	if ink and mesh.get_surface_count() > 0:
		var r := Ink.rim(mesh, thick, [], [], true)
		Ink.follow(r, body.material_override)
		n.add_child(r)
	return n

## A glowing SDF surface (emissive, no ink).
static func glow_piece(f: Callable, lo: Vector3, hi: Vector3, step: float, color: Color) -> Node3D:
	var mesh := SmoothMesh.build(f, lo - Vector3.ONE * 0.1, hi + Vector3.ONE * 0.1, step, SmoothMesh.solid(color))
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = Style.glow(color)
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
	inst.material_override = Style.toon(color)
	return inst

static func box_bounds(c: Vector3, half: Vector3, pad := 0.05) -> Array:
	return [c - half - Vector3(pad, pad, pad), c + half + Vector3(pad, pad, pad)]

## Glowing ring lying flat (Godot's TorusMesh: exactly round, cheap). R = ring radius, r = tube radius.
static func glow_torus(c: Vector3, major: float, minor: float, color: Color) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = major - minor
	t.outer_radius = major + minor
	t.rings = 96
	t.ring_segments = 16
	var m := MeshInstance3D.new()
	m.mesh = t
	m.material_override = Style.glow(color)
	m.position = c
	return m

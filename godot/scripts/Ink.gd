class_name Ink
extends RefCounted

## The one place every outline is made. Each rim uses the shared boiling ink shader, so every
## object (robo, frog, rooms, props, anything spawned later) gets the same hand-drawn line.

static var _material: ShaderMaterial

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/ink_boil.gdshader")
		_material.set_shader_parameter("ink_color", Color(0.48, 0.12, 0.12, 1.0))
	return _material

## Rounded rim for a closed mesh. `thick` is the rim width in the mesh's own units.
static func rim(mesh: ArrayMesh, thick: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = Outline.hull(mesh, thick)
	var mat := material().duplicate() as ShaderMaterial
	mat.set_shader_parameter("thickness", thick)
	m.material_override = mat
	return m

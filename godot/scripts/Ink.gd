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

## Rim for a closed mesh. `thick` (mesh units) only sets how widely normals are smoothed;
## the drawn width is in screen pixels (shader `width_px`), so lines stay thin at any distance.
static func rim(mesh: ArrayMesh, thick: float, occ_c: Array = [], occ_r: Array = []) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = Outline.hull(mesh, thick)
	var mat := material().duplicate() as ShaderMaterial
	mat.set_shader_parameter("thickness", thick)
	# body ellipsoids that hide this rim (limbs pass the body; the body itself passes none)
	var c := []
	var r := []
	for i in 4:
		c.append(occ_c[i] if i < occ_c.size() else Vector4.ZERO)
		r.append(occ_r[i] if i < occ_r.size() else Vector4(1, 1, 1, 0))
	mat.set_shader_parameter("occ_n", mini(occ_c.size(), 4))
	mat.set_shader_parameter("occ_c", c)
	mat.set_shader_parameter("occ_r", r)
	m.material_override = mat
	return m

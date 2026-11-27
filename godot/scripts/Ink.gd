class_name Ink
extends RefCounted

## The one place every outline is made. Every object built with Builders.sdf_piece or Main._piece
## (robo, frog, rooms, props, anything spawned later) gets the same grease-pencil strokes.

static var _material: ShaderMaterial

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/ink_stroke.gdshader")
		_material.set_shader_parameter("ink_color", Color(0.48, 0.12, 0.12, 1.0))
	return _material

## Strokes traced from a closed mesh's outline (see InkStroke.gd). `thick` is kept for callers;
## the drawn width is in screen pixels (shader `width_px`). `occ_c`/`occ_r` are body ellipsoids
## (body space) that hide this object's strokes; the body itself passes none.
static func rim(mesh: ArrayMesh, _thick: float = 0.0, occ_c: Array = [], occ_r: Array = []) -> MeshInstance3D:
	var s := InkStroke.new()
	s.setup(mesh)
	var mat := material().duplicate() as ShaderMaterial
	var c := []
	var r := []
	for i in 4:
		c.append(occ_c[i] if i < occ_c.size() else Vector4.ZERO)
		r.append(occ_r[i] if i < occ_r.size() else Vector4(1, 1, 1, 0))
	mat.set_shader_parameter("occ_n", mini(occ_c.size(), 4))
	mat.set_shader_parameter("occ_c", c)
	mat.set_shader_parameter("occ_r", r)
	s.material_override = mat
	return s

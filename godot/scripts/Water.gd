class_name Water
extends Node3D

## Flood plane for the chaos stages. Smooth surface that rises and bobs gently.

var mesh_inst: MeshInstance3D

func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(14, 12)
	mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = plane
	var m := StandardMaterial3D.new()
	var c := Style.swatch("bondi_blue", "light")
	m.albedo_color = Color(c.r, c.g, c.b, 0.62)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.06
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = m
	add_child(mesh_inst)
	visible = false

func set_level(height_m: float, t: float) -> void:
	visible = height_m > 0.004
	position.y = height_m + sin(t * 2.0) * 0.005

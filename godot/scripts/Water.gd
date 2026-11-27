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
	m.albedo_color = Color(0.25, 0.65, 0.84, 0.62)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.06
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = m
	add_child(mesh_inst)
	visible = false

func set_level(height_m: float, t: float) -> void:
	visible = height_m > 0.004
	position.y = height_m + sin(t * 2.0) * 0.005

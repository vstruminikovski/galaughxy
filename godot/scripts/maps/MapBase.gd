class_name MapBase
extends Node3D

## One map. Main instances the map's .tscn into its MapContainer; the map builds its own set in
## _ready, reports ground height, spawn points (Marker3D children named Spawn*), and builds
## expansion zones on demand. Add a map: a .tscn + a script extending this + an entry in
## res://data/maps.json.

var _expansions := {}

func _ready() -> void:
	build()

## Builds the permanent set. Override.
func build() -> void:
	pass

## Ground height under (x, z). Override for uneven terrain.
func ground(_x: float, _z: float) -> float:
	return 0.0

func spawn_points() -> Array:
	var out := []
	for c in get_children():
		if c is Marker3D and String(c.name).begins_with("Spawn"):
			out.append((c as Marker3D).position)
	return out

## Builds the zone for an expansion id. Override; return null for unknown ids.
func build_expansion(_id: String) -> Node3D:
	return null

func set_expansion(id: String, on: bool) -> void:
	if on and not _expansions.has(id):
		var zone := build_expansion(id)
		if zone == null:
			return
		zone.name = "Expansion_" + id
		add_child(zone)
		_expansions[id] = zone
		zone.scale = Vector3.ONE * 0.01
		var tw := create_tween()
		tw.tween_property(zone, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif _expansions.has(id):
		(_expansions[id] as Node3D).visible = on

func expansion_on(id: String) -> bool:
	return _expansions.has(id) and (_expansions[id] as Node3D).visible

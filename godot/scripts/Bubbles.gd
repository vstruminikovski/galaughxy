class_name Bubbles
extends Node3D

## Comic reaction bubbles over characters' heads (CLAUDE.md section 25; after DOGWALK's emote bubbles,
## Blender Studio, CC-BY 4.0).
## - Ten icons, drawn procedurally in shaders/bubble.gdshader: ! ? heart sweat anger dizzy … idea
##   note sparkle.
## - One bubble per character; a new one replaces the old.
## - Pop-in, wobble, bob and pop-out are pure functions of the studio clock, so scrubbing and movie
##   export replay them exactly.
## Triggered by the keypad (KP 1–9, 0), Character ▸ Emotes, or a Director event:
## {"action": "bubble", "actor": id, "value": "heart", "duration": 1.8}

const IDS := ["exclaim", "question", "heart", "sweat", "anger", "dizzy", "dots", "idea", "note", "sparkle"]
const LABELS := {"exclaim": "❗", "question": "❓", "heart": "❤️", "sweat": "💧", "anger": "💢", "dizzy": "🌀",
	"dots": "💬", "idea": "💡", "note": "🎵", "sparkle": "✨"}
const NAMES := {"exclaim": "Surprise !", "question": "Huh ?", "heart": "Love", "sweat": "Nervous sweat", "anger": "Anger",
	"dizzy": "Dizzy", "dots": "Speechless …", "idea": "Idea", "note": "Humming", "sparkle": "Delight"}
## Palette family for each icon (Style.swatch name, value).
const TINTS := {"exclaim": ["coral", "base"], "question": ["bondi_blue", "base"], "heart": ["coral", "base"],
	"sweat": ["bondi_blue", "light"], "anger": ["coral", "base"], "dizzy": ["space_gray", "base"],
	"dots": ["space_gray", "base"], "idea": ["amber", "base"], "note": ["bondi_blue", "shade"], "sparkle": ["amber", "base"]}
const POP_IN := 0.22
const POP_OUT := 0.18

var main: Node
var _live := {}      # actor -> {node, id, start, life}
var _quad: QuadMesh
var _shader: Shader

func _init(m: Node) -> void:
	main = m
	_quad = QuadMesh.new()
	_quad.size = Vector2(1, 1)
	_shader = load("res://shaders/bubble.gdshader")

## Shows bubble `id` over character n for `life` seconds (studio clock).
func show_bubble(n: Node3D, id: String, life := 1.8) -> void:
	if n == null or not IDS.has(id):
		return
	var b: Dictionary = _live.get(n, {})
	var mi: MeshInstance3D = b.get("node")
	if mi == null or not is_instance_valid(mi):
		mi = MeshInstance3D.new()
		mi.mesh = _quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
		var m := ShaderMaterial.new()
		m.shader = _shader
		m.render_priority = 2
		mi.material_override = m
		add_child(mi)
	var mat := mi.material_override as ShaderMaterial
	var tint: Array = TINTS[id]
	mat.set_shader_parameter("icon", IDS.find(id))
	mat.set_shader_parameter("tint", Style.swatch(String(tint[0]), String(tint[1])))
	mat.set_shader_parameter("paper", Style.swatch("cream", "light"))
	_live[n] = {"node": mi, "id": id, "start": float(main.t), "life": life}
	tick()

## The bubble id showing over n, or "".
func showing(n: Node3D) -> String:
	var b: Dictionary = _live.get(n, {})
	if b.is_empty() or not (b["node"] as Node3D).visible:
		return ""
	return String(b["id"])

func clear() -> void:
	for n in _live:
		var mi: MeshInstance3D = _live[n]["node"]
		if is_instance_valid(mi):
			mi.queue_free()
	_live.clear()

## Per frame (after the poses): follow the heads and animate from the clock.
func tick() -> void:
	var cam: Camera3D = main.cam
	for n in _live.keys():
		var b: Dictionary = _live[n]
		var mi: MeshInstance3D = b["node"]
		if not is_instance_valid(n) or not is_instance_valid(mi):
			if is_instance_valid(mi):
				mi.queue_free()
			_live.erase(n)
			continue
		var age: float = float(main.t) - float(b["start"])
		var life: float = b["life"]
		if age < 0.0 or age > life or not (n as Node3D).is_visible_in_tree():
			mi.visible = false
			continue
		mi.visible = true
		var pop := _pop(age, life)
		var h: float = main.height_of(n)
		var head: Vector3 = main.head_pos(n)
		var right := cam.global_transform.basis.x
		var side := 1.0 if (head - cam.global_position).dot(right) <= 0.0 else -1.0
		var dist := cam.global_position.distance_to(head)
		var size := 0.36 * clampf(h / 0.55, 0.75, 1.5) * clampf(dist / 3.0, 1.0, 2.4)
		var bob := sin(age * 5.0) * 0.012 * size / 0.36
		mi.global_position = head + Vector3(0, h * 0.2 + size * 0.55 + bob, 0) - right * side * size * 0.32
		mi.scale = Vector3.ONE * size * pop
		var mat := mi.material_override as ShaderMaterial
		mat.set_shader_parameter("age", age)
		mat.set_shader_parameter("side", side)
		mat.set_shader_parameter("tilt", sin(age * 11.0) * 0.14 * exp(-age * 3.5) + sin(age * 2.2) * 0.025)

## 0 -> 1.15 -> 1 on the way in, shrinking away at the end.
static func _pop(age: float, life: float) -> float:
	var k := 1.0
	if age < POP_IN:
		var x := age / POP_IN
		k = sin(x * PI * 0.5) * 1.15 if x < 0.7 else lerpf(1.15, 1.0, (x - 0.7) / 0.3)
	var out := life - age
	if out < POP_OUT:
		k *= clampf(out / POP_OUT, 0.0, 1.0)
	return maxf(k, 0.001)

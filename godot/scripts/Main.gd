extends Node3D

## Galaughxy controller: scenes, portals, cameras (static / slider / drone / free-fly),
## the robo and the frog, flood chaos, touch + keyboard controls, and the world map.
## Ported from the Three.js studio (src/ui/Stage.tsx, GameHUD.tsx, CameraRigs.tsx, ...).

const SCENES := {
	"kitchen": {"title": "The Overflowing Kitchen", "tag": "flood the kitchen!", "sky": Color("#8fc4e8"), "map": Vector2(24, 62), "icon": "🍳", "portals": ["pond"]},
	"pond": {"title": "Pond Life", "tag": "a nature mockumentary", "sky": Color("#b9cfc4"), "map": Vector2(72, 40), "icon": "🐸", "portals": ["kitchen", "garden"]},
	"garden": {"title": "Backyard Garden", "tag": "lawn, fence, tiny tree", "sky": Color("#a9d3ea"), "map": Vector2(30, 24), "icon": "🌷", "portals": ["pond"]},
}
const ORDER := ["kitchen", "pond", "garden"]
const CAMS := {
	"kitchen": {"static": [Vector3(0, 1.7, 7.2), Vector3(0, 1.0, 0), 38.0], "slider": [Vector3(-2.6, 1.3, 3.6), Vector3(2.6, 1.3, 3.6), Vector3(0, -0.25, -3.6), 38.0], "drone": [Vector3(0, 0.4, 0), 6.5, 5.5, 38.0]},
	"pond": {"static": [Vector3(0.35, 0.55, 3.9), Vector3(-0.3, 0.28, 1.2), 22.0], "slider": [Vector3(-1.8, 0.45, 3.4), Vector3(1.6, 0.45, 3.4), Vector3(0, -0.18, -2.2), 26.0], "drone": [Vector3(0.3, 0, -0.8), 6.2, 3.8, 34.0]},
	"garden": {"static": [Vector3(0, 1.6, 5.5), Vector3(0, 0.7, 0), 38.0], "slider": [Vector3(-3.2, 1.3, 4.2), Vector3(3.2, 1.3, 4.2), Vector3(0, -0.3, -4.0), 38.0], "drone": [Vector3(0, 0, 0), 7.0, 5.0, 38.0]},
}
const EXPRS := ["DEADPAN", "SMIRK", "PANIC", "ANGRY", "HAPPY", "SHOCKED"]
const LIDS := {
	"DEADPAN": [-0.3, -0.3, 0.0, 1.0], "SMIRK": [-0.2, -1.0, 0.15, 1.0], "PANIC": [-1.45, -1.45, 0.0, 1.22],
	"ANGRY": [-0.4, -0.4, 0.5, 0.95], "HAPPY": [-0.05, -0.05, -0.25, 1.0], "SHOCKED": [-1.55, -1.55, 0.0, 1.3],
}
const WALK := 1.7
const HOP := 1.1
const FROG_SIZE := 0.03
const ROBO_SIZE := 0.07
const ROOM_SIZE := 0.1

var scene_name := ""
var world: Node3D
var env: Environment
var cam: Camera3D
var rig := "static"
var fly_pos := Vector3.ZERO
var fly_yaw := 0.0
var fly_pitch := 0.0
var look := Vector2.ZERO
var actor: Node3D
var actor_kind := ""
var actor_pos := Vector3.ZERO
var actor_yaw := 0.0
var actor_moving := 0.0
var actor_hop := 0.0
var hop_lift := 0.0
var jaw := 0.0
var expr_i := 0
var talk := false
var water: Water
var flood := 0.0
var flood_target := 0.0
var stage := 0
var t := 0.0
var slider_t := 0.0
var map_open := false
var pond: PondWorld
var frog_parts := {}
var robo_parts := {}
var portal_nodes := []
var hud_label: Label
var map_panel: Panel
var keys := {}
var joy_id := -1
var joy_origin := Vector2.ZERO
var joy_vec := Vector2.ZERO
var look_id := -1
var last_look := Vector2.ZERO
var test_runner: SelfTest
var joy_pad: JoyPad

func _ready() -> void:
	_setup_environment()
	_setup_camera()
	_setup_hud()
	water = Water.new()
	add_child(water)
	var args := OS.get_cmdline_user_args()
	var start := "garden"
	if args.has("--scene"):
		start = args[args.find("--scene") + 1]
	load_scene(start)
	if args.has("--rig"):
		_set_rig(args[args.find("--rig") + 1])
	if args.has("--shot"):
		_shot_and_quit(args[args.find("--shot") + 1])
	if args.has("--test"):
		test_runner = SelfTest.new(self)
		test_runner.run()

func _shot_and_quit(path: String) -> void:
	for i in 60:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("[shot] ", path)
	get_tree().quit()

# ── environment ───────────────────────────────────────────────────────────────────
func _setup_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = false
	add_child(sun)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#dff1ff")
	env.ambient_light_energy = 0.55
	we.environment = env
	add_child(we)

func _setup_camera() -> void:
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 200.0
	add_child(cam)
	cam.current = true

# ── scenes ────────────────────────────────────────────────────────────────────────
func load_scene(name: String) -> void:
	if world:
		world.queue_free()
	scene_name = name
	world = Node3D.new()
	add_child(world)
	env.background_color = SCENES[name]["sky"]
	RenderingServer.set_default_clear_color(SCENES[name]["sky"])
	portal_nodes.clear()
	flood = 0.0
	flood_target = 0.0
	stage = 0
	slider_t = 0.0
	look = Vector2.ZERO
	match name:
		"kitchen":
			world.add_child(KitchenWorld.build())
			_spawn_robo(Vector3(0, 0, 0.3))
			_portal(Vector3(-2.95, 0, 0.9), -PI / 2, "pond")
		"garden":
			world.add_child(GardenWorld.build())
			_spawn_robo(Vector3(0, 0, 0.3))
			_portal(Vector3(0, 0, -4.8), 0.0, "pond")
		"pond":
			pond = PondWorld.new()
			world.add_child(pond.build())
			_spawn_frog(Vector3(-0.3, 0, 1.2))
			_portal(Vector3(-5.4, 0, 3.6), PI / 2, "kitchen")
			_portal(Vector3(5.4, 0, -3.4), -PI / 2, "garden")
	_update_hud()

func _piece(mesh: ArrayMesh, ink: Color, thick := 0.012) -> Node3D:
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = _lit()
	n.add_child(body)
	var rim := MeshInstance3D.new()
	rim.mesh = Outline.hull(mesh, thick)
	rim.material_override = _ink(ink)
	n.add_child(rim)
	return n

func _lit() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.7
	return m

## One smooth part as a node on its pivot: surface, glow (emissive) or lit, plus rounded ink.
func _smooth_part(part: Dictionary, thick: float) -> Node3D:
	var pivot: Vector3 = part["pivot"]
	var mesh := SmoothMesh.build(part["sdf"], part["lo"], part["hi"], part["step"], part["color"], pivot)
	var n := Node3D.new()
	n.position = pivot
	if part.get("glow", false):
		var g := MeshInstance3D.new()
		g.mesh = mesh
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.emission_enabled = true
		m.emission_energy_multiplier = 1.6
		m.emission_texture = null
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		g.material_override = m
		n.add_child(g)
		return n
	var piece := _piece(mesh, Color("#7a1f1f"), thick)
	n.add_child(piece)
	return n

func _ink(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _portal(at: Vector3, yaw: float, to: String) -> void:
	var p := Node3D.new()
	p.position = at
	p.rotation.y = yaw
	world.add_child(p)
	var door := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.84, 2.08, 0.06)
	door.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#7fd4ff")
	m.emission_enabled = true
	m.emission = Color("#7fd4ff")
	m.emission_energy_multiplier = 0.6
	door.material_override = m
	door.position = Vector3(0, 1.05, 0.01)
	p.add_child(door)
	portal_nodes.append({"node": p, "to": to, "at": at})

# ── actors ────────────────────────────────────────────────────────────────────────
func _spawn_robo(at: Vector3) -> void:
	actor_kind = "robo"
	actor_pos = at
	actor_yaw = 0.0
	actor = Node3D.new()
	world.add_child(actor)
	var parts := RoboParts.parts(Color("#4aa3df"))
	var head: Node3D = null
	for key in parts:
		var part: Dictionary = parts[key]
		part["step"] = 0.02
		var node := _smooth_part(part, 0.006)
		if key == "head":
			head = node
			actor.add_child(node)
		elif key in ["antenna", "beacon"]:
			node.position = Vector3.ZERO # already shifted to the neck pivot
			head.add_child(node)
		else:
			actor.add_child(node)
	robo_parts = {"head": head}

func _spawn_frog(at: Vector3) -> void:
	actor_kind = "frog"
	actor_pos = at
	actor_yaw = 0.0
	actor = Node3D.new()
	actor.scale = Vector3.ONE * FrogModel.FROG_SCALE
	world.add_child(actor)
	var parts := FrogModel.parts()
	frog_parts = {}
	for key in parts:
		var part: Dictionary = parts[key]
		part["step"] = 0.5
		var node := _smooth_part(part, 0.4)
		actor.add_child(node)
		frog_parts[key] = node

# ── cameras ───────────────────────────────────────────────────────────────────────
func _update_camera(dt: float) -> void:
	if rig == "free":
		_update_fly(dt)
		return
	var c: Dictionary = CAMS[scene_name]
	var pos: Vector3
	var target: Vector3
	var fov: float
	match rig:
		"static":
			pos = c["static"][0]
			target = c["static"][1]
			fov = c["static"][2]
		"slider":
			var s: Array = c["slider"]
			pos = s[0].lerp(s[1], smoothstep(0.0, 1.0, slider_t))
			target = pos + s[2]
			fov = s[3]
		_:
			var d: Array = c["drone"]
			var a := t * 0.07
			pos = d[0] + Vector3(sin(a) * d[1], d[2] + sin(t * 1.3) * 0.06, cos(a) * d[1])
			target = d[0]
			fov = d[3]
	cam.position = pos
	cam.look_at(target, Vector3.UP)
	cam.fov = fov

func _update_fly(dt: float) -> void:
	var fx := joy_vec.x
	var fz := joy_vec.y
	var fy := 0.0
	if keys.has("w") or keys.has("up"): fz -= 1.0
	if keys.has("s") or keys.has("down"): fz += 1.0
	if keys.has("a") or keys.has("left"): fx -= 1.0
	if keys.has("d") or keys.has("right"): fx += 1.0
	if keys.has("space"): fy += 1.0
	if keys.has("shift"): fy -= 1.0
	var fwd := Vector3(-sin(fly_yaw) * cos(fly_pitch), sin(fly_pitch), -cos(fly_yaw) * cos(fly_pitch))
	var right := Vector3(cos(fly_yaw), 0, -sin(fly_yaw))
	var n := maxf(1.0, Vector2(fx, fz).length())
	var sp := 3.2 * dt
	fly_pos += fwd * (-fz / n) * sp + right * (fx / n) * sp + Vector3(0, fy * sp, 0)
	cam.position = fly_pos
	cam.look_at(fly_pos + fwd, Vector3.UP)
	cam.fov = 38.0

func _set_rig(r: String) -> void:
	if r == "free" and rig != "free":
		_capture_fly()
	rig = r

func _capture_fly() -> void:
	var dir := -cam.global_transform.basis.z
	fly_pos = cam.global_position
	fly_yaw = atan2(-dir.x, -dir.z)
	fly_pitch = asin(clampf(dir.y, -1.0, 1.0))

# ── per frame ─────────────────────────────────────────────────────────────────────
func _process(dt: float) -> void:
	t += dt
	# look drag (camera orbit or fly turn)
	if rig == "free":
		fly_yaw -= look.x * 0.004
		fly_pitch = clampf(fly_pitch - look.y * 0.004, -1.3, 1.3)
		look = Vector2.ZERO
	else:
		look *= 0.9
	_update_actor(dt)
	_update_flood(dt)
	_update_camera(dt)
	_update_portals()
	_animate_actor(dt)

func _update_actor(dt: float) -> void:
	if actor == null or rig == "free":
		return
	var mx := joy_vec.x
	var mz := joy_vec.y
	if keys.has("w") or keys.has("up"): mz -= 1.0
	if keys.has("s") or keys.has("down"): mz += 1.0
	if keys.has("a") or keys.has("left"): mx -= 1.0
	if keys.has("d") or keys.has("right"): mx += 1.0
	var len := Vector2(mx, mz).length()
	var b := _bounds()
	if len > 0.08:
		var n := maxf(1.0, len)
		var sp := WALK * dt
		if actor_kind == "frog":
			var air := maxf(0.0, sin(t * 9.0))
			sp = HOP * dt * (0.3 + air * 1.6)
		actor_pos.x = clampf(actor_pos.x + (mx / n) * sp, b.position.x + 0.3, b.end.x - 0.3)
		actor_pos.z = clampf(actor_pos.z + (mz / n) * sp, b.position.y + 0.3, b.end.y - 0.3)
		actor_yaw = atan2(mx, mz)
		actor_moving = minf(1.0, len)
	else:
		actor_moving = lerpf(actor_moving, 0.0, minf(1.0, dt * 8.0))
	actor.position = actor_pos
	actor.rotation.y = lerp_angle(actor.rotation.y, actor_yaw, minf(1.0, dt * 10.0))
	# robo sits on the ground; the frog follows the pond terrain and swims when flooded
	if actor_kind == "frog":
		var ground := pond.ground(actor_pos.x, actor_pos.z)
		var water_h := flood * 0.5
		var swim := water_h > ground + 0.12
		actor.position.y = (water_h - 0.17) if swim else ground + actor_hop
		actor_hop = maxf(0.0, sin(t * 9.0)) * 0.13 * actor_moving + hop_lift

func _bounds() -> Rect2:
	match scene_name:
		"kitchen": return Rect2(-3, -2.5, 6, 5)
		"pond": return Rect2(-5.5, -4.5, 11, 9)
		_: return Rect2(-5, -4.5, 10, 9)

func _update_portals() -> void:
	if actor == null:
		return
	for p in portal_nodes:
		if Vector2(actor_pos.x - p["at"].x, actor_pos.z - p["at"].z).length() < 0.9:
			load_scene(p["to"])
			return

func _animate_actor(dt: float) -> void:
	if actor == null:
		return
	var expr: String = EXPRS[expr_i]
	var talking := talk
	if actor_kind == "frog":
		var L: Array = LIDS[expr]
		var blink := 1.5 if fmod(t, 3.7) < 0.12 else 0.0
		frog_parts["lidL"].rotation = Vector3(maxf(L[0], blink), 0, L[2])
		frog_parts["lidR"].rotation = Vector3(maxf(L[1], blink), 0, -L[2])
		frog_parts["eyeL"].scale = Vector3.ONE * L[3]
		frog_parts["eyeR"].scale = Vector3.ONE * L[3]
		var target := 0.0
		if talking:
			target = maxf(0.0, sin(t * 14.0) + sin(t * 21.0) * 0.5) * 0.24
		if expr == "SHOCKED": target = maxf(target, 0.28)
		if expr == "PANIC": target = maxf(target, 0.12 + absf(sin(t * 9.0)) * 0.1)
		jaw = lerpf(jaw, target, minf(1.0, dt * 25.0))
		frog_parts["jaw"].rotation.x = jaw
		var air := maxf(0.0, sin(t * 9.0)) * actor_moving
		frog_parts["legL"].rotation.x = -air * 1.1
		frog_parts["legR"].rotation.x = -air * 1.1
		frog_parts["armL"].rotation.x = air * 0.7
		frog_parts["armR"].rotation.x = air * 0.7
	else:
		var head: Node3D = robo_parts["head"]
		head.position.y = 0.5 + (absf(sin(t * 9.0)) * 0.02 if talking else 0.0)
		head.rotation.z = 0.12 if expr == "SMIRK" else 0.0

# ── flood ─────────────────────────────────────────────────────────────────────────
func _update_flood(dt: float) -> void:
	flood = lerpf(flood, flood_target, minf(1.0, dt * 1.2))
	var level := flood * (0.5 if scene_name == "pond" else 1.0)
	water.set_level(level, t)
	water.mesh_inst.scale = Vector3(1, 1, 1)
	water.position.x = 0.0
	water.position.z = 0.0

func set_stage(s: int) -> void:
	stage = s
	match s:
		0: flood_target = 0.0
		1: flood_target = 0.0
		2: flood_target = 0.32 / 0.5
		3: flood_target = 0.82 / 0.5
	if scene_name == "kitchen":
		flood_target = [0.0, 0.1, 0.32, 0.82][s]

func advance_chaos() -> void:
	set_stage(0 if stage >= 3 else stage + 1)

# ── input ─────────────────────────────────────────────────────────────────────────
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null:
		return
	var name := _key_name(k)
	if k.pressed and not k.echo:
		match name:
			"space":
				talk = true
			"1", "2", "3", "4", "5", "6":
				expr_i = int(name) - 1
			"z": _set_rig("static")
			"x": _set_rig("slider")
			"c": _set_rig("drone")
			"n": _toggle_fly()
			"m": _toggle_map()
			"q": set_stage(1)
			"e": set_stage(2)
			"r": set_stage(3)
			"t": set_stage(0)
			"g": advance_chaos()
			"f": _hop()
			"p": _save_png()
			"escape": map_open = false; map_panel.visible = false
	if k.pressed:
		keys[name] = true
	else:
		keys.erase(name)
		if name == "space":
			talk = false

func _key_name(k: InputEventKey) -> String:
	match k.keycode:
		KEY_SPACE: return "space"
		KEY_SHIFT: return "shift"
		KEY_UP: return "up"
		KEY_DOWN: return "down"
		KEY_LEFT: return "left"
		KEY_RIGHT: return "right"
		KEY_ESCAPE: return "escape"
	return k.as_text_keycode().to_lower()

func _input(event: InputEvent) -> void:
	var vp := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		var pressed: bool = event.pressed
		var pos: Vector2 = event.position
		if pressed:
			if map_open:
				return
			if pos.x < vp.x * 0.42 and joy_id == -1 and pos.y > vp.y * 0.35:
				joy_id = event.index if event is InputEventScreenTouch else 0
				joy_origin = pos
				joy_vec = Vector2.ZERO
				joy_pad.origin = pos
				joy_pad.knob = pos
				joy_pad.active = true
			elif pos.x >= vp.x * 0.42 and look_id == -1 and not _over_button(pos):
				look_id = event.index if event is InputEventScreenTouch else 0
				last_look = pos
		else:
			if (event.index if event is InputEventScreenTouch else 0) == joy_id:
				joy_id = -1
				joy_vec = Vector2.ZERO
				joy_pad.active = false
			if (event.index if event is InputEventScreenTouch else 0) == look_id:
				look_id = -1
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and look_id != -1):
		var idx: int = event.index if event is InputEventScreenDrag else 0
		if idx == joy_id:
			var d: Vector2 = event.position - joy_origin
			joy_vec = d.limit_length(70.0) / 70.0
			joy_pad.knob = joy_pad.origin + d.limit_length(70.0)
		elif idx == look_id:
			var rel: Vector2 = event.position - last_look
			look += rel
			last_look = event.position

func _over_button(pos: Vector2) -> bool:
	for b in hud_buttons:
		if b.get_global_rect().has_point(pos):
			return true
	return false

func _toggle_fly() -> void:
	_set_rig("static" if rig == "free" else "free")

func _hop() -> void:
	if actor_kind == "frog":
		var tw := create_tween()
		tw.tween_property(self, "hop_lift", 0.22, 0.22).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "hop_lift", 0.0, 0.26)

func _save_png() -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "user://galaughxy-%d.png" % Time.get_unix_time_from_system()
	img.save_png(path)
	print("[png] ", ProjectSettings.globalize_path(path))

# ── HUD ───────────────────────────────────────────────────────────────────────────
var hud_buttons: Array[Control] = []

func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_label = Label.new()
	hud_label.position = Vector2(12, 8)
	hud_label.add_theme_font_size_override("font_size", 14)
	layer.add_child(hud_label)
	joy_pad = JoyPad.new()
	joy_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(joy_pad)
	# top-left: map, fly, rig
	var row := HBoxContainer.new()
	row.position = Vector2(12, 34)
	row.add_theme_constant_override("separation", 8)
	layer.add_child(row)
	for entry in [["🗺 Map", "m"], ["🛸 Fly", "n"], ["Static", "z"], ["Slider", "x"], ["Drone", "c"], ["PNG", "p"]]:
		var b := Button.new()
		b.text = entry[0]
		b.custom_minimum_size = Vector2(88, 44)
		b.pressed.connect(func(): _key_pressed(entry[1]))
		row.add_child(b)
		hud_buttons.append(b)
	# bottom-right: action buttons
	var acts := VBoxContainer.new()
	acts.add_theme_constant_override("separation", 10)
	acts.anchor_left = 1.0
	acts.anchor_top = 1.0
	acts.anchor_right = 1.0
	acts.anchor_bottom = 1.0
	acts.offset_left = -200
	acts.offset_top = -330
	acts.offset_right = -12
	acts.offset_bottom = -12
	layer.add_child(acts)
	var talk_b := Button.new()
	talk_b.text = "TALK (hold)"
	talk_b.custom_minimum_size = Vector2(180, 64)
	talk_b.button_down.connect(func(): talk = true)
	talk_b.button_up.connect(func(): talk = false)
	acts.add_child(talk_b)
	hud_buttons.append(talk_b)
	var face := Button.new()
	face.text = "FACE"
	face.pressed.connect(func(): expr_i = (expr_i + 1) % 6)
	acts.add_child(face)
	hud_buttons.append(face)
	var hop := Button.new()
	hop.text = "HOP"
	hop.pressed.connect(_hop)
	acts.add_child(hop)
	hud_buttons.append(hop)
	var chaos := Button.new()
	chaos.text = "CHAOS"
	chaos.pressed.connect(advance_chaos)
	acts.add_child(chaos)
	hud_buttons.append(chaos)
	# world map overlay
	map_panel = Panel.new()
	map_panel.anchor_right = 1.0
	map_panel.anchor_bottom = 1.0
	map_panel.visible = false
	layer.add_child(map_panel)
	for name in ORDER:
		var info: Dictionary = SCENES[name]
		var nb := Button.new()
		nb.text = "%s %s\n%s" % [info["icon"], info["title"], info["tag"]]
		nb.anchor_left = info["map"].x / 100.0
		nb.anchor_top = info["map"].y / 100.0
		nb.custom_minimum_size = Vector2(170, 64)
		nb.pressed.connect(func(): _travel(name))
		map_panel.add_child(nb)
	_update_hud()

func _key_pressed(k: String) -> void:
	var ev := InputEventKey.new()
	ev.keycode = OS.find_keycode_from_string(k)
	ev.pressed = true
	Input.parse_input_event(ev)
	var rel := InputEventKey.new()
	rel.keycode = ev.keycode
	rel.pressed = false
	Input.parse_input_event(rel)

func _toggle_map() -> void:
	map_open = not map_open
	map_panel.visible = map_open

func _travel(name: String) -> void:
	map_open = false
	map_panel.visible = false
	load_scene(name)

func _update_hud() -> void:
	if not SCENES.has(scene_name):
		return
	var info: Dictionary = SCENES[scene_name]
	var chaos: String = ["calm", "drip", "surge", "FLOOD"][stage]
	hud_label.text = "%s · %s    [%s · %s · chaos: %s]" % [info["title"], info["tag"], rig, EXPRS[expr_i], chaos]

## Draws the floating joystick while a thumb is on the left half.
class JoyPad:
	extends Control
	var origin := Vector2.ZERO
	var knob := Vector2.ZERO
	var active := false

	func _draw() -> void:
		if not active:
			return
		draw_circle(origin, 70.0, Color(1, 1, 1, 0.12))
		draw_arc(origin, 70.0, 0, TAU, 48, Color(1, 1, 1, 0.45), 2.0)
		draw_circle(knob, 26.0, Color(0.22, 0.9, 1.0, 0.7))

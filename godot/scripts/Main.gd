extends Node3D

## Galaughxy studio root. Persistent across maps: camera rig, HUD, cast, voice, director and the
## On Twos clock. Maps are .tscn scenes listed in res://data/maps.json and load into MapContainer;
## the cast (res://data/characters.json) lives in CastRoot and follows you between maps.
##
## Every control is an InputMap action (Controls.gd). Human input (keys, touch HUD) and the AI
## Director both end up in act() / walk_to() / say(), so they drive identical movement, sound and
## stepped animation. Each character keeps its own motion state, so the Director can move several
## at once while you puppet another.
##
## One simulation step (_step) moves the director, characters, flood, voice clock and poses.
## Live play calls it every frame; scrubbing and retakes call it at a fixed 1/60 s to fast-forward
## deterministically from a shot's starting snapshot.

const EXPRS := ["DEADPAN", "SMIRK", "PANIC", "ANGRY", "HAPPY", "SHOCKED"]
const LIDS := {
	"DEADPAN": [-0.3, -0.3, 0.0, 1.0], "SMIRK": [-0.2, -1.0, 0.15, 1.0], "PANIC": [-1.45, -1.45, 0.0, 1.22],
	"ANGRY": [-0.4, -0.4, 0.5, 0.95], "HAPPY": [-0.05, -0.05, -0.25, 1.0], "SHOCKED": [-1.55, -1.55, 0.0, 1.3],
}
const WALK := 1.7
const HOP := 1.1
const HOP_TIME := 0.44
const HOP_HEIGHT := 0.2
const CATEGORIES := [["All", "All"], ["Robo", "Robos"], ["Animal", "Animals"], ["Hybrid", "Hybrids"]]
const HOST_VOICE := {"robo": {"pitch": 1.0, "filter": "radio"}, "frog": {"pitch": 0.85, "filter": "none"}}
const CAM_KEYS := {"cam_static": "wide_static", "cam_slider": "slider_push", "cam_drone": "drone_intro"}

# registries
var maps := {}
var map_order: Array = []
var map_alias := {}
var chars := {}
var char_order: Array = []

# persistent studio nodes
var map_container: Node3D
var cast_root: Node3D
var world: MapBase
var env: Environment
var sun: DirectionalLight3D
var cam: Camera3D
var voice: Voice
var director: DirectorController

var scene_name := ""
var rig := "static"
var custom_cam: Array = []
var fly_pos := Vector3.ZERO
var fly_yaw := 0.0
var fly_pitch := 0.0
var look := Vector2.ZERO

# characters: the map's host (robo / frog) and the cast puppets, each with its own motion state
var host: Node3D
var host_kind := ""
var cast: Array = []
var actor: Node3D
var motion := {}

## The controlled character's position / movement / expression (kept per character in `motion`).
var actor_pos: Vector3:
	get: return _m(actor).get("pos", Vector3.ZERO)
	set(v): if _has(actor): motion[actor]["pos"] = v
var actor_moving: float:
	get: return _m(actor).get("moving", 0.0)
var expr_i: int:
	get: return _m(actor).get("expr", 0)
	set(v): if _has(actor): motion[actor]["expr"] = v
var actor_kind: String:
	get: return _kind(actor) if _has(actor) else ""

var jaw := 0.0

# chaos
var water: Water
var flood := 0.0
var flood_target := 0.0
var stage := 0

# time and On Twos
var t := 0.0
var slider_t := 0.0
var on_twos := false
var twos_tick := true
var _twos_last := -1
var _last_anim_t := 0.0

var frog_parts := {}
var frog_ink: Array = []
var robo_parts := {}
var portal_nodes := []

# HUD and input
var hud_layer: CanvasLayer
var hud_root: Control
var hud_clean := false
var hud_label: Label
var subtitle: Label
var map_panel: Panel
var cast_panel: Panel
var director_panel: Panel
var director_list: VBoxContainer
var director_status: Label
var maps_list: VBoxContainer
var cast_grid: GridContainer
var cast_cards: Array = []
var cast_filter := "All"
var cast_search: LineEdit
var cast_status: Label
var twos_button: Button
var fade: ColorRect
var timeline: PanelContainer
var tl_pills: HBoxContainer
var tl_slider: HSlider
var tl_time: Label
var tl_play: Button
var tl_loop: Button
var tl_overdub: Button
var tl_save: Button
var _tl_episode := ""
var map_open := false
var cast_open := false
var director_open := false
var joy_id := -1
var joy_origin := Vector2.ZERO
var joy_vec := Vector2.ZERO
var joy_down_t := 0.0
var look_id := -1
var last_look := Vector2.ZERO
var look_origin := Vector2.ZERO
var look_down_t := 0.0
var test_runner: SelfTest
var joy_pad: JoyPad
var hud_buttons: Array[Control] = []
var expansions_on := {}
var _subtitle_until := 0.0
var _talk_held := false
var _shot_mode := false   # screenshot / movie runs ignore the keyboard and never take focus

func _ready() -> void:
	Controls.setup()
	_load_registries()
	_setup_environment()
	_setup_camera()
	map_container = Node3D.new()
	map_container.name = "MapContainer"
	add_child(map_container)
	cast_root = Node3D.new()
	cast_root.name = "CastRoot"
	add_child(cast_root)
	water = Water.new()
	add_child(water)
	voice = Voice.new()
	voice.name = "Voice"
	add_child(voice)
	director = DirectorController.new(self)
	director.name = "Director"
	add_child(director)
	director.changed.connect(_on_director_changed)
	_setup_hud()
	var args := OS.get_cmdline_user_args()
	if args.has("--shot"):
		_shot_mode = true
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var start := "backyard_garden"
	if args.has("--scene"):
		start = args[args.find("--scene") + 1]
	load_scene(start)
	if args.has("--expand"):
		for e in maps[scene_name].get("expansions", []):
			set_expansion(String(e["id"]), true)
	if args.has("--roster"):
		for i in char_order.size():
			var p := spawn_character(String(char_order[i]))
			p.scale = Vector3.ONE
			place(p, Vector3(-1.6 + (i % 5) * 0.8, 0, -0.9 + int(i / 5) * 0.75), 0.0)
		if host:
			host.visible = false
	if args.has("--rig"):
		_set_rig(args[args.find("--rig") + 1])
	if args.has("--cam"):
		custom_cam = Array(String(args[args.find("--cam") + 1]).split(",")).map(func(v): return float(v))
		rig = "custom"
	if args.has("--episode"):
		var shot := String(args[args.find("--at-shot") + 1]) if args.has("--at-shot") else ""
		director.play_episode(String(args[args.find("--episode") + 1]), shot)
		if args.has("--quit-after-episode"):
			director.finished.connect(func(): get_tree().quit())
	if args.has("--open"):
		match String(args[args.find("--open") + 1]):
			"cast": _toggle_cast()
			"maps": _toggle_map()
			"director": _toggle_director()
			"timeline": _toggle_timeline()
	if args.has("--shot"):
		var wait := float(args[args.find("--wait") + 1]) if args.has("--wait") else 1.5
		_shot_and_quit(String(args[args.find("--shot") + 1]), wait)
	if args.has("--test"):
		test_runner = SelfTest.new(self)
		test_runner.run()

func _shot_and_quit(path: String, wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("[shot] ", path)
	print("[ink] outline meshes %d, setup avg %.2f ms" % [InkStroke.builds, InkStroke.build_ms / maxi(1, InkStroke.builds)])
	print("[perf] fps %d, draw calls %d, primitives %d" % [Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit()

# ── registries ────────────────────────────────────────────────────────────────────
func _load_registries() -> void:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps.json"))
	for entry in m["maps"]:
		var id := String(entry["id"])
		maps[id] = entry
		map_order.append(id)
		map_alias[id] = id
		for a in entry.get("aliases", []):
			map_alias[String(a)] = id
	var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters.json"))
	for entry in c["characters"]:
		chars[String(entry["id"])] = entry
		char_order.append(String(entry["id"]))

static func v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

# ── motion state ──────────────────────────────────────────────────────────────────
func _has(n: Node3D) -> bool:
	return n != null and is_instance_valid(n) and motion.has(n)

func _m(n: Node3D) -> Dictionary:
	return motion[n] if _has(n) else {}

func _kind(n: Node3D) -> String:
	return "puppet" if n is Puppet else host_kind

func _register(n: Node3D) -> void:
	motion[n] = {"pos": Vector3(n.position.x, 0, n.position.z), "yaw": n.rotation.y, "moving": 0.0,
		"hop": 0.0, "hop_start": -100.0, "bob": 0.0, "expr": 0, "target": null}

func _actors() -> Array:
	var out: Array = []
	if host and is_instance_valid(host):
		out.append(host)
	for p in cast:
		if is_instance_valid(p):
			out.append(p)
	return out

## Roster id of a character ("host" for the map's robo / frog).
func id_of(n: Node3D) -> String:
	if n is Puppet:
		return String((n as Puppet).info["id"])
	return "host" if n == host and n != null else ""

func voice_of(n: Node3D) -> Dictionary:
	if n is Puppet:
		return (n as Puppet).info.get("voice", {})
	return HOST_VOICE.get(host_kind, {})

## Rough standing height, for camera framing.
func height_of(n: Node3D) -> float:
	if n is Puppet and (n as Puppet)._j.has("Head"):
		return maxf(0.25, ((n as Puppet)._j["Head"] as Node3D).global_position.y - n.global_position.y + 0.12)
	return 0.95 if host_kind == "robo" else 0.4

func head_pos(n: Node3D) -> Vector3:
	if n is Puppet and (n as Puppet)._j.has("Head"):
		return ((n as Puppet)._j["Head"] as Node3D).global_position + Vector3(0, 0.05, 0)
	return n.global_position + Vector3(0, height_of(n) * 0.8, 0)

# ── environment ───────────────────────────────────────────────────────────────────
func _setup_environment() -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = false
	add_child(sun)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment = env
	add_child(we)

func _apply_lighting(info: Dictionary) -> void:
	var s: Dictionary = info.get("sun", {"rot": [-50, 35, 0], "color": "#ffffff", "energy": 0.4})
	sun.rotation_degrees = v3(s["rot"])
	sun.light_color = Color(String(s["color"]))
	sun.light_energy = float(s["energy"])
	env.ambient_light_color = Color(String(info.get("ambient", "#dff1ff")))
	env.ambient_light_energy = float(info.get("ambient_energy", 0.55))
	var sky := Color(String(info["sky"]))
	env.background_color = sky
	RenderingServer.set_default_clear_color(sky)

func _setup_camera() -> void:
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 200.0
	add_child(cam)
	cam.current = true

# ── maps ──────────────────────────────────────────────────────────────────────────
func load_scene(name: String) -> void:
	var id: String = map_alias.get(name, "")
	if id == "":
		push_warning("unknown map: " + name)
		return
	var was_host := actor == null or actor == host
	if host:
		motion.erase(host)
		voice.stop(host)
	if world:
		map_container.remove_child(world)
		world.queue_free()
	host = null
	frog_parts = {}
	robo_parts = {}
	scene_name = id
	var info: Dictionary = maps[id]
	world = (load(String(info["scene"])) as PackedScene).instantiate() as MapBase
	map_container.add_child(world)
	_apply_lighting(info)
	portal_nodes.clear()
	expansions_on = {}
	flood = 0.0
	flood_target = 0.0
	stage = 0
	slider_t = 0.0
	look = Vector2.ZERO
	var at := v3(info.get("host_at", [0, 0, 0.3]))
	match String(info.get("host", "")):
		"robo": _spawn_robo(at)
		"frog": _spawn_frog(at)
	if host:
		_register(host)
	for p in info.get("portals", []):
		_portal(v3(p["at"]), float(p["yaw"]), String(p["to"]))
	# the cast follows you to the new map's spawn points
	var spots := world.spawn_points()
	for i in cast.size():
		var spot: Vector3 = spots[i % spots.size()] if spots.size() > 0 else Vector3(0, 0, 1)
		spot += Vector3(0.45 * int(i / maxi(1, spots.size())), 0, 0)
		place(cast[i], spot, 0.0)
	if was_host or not (actor is Puppet):
		actor = null
		if host:
			_take_control(host)
	_update_hud()
	_refresh_maps_drawer()

func set_expansion(id: String, on: bool) -> void:
	world.set_expansion(id, on)
	expansions_on[id] = on
	_refresh_maps_drawer()

func _bounds() -> Rect2:
	var b: Array = maps[scene_name]["bounds"]
	var r := Rect2(float(b[0]), float(b[1]), float(b[2]), float(b[3]))
	for e in maps[scene_name].get("expansions", []):
		var eb: Array = e.get("bounds", [])
		if eb.size() == 4 and expansions_on.get(String(e["id"]), false):
			r = r.merge(Rect2(float(eb[0]), float(eb[1]), float(eb[2]), float(eb[3])))
	return r

func _piece(mesh: ArrayMesh, _ink_col: Color, thick := 0.009, occ: Dictionary = {}) -> Node3D:
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = _lit()
	n.add_child(body)
	n.add_child(Ink.rim(mesh, thick, occ.get("c", []), occ.get("r", [])))
	return n

func _lit() -> StandardMaterial3D:
	return Style.toon(Color.WHITE, true)

## One smooth part as a node on its pivot: surface, glow (emissive) or lit, plus ink strokes.
func _smooth_part(part: Dictionary, thick: float, occ: Dictionary = {}) -> Node3D:
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
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		g.material_override = m
		n.add_child(g)
		return n
	n.add_child(_piece(mesh, Color("#7a1f1f"), thick, occ))
	return n

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

# ── hosts ─────────────────────────────────────────────────────────────────────────
func _spawn_robo(at: Vector3) -> void:
	host_kind = "robo"
	host = Node3D.new()
	host.name = "Robo"
	host.position = at
	world.add_child(host)
	var parts := RoboParts.parts(Style.swatch("bondi_blue"))
	var head: Node3D = null
	for key in parts:
		var part: Dictionary = parts[key]
		part["step"] = 0.012
		var node := _smooth_part(part, 0.0045)
		if key == "head":
			head = node
			host.add_child(node)
		elif key in ["antenna", "beacon"]:
			node.position = Vector3.ZERO # already shifted to the neck pivot
			head.add_child(node)
		else:
			host.add_child(node)
	robo_parts = {"head": head}

func _spawn_frog(at: Vector3) -> void:
	host_kind = "frog"
	host = Node3D.new()
	host.name = "Bog"
	host.position = at
	host.scale = Vector3.ONE * FrogModel.FROG_SCALE
	world.add_child(host)
	var parts := FrogModel.parts()
	var occ := FrogModel.occluders()
	frog_parts = {}
	for key in parts:
		var part: Dictionary = parts[key]
		part["step"] = 0.5
		# the body has no occluders; every limb and feature hides its line inside the body
		var node := _smooth_part(part, 0.25, {} if key == "body" else occ)
		host.add_child(node)
		frog_parts[key] = node
	frog_ink = _collect_ink(host)

func _collect_ink(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D and n.material_override is ShaderMaterial:
		out.append(n.material_override)
	for c in n.get_children():
		out.append_array(_collect_ink(c))
	return out

func _name_of(n: Node3D) -> String:
	if n is Puppet:
		return (n as Puppet).display_name()
	return "Bog" if host_kind == "frog" else "Robo"

# ── cast ──────────────────────────────────────────────────────────────────────────
func spawn_character(id: String, control := true) -> Puppet:
	var p := Puppet.create(chars[id])
	cast_root.add_child(p)
	var spots := world.spawn_points()
	var n := cast.size()
	var spot: Vector3 = spots[n % spots.size()] if spots.size() > 0 else Vector3(0, 0, 1)
	spot += Vector3(0.45 * int(n / maxi(1, spots.size())), 0, 0)
	p.position = Vector3(spot.x, world.ground(spot.x, spot.z), spot.z)
	_register(p)
	p.scale = Vector3.ONE * 0.01
	var tw := create_tween()
	tw.tween_property(p, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	cast.append(p)
	if control:
		_take_control(p)
	_update_hud()
	return p

## A character by roster id ("host" for the map's robo / frog), or null. Never spawns.
func find_actor(id: String) -> Node3D:
	if id == "host" or (id != "" and id == host_kind):
		return host
	for p in cast:
		if is_instance_valid(p) and String((p as Puppet).info["id"]) == id:
			return p
	return null

## Finds a character by roster id; spawns it if the cast does not have it yet.
func actor_for(id: String) -> Node3D:
	var n := find_actor(id)
	if n == null and chars.has(id):
		n = spawn_character(id, false)
		n.scale = Vector3.ONE
	return n

## Puts a character at a spot (x, z) facing yaw, on the ground, with no walk target.
func place(n: Node3D, at: Vector3, yaw: float) -> void:
	if not _has(n):
		_register(n)
	var m: Dictionary = motion[n]
	m["pos"] = Vector3(at.x, 0, at.z)
	m["yaw"] = yaw
	m["target"] = null
	m["moving"] = 0.0
	m["hop"] = 0.0
	m["hop_start"] = -100.0
	n.position = Vector3(at.x, world.ground(at.x, at.z), at.z)
	n.rotation.y = yaw

func despawn_selected() -> void:
	if not (actor is Puppet):
		return
	var p: Puppet = actor
	cast.erase(p)
	motion.erase(p)
	voice.stop(p)
	p.queue_free()
	actor = null
	if host:
		_take_control(host)
	_update_hud()

func clear_cast() -> void:
	for p in cast:
		motion.erase(p)
		voice.stop(p)
		(p as Node).queue_free()
	cast.clear()
	actor = null
	if host:
		_take_control(host)
	_update_hud()

func _take_control(n: Node3D) -> void:
	if n == null or n == actor:
		return
	if _has(actor):
		motion[actor]["moving"] = 0.0
	voice.live(null, {})
	actor = n
	if not _has(n):
		_register(n)
	_update_hud()

func cycle_control() -> void:
	var list := _actors()
	if list.is_empty():
		return
	var i := list.find(actor)
	_take_control(list[(i + 1) % list.size()])

## Tap a character on screen to control it.
func _pick(screen: Vector2) -> bool:
	var best: Node3D = null
	var best_d := 90.0
	for n in _actors():
		if not (n as Node3D).visible:
			continue
		var wp: Vector3 = (n as Node3D).global_position + Vector3(0, 0.25, 0)
		if cam.is_position_behind(wp):
			continue
		var d := cam.unproject_position(wp).distance_to(screen)
		if d < best_d:
			best_d = d
			best = n
	if best:
		_take_control(best)
		return true
	return false

# ── actions: the one entry point for humans and the Director ─────────────────────
## Character actions: hop, expr_1..expr_6, emote_wave/point/facepalm/shrug.
func act(n: Node3D, action: String) -> void:
	if not _has(n):
		return
	if action == "hop":
		motion[n]["hop_start"] = t
	elif action.begins_with("expr_"):
		motion[n]["expr"] = clampi(int(action.substr(5)) - 1, 0, EXPRS.size() - 1)
		_update_hud()
	elif action.begins_with("emote_"):
		if n is Puppet:
			(n as Puppet).emote(action)
		else:
			motion[n]["hop_start"] = t # hosts have no arms: they bounce instead

func walk_to(n: Node3D, at: Vector3) -> void:
	if _has(n):
		motion[n]["target"] = Vector3(at.x, 0, at.z)

func face(n: Node3D, yaw: float) -> void:
	if _has(n):
		motion[n]["yaw"] = yaw

## Speaks a line with the character's voice preset; shows the subtitle; returns the duration.
func say(n: Node3D, audio: String, text: String, duration := -1.0) -> float:
	if not _has(n):
		return 0.0
	var d := voice.say(n, voice_of(n), audio, text, duration)
	if text != "":
		subtitle.text = "%s: %s" % [_name_of(n), text]
		subtitle.visible = true
		_subtitle_until = voice.clock + d + 0.3
	return d

func _trigger(action: String) -> void:
	match action:
		"cam_static", "cam_slider", "cam_drone":
			if director.drives_camera():
				director.cam_cut_live(CAM_KEYS[action])
			else:
				_set_rig({"cam_static": "static", "cam_slider": "slider", "cam_drone": "drone"}[action])
		"fly":
			if not director.playing: # free fly is studio-only: recording cameras never drift
				_toggle_fly()
		"maps": _toggle_map()
		"cast": _toggle_cast()
		"director": _toggle_director()
		"timeline": _toggle_timeline()
		"play_pause": director.toggle_pause()
		"overdub": director.toggle_overdub()
		"next_actor": cycle_control()
		"twos": _toggle_twos()
		"chaos_1", "chaos_2", "chaos_3", "chaos_drain", "chaos_next":
			var s := {"chaos_1": 1, "chaos_2": 2, "chaos_3": 3, "chaos_drain": 0}.get(action, 0 if stage >= 3 else stage + 1) as int
			set_stage(s)
			if director.overdub:
				director.record_chaos(s)
		"png": _save_png()
		"cancel":
			if director.playing and hud_clean:
				director.stop(true)
			_close_drawers()
		_:
			act(actor, action)
			if director.overdub:
				director.record_action(action)

## Polls the InputMap once per frame.
func _handle_input() -> void:
	if _shot_mode:
		return
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is LineEdit
	var flying := rig == "free"
	for action in Controls.TRIGGERS:
		if not Input.is_action_just_pressed(action):
			continue
		if typing and action != "cancel":
			continue
		if flying and not Controls.FLY_OK.has(action):
			continue # every other command is off while flying
		if _drawer_open() and not Controls.DRAWER_OK.has(action):
			continue
		_trigger(action)
	# hold Talk: live test voice through the character's preset (Space rises instead while flying)
	var talking := Input.is_action_pressed("talk") and not flying and not typing and not _drawer_open()
	if talking != _talk_held:
		_talk_held = talking
		if talking:
			director.talk_begin()
		else:
			director.talk_end()
	voice.live(actor if talking and _has(actor) else null, voice_of(actor) if _has(actor) else {})

# ── cameras ───────────────────────────────────────────────────────────────────────
## Pose of a map rig: [position, target, fov].
func rig_pose(r: String) -> Array:
	var c: Dictionary = maps[scene_name]["cams"]
	match r:
		"slider":
			var s: Array = c["slider"]
			var pos := v3(s[0]).lerp(v3(s[1]), smoothstep(0.0, 1.0, slider_t))
			return [pos, pos + v3(s[2]), float(s[3])]
		"drone":
			var d: Array = c["drone"]
			var a := t * 0.07
			var pos := v3(d[0]) + Vector3(sin(a) * float(d[1]), float(d[2]) + sin(t * 1.3) * 0.06, cos(a) * float(d[1]))
			return [pos, v3(d[0]), float(d[3])]
	var st: Array = c["static"]
	return [v3(st[0]), v3(st[1]), float(st[2])]

func _update_camera(dt: float) -> void:
	if rig == "free":
		_update_fly(dt)
		return
	if director.drives_camera():
		director.update_camera(cam, dt)
		return
	if rig == "custom" and custom_cam.size() >= 7:
		cam.position = Vector3(custom_cam[0], custom_cam[1], custom_cam[2])
		cam.look_at(Vector3(custom_cam[3], custom_cam[4], custom_cam[5]), Vector3.UP)
		cam.fov = custom_cam[6]
		return
	var p := rig_pose(rig)
	cam.position = p[0]
	cam.look_at(p[1], Vector3.UP)
	cam.fov = p[2]

func _update_fly(dt: float) -> void:
	var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back") + joy_vec
	var fx := mv.x
	var fz := mv.y
	var fy := 1.0 if Input.is_action_pressed("talk") else 0.0
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
	_sync_fly_hud()
	_update_hud()

## While flying only Maps, Cast, Director, Fly and PNG stay on screen; the other buttons hide.
func _sync_fly_hud() -> void:
	var flying := rig == "free"
	for b in hud_buttons:
		var keep: bool = (b as Button).text in ["🗺 Maps", "🎭 Cast", "🎬 Director", "🛸 Fly", "PNG"]
		b.visible = keep or not flying

func _capture_fly() -> void:
	var dir := -cam.global_transform.basis.z
	fly_pos = cam.global_position
	fly_yaw = atan2(-dir.x, -dir.z)
	fly_pitch = asin(clampf(dir.y, -1.0, 1.0))

# ── director hooks ────────────────────────────────────────────────────────────────
## Resets the animation clock at the start of a shot, so every shot replays identically.
func reset_clock() -> void:
	t = 0.0
	_twos_last = -1
	_last_anim_t = 0.0
	slider_t = 0.0
	for m in motion.values():
		m["hop_start"] = -100.0
		m["hop"] = 0.0

func on_director_start(clean: bool) -> void:
	if rig == "free":
		_set_rig("static")
	_close_drawers()
	set_clean_hud(clean)

func on_director_stop(_take_over: bool) -> void:
	set_clean_hud(false)
	if host:
		host.visible = true
	_update_hud()

## Clean HUD hides every overlay except subtitles, for recording. A tap or Esc takes over.
func set_clean_hud(on: bool) -> void:
	hud_clean = on
	hud_root.visible = not on
	joy_pad.active = false

func _on_director_changed() -> void:
	_refresh_timeline()
	update_director_status()
	_update_hud()

# ── per frame ─────────────────────────────────────────────────────────────────────
func _process(dt: float) -> void:
	_handle_input()
	_step(dt, true)
	if rig == "free":
		fly_yaw -= look.x * 0.004
		fly_pitch = clampf(fly_pitch - look.y * 0.004, -1.3, 1.3)
		look = Vector2.ZERO
	else:
		look *= 0.9
	_update_camera(dt)
	_update_portals()
	if subtitle.visible and voice.clock > _subtitle_until:
		subtitle.visible = false
	_sync_timeline()

## One simulation step. live = false while fast-forwarding (no human input, no sound).
func _step(dt: float, live: bool) -> void:
	t += dt
	# On Twos: character poses and positions update 12 times a second; the camera stays smooth
	if on_twos:
		var f := int(floor(t * 12.0))
		twos_tick = f != _twos_last
		if twos_tick:
			_twos_last = f
	else:
		twos_tick = true
	director.process_shot(dt)
	_update_actors(dt, live)
	_update_flood(dt)
	voice.tick(dt)
	_animate(dt)

func _update_actors(dt: float, live: bool) -> void:
	var mv := Vector2.ZERO
	if live and rig != "free" and not _drawer_open() and not hud_clean and not _shot_mode:
		mv = (Input.get_vector("move_left", "move_right", "move_forward", "move_back") + joy_vec).limit_length(1.0)
	var b := _bounds()
	for n in _actors():
		var m: Dictionary = motion[n]
		var dir := mv if n == actor else Vector2.ZERO
		# a walk target (from the Director) steers the character until it arrives
		if m["target"] != null:
			var to: Vector3 = m["target"] - m["pos"]
			if Vector2(to.x, to.z).length() < 0.06:
				m["target"] = null
			else:
				dir = Vector2(to.x, to.z).normalized()
		_walk(n, m, dir, dt, b)

func _walk(n: Node3D, m: Dictionary, dir: Vector2, dt: float, b: Rect2) -> void:
	var kind := _kind(n)
	var len := dir.length()
	if len > 0.08:
		var sp := WALK * dt
		if kind == "frog":
			sp = HOP * dt * (0.3 + maxf(0.0, sin(t * 9.0)) * 1.6)
		var p: Vector3 = m["pos"]
		p.x = clampf(p.x + dir.x * sp, b.position.x + 0.3, b.end.x - 0.3)
		p.z = clampf(p.z + dir.y * sp, b.position.y + 0.3, b.end.y - 0.3)
		m["pos"] = p
		m["yaw"] = atan2(dir.x, dir.y)
		m["moving"] = minf(1.0, len)
	else:
		m["moving"] = lerpf(m["moving"], 0.0, minf(1.0, dt * 8.0))
	# hop: an analytic arc from its start time, so scrubbing lands on the same height
	m["hop"] = HOP_HEIGHT * sin(PI * clampf((t - float(m["hop_start"])) / HOP_TIME, 0.0, 1.0))
	m["bob"] = maxf(0.0, sin(t * 9.0)) * 0.13 * m["moving"] if kind == "frog" else 0.0
	if not twos_tick:
		return
	var pos: Vector3 = m["pos"]
	var ground := world.ground(pos.x, pos.z)
	n.position = Vector3(pos.x, ground + m["hop"] + m["bob"], pos.z)
	n.rotation.y = lerp_angle(n.rotation.y, m["yaw"], 1.0 if on_twos else minf(1.0, dt * 10.0))
	# the frog and the cast float when the flood is deep; the robo stays on the floor
	if kind != "robo" and flood > ground + 0.12:
		n.position.y = flood - (0.17 if kind == "frog" else 0.06) + sin(t * 2.0 + pos.x) * 0.01

func _update_portals() -> void:
	if not _has(actor) or director.playing:
		return
	var p: Vector3 = actor_pos
	for portal in portal_nodes:
		if Vector2(p.x - portal["at"].x, p.z - portal["at"].z).length() < 0.9:
			load_scene(portal["to"])
			return

func _animate(dt: float) -> void:
	if not twos_tick:
		return
	var ta: float = floor(t * 12.0) / 12.0 if on_twos else t
	var ad: float = t - _last_anim_t if on_twos else dt
	_last_anim_t = t
	if _has(host):
		var hm: Dictionary = motion[host]
		_animate_host(ta, ad, EXPRS[hm["expr"]], voice.is_talking(host), hm["moving"])
	for p in cast:
		if not _has(p):
			continue
		var pup: Puppet = p
		var m: Dictionary = motion[pup]
		pup.talk = voice.is_talking(pup)
		pup.talk_level = voice.level(pup)
		pup.moving = m["moving"]
		pup.expr_i = m["expr"]
		pup.hop = m["hop"]
		pup.flood_over = flood > world.ground(pup.position.x, pup.position.z) + 0.03
		pup.animate(ta, ad)

func _animate_host(ta: float, dt: float, expr: String, talking: bool, mv: float) -> void:
	var lvl := voice.level(host)
	if host_kind == "frog" and not frog_parts.is_empty():
		var L: Array = LIDS[expr]
		var blink := 1.5 if fmod(ta, 3.7) < 0.12 else 0.0
		frog_parts["lidL"].rotation = Vector3(maxf(L[0], blink), 0, L[2])
		frog_parts["lidR"].rotation = Vector3(maxf(L[1], blink), 0, -L[2])
		frog_parts["eyeL"].scale = Vector3.ONE * L[3]
		frog_parts["eyeR"].scale = Vector3.ONE * L[3]
		var target := 0.0
		if talking:
			target = lvl * 0.3 if lvl >= 0.0 else maxf(0.0, sin(ta * 14.0) + sin(ta * 21.0) * 0.5) * 0.24
		if expr == "SHOCKED": target = maxf(target, 0.28)
		if expr == "PANIC": target = maxf(target, 0.12 + absf(sin(ta * 9.0)) * 0.1)
		jaw = lerpf(jaw, target, minf(1.0, dt * 25.0))
		frog_parts["jaw"].rotation.x = jaw
		var air := maxf(0.0, sin(ta * 9.0)) * mv
		frog_parts["legL"].rotation.x = -air * 1.1
		frog_parts["legR"].rotation.x = -air * 1.1
		frog_parts["armL"].rotation.x = air * 0.7
		frog_parts["armR"].rotation.x = air * 0.7
		var to_body: Transform3D = frog_parts["body"].global_transform.affine_inverse()
		for m in frog_ink:
			(m as ShaderMaterial).set_shader_parameter("to_body", to_body)
	elif host_kind == "robo" and robo_parts.has("head"):
		var head: Node3D = robo_parts["head"]
		var bounce := 0.0
		if talking:
			bounce = lvl * 0.03 if lvl >= 0.0 else absf(sin(ta * 9.0)) * 0.02
		head.position.y = 0.5 + bounce
		head.rotation.z = 0.12 if expr == "SMIRK" else 0.0

# ── flood ─────────────────────────────────────────────────────────────────────────
func _update_flood(dt: float) -> void:
	flood = lerpf(flood, flood_target, minf(1.0, dt * 1.2))
	water.set_level(flood, t)

func set_stage(s: int) -> void:
	stage = s
	var levels: Array = maps[scene_name].get("flood", [0, 0.1, 0.32, 0.82])
	flood_target = float(levels[clampi(s, 0, levels.size() - 1)])
	_update_hud()

func advance_chaos() -> void:
	set_stage(0 if stage >= 3 else stage + 1)

# ── touch ─────────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if _shot_mode:
		return
	var vp := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		var pressed: bool = event.pressed
		var pos: Vector2 = event.position
		var idx: int = event.index if event is InputEventScreenTouch else 0
		if pressed and hud_clean:
			# clean recording: any tap stops the director and lets you take over a character
			director.stop(true)
			_pick(pos)
			get_viewport().set_input_as_handled()
			return
		if pressed:
			if _drawer_open() or _over_button(pos):
				return
			if pos.x < vp.x * 0.42 and joy_id == -1 and pos.y > vp.y * 0.35:
				joy_id = idx
				joy_origin = pos
				joy_down_t = t
				joy_vec = Vector2.ZERO
				joy_pad.origin = pos
				joy_pad.knob = pos
				joy_pad.active = true
			elif pos.x >= vp.x * 0.42 and look_id == -1:
				look_id = idx
				last_look = pos
				look_origin = pos
				look_down_t = t
		else:
			if idx == joy_id:
				joy_id = -1
				joy_vec = Vector2.ZERO
				joy_pad.active = false
				if pos.distance_to(joy_origin) < 12.0 and absf(t - joy_down_t) < 0.35:
					_pick(pos)
			if idx == look_id:
				look_id = -1
				if pos.distance_to(look_origin) < 12.0 and absf(t - look_down_t) < 0.35:
					_pick(pos)
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and (look_id != -1 or joy_id != -1)):
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
		if b.is_visible_in_tree() and b.get_global_rect().has_point(pos):
			return true
	if timeline and timeline.is_visible_in_tree() and timeline.get_global_rect().has_point(pos):
		return true
	return false

func _toggle_fly() -> void:
	_set_rig("static" if rig == "free" else "free")

func _toggle_twos() -> void:
	on_twos = not on_twos
	_update_hud()

func _save_png() -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "user://galaughxy-%d.png" % Time.get_unix_time_from_system()
	img.save_png(path)
	print("[png] ", ProjectSettings.globalize_path(path))

# ── HUD ───────────────────────────────────────────────────────────────────────────
func _setup_hud() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud_root)
	hud_label = Label.new()
	hud_label.position = Vector2(12, 8)
	hud_label.add_theme_font_size_override("font_size", 14)
	hud_root.add_child(hud_label)
	joy_pad = JoyPad.new()
	joy_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.add_child(joy_pad)
	# top-left claws: every button taps an InputMap action
	var row := HBoxContainer.new()
	row.position = Vector2(12, 34)
	row.add_theme_constant_override("separation", 8)
	hud_root.add_child(row)
	for entry in [["🗺 Maps", "maps"], ["🎭 Cast", "cast"], ["🎬 Director", "director"], ["⏱ Timeline", "timeline"], ["🛸 Fly", "fly"],
			["Static", "cam_static"], ["Slider", "cam_slider"], ["Drone", "cam_drone"], ["12fps", "twos"], ["PNG", "png"]]:
		var b := _button(entry[0], Vector2(88, 44))
		b.pressed.connect(func(): Controls.tap(get_tree(), entry[1]))
		if entry[1] == "twos":
			b.toggle_mode = true
			twos_button = b
		row.add_child(b)
		hud_buttons.append(b)
	# emote column, left of the action column
	var emotes := VBoxContainer.new()
	emotes.add_theme_constant_override("separation", 10)
	_anchor_bottom_right(emotes, -330, -212)
	hud_root.add_child(emotes)
	for entry in [["WAVE", "emote_wave"], ["POINT", "emote_point"], ["PALM", "emote_facepalm"], ["SHRUG", "emote_shrug"]]:
		var b := _button(entry[0], Vector2(118, 0))
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): Controls.tap(get_tree(), entry[1]))
		emotes.add_child(b)
		hud_buttons.append(b)
	# bottom-right action column
	var acts := VBoxContainer.new()
	acts.add_theme_constant_override("separation", 10)
	_anchor_bottom_right(acts, -200, -12)
	hud_root.add_child(acts)
	var talk_b := _button("TALK (hold)", Vector2(180, 64))
	talk_b.button_down.connect(func(): Input.action_press("talk"))
	talk_b.button_up.connect(func(): Input.action_release("talk"))
	acts.add_child(talk_b)
	hud_buttons.append(talk_b)
	var face_b := _button("FACE", Vector2.ZERO)
	face_b.pressed.connect(func(): Controls.tap(get_tree(), "expr_%d" % ((expr_i + 1) % EXPRS.size() + 1)))
	acts.add_child(face_b)
	hud_buttons.append(face_b)
	var hop_b := _button("HOP", Vector2.ZERO)
	hop_b.pressed.connect(func(): Controls.tap(get_tree(), "hop"))
	acts.add_child(hop_b)
	hud_buttons.append(hop_b)
	var chaos_b := _button("CHAOS", Vector2.ZERO)
	chaos_b.pressed.connect(func(): Controls.tap(get_tree(), "chaos_next"))
	acts.add_child(chaos_b)
	hud_buttons.append(chaos_b)
	_build_timeline()
	_build_cast_drawer()
	_build_maps_drawer()
	_build_director_drawer()
	# subtitles and the fade live outside hud_root, so they stay visible in clean recording
	subtitle = Label.new()
	subtitle.anchor_left = 0.12
	subtitle.anchor_right = 0.88
	subtitle.anchor_top = 0.84
	subtitle.anchor_bottom = 0.95
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	subtitle.add_theme_constant_override("outline_size", 7)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle.visible = false
	hud_layer.add_child(subtitle)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(fade)

func _anchor_bottom_right(c: Control, left: float, right: float) -> void:
	c.anchor_left = 1.0
	c.anchor_top = 1.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = left
	c.offset_top = -330
	c.offset_right = right
	c.offset_bottom = -12

## HUD buttons never take keyboard focus, so Space and Tab always reach the studio.
func _button(text: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	return b

func _drawer_panel() -> Array:
	var p := Panel.new()
	p.anchor_left = 0.06
	p.anchor_right = 0.94
	p.anchor_top = 0.08
	p.anchor_bottom = 0.95
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14, 0.95)
	sb.set_corner_radius_all(18)
	p.add_theme_stylebox_override("panel", sb)
	p.visible = false
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	p.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)
	hud_root.add_child(p)
	return [p, v]

func _drawer_header(v: VBoxContainer, title: String, close: Callable) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 22)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var x := _button("✕", Vector2(48, 44))
	x.pressed.connect(close)
	h.add_child(x)
	v.add_child(h)

func _card() -> Array:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.18, 0.22, 0.9)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", sb)
	return [card, sb]

func _build_cast_drawer() -> void:
	var pv := _drawer_panel()
	cast_panel = pv[0]
	var v: VBoxContainer = pv[1]
	_drawer_header(v, "🎭 Cast · tap a card to spawn", _close_drawers)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for cat in CATEGORIES:
		var count := char_order.size() if cat[0] == "All" else char_order.filter(func(id): return chars[id]["category"] == cat[0]).size()
		var b := _button("%s (%d)" % [cat[1], count], Vector2(0, 44))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = cat[0] == "All"
		b.pressed.connect(func(): cast_filter = cat[0]; _filter_cast())
		filters.add_child(b)
	cast_search = LineEdit.new()
	cast_search.placeholder_text = "Search…"
	cast_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cast_search.custom_minimum_size = Vector2(160, 44)
	cast_search.text_changed.connect(func(_s): _filter_cast())
	filters.add_child(cast_search)
	v.add_child(filters)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	cast_grid = GridContainer.new()
	cast_grid.columns = 4
	cast_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cast_grid.add_theme_constant_override("h_separation", 10)
	cast_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(cast_grid)
	for id in char_order:
		var data: Dictionary = chars[id]
		var card := _button("%s  %s\n%s · %s" % [data["icon"], data["name"], data["category"], data["gag"]], Vector2(0, 92))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.clip_text = true
		var col := Color(String(data["color"]))
		var light := col.get_luminance() > 0.6
		for state in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = col.darkened(0.15 if state == "pressed" else 0.0).lerp(Color.WHITE, 0.08 if state == "hover" else 0.0)
			sb.set_corner_radius_all(14)
			sb.content_margin_left = 12
			sb.content_margin_right = 12
			card.add_theme_stylebox_override(state, sb)
		for fc in ["font_color", "font_hover_color", "font_pressed_color"]:
			card.add_theme_color_override(fc, Color("#1b1d22") if light else Color.WHITE)
		card.pressed.connect(func(): spawn_character(id))
		cast_grid.add_child(card)
		cast_cards.append({"button": card, "data": data})
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	cast_status = Label.new()
	cast_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(cast_status)
	var next := _button("Next (Tab)", Vector2(120, 44))
	next.pressed.connect(cycle_control)
	foot.add_child(next)
	var des := _button("Despawn Selected", Vector2(170, 44))
	des.pressed.connect(despawn_selected)
	foot.add_child(des)
	var clr := _button("Clear Cast", Vector2(120, 44))
	clr.pressed.connect(clear_cast)
	foot.add_child(clr)
	v.add_child(foot)

func _filter_cast() -> void:
	var q := cast_search.text.strip_edges().to_lower()
	for c in cast_cards:
		var d: Dictionary = c["data"]
		var cat_ok: bool = cast_filter == "All" or d["category"] == cast_filter
		var text := ("%s %s %s %s" % [d["name"], d["id"], d["category"], d["gag"]]).to_lower()
		(c["button"] as Button).visible = cat_ok and (q == "" or text.contains(q))

func _build_maps_drawer() -> void:
	var pv := _drawer_panel()
	map_panel = pv[0]
	var v: VBoxContainer = pv[1]
	_drawer_header(v, "🗺 Maps & Expansions", _close_drawers)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	maps_list = VBoxContainer.new()
	maps_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	maps_list.add_theme_constant_override("separation", 10)
	scroll.add_child(maps_list)

func _refresh_maps_drawer() -> void:
	if maps_list == null:
		return
	for c in maps_list.get_children():
		c.queue_free()
	for id in map_order:
		var info: Dictionary = maps[id]
		var current: bool = id == scene_name
		var cs := _card()
		var card: PanelContainer = cs[0]
		if current:
			(cs[1] as StyleBoxFlat).bg_color = Color(0.2, 0.3, 0.45, 0.9)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var title := Label.new()
		title.text = "%s  %s" % [info["icon"], info["title"]]
		title.add_theme_font_size_override("font_size", 20)
		text.add_child(title)
		var sub := Label.new()
		sub.text = "%s\nChaos: %s" % [info["tag"], info["chaos"]]
		sub.add_theme_font_size_override("font_size", 13)
		sub.modulate = Color(1, 1, 1, 0.75)
		text.add_child(sub)
		if current:
			for e in info.get("expansions", []):
				var tog := CheckButton.new()
				tog.text = String(e["title"])
				tog.focus_mode = Control.FOCUS_NONE
				tog.button_pressed = expansions_on.get(String(e["id"]), false)
				tog.toggled.connect(func(on: bool): set_expansion(String(e["id"]), on))
				text.add_child(tog)
		var load_b := _button("Current map" if current else "Load Map", Vector2(150, 52))
		load_b.disabled = current
		load_b.pressed.connect(func(): _travel(id))
		row.add_child(load_b)
		maps_list.add_child(card)

func _build_director_drawer() -> void:
	var pv := _drawer_panel()
	director_panel = pv[0]
	var v: VBoxContainer = pv[1]
	_drawer_header(v, "🎬 Director", _close_drawers)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	director_status = Label.new()
	director_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	director_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(director_status)
	var retake := _button("⟲ Retake", Vector2(120, 44))
	retake.pressed.connect(func(): _close_drawers(); director.retake())
	top.add_child(retake)
	var stop := _button("■ Stop / Take Over", Vector2(190, 44))
	stop.pressed.connect(func(): director.stop(true))
	top.add_child(stop)
	var save := _button("💾 Save Episode", Vector2(160, 44))
	save.pressed.connect(_save_episode)
	top.add_child(save)
	v.add_child(top)
	var hint := Label.new()
	hint.text = "Play Episode hides the HUD for clean recording: tap the screen or press Esc to stop and take over."
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.7)
	v.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	director_list = VBoxContainer.new()
	director_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	director_list.add_theme_constant_override("separation", 10)
	scroll.add_child(director_list)
	_refresh_director_drawer()

func _refresh_director_drawer() -> void:
	if director_list == null:
		return
	for c in director_list.get_children():
		c.queue_free()
	for ep_id in director.order:
		var ep: Dictionary = director.episodes[ep_id]
		var cs := _card()
		var card: PanelContainer = cs[0]
		if ep_id == _timeline_episode():
			(cs[1] as StyleBoxFlat).bg_color = Color(0.2, 0.3, 0.45, 0.9)
		var v := VBoxContainer.new()
		card.add_child(v)
		var head := HBoxContainer.new()
		var title := Label.new()
		var map_id: String = map_alias.get(String(ep.get("map", "")), "")
		title.text = "%s  ·  %s  ·  %d shots" % [ep.get("title", ep_id), maps[map_id]["title"] if map_id != "" else "?", ep["shots"].size()]
		title.add_theme_font_size_override("font_size", 19)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var sel := _button("Select", Vector2(100, 48))
		sel.pressed.connect(func(): _tl_episode = ep_id; _refresh_timeline(); _refresh_director_drawer())
		head.add_child(sel)
		var play := _button("▶ Play Episode", Vector2(160, 48))
		play.pressed.connect(func(): _tl_episode = ep_id; director.play_episode(ep_id))
		head.add_child(play)
		v.add_child(head)
		for i in ep["shots"].size():
			var shot: Dictionary = ep["shots"][i]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var name := Label.new()
			name.text = "%d. %s   ·  %s  ·  %.1f s" % [i + 1, shot.get("name", shot["id"]), shot.get("cam", "wide_static"), director.estimate_length(shot)]
			name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name)
			var p := _button("▶ Shot", Vector2(100, 44))
			p.pressed.connect(func(): _tl_episode = ep_id; director.play_shot(ep_id, i, false))
			row.add_child(p)
			var l := _button("🔁 Loop", Vector2(100, 44))
			l.pressed.connect(func(): _tl_episode = ep_id; director.play_shot(ep_id, i, true))
			row.add_child(l)
			v.add_child(row)
		director_list.add_child(card)

# ── timeline bar ──────────────────────────────────────────────────────────────────
func _timeline_episode() -> String:
	if director.ep_id != "":
		return director.ep_id
	if _tl_episode == "" and not director.order.is_empty():
		_tl_episode = director.order[0]
	return _tl_episode

func _build_timeline() -> void:
	timeline = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14, 0.9)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(10)
	timeline.add_theme_stylebox_override("panel", sb)
	timeline.anchor_top = 1.0
	timeline.anchor_bottom = 1.0
	timeline.anchor_right = 1.0
	timeline.offset_left = 12
	timeline.offset_right = -342
	timeline.offset_top = -126
	timeline.offset_bottom = -12
	timeline.visible = false
	hud_root.add_child(timeline)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	timeline.add_child(v)
	tl_pills = HBoxContainer.new()
	tl_pills.add_theme_constant_override("separation", 6)
	v.add_child(tl_pills)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	tl_play = _button("▶", Vector2(48, 40))
	tl_play.pressed.connect(func(): Controls.tap(get_tree(), "play_pause"))
	row.add_child(tl_play)
	tl_slider = HSlider.new()
	tl_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tl_slider.step = 0.01
	tl_slider.focus_mode = Control.FOCUS_NONE
	tl_slider.value_changed.connect(func(v: float): director.seek(v))
	row.add_child(tl_slider)
	tl_time = Label.new()
	tl_time.custom_minimum_size = Vector2(110, 0)
	row.add_child(tl_time)
	tl_loop = _button("🔁", Vector2(48, 40))
	tl_loop.toggle_mode = true
	row.add_child(tl_loop)
	tl_overdub = _button("● OVERDUB", Vector2(120, 40))
	tl_overdub.toggle_mode = true
	tl_overdub.pressed.connect(func(): Controls.tap(get_tree(), "overdub"))
	row.add_child(tl_overdub)
	tl_save = _button("Save Episode", Vector2(120, 40))
	tl_save.pressed.connect(_save_episode)
	row.add_child(tl_save)

func _refresh_timeline() -> void:
	if tl_pills == null:
		return
	for c in tl_pills.get_children():
		c.queue_free()
	var id := _timeline_episode()
	if id == "" or not director.episodes.has(id):
		return
	var shots: Array = director.episodes[id]["shots"]
	for i in shots.size():
		var b := _button("Shot %d" % (i + 1), Vector2(76, 34))
		b.toggle_mode = true
		b.button_pressed = director.ep_id == id and director.shot_i == i
		b.tooltip_text = String(shots[i].get("name", ""))
		b.pressed.connect(func(): director.play_shot(id, i, tl_loop.button_pressed))
		tl_pills.add_child(b)
	var all := _button("Play All", Vector2(90, 34))
	all.pressed.connect(func(): director.play_episode(id))
	tl_pills.add_child(all)

func _sync_timeline() -> void:
	if timeline == null or not timeline.visible:
		return
	tl_slider.max_value = maxf(0.01, director.shot_len)
	tl_slider.set_value_no_signal(director.shot_t)
	tl_time.text = "%.2f / %.2f s" % [director.shot_t, director.shot_len]
	tl_play.text = "⏸" if director.playing and not director.paused else "▶"
	tl_overdub.set_pressed_no_signal(director.overdub)
	if director.loop != tl_loop.button_pressed and director.playing and director.mode == "shot":
		director.loop = tl_loop.button_pressed

func _toggle_timeline() -> void:
	timeline.visible = not timeline.visible
	if timeline.visible:
		_refresh_timeline()

func _save_episode() -> void:
	if director.ep.is_empty() and _timeline_episode() != "":
		director.ep_id = _timeline_episode()
		director.ep = director.episodes[director.ep_id]
	var paths := director.save()
	if subtitle and not paths.is_empty():
		subtitle.text = "Saved: " + ", ".join(paths)
		subtitle.visible = true
		_subtitle_until = voice.clock + 2.5
	print("[save] ", paths)

# ── drawers ───────────────────────────────────────────────────────────────────────
func _drawer_open() -> bool:
	return map_open or cast_open or director_open

func _toggle_map() -> void:
	var open := not map_open
	_close_drawers()
	map_open = open
	map_panel.visible = open
	if open:
		_refresh_maps_drawer()

func _toggle_cast() -> void:
	var open := not cast_open
	_close_drawers()
	cast_open = open
	cast_panel.visible = open
	_update_hud()

func _toggle_director() -> void:
	var open := not director_open
	if hud_clean:
		director.stop(true)
	_close_drawers()
	director_open = open
	director_panel.visible = open
	if open:
		_refresh_director_drawer()
		update_director_status()

func _close_drawers() -> void:
	map_open = false
	cast_open = false
	director_open = false
	map_panel.visible = false
	cast_panel.visible = false
	director_panel.visible = false
	joy_id = -1
	look_id = -1
	joy_vec = Vector2.ZERO
	joy_pad.active = false
	var focus := get_viewport().gui_get_focus_owner()
	if focus:
		focus.release_focus()

func update_director_status() -> void:
	if director_status:
		director_status.text = director.status_text()

## Loads a map with a quick fade through black.
func _travel(id: String) -> void:
	_close_drawers()
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.18)
	tw.tween_callback(func(): load_scene(id))
	tw.tween_property(fade, "color:a", 0.0, 0.28)

func _update_hud() -> void:
	if hud_label == null or not maps.has(scene_name):
		return
	var info: Dictionary = maps[scene_name]
	var chaos: String = ["calm", "drip", "surge", "FLOOD"][stage]
	var who := _name_of(actor) if _has(actor) else "-"
	var take := ""
	if director and director.playing:
		take = " · 🎬 shot %d" % (director.shot_i + 1)
	hud_label.text = "%s · %s    [%s · %s · chaos: %s · 🎭 %s%s%s]" % [info["title"], info["tag"], rig, EXPRS[expr_i], chaos, who, " · 12fps" if on_twos else "", take]
	if twos_button:
		twos_button.set_pressed_no_signal(on_twos)
	if cast_status:
		cast_status.text = "Controlling: %s   ·   %d on stage" % [who, cast.size()]

## Draws the floating joystick while a thumb is on the left half.
class JoyPad:
	extends Control
	var origin := Vector2.ZERO
	var knob := Vector2.ZERO
	var active := false

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if not active:
			return
		draw_circle(origin, 70.0, Color(1, 1, 1, 0.12))
		draw_arc(origin, 70.0, 0, TAU, 48, Color(1, 1, 1, 0.45), 2.0)
		draw_circle(knob, 26.0, Color(0.22, 0.9, 1.0, 0.7))

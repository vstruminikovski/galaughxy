extends Node3D

## Galaughxy studio root. Persistent across maps: camera rig, HUD (StudioHUD toolboxes), cast,
## voice, director, abilities and the camera path builder. Animation runs smooth every frame. Maps are .tscn scenes listed in res://data/maps.json and load into MapContainer;
## the cast (res://data/characters.json) lives in CastRoot and follows you between maps.
##
## Every control is an InputMap action (Controls.gd). Human input (keys, touch HUD) and the AI
## Director both end up in act() / walk_to() / say(), so they drive identical movement, sound and
## animation. Each character keeps its own motion state, so the Director can move several
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
const CAM_KEYS := {"cam_static": "wide_static", "cam_slider": "slider_push", "cam_drone": "drone_intro", "cam_follow": "two_shot"}

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
var art: Look              # the look: style, moods, sky, depth of field (Look.gd)
var bubbles: Bubbles       # comic reaction bubbles over heads (Bubbles.gd)
var physics: StudioPhysics # rigid bodies, pushers, recording / replay (StudioPhysics.gd)

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
var chaos_shake := 0.0   # camera shake from the current chaos stage
var lowgrav := false     # floaty hops (moon gravity flicker)
var slippery := false    # characters skid and wobble (grease trap)
var light_scale := 1.0   # blackout dimming (1 = normal)
var flash := 0.0         # lightning flash strength
var _base_ambient := 0.62
var _base_sun := 0.4
var _base_sky := Color.WHITE
var water: Water
var flood := 0.0
var flood_target := 0.0
var stage := 0

var ability_flood := 0.0           # water raised by abilities (on top of the map's chaos flood)
var ability_liquid := Color.WHITE
var _liquid := Color.WHITE

# time
var t := 0.0
var slider_t := 0.0
var _last_anim_t := 0.0

var frog_parts := {}
var frog_ink: Array = []
var robo_parts := {}
var portal_nodes := []

# HUD, abilities, camera paths and input
var hud: StudioHUD
var abilities: Abilities
var builder: CameraBuilder
var hud_clean := false
var _context := ""
var joy_id := -1
var joy_origin := Vector2.ZERO
var joy_vec := Vector2.ZERO
var joy_down_t := 0.0
var look_id := -1
var last_look := Vector2.ZERO
var look_origin := Vector2.ZERO
var look_down_t := 0.0
var test_runner: SelfTest
var expansions_on := {}
var _talk_held := false
var _shot_mode := false   # screenshot / movie runs ignore the keyboard and never take focus

func _ready() -> void:
	Look.load_style()
	Controls.setup()
	_load_registries()
	_setup_environment()
	_setup_camera()
	art = Look.new(self)
	art.name = "Look"
	add_child(art)
	art.setup()
	bubbles = Bubbles.new(self)
	bubbles.name = "Bubbles"
	add_child(bubbles)
	physics = StudioPhysics.new(self)
	physics.name = "Physics"
	add_child(physics)
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
	abilities = Abilities.new(self)
	abilities.name = "Abilities"
	add_child(abilities)
	builder = CameraBuilder.new(self)
	builder.name = "CameraBuilder"
	add_child(builder)
	hud = StudioHUD.new(self)
	hud.name = "StudioHUD"
	add_child(hud)
	_liquid = Style.swatch("bondi_blue", "light")
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
	if args.has("--mood"):
		art.pick(String(args[args.find("--mood") + 1]))
	if args.has("--roster"):
		for i in char_order.size():
			var p := spawn_character(String(char_order[i]))
			p.scale = Vector3.ONE
			place(p, Vector3(-1.6 + (i % 5) * 0.8, 0, -0.9 + int(i / 5) * 0.75), 0.0)
		if host:
			host.visible = false
	if args.has("--cast"):   # spawn these roster ids next to each other (screenshots, tests)
		var ids := String(args[args.find("--cast") + 1]).split(",")
		for i in ids.size():
			if chars.has(ids[i]):
				var p := spawn_character(ids[i])
				p.scale = Vector3.ONE
				place(p, Vector3(-0.45 + i * 0.9, 0, 0.6), 0.0)
	if args.has("--physics"):   # lay out a physics set piece next to the controlled character
		for pre in String(args[args.find("--physics") + 1]).split(","):
			physics_preset(pre)
	if args.has("--stage"):
		for k in range(1, int(args[args.find("--stage") + 1]) + 1):
			set_stage(k)
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
		for what in String(args[args.find("--open") + 1]).split(","):
			match what:
				"maps": hud.open_world("Maps")
				"controls": hud.open_world("Controls")
				"settings": hud.open_world("Settings")
				"look": hud.open_world("Look")
				_: hud.set_box(what, true)
	if args.has("--aim"):
		builder.begin(String(args[args.find("--aim") + 1]))
	if args.has("--clean"):
		set_clean_hud(true)
	if args.has("--bubbles"):   # every reaction bubble over the cast, for a contact sheet
		var who := _actors().filter(func(n): return n.visible)
		for i in mini(Bubbles.IDS.size(), who.size()):
			bubbles.show_bubble(who[i], String(Bubbles.IDS[i]), 9999.0)
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

## Illustrated Ink lights the map with its mood (Look); Studio Vinyl uses the map's own sun and ambient.
func _apply_lighting(info: Dictionary) -> void:
	_base_sky = Color(String(info["sky"]))
	art.map_changed(info)
	if Look.illustrated():
		return
	var s: Dictionary = info.get("sun", {"rot": [-50, 35, 0], "color": "#ffffff", "energy": 0.4})
	sun.rotation_degrees = v3(s["rot"])
	sun.light_color = Color(String(s["color"]))
	sun.light_energy = float(s["energy"])
	env.ambient_light_color = Color(String(info.get("ambient", "#dff1ff")))
	env.ambient_light_energy = float(info.get("ambient_energy", 0.55))
	_base_sun = sun.light_energy
	_base_ambient = env.ambient_light_energy
	_base_sky = Color(String(info["sky"]))
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
	world.configure(info)
	physics.map_changed(world)   # colliders from the map's meshes (before the host is spawned)
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
	hud.refresh_maps()
	hud.refresh_character()

func set_expansion(id: String, on: bool) -> void:
	world.set_expansion(id, on)
	expansions_on[id] = on
	physics.build_static(world)
	hud.refresh_maps()

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
	n.add_child(Ink.rim(mesh, thick, occ.get("c", []), occ.get("r", []), true))
	return n

func _lit() -> Material:
	return Style.toon(Color.WHITE, true, {"kind": "character"})

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
		if Look.illustrated():   # past white, so it blooms
			m.albedo_color = Color(1.56, 1.56, 1.56)
		m.set_meta("glow", true)
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
	door.material_override = Style.glow(Color("#7fd4ff"), 0.6) if Look.illustrated() else m
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

## After a look switch: rebuild the map and the cast with the new materials, keeping everyone's place.
func rebuild_look() -> void:
	var keep: Array = []
	for p in cast:
		if is_instance_valid(p) and _has(p):
			keep.append([id_of(p), motion[p]["pos"], motion[p]["yaw"], p == actor])
	clear_cast()
	load_scene(scene_name)
	for k in keep:
		var p := spawn_character(String(k[0]), bool(k[3]))
		p.scale = Vector3.ONE
		place(p, k[1], k[2])

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
## Character actions: hop, expr_1..expr_6, emote_wave/point/facepalm/shrug, ability_1..ability_5.
## `human` casts respect ability cooldowns; the Director's never wait.
func act(n: Node3D, action: String, human := false) -> void:
	if not _has(n):
		return
	if action.begins_with("ability_"):
		var list := abilities.for_actor(n)
		var k := int(action.substr(8)) - 1
		if k >= 0 and k < list.size():
			if abilities.cast(n, String(list[k]["id"]), human) and human and director.overdub:
				director.record_ability(String(list[k]["id"]))
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
	elif action.begins_with("bubble_"):
		bubbles.show_bubble(n, action.substr(7))

func walk_to(n: Node3D, at: Vector3) -> void:
	if _has(n):
		motion[n]["target"] = Vector3(at.x, 0, at.z)

func face(n: Node3D, yaw: float) -> void:
	if _has(n):
		motion[n]["yaw"] = yaw

## Speaks a line with the character's voice preset; shows its captions; returns the duration.
func say(n: Node3D, audio: String, text: String, duration := -1.0) -> float:
	if not _has(n):
		return 0.0
	var d := voice.say(n, voice_of(n), audio, text, duration)
	if text != "":
		hud.show_line(_name_of(n), text, voice.clock + d + 0.3)
	return d

func _trigger(action: String) -> void:
	match action:
		"cam_static", "cam_slider", "cam_drone", "cam_follow":
			if director.drives_camera():
				director.cam_cut_live(CAM_KEYS[action])
			else:
				_set_rig({"cam_static": "static", "cam_slider": "slider", "cam_drone": "drone", "cam_follow": "follow"}[action])
		"fly":
			if not director.playing or director.paused: # free fly is studio-only: recordings never drift
				_toggle_fly()
		"tb_camera": hud.toggle_box("camera")
		"tb_character": hud.toggle_box("character")
		"timeline": hud.toggle_box("timeline")
		"maps":
			if hud.is_open("world"):
				hud.set_box("world", false)
			else:
				hud.open_world("Maps")
		"controls": hud.open_world("Controls")
		"cast": hud.toggle_box("cast")
		"director": hud.toggle_box("director")
		"hide_all": hud.toggle_hide_all()
		"mood_next": art.cycle()
		"physics": hud.toggle_box("physics")
		"physics_kick": physics_kick()
		"play_pause": director.toggle_pause()
		"overdub": director.toggle_overdub()
		"take_toggle": director.toggle_take()
		"take_merge": director.merge_take()
		"take_discard": director.discard_take()
		"cam_key": director.record_cam_key()
		"next_actor": cycle_control()
		"path_pin": builder.drop_pin()
		"path_undo": builder.undo_pin()
		"path_finish": builder.finish()
		"path_preview": builder.preview()
		"path_shorter": builder.duration = maxf(2.0, builder.duration - 0.5)
		"path_longer": builder.duration = minf(20.0, builder.duration + 0.5)
		"chaos_1", "chaos_2", "chaos_3", "chaos_drain", "chaos_next":
			var s := {"chaos_1": 1, "chaos_2": 2, "chaos_3": 3, "chaos_drain": 0}.get(action, 0 if stage >= 3 else stage + 1) as int
			set_stage(s)
			if director.overdub:
				director.record_chaos(s)
		"cancel":
			if builder.aiming:
				builder.cancel()
			elif director.playing and hud_clean:
				director.stop(true)
			else:
				hud.close_windows()
		_:
			act(actor, action, true)
			if director.overdub and not action.begins_with("ability_"):
				director.record_action(action)

## Polls the InputMap once per frame. Typing in a search box blocks every hotkey except Esc.
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
		_trigger(action)
	# hold Talk: live test voice through the character's preset (Space rises instead while flying)
	var talking := Input.is_action_pressed("talk") and not flying and not typing
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
	if rig == "follow":
		_update_follow(dt)
		return
	var p := rig_pose(rig)
	cam.position = p[0]
	cam.look_at(p[1], Vector3.UP)
	cam.fov = p[2]

# ── physics (StudioPhysics.gd) ────────────────────────────────────────────────────
## Drops a physics object beside the controlled character. Recorded into the shot while overdubbing.
func physics_drop(id: String) -> void:
	var f := physics.frame_near(actor if _has(actor) else null)
	var at: Vector3 = f[0] + Vector3.UP * 1.1
	var yaw := float(physics.objects.size()) * 0.7
	physics.spawn(id, at, yaw)
	if director.overdub:
		director.record_physics("spawn", id, {"at": [at.x, at.y, at.z], "yaw": rad_to_deg(yaw)})

## Lays out a set piece (crate pyramid, domino run, bowling strike...) beside the controlled character.
func physics_preset(id: String) -> void:
	var f := physics.frame_near(actor if _has(actor) else null, 1.6)
	physics.spawn_preset(id, f[0], f[1])
	if director.overdub:
		var o: Vector3 = f[0]
		var u: Vector3 = f[1]
		director.record_physics("preset", id, {"at": [o.x, o.y, o.z], "u": [u.x, u.z]})

func physics_kick() -> void:
	if _has(actor) and physics.kick_from(actor) and director.overdub:
		director.record_physics("kick", null, {}, id_of(actor))

# ── follow camera (after DOGWALK's camera, Blender Studio, CC-BY 4.0) ─────────────
var _idle_t := 0.0
var _follow: Array = []

## Keeps a subject and a partner in frame. The camera sits in front of the pair and pulls back and
## tilts down as they separate. push (0..1) dollies in, used for the slow push-in while nobody moves.
func frame_pair(a: Node3D, b: Node3D, push := 0.0, high := false) -> Array:
	var pa := a.global_position
	var pb := b.global_position if b != null else pa
	var ha := height_of(a)
	var h := maxf(ha, height_of(b)) if b != null else ha
	var across := Vector3(pb.x - pa.x, 0, pb.z - pa.z)
	var sep := across.length()
	var zoom := clampf(remap(sep, 0.5, 4.0, 0.0, 1.0), 0.0, 1.0)
	var mid := pa.lerp(pb, lerpf(0.4, 0.5, zoom))
	var front: Vector3
	if sep > 0.25:
		front = Vector3(-across.z, 0, across.x).normalized()
		if front.z < 0.0:
			front = -front   # stay on the set's open side
	else:
		front = (Vector3(sin(a.rotation.y), 0, cos(a.rotation.y)) + Vector3(0, 0, 1.2)).normalized()
	var pitch := deg_to_rad(lerpf(24.0, 40.0, zoom) if high else lerpf(13.0, 28.0, zoom))
	var dist := lerpf(h * 2.7 + 0.7, sep * 1.35 + h * 2.2 + 1.1, zoom) * lerpf(1.0, 0.7, push)
	var look_at := mid + Vector3(0, h * 0.62, 0)
	var pos := look_at + front * cos(pitch) * dist + Vector3(0, sin(pitch) * dist, 0)
	return [pos, look_at, lerpf(42.0, 38.0, zoom)]

## The nearest other visible character within reach, or null.
func partner_of(a: Node3D, reach := 5.0) -> Node3D:
	var best: Node3D = null
	var best_d := reach
	for n: Node3D in _actors():
		if n == a or not n.is_visible_in_tree():
			continue
		var d: float = n.global_position.distance_to(a.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best

func _anyone_moving() -> bool:
	for n in _actors():
		var m: Dictionary = motion[n]
		if float(m["moving"]) > 0.05 or float(m["hop"]) > 0.0:
			return true
	return false

## Live follow rig: eased toward the pair framing; after a few still seconds it slowly pushes in.
func _update_follow(dt: float) -> void:
	if not _has(actor):
		return
	var want := frame_pair(actor, partner_of(actor), smoothstep(3.0, 10.0, _idle_t) * 0.85, true)
	if _follow.is_empty():
		_follow = want
	else:
		var k := 1.0 - exp(-dt * 3.0)
		_follow = [(_follow[0] as Vector3).lerp(want[0], k), (_follow[1] as Vector3).lerp(want[1], k), lerpf(_follow[2], want[2], k)]
	cam.position = _follow[0]
	cam.look_at(_follow[1], Vector3.UP)
	cam.fov = _follow[2]

func _update_fly(dt: float) -> void:
	var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back") + joy_vec
	var fx := mv.x
	var fz := mv.y
	var fy := (1.0 if Input.is_action_pressed("fly_up") else 0.0) - (1.0 if Input.is_action_pressed("fly_down") else 0.0)
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
	if r == "follow" and rig != "follow":
		_follow = []
	rig = r
	_update_hud()

func _capture_fly() -> void:
	var dir := -cam.global_transform.basis.z
	fly_pos = cam.global_position
	fly_yaw = atan2(-dir.x, -dir.z)
	fly_pitch = asin(clampf(dir.y, -1.0, 1.0))

# ── director hooks ────────────────────────────────────────────────────────────────
## Resets the animation clock at the start of a shot, so every shot replays identically.
## Running ability casts keep their elapsed time across the reset.
func reset_clock() -> void:
	abilities.shift_time(-t)
	bubbles.clear()
	t = 0.0
	_last_anim_t = 0.0
	slider_t = 0.0
	for m in motion.values():
		m["hop_start"] = -100.0
		m["hop"] = 0.0

func on_director_start(clean: bool) -> void:
	if rig == "free":
		_set_rig("static")
	if builder.aiming:
		builder.cancel()
	hud.close_windows()
	set_clean_hud(clean)

func on_director_stop(_take_over: bool) -> void:
	set_clean_hud(false)
	if host:
		host.visible = true
	_update_hud()

## Clean HUD hides every overlay except subtitles, for recording. A tap or Esc takes over.
func set_clean_hud(on: bool) -> void:
	hud_clean = on
	hud.set_clean(on)
	hud.joy_pad.active = false

func _on_director_changed() -> void:
	hud.refresh_timeline()
	hud.refresh_camera()
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
	if not builder.update_preview(cam, dt):
		_update_camera(dt)
	_idle_t = 0.0 if _anyone_moving() else _idle_t + dt
	if chaos_shake > 0.0 and rig != "free":
		cam.position += Vector3(sin(t * 37.0) + sin(t * 23.0), sin(t * 29.0 + 1.0), sin(t * 31.0 + 2.0)) * 0.025 * chaos_shake
	art.tick(dt)
	bubbles.tick()
	physics.set_paused(director.playing and director.paused)
	_update_portals()
	hud.sync()
	_update_context()

## One simulation step. live = false while fast-forwarding (no human input, no sound).
func _step(dt: float, live: bool) -> void:
	t += dt
	# world effects are rebuilt every step: map chaos first, then running ability casts on top
	chaos_shake = 0.0
	lowgrav = false
	slippery = false
	light_scale = 1.0
	flash = 0.0
	ability_flood = 0.0
	art.reset_fog()
	director.process_shot(dt)
	_update_actors(dt, live)
	world.chaos_tick(t, self)
	abilities.tick(t, dt)
	_update_flood(dt)
	_apply_chaos_light()
	voice.tick(dt)
	_animate(dt)

func _update_actors(dt: float, live: bool) -> void:
	var mv := Vector2.ZERO
	if live and rig != "free" and not hud_clean and not _shot_mode and not builder.aiming:
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
	var hop_time := HOP_TIME * (2.2 if lowgrav else 1.0)
	var hop_h := HOP_HEIGHT * (2.6 if lowgrav else 1.0)
	m["hop"] = hop_h * sin(PI * clampf((t - float(m["hop_start"])) / hop_time, 0.0, 1.0))
	if lowgrav:
		m["hop"] += 0.06 + sin(t * 1.7 + float(m["pos"].x)) * 0.04
	if slippery and m["moving"] > 0.1:
		m["yaw"] = float(m["yaw"]) + sin(t * 13.0 + float(m["pos"].z) * 3.0) * 0.9
	m["bob"] = maxf(0.0, sin(t * 9.0)) * 0.13 * m["moving"] if kind == "frog" else 0.0
	var pos: Vector3 = m["pos"]
	var ground := world.ground(pos.x, pos.z)
	n.position = Vector3(pos.x, ground + m["hop"] + m["bob"], pos.z)
	n.rotation.y = lerp_angle(n.rotation.y, m["yaw"], 1.0 - exp(-dt * 12.0))
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

## Poses every frame at the real frame time (smooth 30 fps+; Movie Maker locks it to 30 / 60).
func _animate(dt: float) -> void:
	var ta := t
	var ad := dt
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
	# an ability flood (tide, geyser, spill) rides on top of the map's own flood
	if ability_flood > flood + 0.002:
		water.set_level(ability_flood, t)
		water.set_color(ability_liquid)
	else:
		water.set_level(flood, t)
		water.set_color(_liquid)

## Blackouts dim the set and the sky; lightning flashes everything bright for a beat.
func _apply_chaos_light() -> void:
	if Look.illustrated():
		art.apply_light(light_scale, flash)
		return
	env.ambient_light_energy = _base_ambient * light_scale + flash * 1.2
	sun.light_energy = _base_sun * light_scale + flash * 1.4
	var sky := _base_sky.darkened(1.0 - lerpf(0.25, 1.0, light_scale)).lerp(Color.WHITE, clampf(flash, 0.0, 1.0) * 0.8)
	env.background_color = sky

func set_stage(s: int) -> void:
	stage = s
	var levels: Array = maps[scene_name].get("flood", [0, 0.1, 0.32, 0.82])
	flood_target = float(levels[clampi(s, 0, levels.size() - 1)])
	# the stage's liquid colour (foam, milkshake, sea...) or plain water
	var stages: Array = maps[scene_name].get("chaos_stages", [])
	var liquid := Style.swatch("bondi_blue", "light")
	for k in range(s, 0, -1):
		if k - 1 < stages.size() and stages[k - 1].has("water"):
			liquid = Style.snap(Color(String(stages[k - 1]["water"])))
			break
	_liquid = liquid
	water.set_color(liquid)
	world.chaos_set(s, t, self)
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
			if hud.over_ui(pos):
				return
			if pos.x < vp.x * 0.42 and joy_id == -1 and pos.y > vp.y * 0.35:
				joy_id = idx
				joy_origin = pos
				joy_down_t = t
				joy_vec = Vector2.ZERO
				hud.joy_pad.origin = pos
				hud.joy_pad.knob = pos
				hud.joy_pad.active = true
			elif pos.x >= vp.x * 0.42 and look_id == -1:
				look_id = idx
				last_look = pos
				look_origin = pos
				look_down_t = t
		else:
			if idx == joy_id:
				joy_id = -1
				joy_vec = Vector2.ZERO
				hud.joy_pad.active = false
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
			hud.joy_pad.knob = hud.joy_pad.origin + d.limit_length(70.0)
		elif idx == look_id:
			var rel: Vector2 = event.position - last_look
			look += rel
			last_look = event.position

func _toggle_fly() -> void:
	_set_rig("static" if rig == "free" else "free")

# ── HUD glue (the HUD itself lives in ui/StudioHUD.gd) ──────────────────────────
## Lets go of any joystick / look touch (when a window opens over it).
func _release_touch() -> void:
	joy_id = -1
	look_id = -1
	joy_vec = Vector2.ZERO
	if hud and hud.joy_pad:
		hud.joy_pad.active = false

func _update_hud() -> void:
	if hud:
		hud.update_label()

func update_director_status() -> void:
	if hud and hud.director_status:
		hud.director_status.text = director.status_text()

func _save_episode() -> void:
	if director.ep.is_empty():
		director.select_episode(hud.timeline_episode())
	var paths := director.save()
	if not paths.is_empty():
		hud.show_subtitle("Saved: " + ", ".join(paths), voice.clock + 2.5)
	print("[save] ", paths)

## Loads a map with a quick fade through black.
func _travel(id: String) -> void:
	hud.set_box("world", false)
	var tw := create_tween()
	tw.tween_property(hud.fade, "color:a", 1.0, 0.18)
	tw.tween_callback(func(): load_scene(id))
	tw.tween_property(hud.fade, "color:a", 0.0, 0.28)

## Context tips: the live keys for what you are doing right now.
func _update_context(force := false) -> void:
	var id := "default"
	var icon := "💡"
	var text := ""
	var k := Controls.key_label
	if hud_clean:
		id = "clean"
	elif builder.aiming:
		id = "aim_" + builder.kind
		icon = "🎥"
		text = "Frame the view, then Drop Pin [%s] · Undo [%s] · Finish [%s] · Preview [%s] · Esc cancels" % [k.call("path_pin"), k.call("path_undo"), k.call("path_finish"), k.call("path_preview")]
	elif director.take_active():
		id = "take"
		icon = "🔴"
		text = "Recording a live take: perform now · Stop Take [%s] · Camera keyframe [%s]" % [k.call("take_toggle"), k.call("cam_key")]
	elif not director.pending_take.is_empty():
		id = "pending"
		icon = "⇩"
		text = "Take stopped: Merge it into the shot [%s] or Discard [%s]" % [k.call("take_merge"), k.call("take_discard")]
	elif director.playing and director.paused:
		id = "paused"
		icon = "⏸"
		text = "Paused: scrub the timeline · start a live Take [%s] from here · Play [%s]" % [k.call("take_toggle"), k.call("play_pause")]
	elif director.playing:
		id = "playing"
		icon = "🎬"
		text = "Shot playing · Pause [%s] · Overdub [%s] · camera keys cut the shot" % [k.call("play_pause"), k.call("overdub")]
	elif rig == "free":
		id = "fly"
		icon = "🛸"
		text = "Free fly: WASD along your view · drag to look · %s rise · Fly [%s] to exit" % [k.call("fly_up"), k.call("fly")]
	else:
		text = "Walk WASD · Talk %s · Emotes %s %s %s %s · Abilities %s %s %s %s %s · Controls [%s]" % [k.call("talk"),
			k.call("emote_wave"), k.call("emote_point"), k.call("emote_facepalm"), k.call("emote_shrug"),
			k.call("ability_1"), k.call("ability_2"), k.call("ability_3"), k.call("ability_4"), k.call("ability_5"), k.call("controls")]
	if id != _context or force:
		_context = id
		hud.banner.show_tip(id, icon, text)

extends Node3D

## Galaughxy studio root. Persistent across maps: camera rig, HUD, cast and the On Twos clock.
## Maps are .tscn scenes listed in res://data/maps.json and loaded into MapContainer; the cast
## (res://data/characters.json) lives in CastRoot, so spawned characters survive map changes and
## are moved to the new map's spawn points. Each map also has a host actor (the robo or the frog).
## Controls work on keyboard and touch: WASD / left thumb moves whoever you control, Tab or a tap on
## a character switches control, 1-6 expressions, Space talk, F hop, Q/E/R/T chaos, I cast, M maps.

const EXPRS := ["DEADPAN", "SMIRK", "PANIC", "ANGRY", "HAPPY", "SHOCKED"]
const LIDS := {
	"DEADPAN": [-0.3, -0.3, 0.0, 1.0], "SMIRK": [-0.2, -1.0, 0.15, 1.0], "PANIC": [-1.45, -1.45, 0.0, 1.22],
	"ANGRY": [-0.4, -0.4, 0.5, 0.95], "HAPPY": [-0.05, -0.05, -0.25, 1.0], "SHOCKED": [-1.55, -1.55, 0.0, 1.3],
}
const WALK := 1.7
const HOP := 1.1
const CATEGORIES := [["All", "All"], ["Robo", "Robos"], ["Animal", "Animals"], ["Hybrid", "Hybrids"]]

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

var scene_name := ""
var rig := "static"
var custom_cam: Array = []
var fly_pos := Vector3.ZERO
var fly_yaw := 0.0
var fly_pitch := 0.0
var look := Vector2.ZERO

# who is being controlled: the map's host (robo / frog) or a cast puppet
var host: Node3D
var host_kind := ""
var host_expr_i := 0
var cast: Array = []
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
var hud_label: Label
var map_panel: Panel
var cast_panel: Panel
var maps_list: VBoxContainer
var cast_grid: GridContainer
var cast_cards: Array = []
var cast_filter := "All"
var cast_search: LineEdit
var cast_status: Label
var twos_button: Button
var fade: ColorRect
var map_open := false
var cast_open := false
var keys := {}
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

func _ready() -> void:
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
	_setup_hud()
	var args := OS.get_cmdline_user_args()
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
			p.position = Vector3(-1.6 + (i % 5) * 0.8, 0, -0.9 + int(i / 5) * 0.75)
		if host:
			host.visible = false
	if args.has("--rig"):
		_set_rig(args[args.find("--rig") + 1])
	if args.has("--cam"):
		custom_cam = Array(String(args[args.find("--cam") + 1]).split(",")).map(func(v): return float(v))
		rig = "custom"
	if args.has("--open"):
		match String(args[args.find("--open") + 1]):
			"cast": _toggle_cast()
			"maps": _toggle_map()
	if args.has("--shot"):
		_shot_and_quit(args[args.find("--shot") + 1])
	if args.has("--test"):
		test_runner = SelfTest.new(self)
		test_runner.run()

func _shot_and_quit(path: String) -> void:
	for i in 90:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("[shot] ", path)
	print("[ink] builds %d, avg %.2f ms" % [InkStroke.builds, InkStroke.build_ms / maxi(1, InkStroke.builds)])
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
	var s: Dictionary = info.get("sun", {"rot": [-55, 35, 0], "color": "#ffffff", "energy": 0.9})
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
	for p in info.get("portals", []):
		_portal(v3(p["at"]), float(p["yaw"]), String(p["to"]))
	# the cast follows you to the new map's spawn points
	var spots := world.spawn_points()
	for i in cast.size():
		var pup: Puppet = cast[i]
		var spot: Vector3 = spots[i % spots.size()] if spots.size() > 0 else Vector3(0, 0, 1)
		spot += Vector3(0.45 * int(i / maxi(1, spots.size())), 0, 0)
		pup.position = Vector3(spot.x, world.ground(spot.x, spot.z), spot.z)
	if was_host or not (actor is Puppet):
		actor = null
		if host:
			_take_control(host)
	else:
		actor_pos = Vector3(actor.position.x, 0, actor.position.z)
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
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.7
	return m

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
	var parts := RoboParts.parts(Color("#4aa3df"))
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
func spawn_character(id: String) -> Puppet:
	var p := Puppet.create(chars[id])
	cast_root.add_child(p)
	var spots := world.spawn_points()
	var n := cast.size()
	var spot: Vector3 = spots[n % spots.size()] if spots.size() > 0 else Vector3(0, 0, 1)
	spot += Vector3(0.45 * int(n / maxi(1, spots.size())), 0, 0)
	p.position = Vector3(spot.x, world.ground(spot.x, spot.z), spot.z)
	p.scale = Vector3.ONE * 0.01
	var tw := create_tween()
	tw.tween_property(p, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	cast.append(p)
	_take_control(p)
	return p

func despawn_selected() -> void:
	if not (actor is Puppet):
		return
	var p: Puppet = actor
	cast.erase(p)
	p.queue_free()
	actor = null
	if host:
		_take_control(host)
	_update_hud()

func clear_cast() -> void:
	for p in cast:
		(p as Node).queue_free()
	cast.clear()
	actor = null
	if host:
		_take_control(host)
	_update_hud()

func _take_control(n: Node3D) -> void:
	if n == null or n == actor:
		return
	if actor is Puppet and is_instance_valid(actor):
		(actor as Puppet).expr_i = expr_i
		(actor as Puppet).moving = 0.0
		(actor as Puppet).talk = false
	elif actor != null and actor == host:
		host_expr_i = expr_i
	actor = n
	actor_kind = "puppet" if n is Puppet else host_kind
	actor_pos = Vector3(n.position.x, 0, n.position.z)
	actor_yaw = n.rotation.y
	actor_moving = 0.0
	expr_i = (n as Puppet).expr_i if n is Puppet else host_expr_i
	_update_hud()

func cycle_control() -> void:
	var list: Array = []
	if host:
		list.append(host)
	list.append_array(cast)
	if list.is_empty():
		return
	var i := list.find(actor)
	_take_control(list[(i + 1) % list.size()])

## Tap a character on screen to control it.
func _pick(screen: Vector2) -> bool:
	var best: Node3D = null
	var best_d := 90.0
	var list: Array = cast.duplicate()
	if host:
		list.append(host)
	for n in list:
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

# ── cameras ───────────────────────────────────────────────────────────────────────
func _update_camera(dt: float) -> void:
	if rig == "free":
		_update_fly(dt)
		return
	if rig == "custom" and custom_cam.size() >= 7:
		cam.position = Vector3(custom_cam[0], custom_cam[1], custom_cam[2])
		cam.look_at(Vector3(custom_cam[3], custom_cam[4], custom_cam[5]), Vector3.UP)
		cam.fov = custom_cam[6]
		return
	var c: Dictionary = maps[scene_name]["cams"]
	var pos: Vector3
	var target: Vector3
	var fov: float
	match rig:
		"slider":
			var s: Array = c["slider"]
			pos = v3(s[0]).lerp(v3(s[1]), smoothstep(0.0, 1.0, slider_t))
			target = pos + v3(s[2])
			fov = float(s[3])
		"drone":
			var d: Array = c["drone"]
			var a := t * 0.07
			pos = v3(d[0]) + Vector3(sin(a) * float(d[1]), float(d[2]) + sin(t * 1.3) * 0.06, cos(a) * float(d[1]))
			target = v3(d[0])
			fov = float(d[3])
		_:
			var st: Array = c["static"]
			pos = v3(st[0])
			target = v3(st[1])
			fov = float(st[2])
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

## While flying only Maps, Cast, Fly and PNG stay on screen; the other buttons are hidden.
func _sync_fly_hud() -> void:
	var flying := rig == "free"
	for b in hud_buttons:
		var keep: bool = (b as Button).text in ["🗺 Maps", "🎭 Cast", "🛸 Fly", "PNG"]
		b.visible = keep or not flying
	if flying:
		keys.clear()

func _capture_fly() -> void:
	var dir := -cam.global_transform.basis.z
	fly_pos = cam.global_position
	fly_yaw = atan2(-dir.x, -dir.z)
	fly_pitch = asin(clampf(dir.y, -1.0, 1.0))

# ── per frame ─────────────────────────────────────────────────────────────────────
func _process(dt: float) -> void:
	t += dt
	# On Twos: character poses and positions update 12 times a second; the camera stays smooth
	if on_twos:
		var f := int(floor(t * 12.0))
		twos_tick = f != _twos_last
		if twos_tick:
			_twos_last = f
	else:
		twos_tick = true
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
	_animate(dt)

func _update_actor(dt: float) -> void:
	if actor == null or not is_instance_valid(actor) or rig == "free" or _drawer_open():
		actor_moving = lerpf(actor_moving, 0.0, minf(1.0, dt * 8.0))
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
	if actor_kind == "frog":
		actor_hop = maxf(0.0, sin(t * 9.0)) * 0.13 * actor_moving + hop_lift
	else:
		actor_hop = hop_lift
	if not twos_tick:
		return
	var ground := world.ground(actor_pos.x, actor_pos.z)
	actor.position = Vector3(actor_pos.x, ground + actor_hop, actor_pos.z)
	var turn_k := 1.0 if on_twos else minf(1.0, dt * 10.0)
	actor.rotation.y = lerp_angle(actor.rotation.y, actor_yaw, turn_k)
	# the frog and the cast float when the flood is deep; the robo stays on the floor
	if actor_kind != "robo" and flood > ground + 0.12:
		actor.position.y = flood - (0.17 if actor_kind == "frog" else 0.06) + sin(t * 2.0) * 0.01

func _update_portals() -> void:
	if actor == null or not is_instance_valid(actor):
		return
	for p in portal_nodes:
		if Vector2(actor_pos.x - p["at"].x, actor_pos.z - p["at"].z).length() < 0.9:
			load_scene(p["to"])
			return

func _animate(dt: float) -> void:
	if not twos_tick:
		return
	var ta: float = floor(t * 12.0) / 12.0 if on_twos else t
	var ad: float = t - _last_anim_t if on_twos else dt
	_last_anim_t = t
	if host:
		var ctrl := actor == host
		_animate_host(ta, ad, EXPRS[expr_i if ctrl else host_expr_i], talk and ctrl, actor_moving if ctrl else 0.0)
	for p in cast:
		var pup: Puppet = p
		var ctrl := pup == actor
		pup.talk = talk and ctrl
		pup.moving = actor_moving if ctrl else lerpf(pup.moving, 0.0, minf(1.0, ad * 8.0))
		if ctrl:
			pup.expr_i = expr_i
			pup.hop = hop_lift
		else:
			pup.hop = 0.0
			var g := world.ground(pup.position.x, pup.position.z)
			pup.position.y = (flood - 0.06 + sin(ta * 2.0 + pup.position.x) * 0.01) if flood > g + 0.12 else g
		pup.flood_over = flood > world.ground(pup.position.x, pup.position.z) + 0.03
		pup.animate(ta, ad)

func _animate_host(ta: float, dt: float, expr: String, talking: bool, mv: float) -> void:
	if host_kind == "frog" and not frog_parts.is_empty():
		var L: Array = LIDS[expr]
		var blink := 1.5 if fmod(ta, 3.7) < 0.12 else 0.0
		frog_parts["lidL"].rotation = Vector3(maxf(L[0], blink), 0, L[2])
		frog_parts["lidR"].rotation = Vector3(maxf(L[1], blink), 0, -L[2])
		frog_parts["eyeL"].scale = Vector3.ONE * L[3]
		frog_parts["eyeR"].scale = Vector3.ONE * L[3]
		var target := 0.0
		if talking:
			target = maxf(0.0, sin(ta * 14.0) + sin(ta * 21.0) * 0.5) * 0.24
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
		head.position.y = 0.5 + (absf(sin(ta * 9.0)) * 0.02 if talking else 0.0)
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

# ── input ─────────────────────────────────────────────────────────────────────────
## Free-fly uses Minecraft-style keys only: WASD moves along the view, Space rises, drag/touch looks.
const FLY_KEYS := ["w", "a", "s", "d", "up", "down", "left", "right", "space", "n", "m", "i", "p", "escape"]

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null:
		return
	var name := _key_name(k)
	if rig == "free" and not FLY_KEYS.has(name):
		return # every other command is off while flying
	if _drawer_open() and not name in ["escape", "m", "i"]:
		return
	if k.pressed and not k.echo:
		match name:
			"space":
				talk = true
			"1", "2", "3", "4", "5", "6":
				expr_i = int(name) - 1
				_update_hud()
			"z": _set_rig("static")
			"x": _set_rig("slider")
			"c": _set_rig("drone")
			"n": _toggle_fly()
			"m": _toggle_map()
			"i": _toggle_cast()
			"tab": cycle_control()
			"o": _toggle_twos()
			"q": set_stage(1)
			"e": set_stage(2)
			"r": set_stage(3)
			"t": set_stage(0)
			"g": advance_chaos()
			"f": _hop()
			"p": _save_png()
			"escape": _close_drawers()
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
		KEY_TAB: return "tab"
	return k.as_text_keycode().to_lower()

func _input(event: InputEvent) -> void:
	var vp := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		var pressed: bool = event.pressed
		var pos: Vector2 = event.position
		var idx: int = event.index if event is InputEventScreenTouch else 0
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
				if pos.distance_to(joy_origin) < 12.0 and t - joy_down_t < 0.35:
					_pick(pos)
			if idx == look_id:
				look_id = -1
				if pos.distance_to(look_origin) < 12.0 and t - look_down_t < 0.35:
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
	return false

func _toggle_fly() -> void:
	_set_rig("static" if rig == "free" else "free")

func _toggle_twos() -> void:
	on_twos = not on_twos
	_update_hud()

func _hop() -> void:
	var tw := create_tween()
	tw.tween_property(self, "hop_lift", 0.2, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "hop_lift", 0.0, 0.24).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

func _save_png() -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "user://galaughxy-%d.png" % Time.get_unix_time_from_system()
	img.save_png(path)
	print("[png] ", ProjectSettings.globalize_path(path))

# ── HUD ───────────────────────────────────────────────────────────────────────────
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
	# top-left claws
	var row := HBoxContainer.new()
	row.position = Vector2(12, 34)
	row.add_theme_constant_override("separation", 8)
	layer.add_child(row)
	for entry in [["🗺 Maps", "m"], ["🎭 Cast", "i"], ["🛸 Fly", "n"], ["Static", "z"], ["Slider", "x"], ["Drone", "c"], ["12fps", "o"], ["PNG", "p"]]:
		var b := _button(entry[0], Vector2(88, 44))
		b.pressed.connect(func(): _key_pressed(entry[1]))
		if entry[1] == "o":
			b.toggle_mode = true
			twos_button = b
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
	var talk_b := _button("TALK (hold)", Vector2(180, 64))
	talk_b.button_down.connect(func(): talk = true)
	talk_b.button_up.connect(func(): talk = false)
	acts.add_child(talk_b)
	hud_buttons.append(talk_b)
	var face := _button("FACE", Vector2.ZERO)
	face.pressed.connect(func(): expr_i = (expr_i + 1) % 6; _update_hud())
	acts.add_child(face)
	hud_buttons.append(face)
	var hop := _button("HOP", Vector2.ZERO)
	hop.pressed.connect(_hop)
	acts.add_child(hop)
	hud_buttons.append(hop)
	var chaos := _button("CHAOS", Vector2.ZERO)
	chaos.pressed.connect(advance_chaos)
	acts.add_child(chaos)
	hud_buttons.append(chaos)
	_build_cast_drawer(layer)
	_build_maps_drawer(layer)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(fade)

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

func _build_cast_drawer(layer: CanvasLayer) -> void:
	var pv := _drawer_panel()
	cast_panel = pv[0]
	var v: VBoxContainer = pv[1]
	layer.add_child(cast_panel)
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

func _build_maps_drawer(layer: CanvasLayer) -> void:
	var pv := _drawer_panel()
	map_panel = pv[0]
	var v: VBoxContainer = pv[1]
	layer.add_child(map_panel)
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
		var card := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.2, 0.3, 0.45, 0.9) if current else Color(0.17, 0.18, 0.22, 0.9)
		sb.set_corner_radius_all(14)
		sb.set_content_margin_all(12)
		card.add_theme_stylebox_override("panel", sb)
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

func _key_pressed(k: String) -> void:
	var ev := InputEventKey.new()
	ev.keycode = OS.find_keycode_from_string(k)
	ev.pressed = true
	Input.parse_input_event(ev)
	var rel := InputEventKey.new()
	rel.keycode = ev.keycode
	rel.pressed = false
	Input.parse_input_event(rel)

func _drawer_open() -> bool:
	return map_open or cast_open

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

func _close_drawers() -> void:
	map_open = false
	cast_open = false
	map_panel.visible = false
	cast_panel.visible = false
	joy_id = -1
	look_id = -1
	joy_vec = Vector2.ZERO
	joy_pad.active = false

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
	var who := _name_of(actor) if actor != null and is_instance_valid(actor) else "-"
	hud_label.text = "%s · %s    [%s · %s · chaos: %s · 🎭 %s%s]" % [info["title"], info["tag"], rig, EXPRS[expr_i], chaos, who, " · 12fps" if on_twos else ""]
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

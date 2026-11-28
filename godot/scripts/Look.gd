class_name Look
extends Node

## The studio's look (CLAUDE.md section 24). Every model and map can be shown in one of two styles:
##   illustrated  Illustrated Ink (default):
##                - flat colour under one warm key light and a cool ambient
##                - a warm rim on edges that face the light
##                - near-black ink whose weight follows the light
##                - sparse hatching in the shadows
##                - a painted sky, aerial haze, depth of field and film grain
##   vinyl        Studio Vinyl (section 20): the seven Mac Studio colours, cel shading, no finishing pass.
## Moods (res://data/moods.json) are one-click lighting presets: key light, ambient, sky, fog, rim,
## hatching, depth of field and grade. Which mood is used:
##   - a map has a default mood (maps.json "mood")
##   - a hand pick holds for the current map
##   - while an episode is open, a pick belongs to the current shot ("mood" in the shot), and
##     the Director applies it whenever that shot plays.

signal changed

const SETTINGS := "user://settings.cfg"
const STYLES := {"illustrated": "✏️ Illustrated Ink", "vinyl": "🧸 Studio Vinyl"}
const TOGGLES := {"hatch": "Hatching", "rim": "Rim light", "dof": "Depth of field", "grain": "Film grain"}
## Global shader parameters (declared in project.godot [shader_globals]): ill_sun_dir, ill_ink,
## ill_rim, ill_rim_color, ill_hatch, ill_time, ill_boil.

static var style := "illustrated"

var main: Node
var moods := {}
var mood_order: Array = []
var map_defaults := {}
var mood_id := ""
var map_mood := ""
var session_mood := ""     # picked by hand for the current map (no episode open)
var shot_mood := ""        # the playing shot's mood (set by the Director)
var toggles := {"hatch": true, "rim": true, "dof": true, "grain": true}
var sky_mat: ShaderMaterial
var sky: Sky
var post_layer: CanvasLayer
var post: ColorRect
var post_mat: ShaderMaterial
var attrs: CameraAttributesPractical
var base_sun := 0.6
var base_ambient := 1.0
var focus := -1.0          # depth-of-field focus distance (metres), eased toward the subject
var _m := {}
var _chaos_fog := 0.0

## Reads the saved style (or --look illustrated|vinyl). Call before any material is made.
static func load_style() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		style = String(cf.get_value("look", "style", "illustrated"))
	var args := OS.get_cmdline_user_args()
	if args.has("--look"):
		style = String(args[args.find("--look") + 1])
	if not STYLES.has(style):
		style = "illustrated"

static func illustrated() -> bool:
	return style == "illustrated"

func _init(m: Node) -> void:
	main = m
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/moods.json"))
	for e in d["moods"]:
		moods[String(e["id"])] = e
		mood_order.append(String(e["id"]))
	map_defaults = d.get("map_defaults", {})
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		for k in toggles:
			toggles[k] = bool(cf.get_value("look", k, true))

## Builds the sky, depth of field and finishing pass. Needs main.env, main.sun and main.cam.
func setup() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/illustrated_sky.gdshader")
	sky = Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	attrs = CameraAttributesPractical.new()
	main.cam.attributes = attrs
	post_layer = CanvasLayer.new()
	post_layer.name = "LookPost"
	post_layer.layer = 0
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/illustrated_post.gdshader")
	post.material = post_mat
	post_layer.add_child(post)
	add_child(post_layer)
	# debug / profiling: --fx-off shadows,dof,post,glow,hatch
	var args := OS.get_cmdline_user_args()
	if args.has("--fx-off"):
		_fx_off = String(args[args.find("--fx-off") + 1]).split(",")
	_apply_style_env()

var _fx_off: PackedStringArray = []

func _off(what: String) -> bool:
	return _fx_off.has(what)

func _apply_style_env() -> void:
	var env: Environment = main.env
	var sun: DirectionalLight3D = main.sun
	var on := illustrated()
	post_layer.visible = on and not _off("post")
	sun.shadow_enabled = on and not _off("shadows")
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	if on:
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		env.glow_enabled = not _off("glow")
		env.glow_normalized = false
		env.glow_strength = 1.0
		env.glow_bloom = 0.0
		env.glow_hdr_threshold = 1.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
		sun.shadow_bias = 0.04
		sun.shadow_normal_bias = 1.4
		sun.shadow_blur = 1.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL   # one pass: sets are small
		sun.directional_shadow_max_distance = 22.0
	else:
		env.background_mode = Environment.BG_COLOR
		env.sky = null
		env.glow_enabled = false
		env.fog_enabled = false
		attrs.dof_blur_far_enabled = false
		attrs.dof_blur_near_enabled = false

# ── moods ─────────────────────────────────────────────────────────────────────────
## The mood in force: the playing shot's, else a hand pick for this map, else the map's default.
func current() -> String:
	for id in [shot_mood, session_mood, map_mood]:
		if id != "" and moods.has(id):
			return id
	return String(mood_order[0])

func map_changed(info: Dictionary) -> void:
	map_mood = String(info.get("mood", map_defaults.get(String(info.get("category", "")), "blue_hour")))
	session_mood = ""
	apply_mood(current())

## The Director calls this as each shot starts ("" when playback stops).
func set_shot_mood(id: String) -> void:
	if id == shot_mood and id == mood_id:
		return
	shot_mood = id
	apply_mood(current())

## A click on a mood: it belongs to the current shot while an episode is open, else to this map.
func pick(id: String) -> void:
	if not moods.has(id):
		return
	var shot := _open_shot()
	if not shot.is_empty():
		shot["mood"] = id
		main.director.dirty = true
		shot_mood = id
	else:
		session_mood = id
	apply_mood(current())

## Back to the map's own mood (or the shot's inherited one).
func clear_pick() -> void:
	var shot := _open_shot()
	if not shot.is_empty():
		shot.erase("mood")
		main.director.dirty = true
		shot_mood = ""
	session_mood = ""
	apply_mood(current())

func cycle() -> void:
	var i := mood_order.find(current())
	pick(String(mood_order[(i + 1) % mood_order.size()]))

## Where a pick goes, for the Look tab.
func target_text() -> String:
	var d = main.director
	if not _open_shot().is_empty():
		return "Mood for shot %d · %s (%s)" % [d.shot_i + 1, String(_open_shot().get("name", "")), d.peek_episode_title()]
	return "Mood for this map · %s" % String(main.maps.get(main.scene_name, {}).get("title", ""))

func _open_shot() -> Dictionary:
	var d = main.director
	if d == null or d.ep.is_empty() or d.shot_i < 0:
		return {}
	var shots: Array = d.ep.get("shots", [])
	return shots[clampi(d.shot_i, 0, shots.size() - 1)] if not shots.is_empty() else {}

func apply_mood(id: String) -> void:
	if not moods.has(id):
		id = String(mood_order[0])
	mood_id = id
	_m = moods[id]
	if illustrated():
		_apply_illustrated()
	changed.emit()

func _apply_illustrated() -> void:
	var sun: DirectionalLight3D = main.sun
	var env: Environment = main.env
	var s: Dictionary = _m["sun"]
	sun.rotation_degrees = Vector3(float(s["pitch"]), float(s["yaw"]), 0.0)
	# shadow = ambient; light = ambient + sun (both as multipliers in linear light)
	var shadow := Color(String(_m["shadow"]))
	var a := shadow.srgb_to_linear()
	var l := Color(String(_m["light"])).srgb_to_linear()
	var sl := Color(maxf(l.r - a.r, 0.0), maxf(l.g - a.g, 0.0), maxf(l.b - a.b, 0.0))
	var e := maxf(0.001, maxf(sl.r, maxf(sl.g, sl.b)))
	sun.light_color = Color(sl.r / e, sl.g / e, sl.b / e).linear_to_srgb()
	base_sun = e
	base_ambient = 1.0
	sun.light_energy = base_sun
	env.ambient_light_color = shadow
	env.ambient_light_energy = base_ambient
	RenderingServer.global_shader_parameter_set("ill_sun_dir", Basis.from_euler(sun.rotation).z.normalized())
	var rim := Color(String(_m.get("rim_color", "#FFAE6E"))).srgb_to_linear()
	RenderingServer.global_shader_parameter_set("ill_rim_color", Vector3(rim.r, rim.g, rim.b) * float(_m.get("rim_glow", 1.3)))
	var ink := Color(String(_m.get("ink", "#1C1A26"))).srgb_to_linear()
	RenderingServer.global_shader_parameter_set("ill_ink", Vector4(ink.r, ink.g, ink.b, float(_m.get("ink_alpha", 0.85))))
	var sk: Dictionary = _m.get("sky", {})
	for k in sk:
		var v = sk[k]
		sky_mat.set_shader_parameter(k, Color(String(v)) if v is String else float(v))
	sky_mat.set_shader_parameter("exposure", 1.0)
	sky_mat.set_shader_parameter("flash", 0.0)
	env.glow_intensity = float(_m.get("bloom", 0.5))
	var g: Dictionary = _m.get("grade", {})
	post_mat.set_shader_parameter("shadow_tint", _v3(g.get("shadow", [0.5, 0.5, 0.5])))
	post_mat.set_shader_parameter("light_tint", _v3(g.get("light", [0.5, 0.5, 0.5])))
	post_mat.set_shader_parameter("grade", float(g.get("amount", 0.2)))
	post_mat.set_shader_parameter("vignette", float(_m.get("vignette", 0.22)))
	_apply_toggles()
	reset_fog()

func _apply_toggles() -> void:
	RenderingServer.global_shader_parameter_set("ill_rim", float(_m.get("rim", 1.0)) if toggles["rim"] else 0.0)
	RenderingServer.global_shader_parameter_set("ill_hatch", float(_m.get("hatch", 1.0)) if toggles["hatch"] and not _off("hatch") else 0.0)
	post_mat.set_shader_parameter("grain", float(_m.get("grain", 0.035)) if toggles["grain"] else 0.0)

func set_toggle(k: String, on: bool) -> void:
	if not toggles.has(k):
		return
	toggles[k] = on
	_save(k, on)
	if illustrated() and not _m.is_empty():
		_apply_toggles()
	changed.emit()

static func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

# ── style switch ──────────────────────────────────────────────────────────────────
## Switching style rebuilds the map and the cast with the other materials.
func set_style(s: String) -> void:
	if not STYLES.has(s) or s == style:
		return
	style = s
	_save("style", s)
	Ink.reset()
	_apply_style_env()
	main.rebuild_look()
	apply_mood(current())

func _save(key: String, value) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("look", key, value)
	cf.save(SETTINGS)

# ── fog, chaos light, depth of field ──────────────────────────────────────────────
## Every studio step starts from the mood's aerial haze; chaos and abilities add fog on top.
func reset_fog() -> void:
	var env: Environment = main.env
	_chaos_fog = 0.0
	if not illustrated() or _m.is_empty():
		env.fog_enabled = false
		env.fog_density = 0.0
		return
	var f: Dictionary = _m.get("fog", {})
	env.fog_enabled = float(f.get("amount", 0.0)) > 0.0
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(String(f.get("color", "#8F9BD0")))
	env.fog_light_energy = 1.0
	env.fog_density = float(f.get("amount", 0.5))
	env.fog_depth_begin = float(f.get("begin", 6.0))
	env.fog_depth_end = float(f.get("end", 50.0))
	env.fog_depth_curve = 1.0
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0

## Thick chaos / ability fog (exponential), the densest request this step wins.
func add_fog(color: Color, density: float) -> void:
	var env: Environment = main.env
	_chaos_fog = maxf(_chaos_fog, density)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = color
	env.fog_density = _chaos_fog
	env.fog_sky_affect = 0.0

## Blackouts dim the key light, ambient and sky; lightning flashes them bright.
func apply_light(scale: float, flash: float) -> void:
	main.env.ambient_light_energy = base_ambient * scale + flash * 1.2
	main.sun.light_energy = base_sun * scale + flash * 1.4
	sky_mat.set_shader_parameter("exposure", lerpf(0.25, 1.0, scale))
	sky_mat.set_shader_parameter("flash", clampf(flash, 0.0, 1.0) * 0.8)

## Per frame: studio clock for strokes and grain, and depth of field focused on the subject.
func tick(dt: float) -> void:
	RenderingServer.global_shader_parameter_set("ill_time", main.t)
	if not illustrated():
		return
	var amount := float(_m.get("dof", 0.08)) if toggles["dof"] and not _off("dof") else 0.0
	var subject := _subject()
	if amount <= 0.0 or subject == null or main.rig == "free":
		attrs.dof_blur_far_enabled = false
		attrs.dof_blur_near_enabled = false
		focus = -1.0
		return
	var d: float = main.cam.global_position.distance_to(main.head_pos(subject))
	focus = d if focus < 0.0 else lerpf(focus, d, 1.0 - exp(-dt * 6.0))
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = focus * 1.2 + 0.35
	attrs.dof_blur_far_transition = focus * 1.6 + 0.5
	attrs.dof_blur_near_enabled = true
	attrs.dof_blur_near_distance = maxf(0.1, focus * 0.5)
	attrs.dof_blur_near_transition = focus * 0.35
	attrs.dof_blur_amount = amount * clampf(3.0 / maxf(focus, 0.5), 0.25, 1.0)

## Who the lens focuses on: the Director's camera subject while it plays, else the controlled character.
func _subject() -> Node3D:
	var d = main.director
	if d != null and d.playing and d.drives_camera():
		var n: Node3D = d._target_node()
		if n != null:
			return n
	return main.actor if main._has(main.actor) else null

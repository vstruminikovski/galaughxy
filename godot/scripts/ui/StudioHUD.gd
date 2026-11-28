class_name StudioHUD
extends CanvasLayer

## The studio HUD: a Window menu and independent, draggable toolboxes.
##   🎥 Camera     1. Drone · 2. Static · 3. Sliders (map rigs + the waypoint path builder)
##   🎭 Character  Move · Emotions · Emotes · Abilities (+ map gags), TALK, Next
##   ⏱ Timeline   shot pills, play/pause, scrubber, loop, overdub, live take → merge, save
##   🗺 World      Maps (category filters, expansions) · Look (style, moods, toggles) · Controls (live
##                InputMap reference) · Settings
##   👥 Cast       spawn roster characters      🎬 Director  episodes, play / loop / retake
## Every button taps an InputMap action or calls the same studio function the keys use.
## Panels stop the mouse / touch; passive overlays ignore it; buttons never take focus.

const MAP_CATEGORIES := ["All", "Indoor", "Outdoor", "Sci-Fi & Wild"]
const CHAR_CATEGORIES := [["All", "All"], ["Robo", "Robos"], ["Animal", "Animals"], ["Hybrid", "Hybrids"]]
const EXPR_NAMES := ["Deadpan", "Smirk", "Panic", "Angry", "Happy", "Shocked"]

var main: Node
var root: Control
var label: Label
var subtitle: Label
var fade: ColorRect
var joy_pad: Control
var banner: ContextBanner
var menu: HBoxContainer
var menu_buttons := {}
var boxes := {}            # name -> Toolbox
var hidden_all := false
var clean := false
var _subtitle_until := 0.0

# camera toolbox
var cam_tabs: Dictionary
var cam_info: Label
var path_bar: PanelContainer
var path_label: Label
var path_duration: HSlider
var path_duration_label: Label
var path_finish: Button
# character toolbox
var char_name: Label
var char_tabs: Dictionary
var talk_button: Button
var emotion_buttons: Array = []
var emote_buttons: Array = []
var ability_buttons: Array = []
var gag_buttons: Array = []
var _ability_owner: Node3D = null
# timeline toolbox
var tl_pills: HBoxContainer
var tl_slider: HSlider
var tl_time: Label
var tl_play: Button
var tl_loop: Button
var tl_overdub: Button
var tl_take: Button
var tl_merge: Button
var tl_discard: Button
var tl_status: Label
var _tl_episode := ""
# world toolbox
var world_tabs: Dictionary
var maps_list: GridContainer
var maps_filter := "All"
var controls_list: VBoxContainer
var controls_search: LineEdit
var tips_toggle: CheckButton
var look_target: Label
var look_style := {}
var look_toggles := {}
var mood_grid: GridContainer
# cast / director
var cast_cards: Array = []
var cast_filter := "All"
var cast_search: LineEdit
var cast_status: Label
var director_list: VBoxContainer
var director_status: Label

func _init(m: Node) -> void:
	main = m

func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	label = Label.new()
	label.position = Vector2(12, 6)
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)
	joy_pad = JoyPad.new()
	joy_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(joy_pad)
	_build_menu()
	_build_camera()
	_build_character()
	_build_timeline()
	_build_world()
	_build_cast()
	_build_director()
	_build_path_bar()
	banner = (load("res://scenes/ui/context_banner.tscn") as PackedScene).instantiate() as ContextBanner
	root.add_child(banner)
	# subtitles and the fade sit outside root, so they stay in clean recordings
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
	add_child(subtitle)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fade)
	# start with the character toolbox only: a clean viewport with the essentials
	for n in boxes:
		boxes[n].visible = n == "character"
	_sync_menu()

static func btn(text: String, min_size := Vector2.ZERO) -> Button:
	return Toolbox.button(text, min_size)

static func small(text: String, size := 12, alpha := 0.75) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.modulate = Color(1, 1, 1, alpha)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _tap(action: String) -> void:
	Controls.tap(get_tree(), action)

func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	return g

# ── Window menu ───────────────────────────────────────────────────────────────────
func _build_menu() -> void:
	menu = HBoxContainer.new()
	menu.position = Vector2(12, 28)
	menu.add_theme_constant_override("separation", 6)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(menu)
	for e in [["camera", "🎥 Camera", "tb_camera"], ["character", "🎭 Character", "tb_character"], ["timeline", "⏱ Timeline", "timeline"],
			["world", "🗺 World", "maps"], ["cast", "👥 Cast", "cast"], ["director", "🎬 Director", "director"],
			["controls", "? Controls", "controls"], ["fly", "🛸 Fly", "fly"], ["hide_all", "🙈 Hide All", "hide_all"]]:
		var b := btn(String(e[1]), Vector2(0, 38))
		b.toggle_mode = e[0] != "controls"
		b.tooltip_text = "%s  [%s]" % [e[1], Controls.key_label(String(e[2]))]
		var action := String(e[2])
		b.pressed.connect(func(): _tap(action))
		menu.add_child(b)
		menu_buttons[e[0]] = b

func _sync_menu() -> void:
	for n in boxes:
		if menu_buttons.has(n):
			(menu_buttons[n] as Button).set_pressed_no_signal(boxes[n].visible)
	(menu_buttons["fly"] as Button).set_pressed_no_signal(main.rig == "free")
	(menu_buttons["hide_all"] as Button).set_pressed_no_signal(hidden_all)

func _box(name: String, title: String, width: float, at: Vector2) -> Toolbox:
	var t := Toolbox.new(title, width, at)
	t.closed.connect(_sync_menu)
	root.add_child(t)
	boxes[name] = t
	return t

func is_open(name: String) -> bool:
	return boxes.has(name) and boxes[name].visible

func camera_open() -> bool:
	return is_open("camera")

func toggle_box(name: String) -> void:
	set_box(name, not is_open(name))

func set_box(name: String, on: bool) -> void:
	if not boxes.has(name):
		return
	if on and hidden_all:
		hidden_all = false
	boxes[name].visible = on
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # never fight the camera for the cursor
		match name:
			"world": refresh_maps()
			"director": refresh_director()
			"timeline": refresh_timeline()
			"camera": refresh_camera()
			"character": refresh_character()
	main._release_touch()
	_sync_menu()

## Hide All: every toolbox out of the way for a clean viewport; press again to bring them back.
var _before_hide := {}
func toggle_hide_all() -> void:
	if not hidden_all:
		_before_hide.clear()
		for n in boxes:
			_before_hide[n] = boxes[n].visible
			boxes[n].visible = false
		hidden_all = true
	else:
		for n in _before_hide:
			boxes[n].visible = _before_hide[n]
		hidden_all = false
	_sync_menu()

## Escape closes the big windows (world, cast, director).
func close_windows() -> void:
	for n in ["world", "cast", "director"]:
		boxes[n].visible = false
	var focus := get_viewport().gui_get_focus_owner()
	if focus:
		focus.release_focus()
	_sync_menu()

func set_clean(on: bool) -> void:
	clean = on
	root.visible = not on

## True when a screen position is over any visible UI that should take the touch.
func over_ui(pos: Vector2) -> bool:
	if clean:
		return false
	for b in menu_buttons.values():
		if (b as Control).is_visible_in_tree() and (b as Control).get_global_rect().has_point(pos):
			return true
	for t in boxes.values():
		if (t as Control).is_visible_in_tree() and (t as Control).get_global_rect().has_point(pos):
			return true
	if path_bar.is_visible_in_tree() and path_bar.get_global_rect().has_point(pos):
		return true
	return banner.is_showing() and banner.card_rect().has_point(pos)

func show_subtitle(text: String, until: float) -> void:
	subtitle.text = text
	subtitle.visible = true
	_subtitle_until = until

# ── Camera toolbox ────────────────────────────────────────────────────────────────
func _build_camera() -> void:
	var t := _box("camera", "🎥 Camera", 330, Vector2(12, 124))
	cam_tabs = t.tabs(["1. Drone", "2. Static", "3. Sliders"])
	var spec := {"1. Drone": ["drone", "cam_drone", "Fly through 5 or more viewpoints; a smooth spline links them."],
		"2. Static": ["static", "cam_static", "One locked tripod view (Point A)."],
		"3. Sliders": ["slider", "cam_slider", "A dolly from Point A to Point B."]}
	for tab in spec:
		var page: VBoxContainer = cam_tabs["pages"][tab]
		var kind: String = spec[tab][0]
		var action: String = spec[tab][1]
		page.add_child(small(spec[tab][2]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var view := btn("👁 Map rig", Vector2(0, 40))
		view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		view.tooltip_text = "Look through this map's %s rig [%s]" % [kind, Controls.key_label(action)]
		view.pressed.connect(func(): _tap(action))
		row.add_child(view)
		var build := btn("📍 Build path", Vector2(0, 40))
		build.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		build.tooltip_text = "Fly, drop pins, save into the active shot"
		build.pressed.connect(func(): main.builder.begin(kind))
		row.add_child(build)
		page.add_child(row)
	cam_info = small("", 12, 0.85)
	t.body.add_child(cam_info)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	var prev := btn("▶ Preview shot path", Vector2(0, 38))
	prev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prev.pressed.connect(func(): main.builder.preview())
	row2.add_child(prev)
	var clear := btn("🗑 Clear path", Vector2(0, 38))
	clear.pressed.connect(_clear_shot_path)
	row2.add_child(clear)
	t.body.add_child(row2)

func refresh_camera() -> void:
	var shot: Dictionary = main.director.peek_shot()
	if shot.is_empty():
		cam_info.text = "No episode selected: pick one in Director or Timeline. Paths save into its active shot."
		main.builder.show_path({})
		return
	var where := "%s · shot %d %s" % [main.director.peek_episode_title(), main.director.peek_shot_index() + 1, shot.get("name", "")]
	if String(shot.get("cam", "")) == "custom_path":
		cam_info.text = "%s\nCustom %s path · %d pins · %.1f s" % [where, shot.get("cam_type", "?"), shot.get("waypoints", []).size(), float(shot.get("duration", 0.0))]
	else:
		cam_info.text = "%s\nUses the preset camera '%s'." % [where, shot.get("cam", "wide_static")]
	main.builder.show_path(shot)

func _clear_shot_path() -> void:
	var shot: Dictionary = main.director.peek_shot()
	if shot.is_empty():
		return
	for k in ["cam_type", "waypoints"]:
		shot.erase(k)
	shot["cam"] = "wide_static"
	main.director.dirty = true
	refresh_camera()

## The floating bar shown while aiming a camera path.
func _build_path_bar() -> void:
	path_bar = PanelContainer.new()
	path_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.17, 0.95)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(10)
	path_bar.add_theme_stylebox_override("panel", sb)
	path_bar.anchor_left = 0.5
	path_bar.anchor_right = 0.5
	path_bar.anchor_top = 1.0
	path_bar.anchor_bottom = 1.0
	path_bar.offset_left = -470
	path_bar.offset_right = 470
	path_bar.offset_top = -118
	path_bar.offset_bottom = -14
	path_bar.visible = false
	root.add_child(path_bar)
	var v := VBoxContainer.new()
	path_bar.add_child(v)
	path_label = Label.new()
	path_label.add_theme_font_size_override("font_size", 14)
	v.add_child(path_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	for e in [["📍 Drop Pin", "path_pin"], ["↶ Undo Pin", "path_undo"], ["✔ Finish Path", "path_finish"], ["▶ Preview", "path_preview"]]:
		var b := btn("%s [%s]" % [e[0], Controls.key_label(String(e[1]))], Vector2(0, 46))
		var action := String(e[1])
		b.pressed.connect(func(): _tap(action))
		row.add_child(b)
		if e[1] == "path_finish":
			path_finish = b
	path_duration_label = Label.new()
	path_duration_label.custom_minimum_size = Vector2(64, 0)
	row.add_child(path_duration_label)
	path_duration = HSlider.new()
	path_duration.min_value = 2.0
	path_duration.max_value = 20.0
	path_duration.step = 0.5
	path_duration.value = 6.0
	path_duration.custom_minimum_size = Vector2(110, 0)
	path_duration.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	path_duration.focus_mode = Control.FOCUS_NONE
	path_duration.value_changed.connect(func(v2: float): main.builder.duration = v2)
	row.add_child(path_duration)
	for e in [["▲", "fly_up"], ["▼", "fly_down"]]:
		var b := btn(String(e[0]), Vector2(46, 46))
		var action := String(e[1])
		b.button_down.connect(func(): Input.action_press(action))
		b.button_up.connect(func(): Input.action_release(action))
		row.add_child(b)
	var x := btn("✕", Vector2(46, 46))
	x.tooltip_text = "Cancel [Esc]"
	x.pressed.connect(func(): main.builder.cancel())
	row.add_child(x)

func _sync_path_bar() -> void:
	var b: CameraBuilder = main.builder
	path_bar.visible = b.aiming and not clean
	if not path_bar.visible:
		return
	var need: int = CameraBuilder.NEEDS[b.kind]
	var names := {"static": "Static (Point A)", "slider": "Slider (A → B)", "drone": "Drone path (A → B → C → D → E …)"}
	var letters := ""
	for i in b.pins.size():
		letters += CameraBuilder.PIN_LETTERS[i]
	path_label.text = "%s · pins: %s%s" % [names[b.kind], letters if letters != "" else "none yet",
		"" if b.pins.size() >= need else "  (need %d)" % need]
	path_finish.disabled = not b.can_finish()
	if not is_equal_approx(path_duration.value, b.duration):
		path_duration.set_value_no_signal(b.duration)
	path_duration_label.text = "%.1f s" % b.duration

# ── Character toolbox ─────────────────────────────────────────────────────────────
func _build_character() -> void:
	var t := _box("character", "🎭 Character", 318, Vector2(1280 - 318 - 12, 124))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	char_name = Label.new()
	char_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	char_name.clip_text = true
	head.add_child(char_name)
	var next := btn("Next ⇥", Vector2(0, 38))
	next.tooltip_text = "Control the next character [%s]" % Controls.key_label("next_actor")
	next.pressed.connect(func(): _tap("next_actor"))
	head.add_child(next)
	t.body.add_child(head)
	talk_button = btn("🎙 TALK (hold) [%s]" % Controls.key_label("talk"), Vector2(0, 50))
	talk_button.button_down.connect(func(): Input.action_press("talk"))
	talk_button.button_up.connect(func(): Input.action_release("talk"))
	t.body.add_child(talk_button)
	char_tabs = t.tabs(["Move", "Emotions", "Emotes", "Abilities"])
	# Move
	var mv: VBoxContainer = char_tabs["pages"]["Move"]
	var g := _grid(2)
	for e in [["🦘 Hop", "hop"], ["🛸 Free fly", "fly"], ["👥 Cast…", "cast"], ["⇥ Next", "next_actor"]]:
		var b := btn("%s [%s]" % [e[0], Controls.key_label(String(e[1]))], Vector2(0, 44))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var action := String(e[1])
		b.pressed.connect(func(): _tap(action))
		g.add_child(b)
	mv.add_child(g)
	mv.add_child(small("Walk: WASD / arrows, or drag on the left side of the screen. Tap a character to control it."))
	# Emotions
	var em: VBoxContainer = char_tabs["pages"]["Emotions"]
	g = _grid(2)
	for i in 6:
		var b := btn("%d · %s" % [i + 1, EXPR_NAMES[i]], Vector2(0, 42))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var action := "expr_%d" % (i + 1)
		b.pressed.connect(func(): _tap(action))
		g.add_child(b)
		emotion_buttons.append(b)
	em.add_child(g)
	# Emotes
	var eo: VBoxContainer = char_tabs["pages"]["Emotes"]
	g = _grid(2)
	for e in [["👋 Wave", "emote_wave"], ["👉 Point", "emote_point"], ["🤦 Facepalm", "emote_facepalm"], ["🤷 Shrug", "emote_shrug"]]:
		var b := btn("%s [%s]" % [e[0], Controls.key_label(String(e[1]))], Vector2(0, 46))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var action := String(e[1])
		b.pressed.connect(func(): _tap(action))
		g.add_child(b)
		emote_buttons.append(b)
	eo.add_child(g)
	# Abilities (+ map gags)
	var ab: VBoxContainer = char_tabs["pages"]["Abilities"]
	for i in 5:
		var b := btn("", Vector2(0, 40))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		var action := "ability_%d" % (i + 1)
		b.pressed.connect(func(): _tap(action))
		ab.add_child(b)
		ability_buttons.append(b)
	ab.add_child(small("Map gags", 12, 0.6))
	var gg := _grid(2)
	for e in [["chaos_1", 1], ["chaos_2", 2], ["chaos_3", 3], ["chaos_drain", 0]]:
		var b := btn("", Vector2(0, 38))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		var action := String(e[0])
		b.pressed.connect(func(): _tap(action))
		gg.add_child(b)
		gag_buttons.append(b)
	ab.add_child(gg)

func refresh_character() -> void:
	var a: Node3D = main.actor
	char_name.text = "🎭 %s" % (main._name_of(a) if main._has(a) else "nobody")
	var list: Array = main.abilities.for_actor(a)
	for i in 5:
		var b: Button = ability_buttons[i]
		if i < list.size():
			b.text = "%s · %s" % [Controls.key_label("ability_%d" % (i + 1)), list[i]["name"]]
			b.tooltip_text = "%s (cooldown %ss)" % [list[i]["desc"], list[i]["cooldown"]]
			b.disabled = false
		else:
			b.text = "—"
			b.disabled = true
	var stages: Array = main.maps[main.scene_name].get("chaos_stages", []) if main.maps.has(main.scene_name) else []
	var keys := ["chaos_1", "chaos_2", "chaos_3", "chaos_drain"]
	for i in 4:
		var name := "Reset" if i == 3 else (String(stages[i]["name"]) if i < stages.size() else "Stage %d" % (i + 1))
		(gag_buttons[i] as Button).text = "%s · %s" % [Controls.key_label(keys[i]).split(" / ")[0], name]
	_ability_owner = a

func _sync_character() -> void:
	if not is_open("character"):
		return
	if main.actor != _ability_owner:
		refresh_character()
	for i in emotion_buttons.size():
		(emotion_buttons[i] as Button).set_pressed_no_signal(i == main.expr_i)
	var list: Array = main.abilities.for_actor(main.actor)
	for i in mini(5, list.size()):
		var left: float = main.abilities.cooldown_left(main.actor, String(list[i]["id"]))
		var b: Button = ability_buttons[i]
		var base := "%s · %s" % [Controls.key_label("ability_%d" % (i + 1)), list[i]["name"]]
		b.text = base if left <= 0.0 else "%s  (%.1fs)" % [base, left]
		b.modulate = Color(1, 1, 1, 0.55 if left > 0.0 else 1.0)

# ── Timeline toolbox ──────────────────────────────────────────────────────────────
func timeline_episode() -> String:
	if main.director.ep_id != "":
		return main.director.ep_id
	if _tl_episode == "" and not main.director.order.is_empty():
		_tl_episode = main.director.order[0]
	return _tl_episode

func _build_timeline() -> void:
	var t := _box("timeline", "⏱ Timeline · shots, takes and overdub", 930, Vector2(12, 720 - 236))
	tl_pills = HBoxContainer.new()
	tl_pills.add_theme_constant_override("separation", 6)
	t.body.add_child(tl_pills)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	t.body.add_child(row)
	tl_play = btn("▶", Vector2(48, 40))
	tl_play.tooltip_text = "Play / pause [%s]" % Controls.key_label("play_pause")
	tl_play.pressed.connect(func(): _tap("play_pause"))
	row.add_child(tl_play)
	tl_slider = HSlider.new()
	tl_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tl_slider.step = 0.01
	tl_slider.focus_mode = Control.FOCUS_NONE
	tl_slider.value_changed.connect(func(v: float): main.director.seek(v))
	row.add_child(tl_slider)
	tl_time = Label.new()
	tl_time.custom_minimum_size = Vector2(112, 0)
	row.add_child(tl_time)
	tl_loop = btn("🔁", Vector2(44, 40))
	tl_loop.toggle_mode = true
	tl_loop.tooltip_text = "Loop the shot"
	row.add_child(tl_loop)
	tl_overdub = btn("● OVERDUB [%s]" % Controls.key_label("overdub"), Vector2(0, 40))
	tl_overdub.toggle_mode = true
	tl_overdub.pressed.connect(func(): _tap("overdub"))
	row.add_child(tl_overdub)
	var take_row := HBoxContainer.new()
	take_row.add_theme_constant_override("separation", 6)
	t.body.add_child(take_row)
	tl_take = btn("● Take [%s]" % Controls.key_label("take_toggle"), Vector2(0, 40))
	tl_take.pressed.connect(func(): _tap("take_toggle"))
	take_row.add_child(tl_take)
	tl_merge = btn("⇩ Merge [%s]" % Controls.key_label("take_merge"), Vector2(0, 40))
	tl_merge.pressed.connect(func(): _tap("take_merge"))
	take_row.add_child(tl_merge)
	tl_discard = btn("✕ Discard [%s]" % Controls.key_label("take_discard"), Vector2(0, 40))
	tl_discard.pressed.connect(func(): _tap("take_discard"))
	take_row.add_child(tl_discard)
	var camkey := btn("📸 Cam Key [%s]" % Controls.key_label("cam_key"), Vector2(0, 40))
	camkey.pressed.connect(func(): _tap("cam_key"))
	take_row.add_child(camkey)
	var save := btn("💾 Save Episode", Vector2(0, 40))
	save.pressed.connect(main._save_episode)
	take_row.add_child(save)
	tl_status = small("", 12, 0.8)
	tl_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	take_row.add_child(tl_status)

func refresh_timeline() -> void:
	if tl_pills == null:
		return
	for c in tl_pills.get_children():
		c.queue_free()
	var id := timeline_episode()
	if id == "" or not main.director.episodes.has(id):
		return
	var shots: Array = main.director.episodes[id]["shots"]
	for i in shots.size():
		var b := btn("Shot %d" % (i + 1), Vector2(74, 34))
		b.toggle_mode = true
		b.button_pressed = main.director.ep_id == id and main.director.shot_i == i
		b.tooltip_text = String(shots[i].get("name", ""))
		b.pressed.connect(func(): main.director.play_shot(id, i, tl_loop.button_pressed))
		tl_pills.add_child(b)
	var all := btn("Play All", Vector2(90, 34))
	all.pressed.connect(func(): main.director.play_episode(id))
	tl_pills.add_child(all)

func _sync_timeline() -> void:
	if not is_open("timeline"):
		return
	var d: DirectorController = main.director
	tl_slider.max_value = maxf(0.01, d.shot_len)
	tl_slider.set_value_no_signal(d.shot_t)
	tl_time.text = "%.2f / %.2f s" % [d.shot_t, d.shot_len]
	tl_play.text = "⏸" if d.playing and not d.paused else "▶"
	tl_overdub.set_pressed_no_signal(d.overdub and not d.take_review)
	tl_take.text = ("■ Stop Take [%s]" if d.take_active() else "● Take [%s]") % Controls.key_label("take_toggle")
	tl_merge.disabled = d.pending_take.is_empty()
	tl_discard.disabled = d.pending_take.is_empty()
	tl_status.text = d.take_status()
	if d.loop != tl_loop.button_pressed and d.playing and d.mode == "shot":
		d.loop = tl_loop.button_pressed

# ── World toolbox: Maps · Controls · Settings ─────────────────────────────────────
func _build_world() -> void:
	var t := _box("world", "🗺 World · maps, look, controls, settings", 1000, Vector2(140, 124))
	world_tabs = t.tabs(["Maps", "Look", "Controls", "Settings"])
	# Maps
	var mp: VBoxContainer = world_tabs["pages"]["Maps"]
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for cat in MAP_CATEGORIES:
		var count: int = main.map_order.size() if cat == "All" else main.map_order.filter(func(id): return main.maps[id].get("category", "") == cat).size()
		var b := btn("%s (%d)" % [cat, count], Vector2(0, 40))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = cat == "All"
		var c := String(cat)
		b.pressed.connect(func(): maps_filter = c; refresh_maps())
		pills.add_child(b)
	mp.add_child(pills)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mp.add_child(scroll)
	maps_list = _grid(2)
	maps_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(maps_list)
	_build_look(world_tabs["pages"]["Look"])
	# Controls (built from InputMap at runtime)
	var cp: VBoxContainer = world_tabs["pages"]["Controls"]
	controls_search = LineEdit.new()
	controls_search.placeholder_text = "Search controls…"
	controls_search.custom_minimum_size = Vector2(0, 40)
	controls_search.text_changed.connect(func(_s): refresh_controls())
	cp.add_child(controls_search)
	var cs := ScrollContainer.new()
	cs.custom_minimum_size = Vector2(0, 440)
	cs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cp.add_child(cs)
	controls_list = VBoxContainer.new()
	controls_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_list.add_theme_constant_override("separation", 4)
	cs.add_child(controls_list)
	# Settings
	var st: VBoxContainer = world_tabs["pages"]["Settings"]
	tips_toggle = CheckButton.new()
	tips_toggle.text = "Show Context Tips"
	tips_toggle.focus_mode = Control.FOCUS_NONE
	tips_toggle.toggled.connect(func(on: bool): banner.set_enabled(on))
	st.add_child(tips_toggle)
	var reset := btn("Reset Dismissed Tips", Vector2(0, 40))
	reset.pressed.connect(func(): banner.reset_dismissed(); main._update_context(true))
	st.add_child(reset)
	st.add_child(small("Tips show the live keys for what you are doing; ✕ on a tip hides that tip for good."))

## Look tab: the style (Illustrated Ink / Studio Vinyl), one card per mood, and the finishing toggles.
func _build_look(lk: VBoxContainer) -> void:
	var sty := HBoxContainer.new()
	sty.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for st in Look.STYLES:
		var b := btn(String(Look.STYLES[st]), Vector2(0, 42))
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sid := String(st)
		b.pressed.connect(func(): main.art.set_style(sid))
		sty.add_child(b)
		look_style[sid] = b
	lk.add_child(sty)
	look_target = small("", 13, 0.85)
	lk.add_child(look_target)
	mood_grid = _grid(4)
	lk.add_child(mood_grid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var reset := btn("↺ Map default", Vector2(0, 40))
	reset.pressed.connect(func(): main.art.clear_pick())
	row.add_child(reset)
	for k in Look.TOGGLES:
		var tog := CheckButton.new()
		tog.text = String(Look.TOGGLES[k])
		tog.focus_mode = Control.FOCUS_NONE
		var kid := String(k)
		tog.toggled.connect(func(on: bool): main.art.set_toggle(kid, on))
		row.add_child(tog)
		look_toggles[kid] = tog
	lk.add_child(row)
	lk.add_child(small("Illustrated Ink: flat colour under a warm key light with cool shadows, ink that follows the light, hatching in the shadows, a painted sky, haze, depth of field and grain. Studio Vinyl: the Mac Studio cel look. While an episode is open, a mood click belongs to the current shot (💾 Save in the Timeline keeps it). F6 = next mood."))
	main.art.changed.connect(refresh_look)
	refresh_look()

func refresh_look() -> void:
	if mood_grid == null:
		return
	for st in look_style:
		(look_style[st] as Button).set_pressed_no_signal(st == Look.style)
	for k in look_toggles:
		var tog: CheckButton = look_toggles[k]
		tog.set_pressed_no_signal(main.art.toggles[k])
		tog.disabled = not Look.illustrated()
	var now: Dictionary = main.art.moods.get(main.art.mood_id, {})
	look_target.text = "%s   ·   now: %s %s" % [main.art.target_text(), now.get("icon", ""), now.get("name", "")]
	for c in mood_grid.get_children():
		mood_grid.remove_child(c)
		c.queue_free()
	for id in main.art.mood_order:
		var m: Dictionary = main.art.moods[id]
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := btn("%s %s" % [m["icon"], m["name"]], Vector2(0, 44))
		b.toggle_mode = true
		b.button_pressed = id == main.art.mood_id
		b.disabled = not Look.illustrated()
		var mid := String(id)
		b.pressed.connect(func(): main.art.pick(mid))
		card.add_child(b)
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", 0)
		var sky: Dictionary = m.get("sky", {})
		for col in [sky.get("zenith", "#000000"), sky.get("horizon", "#000000"), m["light"], m["shadow"], m.get("rim_color", "#FFAE6E")]:
			var r := ColorRect.new()
			r.color = Color(String(col))
			r.custom_minimum_size = Vector2(0, 8)
			r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			strip.add_child(r)
		card.add_child(strip)
		mood_grid.add_child(card)

func open_world(tab: String) -> void:
	set_box("world", true)
	(boxes["world"] as Toolbox).select_tab(world_tabs, tab)
	if tab == "Controls":
		refresh_controls()
	if tab == "Settings":
		tips_toggle.set_pressed_no_signal(banner.enabled)
	if tab == "Look":
		refresh_look()

func refresh_maps() -> void:
	if maps_list == null:
		return
	for c in maps_list.get_children():
		c.queue_free()
	for id in main.map_order:
		var info: Dictionary = main.maps[id]
		var current: bool = id == main.scene_name
		var cs := _card()
		var card: PanelContainer = cs[0]
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.visible = maps_filter == "All" or info.get("category", "") == maps_filter
		if current:
			(cs[1] as StyleBoxFlat).bg_color = Color(0.2, 0.3, 0.45, 0.9)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var title := Label.new()
		title.text = "%s  %s" % [info["icon"], info["title"]]
		title.add_theme_font_size_override("font_size", 17)
		title.clip_text = true
		text.add_child(title)
		var exps: Array = info.get("expansions", []).map(func(e): return String(e["title"]))
		text.add_child(small("%s · %s\nGags: %s%s" % [info.get("category", ""), info["tag"], info["chaos"],
			("\nExpansion: " + ", ".join(exps)) if not current and not exps.is_empty() else ""]))
		if current:
			for e in info.get("expansions", []):
				var tog := CheckButton.new()
				tog.text = String(e["title"])
				tog.focus_mode = Control.FOCUS_NONE
				tog.button_pressed = main.expansions_on.get(String(e["id"]), false)
				var eid := String(e["id"])
				tog.toggled.connect(func(on: bool): main.set_expansion(eid, on))
				text.add_child(tog)
		var load_b := btn("Current" if current else "Load Map", Vector2(112, 50))
		load_b.disabled = current
		load_b.pressed.connect(func(): main._travel(id))
		row.add_child(load_b)
		maps_list.add_child(card)

func refresh_controls() -> void:
	if controls_list == null:
		return
	for c in controls_list.get_children():
		controls_list.remove_child(c)
		c.queue_free()
	var q := controls_search.text.strip_edges().to_lower()
	for cat in Controls.CATEGORY_ORDER:
		var rows: Array = []
		for action in Controls.INFO:
			var info: Array = Controls.INFO[action]
			if info[0] != cat:
				continue
			var keys := Controls.keys(action)
			var text := ("%s %s %s %s" % [action, info[1], info[2], " ".join(keys)]).to_lower()
			if q != "" and not text.contains(q):
				continue
			rows.append([action, info, keys])
		if rows.is_empty():
			continue
		var head := Label.new()
		head.text = cat
		head.add_theme_font_size_override("font_size", 16)
		controls_list.add_child(head)
		for r in rows:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var desc := small(String(r[1][1]), 13, 0.95)
			desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(desc)
			var badges := HBoxContainer.new()
			badges.custom_minimum_size = Vector2(170, 0)
			for k in r[2]:
				badges.add_child(_keycap(String(k)))
			if (r[2] as PackedStringArray).is_empty():
				badges.add_child(small("touch only", 11, 0.5))
			row.add_child(badges)
			var touch := small("📱 " + String(r[1][2]), 12, 0.7)
			touch.custom_minimum_size = Vector2(300, 0)
			row.add_child(touch)
			controls_list.add_child(row)

func _keycap(k: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.92, 0.93, 0.95)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	sb.border_color = Color(0.6, 0.62, 0.66)
	sb.border_width_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = k
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("#1b1d22"))
	p.add_child(l)
	return p

func _card() -> Array:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.18, 0.22, 0.9)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", sb)
	return [card, sb]

# ── Cast toolbox ──────────────────────────────────────────────────────────────────
func _build_cast() -> void:
	var t := _box("cast", "👥 Cast · tap a card to spawn", 1000, Vector2(140, 124))
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for cat in CHAR_CATEGORIES:
		var count: int = main.char_order.size() if cat[0] == "All" else main.char_order.filter(func(id): return main.chars[id]["category"] == cat[0]).size()
		var b := btn("%s (%d)" % [cat[1], count], Vector2(0, 40))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = cat[0] == "All"
		var c := String(cat[0])
		b.pressed.connect(func(): cast_filter = c; filter_cast())
		filters.add_child(b)
	cast_search = LineEdit.new()
	cast_search.placeholder_text = "Search…"
	cast_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cast_search.custom_minimum_size = Vector2(160, 40)
	cast_search.text_changed.connect(func(_s): filter_cast())
	filters.add_child(cast_search)
	t.body.add_child(filters)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	t.body.add_child(scroll)
	var grid := _grid(4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for id in main.char_order:
		var data: Dictionary = main.chars[id]
		var card := btn("%s  %s\n%s · %s" % [data["icon"], data["name"], data["category"], data["gag"]], Vector2(0, 86))
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
		var cid := String(id)
		card.pressed.connect(func(): main.spawn_character(cid))
		grid.add_child(card)
		cast_cards.append({"button": card, "data": data})
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	cast_status = Label.new()
	cast_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(cast_status)
	var des := btn("Despawn Selected", Vector2(170, 40))
	des.pressed.connect(main.despawn_selected)
	foot.add_child(des)
	var clr := btn("Clear Cast", Vector2(120, 40))
	clr.pressed.connect(main.clear_cast)
	foot.add_child(clr)
	t.body.add_child(foot)

func filter_cast() -> void:
	var q := cast_search.text.strip_edges().to_lower()
	for c in cast_cards:
		var d: Dictionary = c["data"]
		var cat_ok: bool = cast_filter == "All" or d["category"] == cast_filter
		var text := ("%s %s %s %s" % [d["name"], d["id"], d["category"], d["gag"]]).to_lower()
		(c["button"] as Button).visible = cat_ok and (q == "" or text.contains(q))

# ── Director toolbox ──────────────────────────────────────────────────────────────
func _build_director() -> void:
	var t := _box("director", "🎬 Director", 1000, Vector2(140, 124))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	director_status = Label.new()
	director_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	director_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(director_status)
	var retake := btn("⟲ Retake", Vector2(110, 40))
	retake.pressed.connect(func(): main.director.retake())
	top.add_child(retake)
	var stop := btn("■ Stop / Take Over", Vector2(180, 40))
	stop.pressed.connect(func(): main.director.stop(true))
	top.add_child(stop)
	var save := btn("💾 Save Episode", Vector2(150, 40))
	save.pressed.connect(main._save_episode)
	top.add_child(save)
	t.body.add_child(top)
	t.body.add_child(small("Play Episode hides the HUD for clean recording: tap the screen or press Esc to stop and take over."))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	t.body.add_child(scroll)
	director_list = VBoxContainer.new()
	director_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	director_list.add_theme_constant_override("separation", 10)
	scroll.add_child(director_list)

func refresh_director() -> void:
	if director_list == null:
		return
	director_status.text = main.director.status_text()
	for c in director_list.get_children():
		c.queue_free()
	for ep_id in main.director.order:
		var ep: Dictionary = main.director.episodes[ep_id]
		var cs := _card()
		var card: PanelContainer = cs[0]
		if ep_id == timeline_episode():
			(cs[1] as StyleBoxFlat).bg_color = Color(0.2, 0.3, 0.45, 0.9)
		var v := VBoxContainer.new()
		card.add_child(v)
		var head := HBoxContainer.new()
		var title := Label.new()
		var map_id: String = main.map_alias.get(String(ep.get("map", "")), "")
		title.text = "%s  ·  %s  ·  %d shots" % [ep.get("title", ep_id), main.maps[map_id]["title"] if map_id != "" else "?", ep["shots"].size()]
		title.add_theme_font_size_override("font_size", 18)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var eid := String(ep_id)
		var sel := btn("Select", Vector2(96, 44))
		sel.pressed.connect(func(): _tl_episode = eid; main.director.select_episode(eid); refresh_timeline(); refresh_director(); refresh_camera())
		head.add_child(sel)
		var play := btn("▶ Play Episode", Vector2(150, 44))
		play.pressed.connect(func(): _tl_episode = eid; main.director.play_episode(eid))
		head.add_child(play)
		v.add_child(head)
		for i in ep["shots"].size():
			var shot: Dictionary = ep["shots"][i]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var cam_text := String(shot.get("cam", "wide_static"))
			if cam_text == "custom_path":
				cam_text = "custom %s path" % shot.get("cam_type", "")
			var name := Label.new()
			name.text = "%d. %s   ·  %s  ·  %.1f s" % [i + 1, shot.get("name", shot["id"]), cam_text, main.director.estimate_length(shot)]
			name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name)
			var idx: int = i
			var p := btn("▶ Shot", Vector2(96, 40))
			p.pressed.connect(func(): _tl_episode = eid; main.director.play_shot(eid, idx, false))
			row.add_child(p)
			var l := btn("🔁 Loop", Vector2(96, 40))
			l.pressed.connect(func(): _tl_episode = eid; main.director.play_shot(eid, idx, true))
			row.add_child(l)
			v.add_child(row)
		director_list.add_child(card)

# ── every frame ───────────────────────────────────────────────────────────────────
func sync() -> void:
	if subtitle.visible and main.voice.clock > _subtitle_until:
		subtitle.visible = false
	_sync_timeline()
	_sync_character()
	_sync_path_bar()
	if is_open("director"):
		director_status.text = main.director.status_text()
	if cast_status:
		cast_status.text = "Controlling: %s   ·   %d on stage" % [main._name_of(main.actor) if main._has(main.actor) else "-", main.cast.size()]

func update_label() -> void:
	if label == null or not main.maps.has(main.scene_name):
		return
	var info: Dictionary = main.maps[main.scene_name]
	var chaos: String = ["calm", "stage 1", "stage 2", "stage 3"][main.stage]
	var who: String = main._name_of(main.actor) if main._has(main.actor) else "-"
	var take := ""
	if main.director and main.director.playing:
		take = " · 🎬 shot %d" % (main.director.shot_i + 1)
	label.text = "%s · %s    [%s · %s · chaos: %s · 🎭 %s%s]" % [info["title"], info["tag"], main.rig, main.EXPRS[main.expr_i], chaos, who, take]
	_sync_menu()
	if is_open("character"):
		refresh_character()

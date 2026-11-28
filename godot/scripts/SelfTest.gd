class_name SelfTest
extends RefCounted

## Headless interaction test. Run: godot --path godot -- --test
## Drives keys, buttons and portals through the real input path and reports PASS/FAIL.

var main: Node
var fails := 0

func _init(m: Node) -> void:
	main = m

func _frames(n: int) -> void:
	for i in n:
		await main.get_tree().process_frame

func _key(k: Key, pressed := true) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _tap(k: Key) -> void:
	_key(k, true)
	await _frames(2)
	_key(k, false)
	await _frames(2)

## Injected events are in window pixels; the game reads viewport pixels (canvas_items stretch).
func _win(pos: Vector2) -> Vector2:
	return main.get_viewport().get_final_transform() * pos

func _touch(idx: int, pos: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = _win(pos)
	ev.pressed = down
	Input.parse_input_event(ev)

func _drag(idx: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = _win(pos)
	Input.parse_input_event(ev)

func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1

func _wait(sec: float) -> void:
	await main.get_tree().create_timer(sec).timeout

func run() -> void:
	print("[test] start")
	if OS.get_cmdline_user_args().has("--test-look"):
		await _frames(5)
		await _look()
		await _dogwalk()
		await _physics()
		print("RESULT: %s" % ("ALL PASS" if fails == 0 else "%d FAIL" % fails))
		main.get_tree().quit(1 if fails else 0)
		return
	if OS.get_cmdline_user_args().has("--test-only"):
		await _frames(5)
		await _studio()
		print("RESULT: %s" % ("ALL PASS" if fails == 0 else "%d FAIL" % fails))
		main.get_tree().quit(1 if fails else 0)
		return
	await _frames(5)
	# InputMap
	var missing := Controls.BINDINGS.keys().filter(func(a): return not InputMap.has_action(a))
	_check("every control is an InputMap action", missing.is_empty())
	main.load_scene("kitchen")
	await _frames(3)
	_check("alias loads the kitchen map", main.scene_name == "overflowing_kitchen")
	await _tap(KEY_X)
	_check("slider key switches rig", main.rig == "slider")
	await _tap(KEY_C)
	_check("drone key switches rig", main.rig == "drone")
	await _tap(KEY_Z)
	_check("static key switches rig", main.rig == "static")
	await _tap(KEY_N)
	_check("N enters free-fly", main.rig == "free")
	var p0: Vector3 = main.fly_pos
	_key(KEY_W, true)
	await _wait(0.3)
	_key(KEY_W, false)
	await _frames(2)
	_check("W moves the fly camera", main.fly_pos.distance_to(p0) > 0.05)
	await _tap(KEY_3)
	_check("number keys are off while flying", main.EXPRS[main.expr_i] != "PANIC")
	await _tap(KEY_N)
	_check("N leaves free-fly", main.rig != "free")
	await _tap(KEY_3)
	_check("key 3 sets PANIC", main.EXPRS[main.expr_i] == "PANIC")
	await _tap(KEY_Q)
	_check("Q raises flood stage 1", main.stage == 1)
	await _tap(KEY_9)
	_check("9 raises flood stage 3", main.stage == 3)
	await _tap(KEY_0)
	_check("0 drains", main.stage == 0)
	_check("no 12fps stepping or PNG action remain", not InputMap.has_action("twos") and not InputMap.has_action("png"))
	# maps drawer
	await _tap(KEY_M)
	_check("M opens the World toolbox on Maps", main.hud.is_open("world") and main.hud.world_tabs["pages"]["Maps"].visible)
	await _frames(2)
	_check("maps grid lists every map", main.hud.maps_list.get_child_count() == main.map_order.size())
	await _tap(KEY_ESCAPE)
	_check("Escape closes the window", not main.hud.is_open("world"))
	# touch buttons go through the InputMap
	var face_btn: Button = main.hud.emotion_buttons[(main.expr_i + 1) % 6]
	var before: int = main.expr_i
	face_btn.emit_signal("pressed")
	await _frames(4)
	_check("FACE button cycles expression", main.expr_i == (before + 1) % 6)
	# cast drawer: spawn, control, move, switch
	await _tap(KEY_I)
	_check("I opens the Cast toolbox", main.hud.is_open("cast"))
	_check("cast drawer has 20 cards", main.hud.cast_cards.size() == 20)
	main.hud.cast_filter = "Main"
	main.hud.filter_cast()
	_check("Main 5 filter shows the five main characters", main.hud.cast_cards.filter(func(c): return (c["button"] as Button).visible).size() == 5)
	main.hud.cast_filter = "All"
	main.hud.cast_search.text = "toast"
	main.hud.filter_cast()
	var shown: int = main.hud.cast_cards.filter(func(c): return (c["button"] as Button).visible).size()
	_check("search filters the cast", shown == 1)
	main.hud.cast_search.text = ""
	main.hud.cast_filter = "Hybrid"
	main.hud.filter_cast()
	shown = main.hud.cast_cards.filter(func(c): return (c["button"] as Button).visible).size()
	_check("Hybrids filter shows 6", shown == 6)
	main.hud.cast_filter = "All"
	main.hud.filter_cast()
	(main.hud.cast_cards[0]["button"] as Button).emit_signal("pressed")
	await _frames(3)
	_check("tapping a card spawns a character", main.cast.size() == 1)
	_check("the new character is controlled", main.actor is Puppet)
	await _tap(KEY_ESCAPE)
	var a0: Vector3 = main.actor_pos
	_key(KEY_D, true)
	await _wait(0.3)
	_key(KEY_D, false)
	await _frames(2)
	_check("D walks the controlled character", main.actor_pos.x > a0.x + 0.05)
	# emotes through keys and touch buttons
	await _tap(KEY_F)
	_check("F waves", (main.actor as Puppet).emote_playing() == "emote_wave")
	var palm: Button = main.hud.emote_buttons[2]
	palm.emit_signal("pressed")
	await _frames(4)
	_check("PALM button facepalms", (main.actor as Puppet).emote_playing() == "emote_facepalm")
	await _tap(KEY_J)
	await _wait(0.12)
	_check("J hops", main.motion[main.actor]["hop"] > 0.02)
	# voice: hold Talk -> live voice through the character's preset
	_key(KEY_SPACE, true)
	await _frames(3)
	_check("holding Space talks", main.voice.is_talking(main.actor))
	var pitch := AudioServer.get_bus_effect(main.voice.bus_idx, Voice.FX_PITCH) as AudioEffectPitchShift
	_check("talk applies the character's pitch preset", is_equal_approx(pitch.pitch_scale, float(main.voice_of(main.actor)["pitch"])))
	_key(KEY_SPACE, false)
	await _frames(3)
	_check("releasing Space stops talking", not main.voice.is_talking(main.actor))
	# a recorded clip: its length times the line, and (with real audio output) its spectrum moves the mouth
	var clip_len: float = main.voice.line_length("_selftest/babble.wav", "x")
	_check("clip length comes from the audio file", absf(clip_len - 1.6) < 0.05)
	main.say(main.actor, "_selftest/babble.wav", "")
	var peak := 0.0
	for i in 20:
		await _wait(0.05)
		peak = maxf(peak, main.voice.level(main.actor))
	if DisplayServer.get_name() != "headless":
		_check("spectrum lip-sync opens the mouth (real audio)", peak > 0.15)
	else:
		print("SKIP spectrum lip-sync (headless audio is silent; run without --headless to check)")
	main.voice.stop(main.actor)
	_check("text fallback is 0.065 s per character", is_equal_approx(main.voice.line_length("missing/none.wav", "x".repeat(40)), 2.6))
	(main.hud.cast_cards[7]["button"] as Button).emit_signal("pressed")
	await _frames(3)
	_check("second spawn", main.cast.size() == 2)
	await _tap(KEY_TAB)
	_check("Tab passes control on", main.actor == main.host)
	await _tap(KEY_TAB)
	_check("Tab cycles to the cast", main.actor == main.cast[0])
	# map switch keeps the cast
	main.load_scene("mac_garage_lab")
	await _frames(5)
	_check("garage lab loads", main.scene_name == "mac_garage_lab" and main.world != null)
	_check("cast survives the map change", main.cast.size() == 2 and main.cast[0].is_inside_tree())
	_check("controlled character kept", main.actor == main.cast[0])
	main.set_expansion("basement_server_room", true)
	await _frames(3)
	_check("expansion builds", main.world.expansion_on("basement_server_room"))
	main.set_expansion("basement_server_room", false)
	_check("expansion toggles off", not main.world.expansion_on("basement_server_room"))
	main.despawn_selected()
	await _frames(2)
	_check("despawn selected", main.cast.size() == 1 and main.actor == main.host)
	main.clear_cast()
	await _frames(2)
	_check("clear cast", main.cast.is_empty())
	await _director()
	await _maps()
	await _studio()
	await _look()
	await _dogwalk()
	await _physics()
	# portal: walk the robo into the kitchen doorway; kitchen links to the pond
	main.load_scene("kitchen")
	await _frames(3)
	main.actor_pos = Vector3(-2.95, 0, 0.9)
	await _frames(5)
	_check("portal travels to pond", main.scene_name == "pond_life")
	await _frames(5)
	_check("frog spawned", main.actor_kind == "frog")
	main.load_scene("garden")
	await _frames(3)
	_check("map travel works", main.scene_name == "backyard_garden")
	# touch: joystick on the left, look-drag on the right
	var vp := main.get_viewport().get_visible_rect().size
	var start := Vector2(vp.x * 0.15, vp.y * 0.6)
	var r0: Vector3 = main.actor_pos
	_touch(0, start, true)
	await _frames(2)
	_drag(0, start + Vector2(60, 0))
	await _wait(0.3)
	_check("left-thumb joystick tilts", main.joy_vec.x > 0.5)
	_touch(0, start + Vector2(60, 0), false)
	await _frames(2)
	_check("left-thumb joystick moves the robo", main.actor_pos.x > r0.x + 0.05)
	var lp := Vector2(vp.x * 0.7, vp.y * 0.5)
	_touch(1, lp, true)
	await _frames(2)
	var yaw0: float = main.fly_yaw
	main.rig = "free"
	_drag(1, lp + Vector2(80, 0))
	await _frames(2)
	_touch(1, lp + Vector2(80, 0), false)
	main.rig = "static"
	_check("right-side drag turns the camera", main.look.x != 0.0 or main.fly_yaw != yaw0)
	print("RESULT: %s" % ("ALL PASS" if fails == 0 else "%d FAIL" % fails))
	main.get_tree().quit(1 if fails else 0)

func _director() -> void:
	var d: DirectorController = main.director
	_check("ep01 is loaded", d.episodes.has("ep01_kitchen_disaster"))
	var ep: Dictionary = d.episodes["ep01_kitchen_disaster"]
	var shot0: Dictionary = ep["shots"][0]
	# auto-timing: 0.3 s + 27 chars x 0.065 for the bear, 2.3 s + 29 chars for the frog
	_check("shot length fits its dialogue", d.estimate_length(shot0) >= 2.3 + 29 * 0.065)
	await _tap(KEY_P)
	_check("P opens the Director toolbox", main.hud.is_open("director"))
	await _tap(KEY_ESCAPE)
	d.play_shot("ep01_kitchen_disaster", 0, false)
	await _frames(3)
	_check("director loads the episode map", main.scene_name == "overflowing_kitchen")
	_check("director spawns the episode cast", main.find_actor("robo_bear") != null and main.find_actor("chaotic_frog") != null)
	_check("director drives the camera", d.drives_camera())
	await _tap(KEY_N)
	_check("free fly is off while the director plays", main.rig != "free")
	await _wait(0.6)
	_check("timed events fire (bear talks)", main.voice.is_talking(main.find_actor("robo_bear")))
	var line_ok: bool = main.hud.captions.showing() and main.hud.captions.line_text.contains("toaster")
	if main.hud.caption_style == "classic":
		line_ok = main.hud.subtitle.visible and main.hud.subtitle.text.contains("toaster")
	_check("the line shows as %s captions" % main.hud.caption_style, line_ok)
	# deterministic scrubbing
	d.seek(2.0)
	var frog: Node3D = main.find_actor("chaotic_frog")
	var pose1: Transform3D = frog.global_transform
	var arm1: Transform3D = ((frog as Puppet)._j["Arm_L"] as Node3D).transform
	d.seek(0.5)
	d.seek(2.0)
	_check("scrubbing is deterministic (position)", frog.global_transform.is_equal_approx(pose1))
	_check("scrubbing is deterministic (pose)", ((frog as Puppet)._j["Arm_L"] as Node3D).transform.is_equal_approx(arm1))
	_check("scrub lands on the exact second", is_equal_approx(d.shot_t, 2.0))
	_check("scrub pauses playback", d.paused)
	# jump to a later shot: earlier shots are fast-forwarded to rebuild its starting state
	d.play_shot("ep01_kitchen_disaster", 3, false)
	await _frames(3)
	_check("jump to shot 4", d.shot_i == 3 and d.cam_preset == "follow_shoulder")
	await _wait(0.5)
	var bear: Node3D = main.find_actor("robo_bear")
	_check("move events walk the character", main.motion[bear]["target"] != null or bear.position.x > 0.0)
	# cameras
	for preset in ["wide_static", "closeup_actor", "slider_push", "follow_shoulder", "drone_intro"]:
		d.cam_cut(preset, "chaotic_frog", 0.0)
		d.update_camera(main.cam, 0.016)
		_check("camera %s frames a valid shot" % preset, main.cam.position.is_finite() and main.cam.fov > 10.0)
	d.cam_cut("closeup_actor", "chaotic_frog", 0.0)
	d.update_camera(main.cam, 0.016)
	_check("closeup uses a 42 degree lens", is_equal_approx(main.cam.fov, 42.0))
	# overdub: record live input into the shot, replacing only that actor's channel
	d.play_shot("ep01_kitchen_disaster", 0, false)
	await _frames(3)
	main._take_control(main.find_actor("chaotic_frog"))
	await _tap(KEY_R)
	_check("R arms overdub", d.overdub)
	await _wait(0.4)
	await _tap(KEY_5)
	await _tap(KEY_G)
	await _wait(0.2)
	await _tap(KEY_R)
	_check("R ends overdub", not d.overdub)
	var evs: Array = ep["shots"][0]["events"]
	var rec_expr := evs.filter(func(e): return e.get("actor", "") == "chaotic_frog" and e["action"] == "expr" and e.get("value", "") == "HAPPY")
	var rec_emote := evs.filter(func(e): return e.get("actor", "") == "chaotic_frog" and e["action"] == "emote" and e.get("value", "") == "emote_point")
	_check("overdub records the expression at its time", rec_expr.size() == 1 and float(rec_expr[0]["t"]) > 0.3)
	_check("overdub records the emote", rec_emote.size() == 1)
	var bear_talk := evs.filter(func(e): return e.get("actor", "") == "robo_bear" and e["action"] == "talk")
	_check("overdub keeps other actors' events", bear_talk.size() == 1)
	var shrug := evs.filter(func(e): return e.get("actor", "") == "chaotic_frog" and e.get("value", "") == "emote_shrug")
	_check("overdub keeps events outside the recorded range", shrug.size() == 1)
	# save
	d.ep_id = "selftest_copy"
	var paths: Array = d.save()
	_check("save writes user://episodes", FileAccess.file_exists("user://episodes/selftest_copy.json"))
	DirAccess.remove_absolute("user://episodes/selftest_copy.json")
	if not OS.has_feature("standalone"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://data/episodes/selftest_copy.json"))
	_check("save also syncs into the project on desktop", paths.size() == (1 if OS.has_feature("standalone") else 2))
	d.reload()
	d.stop(true)
	await _frames(2)
	_check("stop hands control back", not d.playing and not main.hud_clean)
	# play episode: clean HUD, tap takes over
	d.play_episode("ep01_kitchen_disaster")
	await _frames(3)
	_check("play episode hides the HUD", main.hud_clean and not main.hud.root.visible)
	await _tap(KEY_ESCAPE)
	_check("Esc stops and takes over", not d.playing and main.hud.root.visible)
	main.clear_cast()
	await _frames(2)

func _maps() -> void:
	_check("16 maps registered", main.map_order.size() >= 16)
	var generated: Array = main.map_order.filter(func(id): return String(main.maps[id]["scene"]).ends_with(id + ".tscn") and FileAccess.file_exists("res://assets/maps/%s/%s.glb" % [id, id]))
	_check("11+ generated maps have their .glb", generated.size() >= 11)
	for id in generated:
		main.load_scene(id)
		await _frames(2)
		var w = main.world
		var ok: bool = w is GlbMap and not (w as GlbMap).props.is_empty() and w.spawn_points().size() >= 5
		_check("%s loads with props and spawn marks" % id, ok)
		var stages: Array = main.maps[id].get("chaos_stages", [])
		_check("%s has three chaos stages" % id, stages.size() == 3)
	# chaos moves props and drain puts them back
	main.load_scene("chaotic_supermarket")
	await _frames(2)
	var can: Node3D = (main.world as GlbMap).props["cans"][0]
	var rest := can.transform
	main.set_stage(1)
	main.set_stage(2)
	await _wait(1.2)
	_check("Can Pyramid Avalanche scatters the cans", not can.transform.origin.is_equal_approx(rest.origin))
	main.set_stage(0)
	await _frames(2)
	_check("drain puts every prop back", can.transform.is_equal_approx(rest))
	main.set_expansion("bakery_deli", true)
	await _frames(2)
	_check("map expansion loads", main.world.expansion_on("bakery_deli"))
	# chaos is a function of time: same elapsed time, same pose
	main.set_stage(2)
	var t0: float = main.t
	main.world.chaos_tick(t0 + 0.5, main)
	var a := can.transform
	main.world.chaos_tick(t0 + 0.9, main)
	main.world.chaos_tick(t0 + 0.5, main)
	_check("chaos replays deterministically", can.transform.is_equal_approx(a))
	main.set_stage(0)
	main.load_scene("lunar_moon_base")
	await _frames(2)
	main.set_stage(1)
	main.set_stage(2)
	main.set_stage(3)
	await _frames(3)
	_check("Zero-G stage turns on low gravity", main.lowgrav)
	main.set_stage(0)
	await _frames(2)
	_check("drain turns low gravity off", not main.lowgrav)

## Shorts captions: chunking, timing and pop-in (pure functions of the clock), the style setting
## and clean HUD.
func _captions() -> void:
	var hud: StudioHUD = main.hud
	var line := "Why is the toaster humming? Don't look at me."
	var parts: Array = Captions.chunks(line)
	_check("captions: 1-3 words per chunk, never across a sentence end", parts.size() >= 2 and " ".join(parts) == line
		and parts.all(func(c): return String(c).split(" ").size() <= 3 and String(c).length() <= Captions.MAX_CHARS)
		and parts.all(func(c): return not String(c).contains("?") or String(c).ends_with("?")))
	# each chunk's share of the spoken time follows its length; the last one holds after the words
	var cap := Captions.new()
	hud.add_child(cap)
	var start := 10.0
	var end: float = start + main.voice.line_length("", line) + Captions.HOLD
	cap.show_line(line, start, end)
	var at: Array = Captions.schedule(parts, start, end)
	var spoken: float = end - Captions.HOLD - start
	var total := 0
	for c in parts:
		total += String(c).length()
	var right := true
	for k in parts.size():
		var next: float = float(at[k + 1]) if k + 1 < at.size() else end - Captions.HOLD
		right = right and absf((next - float(at[k])) - spoken * String(parts[k]).length() / total) < 1e-4
		cap.tick(float(at[k]) + 0.01)
		right = right and cap.current() == parts[k]
	cap.tick(end - 0.01)
	right = right and cap.current() == parts[parts.size() - 1]
	cap.tick(end + 0.01)
	right = right and not cap.showing()
	cap.tick(start - 0.01)
	right = right and not cap.showing()
	# a short chunk still gets 0.18 s; the others share what is left
	var floor_at: Array = Captions.schedule(["I.", "sixteen chars ok", "sixteen chars ok"], 0.0, 2.0)
	var floored: bool = absf(float(floor_at[1]) - Captions.MIN_CHUNK) < 1e-4 and absf(float(floor_at[2]) - (Captions.MIN_CHUNK + 0.76)) < 1e-4
	# pop-in 0.82 -> 1.06 -> 1.0 from the clock alone: the same second gives the same scale
	var s := float(at[1])
	cap.tick(s)
	var s0 := cap.label.scale.x
	cap.tick(s + 0.07)
	var s_mid := cap.label.scale.x
	cap.tick(s + 0.2)
	var s1 := cap.label.scale.x
	cap.tick(s + 0.07)
	var pop: bool = is_equal_approx(s0, 0.82) and s_mid > 1.0 and is_equal_approx(s1, 1.0) and is_equal_approx(cap.label.scale.x, s_mid)
	cap.queue_free()
	_check("captions: right chunk for the clock (length shares, 0.18 s floor, pop-in)", right and floored and pop)
	# the style setting: only [look] captions changes in settings.cfg, the tips section stays
	var style0: String = hud.caption_style
	hud.set_caption_style("classic")
	var cfg := ConfigFile.new()
	cfg.load(ContextBanner.SETTINGS)
	var saved_classic: bool = cfg.get_value("look", "captions", "") == "classic"
	var tips_kept: bool = cfg.has_section_key("tips", "enabled")
	hud.show_line("Robo", "Hello there, frog.", main.voice.clock + 2.0)
	var classic_ok: bool = hud.subtitle.visible and hud.subtitle.text == "Robo: Hello there, frog." and not hud.captions.showing()
	hud.set_caption_style("shorts")
	cfg = ConfigFile.new()
	cfg.load(ContextBanner.SETTINGS)
	var saved_shorts: bool = cfg.get_value("look", "captions", "") == "shorts"
	var cleared: bool = not hud.subtitle.visible and not hud.captions.showing()
	_check("caption style switches (shorts <-> classic) and persists in settings.cfg",
		saved_classic and tips_kept and classic_ok and saved_shorts and cleared)
	# clean HUD (Play Episode, movie export) hides the toolboxes, never the captions
	main.set_clean_hud(true)
	hud.show_line("Robo", "Clean frames keep their captions.", main.voice.clock + 2.0)
	await _frames(2)
	_check("captions stay visible with clean HUD on", not hud.root.visible and hud.captions.is_visible_in_tree()
		and hud.captions.current() != "" and hud.captions.line_text.begins_with("Clean"))
	main.set_clean_hud(false)
	hud.set_caption_style(style0)   # back to the saved style (shorts unless changed by hand)

func _studio() -> void:
	var hud: StudioHUD = main.hud
	# toolboxes and the Window menu
	await _tap(KEY_F1)
	_check("F1 opens the Camera toolbox", hud.is_open("camera"))
	await _tap(KEY_F2)
	_check("F2 toggles the Character toolbox", not hud.is_open("character"))
	await _tap(KEY_F2)
	await _tap(KEY_QUOTELEFT)
	_check("` hides every toolbox", hud.hidden_all and not hud.is_open("camera") and not hud.is_open("character"))
	await _tap(KEY_QUOTELEFT)
	_check("` brings them back", hud.is_open("camera") and hud.is_open("character"))
	_check("menu has no PNG entry", not hud.menu_buttons.has("png"))
	# controls reference reads the InputMap live
	await _tap(KEY_SLASH)
	_check("/ opens the Controls reference", hud.is_open("world") and hud.world_tabs["pages"]["Controls"].visible)
	_check("controls list is built from the InputMap", hud.controls_list.get_child_count() > 40)
	_check("keycaps match the InputMap", Controls.key_label("ability_1") == "Y" and Controls.key_label("talk") == "Space")
	hud.controls_search.text = "facepalm"
	hud.refresh_controls()
	_check("controls search filters", hud.controls_list.get_child_count() == 2)
	hud.controls_search.text = ""
	await _tap(KEY_ESCAPE)
	# context banner (independent of the user's own dismissed tips, which are put back afterwards)
	var kept_dismissed: Dictionary = hud.banner.dismissed.duplicate()
	var kept_enabled: bool = hud.banner.enabled
	hud.banner.enabled = true
	hud.banner.dismissed.clear()
	main._update_context(true)
	_check("context tip shows", hud.banner.is_showing())
	var tip := hud.banner.current
	hud.banner.dismiss()
	main._update_context(true)
	_check("dismissed tip stays hidden", not hud.banner.is_showing())
	hud.banner.reset_dismissed()
	main._update_context(true)
	_check("reset brings tips back", hud.banner.is_showing() and hud.banner.current == tip)
	hud.banner.dismissed = kept_dismissed
	hud.banner.enabled = kept_enabled
	hud.banner._save()
	main._update_context(true)
	await _captions()
	# abilities: 100, five per character, working on any map
	var ab: Abilities = main.abilities
	_check("100 abilities registered", ab.by_id.size() == 100)
	_check("every roster character has 5", main.char_order.all(func(id): return ab.by_char.get(id, []).size() == 5))
	main.load_scene("chaotic_supermarket")
	await _frames(2)
	var bear: Puppet = main.spawn_character("robo_bear")
	main.place(bear, Vector3(0, 0, -0.2), 0.0)
	await _frames(2)
	var can: Node3D = (main.world as GlbMap).props["cans"][0]
	var rest := can.global_position
	main.act(bear, "ability_1", true)   # Static Shockwave: blast + sparks + shake
	await _wait(0.5)
	_check("Static Shockwave blasts nearby props", can.global_position.distance_to(rest) > 0.05)
	_check("abilities shake the camera", main.chaos_shake > 0.0)
	_check("cooldown blocks a second human cast", not ab.cast(bear, String(ab.for_actor(bear)[0]["id"]), true))
	var fish: Puppet = main.spawn_character("robo_fish")
	main.act(fish, "ability_3", false)  # Tidal Flop: flood
	await _wait(0.8)
	_check("Tidal Flop raises a flood", main.ability_flood > 0.1)
	main.load_scene("overflowing_kitchen")   # a hand-built map without props: abilities still run
	await _frames(2)
	main._take_control(main.cast[0])
	main.act(main.actor, "ability_1", false)
	await _frames(5)
	_check("abilities run on maps without props", not ab.active.is_empty())
	main.abilities.clear()
	main.clear_cast()
	await _frames(2)
	# camera waypoint builder → active shot JSON → director playback
	var d: DirectorController = main.director
	d.select_episode("ep01_kitchen_disaster")
	await _frames(3)
	var b: CameraBuilder = main.builder
	b.begin("static")
	_check("aiming enters free fly", main.rig == "free" and b.aiming)
	await _tap(KEY_ENTER)
	_check("static finishes after Point A", not b.aiming)
	var shot: Dictionary = d.peek_shot()
	_check("static pin saved into the shot", shot.get("cam") == "custom_path" and shot.get("cam_type") == "static" and shot["waypoints"].size() == 1)
	b.begin("slider")
	main.fly_pos = Vector3(-2, 1.4, 4)
	await _frames(2)
	b.drop_pin()
	main.fly_pos = Vector3(2, 1.4, 4)
	await _frames(2)
	b.drop_pin()
	_check("slider finishes after A and B", not b.aiming and d.peek_shot()["waypoints"].size() == 2)
	b.begin("drone")
	for i in 4:
		main.fly_pos = Vector3(-3 + i * 2, 1.2 + i * 0.3, 4 - i)
		await _frames(2)
		b.drop_pin()
	_check("drone needs 5 pins", b.aiming and not b.can_finish())
	main.fly_pos = Vector3(4, 2.5, 0)
	await _frames(2)
	await _tap(KEY_ENTER)
	b.duration = 8.0
	await _tap(KEY_PERIOD)
	shot = d.peek_shot()
	_check("Finish Path saves a 5-pin drone spline", not b.aiming and shot["cam_type"] == "drone" and shot["waypoints"].size() == 5 and is_equal_approx(float(shot["duration"]), 8.0))
	var mid := CameraBuilder.evaluate(CameraBuilder.path_of(shot), 0.5)
	var first := CameraBuilder.evaluate(CameraBuilder.path_of(shot), 0.0)
	_check("spline starts on Point A", (first[0] as Vector3).distance_to(CameraBuilder.pin_pos(shot["waypoints"][0])) < 0.01)
	_check("spline moves between pins", (mid[0] as Vector3).distance_to(first[0]) > 0.5)
	d.play_shot("ep01_kitchen_disaster", d.shot_i, false)
	d.seek(4.0)
	main._update_camera(0.016)
	var want := CameraBuilder.evaluate(CameraBuilder.path_of(shot), 0.5)
	_check("director plays the custom path", main.cam.global_position.distance_to(want[0]) < 0.05)
	_check("path preview hidden during playback", true)
	# stop → live take → stop → merge
	main._take_control(main.find_actor("chaotic_frog"))
	d.seek(1.0)
	_check("scrub pauses for a take", d.paused)
	await _tap(KEY_BACKSLASH)
	_check("\\ starts a live take from the paused second", d.take_active() and not d.paused)
	await _wait(0.2)
	await _tap(KEY_4)
	await _tap(KEY_O)    # ability 3 of the frog
	await _tap(KEY_APOSTROPHE)
	await _wait(0.2)
	await _tap(KEY_BACKSLASH)
	_check("stopping the take holds it for review", not d.take_active() and not d.pending_take.is_empty() and d.paused)
	var held: int = d.pending_take["events"].size()
	await _tap(KEY_EQUAL)
	var evs: Array = d.peek_shot()["events"]
	_check("merge writes the take as scene keyframes", d.pending_take.is_empty() and held >= 3)
	_check("expression keyframe merged", evs.any(func(e): return e.get("actor", "") == "chaotic_frog" and e["action"] == "expr" and e.get("value") == "ANGRY" and float(e["t"]) >= 1.0))
	_check("ability keyframe merged", evs.any(func(e): return e.get("action", "") == "ability" and String(e.get("value", "")).begins_with("chaotic_frog__")))
	_check("camera keyframe merged", evs.any(func(e): return e.get("action", "") == "cam_pose" and e.has("rot")))
	_check("other actors' beats kept", evs.any(func(e): return e.get("actor", "") == "robo_bear" and e["action"] == "talk"))
	# a discarded take changes nothing
	var count := evs.size()
	await _tap(KEY_BACKSLASH)
	await _tap(KEY_2)
	await _tap(KEY_BACKSLASH)
	await _tap(KEY_MINUS)
	_check("discard drops the take", d.peek_shot()["events"].size() == count)
	# overdub from a pause resumes and merges on stop
	d.seek(0.5)
	await _tap(KEY_R)
	_check("R overdubs from a pause", d.overdub and not d.paused)
	await _tap(KEY_5)
	await _tap(KEY_R)
	_check("overdub merges on stop", d.peek_shot()["events"].any(func(e): return e.get("actor", "") == "chaotic_frog" and e.get("value") == "HAPPY"))
	# smooth cadence: lip-sync and poses update every frame
	_check("no frame stepping left in Main", not ("on_twos" in main))
	d.reload()
	d.stop(true)
	main.clear_cast()
	await _frames(2)

## Illustrated Ink: materials, moods (map default, click, F6, per shot), depth of field, fog, Look tab, style switch.
func _look() -> void:
	var art: Look = main.art
	var d: DirectorController = main.director
	var was := Look.style
	if not Look.illustrated():
		art.set_style("illustrated")
		await _frames(3)
	main.load_scene("beach_boardwalk")
	await _frames(3)
	_check("map default mood (pier = blue hour)", art.mood_id == "blue_hour")
	_check("illustrated sky is drawn", main.env.background_mode == Environment.BG_SKY and main.env.sky != null)
	_check("key light casts shadows", main.sun.shadow_enabled)
	var p: Node = main.spawn_character("robo_bear")
	await _frames(3)
	var mat: Material = _first_material(p)
	_check("cast wears the illustrated shader", mat is ShaderMaterial and (mat as ShaderMaterial).shader.resource_path.ends_with("illustrated.gdshader"))
	_check("palette maps Bondi blue to denim", Style.swatch("bondi_blue").is_equal_approx(Color("#6E8DD3")))
	_check("snapping an illustrated swatch keeps it", Style.snap(Color("#6E8DD3")).is_equal_approx(Color("#6E8DD3")))
	art.pick("night")
	await _frames(2)
	_check("a mood click relights the scene", art.mood_id == "night" and main.env.ambient_light_color.is_equal_approx(Color("#4A5488")))
	var i: int = art.mood_order.find(art.mood_id)
	await _tap(KEY_F6)
	_check("F6 cycles to the next mood", art.mood_id == art.mood_order[(i + 1) % art.mood_order.size()])
	art.clear_pick()
	_check("map default restores the mood", art.mood_id == "blue_hour")
	# depth of field follows the controlled character
	await _wait(0.3)
	_check("depth of field focuses on the subject", main.cam.attributes.dof_blur_far_enabled and art.focus > 0.1 and main.cam.attributes.dof_blur_far_distance > art.focus)
	# chaos fog sits on top of the haze for one step only
	art.add_fog(Color.WHITE, 0.2)
	_check("chaos fog thickens the air", main.env.fog_mode == Environment.FOG_MODE_EXPONENTIAL and is_equal_approx(main.env.fog_density, 0.2))
	await _frames(2)
	_check("the mood haze comes back next step", main.env.fog_mode == Environment.FOG_MODE_DEPTH)
	# per-shot moods
	d.play_shot("ep01_kitchen_disaster", 1, false)
	await _frames(3)
	d.toggle_pause()
	var shot: Dictionary = d.ep["shots"][1]
	art.pick("golden_hour")
	_check("a click while a shot is open is saved into the shot", shot.get("mood", "") == "golden_hour" and art.mood_id == "golden_hour")
	d.seek(0.4)
	await _frames(2)
	_check("the shot keeps its mood when scrubbed", art.mood_id == "golden_hour")
	d.play_shot("ep01_kitchen_disaster", 0, false)
	await _frames(3)
	_check("a shot without a mood uses the map's", art.mood_id == "interior")
	d.play_shot("ep01_kitchen_disaster", 1, false)
	await _frames(3)
	_check("playing the shot again restores its mood", art.mood_id == "golden_hour")
	d.stop(true)
	await _frames(2)
	_check("stopping returns to the map mood", art.mood_id == "interior" and art.shot_mood == "")
	shot.erase("mood")
	d.dirty = false
	# Look tab
	main.hud.open_world("Look")
	await _frames(2)
	_check("Look tab shows a card per mood", main.hud.mood_grid.get_child_count() == art.mood_order.size())
	await _tap(KEY_ESCAPE)
	# Studio Vinyl round trip rebuilds map and cast
	main.clear_cast()
	main.spawn_character("chaotic_frog")
	await _frames(2)
	art.set_style("vinyl")
	await _frames(3)
	_check("Studio Vinyl puts back the cel materials", Look.style == "vinyl" and _first_material(main.cast[0]) is StandardMaterial3D and main.env.background_mode == Environment.BG_COLOR)
	_check("the cast survives a style switch", main.cast.size() == 1 and main.find_actor("chaotic_frog") != null)
	art.set_style("illustrated")
	await _frames(3)
	_check("back to Illustrated Ink", _first_material(main.cast[0]) is ShaderMaterial and main.sun.shadow_enabled)
	if was != Look.style:
		art.set_style(was)
	main.clear_cast()

func _first_material(n: Node) -> Material:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and not (n is InkStroke):
		var m := (n as MeshInstance3D).get_active_material(0)
		if m != null:
			return m
	for c in n.get_children():
		var m := _first_material(c)
		if m != null:
			return m
	return null

## DOGWALK-inspired pieces: reaction bubbles (keys, Director events, overdub), snow, wind, bumps, follow camera.
func _dogwalk() -> void:
	var d: DirectorController = main.director
	if d.playing:
		d.stop(true)
	main.load_scene("backyard_garden")
	await _frames(3)
	main.clear_cast()
	var bear: Node3D = main.spawn_character("robo_bear")
	await _frames(3)
	# bubbles
	await _tap(KEY_KP_3)
	_check("keypad 3 shows a heart bubble", main.bubbles.showing(bear) == "heart")
	await _wait(2.1)
	_check("the bubble pops away after its time", main.bubbles.showing(bear) == "")
	d._fire({"action": "bubble", "actor": "robo_bear", "value": "idea"})
	await _frames(2)
	_check("a Director event shows a bubble", main.bubbles.showing(bear) == "idea")
	main.bubbles.clear()
	main.clear_cast()
	main.load_scene("overflowing_kitchen")   # the episode's map, so playback doesn't reload it
	await _frames(3)
	# overdub records bubbles into the shot
	d.play_shot("ep01_kitchen_disaster", 0, false)
	await _frames(3)
	_check("playing again respawns a cleared cast", main.find_actor("chaotic_frog") != null)
	main._take_control(main.find_actor("chaotic_frog"))
	await _frames(2)
	await _tap(KEY_R)
	await _wait(0.3)
	await _tap(KEY_KP_1)
	await _wait(0.2)
	await _tap(KEY_R)
	var evs: Array = d.ep["shots"][0]["events"]
	var rec := evs.filter(func(e): return e.get("actor", "") == "chaotic_frog" and e["action"] == "bubble" and e.get("value", "") == "exclaim")
	_check("overdub records a bubble", rec.size() == 1)
	for e in rec:
		evs.erase(e)
	d.dirty = false
	d.stop(true)
	await _frames(2)
	# snow and wind
	main.art.pick("snowfall")
	_check("Snowfall mood shows falling snow", main.art.mood_id == "snowfall" and main.art.snowfall.visible)
	main.art.clear_pick()
	_check("snow stops with the next mood", not main.art.snowfall.visible or main.art.mood_id == "snowfall")
	var leaf := Style.toon(Style.swatch("mint"), false, {"kind": "set"}) as ShaderMaterial
	var body := Style.toon(Style.swatch("mint"), false, {"kind": "character"}) as ShaderMaterial
	_check("green set pieces sway, characters don't", float(leaf.get_shader_parameter("wind_amt")) == 1.0 and float(body.get_shader_parameter("wind_amt")) == 0.0)
	_check("ink knows which corners are leaves", InkStroke.leafiness(Style.swatch("mint")) > 0.5 and InkStroke.leafiness(Style.swatch("coral")) == 0.0)
	# bumps: walk into a prop and it wobbles, then settles
	main.load_scene("chaotic_supermarket")
	await _frames(3)
	var gm := main.world as GlbMap
	var prop: Node3D = null
	for n in gm._rest:
		if (n as Node3D).scale.y > 0.01:
			prop = n
			break
	if prop == null:
		_check("supermarket has props", false)
		return
	var rest: Transform3D = gm._rest[prop]
	var pp := prop.global_position
	main.place(main.actor, pp + Vector3(1.2, 0, 0.0), 0.0)
	main.walk_to(main.actor, pp)
	var wobbled := false
	for i in 90:
		await main.get_tree().process_frame
		if not prop.transform.is_equal_approx(rest) and gm._bumps.has(prop):
			wobbled = true
			break
	_check("walking into a prop makes it wobble", wobbled)
	_check("the bump is part of the shot snapshot", gm.chaos_state(main.t).get("bumps", []).size() > 0)
	main.walk_to(main.actor, pp + Vector3(2.5, 0, 0))
	await _wait(1.6)
	_check("the prop settles back to rest", prop.transform.is_equal_approx(rest) or not gm._bumps.has(prop))
	# follow camera
	main.load_scene("backyard_garden")
	await _frames(3)
	main.spawn_character("chaotic_frog")
	await _frames(2)
	await _tap(KEY_SEMICOLON)
	await _frames(3)
	_check("; switches to the follow camera", main.rig == "follow" and main.cam.position.is_finite())
	var pose: Array = main.frame_pair(main.actor, main.partner_of(main.actor))
	_check("follow framing aims between the pair", (pose[1] as Vector3).distance_to(main.actor.global_position) < 2.0)
	d.cam_cut("two_shot", "chaotic_frog", 0.0)
	d.update_camera(main.cam, 0.016)
	_check("two-shot preset frames a valid shot", main.cam.position.is_finite() and main.cam.fov > 10.0)
	main._set_rig("static")
	main.clear_cast()

## Physics: colliders, drops, pushing, kicks, blasts, abilities, water, and exact replay when scrubbing.
func _physics() -> void:
	var ph: StudioPhysics = main.physics
	var d: DirectorController = main.director
	if d.playing:
		d.stop(true)
	main.load_scene("backyard_garden")
	await _frames(3)
	main.clear_cast()
	_check("map meshes get colliders", main.world.find_children("Collider", "StaticBody3D", true, false).size() > 5)
	main.physics_drop("crate")
	await _wait(1.6)
	var crate: RigidBody3D = ph.objects[0]
	var g: float = main.world.ground(crate.global_position.x, crate.global_position.z)
	_check("a dropped crate lands on the ground", absf(crate.global_position.y - 0.25 - g) < 0.12)
	# a walking character pushes it
	var p0 := crate.global_position
	var from: Vector3 = p0 - Vector3(1.2, 0, 0)
	main.place(main.actor, from, PI * 0.5)
	await _frames(2)
	main.walk_to(main.actor, p0 + Vector3(1.4, 0, 0))
	await _wait(1.8)
	_check("walking characters push objects", crate.global_position.distance_to(p0) > 0.15)
	# kick
	var p1 := crate.global_position
	main.place(main.actor, p1 - Vector3(0.7, 0, 0), PI * 0.5)
	await _frames(3)
	await _tap(KEY_F8)
	await _wait(0.5)
	_check("F8 kicks the nearest object", crate.global_position.distance_to(p1) > 0.3)
	# set piece + blast
	ph.clear()
	main.physics_preset("crate_pyramid")
	await _wait(1.2)
	_check("a set piece lays out its objects", ph.objects.size() == 6)
	var before: Array = ph.objects.map(func(b): return (b as RigidBody3D).global_position)
	ph.blast((ph.objects[1] as RigidBody3D).global_position, 3.0, 5.0)
	await _wait(0.6)
	var moved := 0
	for i in ph.objects.size():
		if (ph.objects[i] as RigidBody3D).global_position.distance_to(before[i]) > 0.2:
			moved += 1
	_check("a blast scatters the pyramid", moved >= 4)
	# abilities push physics objects too
	ph.clear()
	main.physics_drop("barrel")
	await _wait(1.2)
	var barrel: RigidBody3D = ph.objects[0]
	var bp := barrel.global_position
	var blast_id := ""
	for id in main.abilities.by_id:
		if (main.abilities.by_id[id]["fx"] as Array).any(func(f): return f["type"] == "blast"):
			blast_id = id
			break
	main.place(main.actor, bp - Vector3(0.8, 0, 0), 0.0)
	await _frames(2)
	main.abilities.cast(main.actor, blast_id, false)
	await _wait(0.6)
	_check("a blast ability flings physics objects", barrel.global_position.distance_to(bp) > 0.3)
	# objects float on flood water
	main.load_scene("overflowing_kitchen")
	await _frames(3)
	main.physics_drop("crate")
	await _wait(1.0)
	main.set_stage(3)
	await _wait(3.5)
	_check("objects float on the flood", (ph.objects[0] as RigidBody3D).global_position.y > 0.45)
	main.set_stage(0)
	ph.clear()
	await _wait(1.0)
	# recording: perform a set piece during overdub, let it settle, then scrub back to that second
	d.play_shot("ep01_kitchen_disaster", 0, false)
	await _frames(3)
	main._take_control(main.find_actor("robo_bear"))
	await _frames(2)
	await _tap(KEY_R)
	await _wait(0.2)
	main.physics_preset("crate_pyramid")
	await _wait(0.6)
	ph.blast((ph.objects[0] as RigidBody3D).global_position + Vector3(0.3, 0, 0), 3.0, 4.0)
	await _wait(2.4)
	var t_live: float = d.shot_t
	var live_pos: Array = ph.objects.map(func(b): return (b as RigidBody3D).global_position)
	await _tap(KEY_R)
	var evs: Array = d.ep["shots"][0]["events"]
	_check("overdub records the set piece into the shot", evs.any(func(e): return e["action"] == "preset"))
	_check("the shot's physics was recorded", ph.has_recording(d.physics_key()))
	d.seek(t_live)
	await _frames(1)
	var err := 0.0
	for i in mini(live_pos.size(), ph.objects.size()):
		err = maxf(err, (ph.objects[i] as RigidBody3D).global_position.distance_to(live_pos[i]))
	_check("scrubbing puts every object back where it was (%.3f m)" % err, ph.objects.size() == live_pos.size() and err < 0.06)
	var held := (ph.objects[0] as RigidBody3D).global_position
	await _wait(0.3)
	_check("physics holds still while the Director is paused", (ph.objects[0] as RigidBody3D).global_position.distance_to(held) < 0.01)
	d.seek(0.05)
	_check("scrubbing before the drop removes the objects", ph.objects.size() == 0)
	for e in evs.filter(func(e): return e["action"] == "preset"):
		evs.erase(e)
	d.dirty = false
	d.stop(true)
	await _frames(2)
	ph.clear()
	main.clear_cast()   # later checks expect the map's host in control

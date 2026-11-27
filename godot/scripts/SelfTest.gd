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
	await _tap(KEY_O)
	_check("O turns on 12fps On Twos", main.on_twos)
	await _tap(KEY_O)
	_check("O turns On Twos off", not main.on_twos)
	# maps drawer
	await _tap(KEY_M)
	_check("M opens the maps drawer", main.map_open and main.map_panel.visible)
	await _frames(2)
	_check("maps drawer lists every map", main.maps_list.get_child_count() == main.map_order.size())
	await _tap(KEY_ESCAPE)
	_check("Escape closes the drawer", not main.map_open)
	# touch buttons go through the InputMap
	var face_btn: Button = main.hud_buttons[main.hud_buttons.size() - 3]
	var before: int = main.expr_i
	face_btn.emit_signal("pressed")
	await _frames(4)
	_check("FACE button cycles expression", main.expr_i == (before + 1) % 6)
	# cast drawer: spawn, control, move, switch
	await _tap(KEY_I)
	_check("I opens the cast drawer", main.cast_open)
	_check("cast drawer has 20 cards", main.cast_cards.size() == 20)
	main.cast_search.text = "toast"
	main._filter_cast()
	var shown: int = main.cast_cards.filter(func(c): return (c["button"] as Button).visible).size()
	_check("search filters the cast", shown == 1)
	main.cast_search.text = ""
	main.cast_filter = "Hybrid"
	main._filter_cast()
	shown = main.cast_cards.filter(func(c): return (c["button"] as Button).visible).size()
	_check("Hybrids filter shows 6", shown == 6)
	main.cast_filter = "All"
	main._filter_cast()
	(main.cast_cards[0]["button"] as Button).emit_signal("pressed")
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
	var palm: Button = main.hud_buttons.filter(func(b): return (b as Button).text == "PALM")[0]
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
	(main.cast_cards[7]["button"] as Button).emit_signal("pressed")
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
	_check("P opens the director drawer", main.director_open)
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
	_check("subtitle shows the line", main.subtitle.visible and main.subtitle.text.contains("toaster"))
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
	_check("play episode hides the HUD", main.hud_clean and not main.hud_root.visible)
	await _tap(KEY_ESCAPE)
	_check("Esc stops and takes over", not d.playing and main.hud_root.visible)
	main.clear_cast()
	await _frames(2)

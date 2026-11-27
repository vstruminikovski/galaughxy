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
	await _tap(KEY_R)
	_check("R raises flood stage 3", main.stage == 3)
	await _tap(KEY_T)
	_check("T drains", main.stage == 0)
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
	# buttons
	var face_btn: Button = main.hud_buttons[main.hud_buttons.size() - 3]
	var before: int = main.expr_i
	face_btn.emit_signal("pressed")
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
	main.load_scene("rooftop_terrace")
	await _frames(3)
	_check("rooftop loads", main.scene_name == "rooftop_terrace")
	main.despawn_selected()
	await _frames(2)
	_check("despawn selected", main.cast.size() == 1 and main.actor == main.host)
	main.clear_cast()
	await _frames(2)
	_check("clear cast", main.cast.is_empty())
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

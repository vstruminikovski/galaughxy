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

func _touch(idx: int, pos: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = pos
	ev.pressed = down
	Input.parse_input_event(ev)

func _drag(idx: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = pos
	Input.parse_input_event(ev)

func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1

func run() -> void:
	print("[test] start")
	await _frames(2)
	print("[test] frames ok")
	await _frames(5)
	main.load_scene("kitchen")
	print("[test] loaded")
	await _frames(3)
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
	await _frames(20)
	_key(KEY_W, false)
	_check("W moves the fly camera", main.fly_pos.distance_to(p0) > 0.05)
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
	await _tap(KEY_M)
	_check("M opens map", main.map_open)
	await _tap(KEY_ESCAPE)
	_check("Escape closes map", not main.map_open)
	# buttons
	var face_btn: Button = main.hud_buttons[main.hud_buttons.size() - 3]
	var before: int = main.expr_i
	face_btn.emit_signal("pressed")
	_check("FACE button cycles expression", main.expr_i == (before + 1) % 6)
	# portal: walk the robo into the kitchen doorway; kitchen links to pond
	main.actor_pos = Vector3(-2.95, 0, 0.9)
	await _frames(5)
	_check("portal travels to pond", main.scene_name == "pond")
	# frog hop + talk
	await _frames(5)
	_check("frog spawned", main.actor_kind == "frog")
	main.load_scene("garden")
	await _frames(3)
	_check("map travel works", main.scene_name == "garden")
	# touch: joystick on the left, look-drag on the right
	main.load_scene("garden")
	await _frames(3)
	var vp := main.get_viewport().get_visible_rect().size
	var start := Vector2(vp.x * 0.15, vp.y * 0.6)
	_touch(0, start, true)
	await _frames(2)
	_drag(0, start + Vector2(60, 0))
	await _frames(20)
	_touch(0, start + Vector2(60, 0), false)
	_check("left-thumb joystick moves the robo", main.actor_pos.x > 0.05 or main.joy_vec.x > 0.5)
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

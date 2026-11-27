class_name Puppet
extends Node3D

## One spawned roster character (a .glb from tools/generate_roster.py).
## Every character shares one joint layout, so this class animates any of them deterministically:
##   Hips, Spine, Head, Arm_L/R, Leg_L/R      walk waddle, idle bob, panic flail
##   Eye_L/R, Brow_L/R, Jaw or Mouth           expressions 1-6 and Talk lip-sync
## Gag joints are animated by name: Toast, Steam, Rotor_*, Tentacle_*, Wheel_*, Ear_*, Ball_*,
## Cheek_*, Mustache, Flame, Tail, Antenna_*. Per-character flags (characters.json):
## flop, spin_in_flood, squash_hop, stretch_turn.

const EXPRS := ["DEADPAN", "SMIRK", "PANIC", "ANGRY", "HAPPY", "SHOCKED"]

var info: Dictionary
var model: Node3D
var expr_i := 0
var talk := false
var moving := 0.0
var hop := 0.0
var flood_over := false
## Mouth level from the dialogue spectrum (0..1), or -1 to use the procedural talk bounce.
var talk_level := -1.0

const EMOTE_TIME := {"emote_wave": 1.6, "emote_point": 1.4, "emote_facepalm": 1.6, "emote_shrug": 1.4}
var _emote := ""
var _emote_t := 0.0

var _j := {}
var _rest := {}
var _flags: Array = []
var _talk_amt := 0.0
var _toast := 0.0
var _spin := 0.0
var _wheel := 0.0
var _rotor := 0.0
var _prev_yaw := 0.0
var _turn := 0.0

static func create(data: Dictionary) -> Puppet:
	var p := Puppet.new()
	p.info = data
	p.name = String(data["id"])
	p._flags = data.get("flags", [])
	var scene := load(String(data["model"])) as PackedScene
	p.model = scene.instantiate() as Node3D
	p.model.scale = Vector3.ONE * float(data.get("scale", 1.0))
	p.add_child(p.model)
	Style.restyle(p.model)
	p._index(p.model)
	p._ink(p.model)
	return p

## Plays an upper-body emote (emote_wave, emote_point, emote_facepalm, emote_shrug).
func emote(action: String) -> void:
	if EMOTE_TIME.has(action):
		_emote = action
		_emote_t = 0.0

## Clears every animation memory, so a scrub or retake replays exactly the same poses.
func reset_state() -> void:
	_talk_amt = 0.0
	_toast = 0.0
	_spin = 0.0
	_wheel = 0.0
	_rotor = 0.0
	_prev_yaw = rotation.y
	_turn = 0.0
	_emote = ""
	_emote_t = 0.0
	talk = false
	talk_level = -1.0
	moving = 0.0
	hop = 0.0
	if model:
		model.rotation.y = 0.0

func emote_playing() -> String:
	return _emote

func display_name() -> String:
	return String(info.get("name", name))

func _index(n: Node) -> void:
	for c in n.get_children():
		if c is Node3D:
			_j[String(c.name)] = c
			_rest[String(c.name)] = (c as Node3D).transform
		_index(c)

## Ink only the outer shapes: skip tiny parts, glowing parts and glass, so lines stay sparing.
func _ink(n: Node) -> void:
	for c in n.get_children():
		_ink(c)
	var mi := n as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	if mi.mesh.get_aabb().get_longest_axis_size() < 0.045:
		return
	var mat := mi.get_active_material(0) as BaseMaterial3D
	if mat and (mat.emission_enabled or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
		return
	if mi.mesh is ArrayMesh:
		mi.add_child(Ink.rim(mi.mesh as ArrayMesh))

# ── posing helpers ──────────────────────────────────────────────────────────────
func _has(n: String) -> bool:
	return _j.has(n)

func _pose(n: String, offset := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> void:
	if not _j.has(n):
		return
	var r: Transform3D = _rest[n]
	(_j[n] as Node3D).transform = Transform3D(r.basis * Basis.from_euler(rot) * Basis.from_scale(scl), r.origin + offset)

func _each(prefix: String) -> Array:
	var out := []
	for k in _j:
		if String(k).begins_with(prefix) and not String(k).contains("Mesh"):
			out.append(k)
	out.sort()
	return out

# ── per frame ───────────────────────────────────────────────────────────────────
## ta: animation time (stepped when "on twos"); dt: time since the last animation step.
func animate(ta: float, dt: float) -> void:
	var expr: String = EXPRS[expr_i]
	var panic := expr == "PANIC" or expr == "SHOCKED"
	var k := minf(1.0, dt * 18.0)
	var target := 0.0
	if talk and talk_level >= 0.0:
		target = talk_level * 0.9
	elif talk:
		target = maxf(0.0, sin(ta * 14.0) + sin(ta * 21.0) * 0.5) * 0.65
	_talk_amt = lerpf(_talk_amt, target, k if talk_level < 0.0 else 1.0)
	# emote weight: ease in, hold, ease out
	var ew := 0.0
	if _emote != "":
		_emote_t += dt
		var dur: float = EMOTE_TIME[_emote]
		ew = clampf(_emote_t / 0.15, 0.0, 1.0) * clampf((dur - _emote_t) / 0.2, 0.0, 1.0)
		ew = ew * ew * (3.0 - 2.0 * ew)
		if _emote_t >= dur:
			_emote = ""
	var walk := sin(ta * 9.0) * moving
	var bounce := absf(sin(ta * 9.0)) * moving
	# turn rate (for the dachshund stretch)
	var dyaw := wrapf(rotation.y - _prev_yaw, -PI, PI)
	_prev_yaw = rotation.y
	_turn = lerpf(_turn, absf(dyaw) / maxf(dt, 1e-3), minf(1.0, dt * 6.0))

	# body
	var shake := sin(ta * 41.0) * 0.006 if panic else 0.0
	var shrug_lift := 0.012 * ew if _emote == "emote_shrug" else 0.0
	_pose("Hips", Vector3(shake, bounce * 0.025 + sin(ta * 2.2) * 0.004 + shrug_lift, 0))
	var sway := sin(ta * 9.0) * 0.06 * moving + (sin(ta * 23.0) * 0.07 if panic else 0.0)
	if _flags.has("flop"):
		sway += sin(ta * 13.0) * 0.32 * maxf(moving, 1.0 if sin(ta * 1.3) > 0.55 else 0.0)
	_pose("Spine", Vector3.ZERO, Vector3(0, 0, sway))

	# head: tilt by expression, nod with talk, shake in panic
	var hx := _talk_amt * 0.08 + (0.12 if expr == "ANGRY" else 0.0) - (0.06 if expr == "HAPPY" else 0.0)
	var hy := sin(ta * 30.0) * 0.12 if expr == "PANIC" else 0.0
	var hz := 0.14 if expr == "SMIRK" else (sin(ta * 6.0) * 0.05 if expr == "HAPPY" else 0.0)
	var head_rot := Vector3(hx, hy, hz).lerp(_emote_head(ta), ew)
	_pose("Head", Vector3(0, 0.012 if expr == "SHOCKED" else 0.0, 0), head_rot)

	# arms and legs: waddle, flail, wave
	for s in [1.0, -1.0]:
		var side := "L" if s > 0 else "R"
		var arm := Vector3(walk * 0.6 * s, 0, 0)
		if panic:
			arm.z = s * (1.1 + sin(ta * 21.0 + s) * 0.45)
		elif expr == "HAPPY" and s > 0:
			arm.z = 0.9 + sin(ta * 8.0) * 0.4
		elif expr == "ANGRY":
			arm.z = s * 0.25
		_pose("Arm_" + side, Vector3.ZERO, arm.lerp(_emote_arm(s, ta, arm), ew))
		_pose("Leg_" + side, Vector3.ZERO, Vector3(-walk * 0.7 * s, 0, 0))

	# face
	var blink := fmod(ta + float(String(name).hash() % 100) * 0.037, 3.7) < 0.12
	var eye := {"DEADPAN": Vector3(1, 0.55, 1), "SMIRK": Vector3(1, 0.7, 1), "PANIC": Vector3(1.25, 1.25, 1.25),
		"ANGRY": Vector3(1, 0.7, 1), "HAPPY": Vector3(1, 0.45, 1), "SHOCKED": Vector3(1.4, 1.4, 1.4)}[expr] as Vector3
	for s in [1.0, -1.0]:
		var side := "L" if s > 0 else "R"
		var e := eye
		if expr == "SMIRK" and s < 0:
			e = Vector3(1, 0.4, 1)
		if blink:
			e.y *= 0.1
		_pose("Eye_" + side, Vector3(0, 0.004 if expr == "HAPPY" else 0.0, 0), Vector3.ZERO, e)
		var brow_rot := 0.0
		var brow_y := 0.0
		match expr:
			"ANGRY": brow_rot = -0.4 * s; brow_y = -0.006
			"PANIC", "SHOCKED": brow_y = 0.012
			"SMIRK": brow_rot = 0.25 if s > 0 else 0.0
			"HAPPY": brow_y = 0.006
		_pose("Brow_" + side, Vector3(0, brow_y, 0), Vector3(0, 0, brow_rot))
	var jaw := _talk_amt * 0.5 + (0.3 if expr == "SHOCKED" else (0.15 + absf(sin(ta * 9.0)) * 0.1 if expr == "PANIC" else 0.0))
	_pose("Jaw", Vector3.ZERO, Vector3(jaw, 0, 0))
	var mouth := Vector3(1.3 if expr == "HAPPY" else 1.0, 1.0 + _talk_amt * 3.0 + (2.0 if expr == "SHOCKED" else 0.0), 1.0)
	_pose("Mouth", Vector3.ZERO, Vector3.ZERO, mouth)
	for s in ["L", "R"]:
		_pose("Cheek_" + s, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * (1.0 + _talk_amt * 0.6 + (0.25 if panic else 0.0)))

	# gags
	_toast = lerpf(_toast, 0.11 if expr == "SHOCKED" else 0.0, minf(1.0, dt * (16.0 if expr == "SHOCKED" else 5.0)))
	_pose("Toast", Vector3(0, _toast, 0))
	if _has("Steam"):
		(_j["Steam"] as Node3D).visible = expr == "ANGRY"
		_pose("Steam", Vector3(0, fmod(ta * 0.8, 1.0) * 0.05, 0), Vector3.ZERO, Vector3.ONE * (0.8 + fmod(ta * 0.8, 1.0) * 0.6))
	_rotor += dt * (28.0 + moving * 20.0)
	for n in _each("Rotor_"):
		_pose(n, Vector3.ZERO, Vector3(0, _rotor * (0.25 if n == "Rotor_Key" else 1.0), 0))
	var tent := _each("Tentacle_")
	for i in tent.size():
		_pose(tent[i], Vector3.ZERO, Vector3(sin(ta * (9.0 if panic else 4.0) + i * 1.1) * 0.25 * (1.0 + moving), 0, 0))
	_wheel += dt * moving * 18.0
	var wheel_scale := clampf(moving * 3.0, 0.001, 1.0)
	for n in _each("Wheel_"):
		_pose(n, Vector3.ZERO, Vector3(_wheel, 0, 0), Vector3.ONE * wheel_scale)
	for s in [1.0, -1.0]:
		var side := "L" if s > 0 else "R"
		_pose("Ear_" + side, Vector3.ZERO, Vector3(sin(ta * 6.0 + s) * 0.12 + hop * 2.5 + bounce * 0.2, 0, 0))
	var balls := _each("Ball_")
	for i in balls.size():
		var lift := absf(sin(ta * 7.0 + i * 1.3)) * 0.012 * (1.0 + 3.0 * (_talk_amt + moving + (1.0 if panic else 0.0)))
		_pose(balls[i], Vector3(0, lift, 0))
	var twitch := sin(ta * 25.0) * 0.12 if (talk or expr == "ANGRY") else sin(ta * 2.0) * 0.02
	_pose("Mustache", Vector3.ZERO, Vector3(0, 0, twitch))
	if _has("Flame"):
		(_j["Flame"] as Node3D).visible = hop > 0.02 or moving > 0.5
		_pose("Flame", Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.8 + absf(sin(ta * 37.0)) * 0.5, 1))
	_pose("Tail", Vector3.ZERO, Vector3(0, sin(ta * 8.0) * 0.35 * (0.3 + moving), 0))
	var ant := _each("Antenna_")
	for i in ant.size():
		_pose(ant[i], Vector3.ZERO, Vector3(0, 0, sin(ta * 5.0 + i * 2.0) * 0.1 + walk * 0.1))

	# per-character flags
	if _flags.has("spin_in_flood"):
		_spin += dt * (11.0 if flood_over else 0.0)
		model.rotation.y = _spin
	if _flags.has("squash_hop"):
		var h := clampf(hop / 0.15, 0.0, 1.0)
		model.scale = Vector3(1.0 + 0.3 * h, 1.0 - 0.45 * h, 1.0 + 0.3 * h) * float(info.get("scale", 1.0))
	if _flags.has("stretch_turn"):
		var st := clampf(_turn * 0.12, 0.0, 0.7)
		_pose("LongBody", Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 1.0 + st))
		for f in _each("Fold_"):
			_pose(f, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 1.0 + st))
		_pose("Head", Vector3(0, 0, st * 0.2), Vector3(hx, hy, hz))
		_pose("Tail", Vector3(0, 0, -st * 0.2), Vector3(0, sin(ta * 8.0) * 0.35 * (0.3 + moving), 0))
		for s in ["L", "R"]:
			_pose("Arm_" + s, Vector3(0, 0, st * 0.17), Vector3(walk * 0.6, 0, 0))
			_pose("Leg_" + s, Vector3(0, 0, -st * 0.17), Vector3(-walk * 0.7, 0, 0))


## Arm rotation for the current emote (s = +1 left arm, -1 right arm). Godot axes: +X is the
## character's left, +Z forward; rotating an arm about Z raises it sideways, about X swings it forward.
func _emote_arm(s: float, ta: float, base: Vector3) -> Vector3:
	match _emote:
		"emote_wave":
			return Vector3(0, 0, -2.5 + sin(ta * 14.0) * 0.35) if s < 0 else base
		"emote_point":
			return Vector3(-1.5, 0, -0.12) if s < 0 else base
		"emote_facepalm":
			return Vector3(-2.15, 0, 0.55) if s < 0 else base
		"emote_shrug":
			return Vector3(-0.55, 0, s * 0.95)
	return base

func _emote_head(ta: float) -> Vector3:
	match _emote:
		"emote_wave": return Vector3(0, 0, -0.1)
		"emote_point": return Vector3(0, -0.35, 0)
		"emote_facepalm": return Vector3(0.34, 0, 0)
		"emote_shrug": return Vector3(0, 0, 0.18 + sin(ta * 3.0) * 0.03)
	return Vector3.ZERO

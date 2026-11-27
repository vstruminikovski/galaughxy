class_name DirectorController
extends Node

## Audio-first, shot-based director.
## Episodes live in res://data/episodes/*.json (saved copies in user://episodes/ win). An episode is
## a list of shots; each shot has a camera, an optional shake impulse and timed events:
##   move [x, y, z] · expr · emote · hop · talk (audio clip / text) · chaos 0-3 · cam · face
## Smart auto-timing: a shot lasts at least min_duration and, when auto_advance_on_audio is on, long
## enough for every line (clip length, or 0.065 s per character until the clip is recorded).
## Every shot starts from a snapshot of the cast, so a shot can be played, looped, retaken, jumped
## to or scrubbed to an exact second and always replays the same way (fixed-step fast-forward).
## Overdub records the controlled character's live input into the shot at the exact time,
## replacing only that character's conflicting channel (move / expr / gesture / talk; cam / chaos).

signal finished
signal changed

const STEP := 1.0 / 60.0
const MOVE_SAMPLE := 0.25
const TRACKING := ["closeup_actor", "follow_shoulder"]

var main: Node
var episodes := {}
var order: Array = []
var ep_id := ""
var ep: Dictionary = {}
var shot_i := -1
var shot_t := 0.0
var shot_len := 0.0
var playing := false
var paused := false
var loop := false
var mode := ""
var simulating := false
var dirty := false
var snapshots := {}
var _events: Array = []
var _fired := 0

# camera
var released := false
var cam_preset := "wide_static"
var cam_target := ""
var cam_push := [0.0, 100.0]
var cut_time := 0.0
var trauma := 0.0
var _blend_t := 0.0
var _from: Array = []
var _cur: Array = []
var _snap_cam := true

# overdub
var overdub := false
var _rec := {}
var _talk_start := -1.0
var _move_t := 0.0
var _was_moving := false

func _init(m: Node) -> void:
	main = m

func _ready() -> void:
	reload()

func reload() -> void:
	episodes.clear()
	order.clear()
	for dir in ["res://data/episodes/", "user://episodes/"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if not f.ends_with(".json"):
				continue
			var e = JSON.parse_string(FileAccess.get_file_as_string(dir + f))
			if e is Dictionary and e.has("episode_id"):
				var id := String(e["episode_id"])
				episodes[id] = e
				if not order.has(id):
					order.append(id)
	order.sort()

# ── timing ────────────────────────────────────────────────────────────────────────
func line_length(e: Dictionary) -> float:
	return main.voice.line_length(String(e.get("audio", "")), String(e.get("text", "")), float(e.get("duration", -1.0)))

## Smart auto-timing: long enough for the last event and (if enabled) every line.
func estimate_length(shot: Dictionary) -> float:
	var length := float(shot.get("min_duration", 3.0))
	var last := 0.0
	var talk_end := 0.0
	for e in shot.get("events", []):
		var t := float(e.get("t", 0.0))
		last = maxf(last, t)
		if e.get("action", "") == "talk":
			talk_end = maxf(talk_end, t + line_length(e))
	if shot.get("auto_advance_on_audio", true):
		length = maxf(length, talk_end + 0.35)
	length = maxf(length, last + 0.6)
	if shot.has("duration"):
		length = maxf(length, float(shot["duration"]))
	return length

# ── playback ──────────────────────────────────────────────────────────────────────
func _shots() -> Array:
	return ep.get("shots", [])

func play_episode(id: String, shot_id := "") -> void:
	if not episodes.has(id):
		push_warning("unknown episode: " + id)
		return
	_open(id, true)
	mode = "episode"
	loop = false
	_begin(true)
	var i := 0
	for k in _shots().size():
		if String(_shots()[k]["id"]) == shot_id:
			i = k
	_go_to_shot(i)

func play_shot(id: String, i: int, looped := false) -> void:
	if not episodes.has(id):
		return
	_open(id, id != ep_id or snapshots.is_empty())
	mode = "shot"
	loop = looped
	_begin(false)
	_go_to_shot(clampi(i, 0, _shots().size() - 1))

func _open(id: String, fresh: bool) -> void:
	_commit()
	if fresh:
		ep_id = id
		ep = episodes[id]
		snapshots.clear()
		_setup_cast()

func _begin(clean: bool) -> void:
	playing = true
	paused = false
	released = false
	main.voice.set_paused(false)
	main.on_director_start(clean)

## Loads the episode's map and puts its cast on their marks; this is shot 1's starting snapshot.
func _setup_cast() -> void:
	var map: String = main.map_alias.get(String(ep.get("map", "")), "")
	if map != "" and main.scene_name != map:
		main.load_scene(map)
	var cast: Dictionary = ep.get("cast", {})
	for id in _actor_ids():
		var n: Node3D = main.actor_for(id)
		if n == null:
			continue
		var c: Dictionary = cast.get(id, {})
		if c.has("at"):
			var at: Array = c["at"]
			main.place(n, Vector3(float(at[0]), 0, float(at[at.size() - 1])), deg_to_rad(float(c.get("yaw", 0.0))))
		main.motion[n]["expr"] = maxi(0, main.EXPRS.find(String(c.get("expr", "DEADPAN"))))
	snapshots[0] = _capture()

func _actor_ids() -> Array:
	var ids: Array = []
	for id in ep.get("cast", {}):
		ids.append(String(id))
	for shot in _shots():
		for e in shot.get("events", []):
			var a := String(e.get("actor", ""))
			if a != "" and not ids.has(a):
				ids.append(a)
	return ids

func _capture() -> Dictionary:
	var s := {"flood": main.flood, "flood_target": main.flood_target, "stage": main.stage, "actors": {}}
	for n in main._actors():
		var m: Dictionary = main.motion[n]
		s["actors"][main.id_of(n)] = {"pos": m["pos"], "yaw": m["yaw"], "expr": m["expr"], "target": m["target"]}
	return s

func _restore(s: Dictionary) -> void:
	main.voice.stop_all()
	for id in s["actors"]:
		var n: Node3D = main.find_actor(id)
		if n == null:
			continue
		var a: Dictionary = s["actors"][id]
		main.place(n, a["pos"], a["yaw"])
		main.motion[n]["expr"] = a["expr"]
		main.motion[n]["target"] = a["target"]
		if n is Puppet:
			(n as Puppet).reset_state()
	main.flood = s["flood"]
	main.flood_target = s["flood_target"]
	main.stage = s["stage"]
	main.jaw = 0.0

## Restores (or rebuilds by fast-forwarding earlier shots) the state at the start of shot i.
func _go_to_shot(i: int) -> void:
	if not snapshots.has(i):
		var k := i
		while k > 0 and not snapshots.has(k):
			k -= 1
		_restore(snapshots[k])
		while k < i:
			_enter_shot(k)
			_simulate(shot_len)
			k += 1
			snapshots[k] = _capture()
	_restore(snapshots[i])
	_enter_shot(i)
	main.voice.resume_audio()

func _enter_shot(i: int) -> void:
	shot_i = i
	var shot: Dictionary = _shots()[i]
	_events = shot.get("events", []).duplicate()
	_events.sort_custom(func(a, b): return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	_fired = 0
	shot_t = 0.0
	shot_len = estimate_length(shot)
	main.reset_clock()
	if main.host:
		main.host.visible = _actor_ids().has("host")
	trauma = 0.0
	cam_cut(String(shot.get("cam", "wide_static")), String(shot.get("cam_target", "")),
		float(shot.get("cut", 0.0)), shot.get("push", [0.0, 100.0]), float(shot.get("shake", 0.0)))
	if overdub:
		_arm_overdub()
	changed.emit()

## Silent fixed-step fast-forward of the current shot up to `until` seconds.
func _simulate(until: float) -> void:
	simulating = true
	var was_paused := paused
	paused = false
	main.voice.silent = true
	var guard := 0
	while shot_t < until - 1e-6 and guard < 20000:
		main._step(minf(STEP, until - shot_t), false)
		guard += 1
	if absf(shot_t - until) < 1e-4:
		shot_t = until
	main.voice.silent = false
	paused = was_paused
	simulating = false

func process_shot(dt: float) -> void:
	if not playing or paused or ep.is_empty():
		return
	shot_t += dt
	while _fired < _events.size() and float(_events[_fired].get("t", 0.0)) <= shot_t:
		_fire(_events[_fired])
		_fired += 1
	trauma = maxf(0.0, trauma - dt * 0.9)
	if simulating:
		return
	if overdub:
		_sample_overdub()
	if shot_t >= shot_len:
		_shot_done()

func _shot_done() -> void:
	_commit()
	if loop:
		_go_to_shot(shot_i)
	elif mode == "episode" and shot_i + 1 < _shots().size():
		snapshots[shot_i + 1] = _capture()
		_enter_shot(shot_i + 1)
	else:
		stop(false)
		finished.emit()

func retake() -> void:
	if ep.is_empty() or shot_i < 0:
		return
	_commit()
	playing = true
	paused = false
	released = false
	main.voice.set_paused(false)
	_go_to_shot(shot_i)

## Stops the director. Take Over leaves the cast where it is so you can possess anyone live.
func stop(take_over := true) -> void:
	_commit()
	overdub = false
	playing = false
	paused = false
	released = true
	main.voice.stop_all()
	main.on_director_stop(take_over)
	changed.emit()

func toggle_pause() -> void:
	if not playing:
		if not ep.is_empty():
			play_shot(ep_id, maxi(shot_i, 0), loop)
		elif not order.is_empty():
			play_shot(order[0], 0, false)
		return
	paused = not paused
	main.voice.set_paused(paused)
	changed.emit()

## Scrubs the current shot to an exact second: restore its snapshot, fast-forward silently.
func seek(to: float) -> void:
	if ep.is_empty() or shot_i < 0:
		return
	_commit()
	overdub = false
	if not playing:
		playing = true
		released = false
		main.on_director_start(false)
	paused = true
	main.voice.set_paused(true)
	_restore(snapshots[shot_i])
	_enter_shot(shot_i)
	_simulate(clampf(to, 0.0, shot_len))
	main.voice.resume_audio()
	main.voice.set_paused(true)
	_snap_cam = true
	changed.emit()

func _fire(e: Dictionary) -> void:
	var id := String(e.get("actor", ""))
	if overdub and id != "" and id == String(_rec.get("actor", "")):
		return # this character is being performed live
	var n: Node3D = main.find_actor(id) if id != "" else null
	var v = e.get("value", null)
	match String(e.get("action", "")):
		"expr": main.act(n, "expr_%d" % (main.EXPRS.find(String(v)) + 1))
		"emote": main.act(n, String(v))
		"hop": main.act(n, "hop")
		"talk": main.say(n, String(e.get("audio", "")), String(e.get("text", "")), float(e.get("duration", -1.0)))
		"move":
			var to: Array = e.get("value", e.get("to", [0, 0, 0]))
			main.walk_to(n, Vector3(float(to[0]), 0, float(to[to.size() - 1])))
		"face": main.face(n, deg_to_rad(float(v)))
		"chaos": main.set_stage(int(v))
		"shake": trauma = maxf(trauma, float(v))
		"cam":
			cam_cut(String(v), String(e.get("target", "")), float(e.get("cut", 0.0)), e.get("push", [0.0, 100.0]), float(e.get("shake", 0.0)))

# ── cameras ───────────────────────────────────────────────────────────────────────
func drives_camera() -> bool:
	return playing and not released and not ep.is_empty()

func release_camera() -> void:
	released = true

## Cuts to a camera preset: cut = 0 is a hard cut, 0.25 a smooth ease; shake adds trauma.
func cam_cut(preset: String, target := "", cut := 0.0, push = [0.0, 100.0], shake := 0.0) -> void:
	_from = _cur.duplicate()
	cam_preset = preset
	cam_target = target
	cam_push = push
	cut_time = cut
	_blend_t = 0.0
	trauma = maxf(trauma, shake)
	_snap_cam = true

func update_camera(cam: Camera3D, dt: float) -> void:
	var d := _desired()
	if TRACKING.has(cam_preset) and not _snap_cam and _cur.size() == 3:
		var k := 1.0 - exp(-6.0 * dt)
		_cur = [(_cur[0] as Vector3).lerp(d[0], k), (_cur[1] as Vector3).lerp(d[1], k), lerpf(_cur[2], d[2], k)]
	else:
		_cur = d
	_snap_cam = false
	var pose := _cur
	if cut_time > 0.0 and _blend_t < cut_time and _from.size() == 3:
		var e := smoothstep(0.0, 1.0, _blend_t / cut_time)
		pose = [(_from[0] as Vector3).lerp(_cur[0], e), (_from[1] as Vector3).lerp(_cur[1], e), lerpf(_from[2], _cur[2], e)]
		_blend_t += dt
	var s := trauma * trauma
	var off := Vector3(sin(shot_t * 37.0) + sin(shot_t * 23.0), sin(shot_t * 29.0 + 1.0), sin(shot_t * 31.0 + 2.0)) * 0.06 * s
	cam.position = pose[0] + off
	cam.look_at(pose[1] + off * 0.5, Vector3.UP)
	cam.fov = pose[2]

func _target_node() -> Node3D:
	if cam_target != "":
		var n: Node3D = main.find_actor(cam_target)
		if n:
			return n
	var sp: Node3D = main.voice.speaker()
	if sp and is_instance_valid(sp):
		return sp
	return main.actor

func _desired() -> Array:
	var c: Dictionary = main.maps[main.scene_name]["cams"]
	var prog := clampf(shot_t / maxf(shot_len, 0.01), 0.0, 1.0)
	match cam_preset:
		"slider_push", "slider":
			var s: Array = c["slider"]
			var p := lerpf(float(cam_push[0]), float(cam_push[1]), prog) / 100.0
			var pos: Vector3 = main.v3(s[0]).lerp(main.v3(s[1]), p)
			var look: Vector3 = pos + main.v3(s[2])
			# keep the subject (target or speaker) in frame while the dolly moves
			var subject := _target_node()
			if subject and is_instance_valid(subject) and subject.visible:
				look = look.lerp(subject.global_position + Vector3(0, main.height_of(subject) * 0.6, 0), 0.75)
			return [pos, look, float(s[3])]
		"drone_intro", "drone":
			var d: Array = c["drone"]
			var a := 0.9 + shot_t * 0.3
			var r := float(d[1]) * (1.25 - 0.25 * prog)
			var h := float(d[2]) * (1.2 - 0.25 * prog)
			var centre: Vector3 = main.v3(d[0])
			return [centre + Vector3(sin(a) * r, h, cos(a) * r), centre + Vector3(0, 0.3, 0), float(d[3])]
		"closeup_actor", "follow_shoulder":
			var n := _target_node()
			if n and is_instance_valid(n):
				var h: float = main.height_of(n)
				var yaw := n.rotation.y
				var fwd := Vector3(sin(yaw), 0, cos(yaw))
				if cam_preset == "closeup_actor":
					var head: Vector3 = main.head_pos(n)
					var aim := head - Vector3(0, h * 0.18, 0)
					return [aim + fwd * clampf(h * 3.0, 0.85, 2.2) + Vector3(0, h * 0.12, 0), aim, 42.0]
				var base := n.global_position
				var right := Vector3(-fwd.z, 0, fwd.x)
				return [base - fwd * maxf(1.1, h * 2.8) + right * h * 0.6 + Vector3(0, h * 1.7, 0),
					base + fwd * 1.2 + Vector3(0, h * 0.7, 0), 50.0]
	return main.rig_pose("static")

## A human camera key during playback cuts the director camera (and is recorded in Overdub).
func cam_cut_live(preset: String) -> void:
	cam_cut(preset, "", 0.0)
	if overdub:
		_record("cam", preset, "")

# ── overdub ───────────────────────────────────────────────────────────────────────
static func channel(action: String) -> String:
	match action:
		"emote", "hop": return "gesture"
	return action

func toggle_overdub() -> void:
	if overdub:
		_commit()
		overdub = false
	elif playing and not paused and main._has(main.actor):
		overdub = true
		_arm_overdub()
	changed.emit()

func _arm_overdub() -> void:
	_rec = {"actor": main.id_of(main.actor), "channels": {}, "events": []}
	_talk_start = -1.0
	_move_t = shot_t
	_was_moving = false

func _record(action: String, value, actor = null) -> void:
	if not overdub or _rec.is_empty():
		return
	var who := String(_rec["actor"]) if actor == null else String(actor)
	var t := snappedf(shot_t, 0.01)
	var e := {"t": t, "action": action}
	if who != "":
		e["actor"] = who
	if value != null:
		e["value"] = value
	var key := who + ":" + channel(action)
	if not _rec["channels"].has(key):
		_rec["channels"][key] = t
	_rec["events"].append(e)

## A character action performed live by the human (expr_n, emote_*, hop).
func record_action(action: String) -> void:
	if action.begins_with("expr_"):
		_record("expr", main.EXPRS[clampi(int(action.substr(5)) - 1, 0, 5)])
	elif action.begins_with("emote_"):
		_record("emote", action)
	elif action == "hop":
		_record("hop", null)

func record_chaos(s: int) -> void:
	_record("chaos", s, "")

func talk_begin() -> void:
	if overdub:
		_talk_start = snappedf(shot_t, 0.01)

func talk_end() -> void:
	if not overdub or _talk_start < 0.0:
		return
	var start := _talk_start
	_talk_start = -1.0
	var e := {"t": start, "actor": _rec["actor"], "action": "talk", "text": "", "duration": snappedf(maxf(0.2, shot_t - start), 0.01)}
	var key := String(_rec["actor"]) + ":talk"
	if not _rec["channels"].has(key):
		_rec["channels"][key] = start
	_rec["events"].append(e)

func _sample_overdub() -> void:
	if _rec.is_empty() or not main._has(main.actor):
		return
	var m: Dictionary = main.motion[main.actor]
	var moving: bool = m["moving"] > 0.3
	if (moving and shot_t - _move_t >= MOVE_SAMPLE) or (_was_moving and not moving):
		var p: Vector3 = m["pos"]
		_record("move", [snappedf(p.x, 0.01), 0.0, snappedf(p.z, 0.01)])
		_move_t = shot_t
	_was_moving = moving

## Writes the take into the shot: drop old events of each recorded actor/channel inside the
## recorded time range, keep everything else, then add the new ones.
func _commit() -> void:
	if _rec.is_empty() or shot_i < 0:
		_rec = {}
		return
	talk_end()
	if _rec["events"].is_empty():
		_rec = {}
		return
	var end := shot_t
	var shot: Dictionary = _shots()[shot_i]
	var kept: Array = []
	for e in shot.get("events", []):
		var key := String(e.get("actor", "")) + ":" + channel(String(e.get("action", "")))
		var t := float(e.get("t", 0.0))
		if _rec["channels"].has(key) and t >= float(_rec["channels"][key]) - 0.001 and t <= end + 0.001:
			continue
		kept.append(e)
	kept.append_array(_rec["events"])
	kept.sort_custom(func(a, b): return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	shot["events"] = kept
	dirty = true
	for k in snapshots.keys():
		if int(k) > shot_i:
			snapshots.erase(k)
	_rec = {}
	changed.emit()

# ── save ──────────────────────────────────────────────────────────────────────────
## Saves to user://episodes/ (and back into res://data/episodes/ when running from the project).
func save() -> Array:
	_commit()
	if ep.is_empty():
		return []
	var text := JSON.stringify(ep, "\t", false)
	var paths: Array = []
	DirAccess.make_dir_recursive_absolute("user://episodes")
	var targets := ["user://episodes/%s.json" % ep_id]
	if not OS.has_feature("standalone"):
		targets.append("res://data/episodes/%s.json" % ep_id)
	for path in targets:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(text + "\n")
			f.close()
			paths.append(ProjectSettings.globalize_path(path))
	dirty = false
	changed.emit()
	return paths

func status_text() -> String:
	if ep.is_empty():
		return "No episode loaded"
	var shot_name := ""
	if shot_i >= 0 and shot_i < _shots().size():
		shot_name = String(_shots()[shot_i].get("name", _shots()[shot_i]["id"]))
	var state := "paused" if paused else ("playing" if playing else "stopped")
	return "%s · shot %d/%d %s · %.2f / %.2f s · %s%s%s%s" % [ep.get("title", ep_id), shot_i + 1, _shots().size(), shot_name,
		shot_t, shot_len, state, " · LOOP" if loop else "", " · ● OVERDUB" if overdub else "", " · unsaved" if dirty else ""]

class_name StudioPhysics
extends Node3D

## Real rigid-body physics for the studio (CLAUDE.md section 26), made safe for the Director.
## - Every map gets static colliders from its own meshes. Props carry theirs, so chaos FX that move a
##   prop move its collider too.
## - Characters push things: each one is followed by a kinematic capsule.
## - Physics objects (res://data/physics_props.json) are dropped from the 🧱 Physics toolbox, spawned
##   by Director events, or flung by abilities (blast, launch, push, knockback, magnet, quake).
## - Objects float on flood water and drift in low gravity.
## - Determinism: while a shot plays live, every object's motion is recorded (30 samples a second).
##   A scrub, retake or jump puts each object exactly where the recording has it, and live play
##   carries on from there. Shot snapshots hold the objects too. Physics pauses with the Director.

const RATE := 30.0
const KILL_Y := -3.0
const LAYER_WORLD := 1
const LAYER_PUSHER := 2
const LAYER_OBJECT := 4

var main: Node
var defs := {}
var order: Array = []
var presets := {}
var preset_order: Array = []
var objects: Array = []          # RigidBody3D in spawn order; the index is the object's id (pid)
var recordings := {}             # "<episode>:<shot>" -> {pid: Array [t, px, py, pz, qx, qy, qz, qw, ...]}
var _pushers := {}               # actor -> AnimatableBody3D
var _scenes := {}
var _shapes := {}
var _last_sample := -1.0
var _last_key := ""
var _active := true
var _gravity := 9.8

func _init(m: Node) -> void:
	main = m
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/physics_props.json"))
	for p in d["props"]:
		defs[String(p["id"])] = p
		order.append(String(p["id"]))
	for p in d.get("presets", []):
		presets[String(p["id"])] = p
		preset_order.append(String(p["id"]))

# ── world ─────────────────────────────────────────────────────────────────────────
## A new map: objects and recordings belong to the old one.
func map_changed(root: Node) -> void:
	clear()
	build_static(root)

## Static colliders: one concave shape per visible mesh (sets, floors, props). Skips glow, glass,
## ink, tiny parts and anything inside a character.
func build_static(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi is InkStroke or mi is InkEdges or mi.mesh == null or mi.has_node("Collider"):
			continue
		if main.host != null and is_instance_valid(main.host) and main.host.is_ancestor_of(mi):
			continue
		var mat := mi.get_active_material(0)
		if Style.is_glow(mat) or Style.is_clear(mat):
			continue
		if mi.mesh.get_aabb().get_longest_axis_size() < 0.06:
			continue
		var shape := mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		shape.backface_collision = true
		var body := StaticBody3D.new()
		body.name = "Collider"
		body.collision_layer = LAYER_WORLD
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)

# ── objects ───────────────────────────────────────────────────────────────────────
func spawn(id: String, at: Vector3, yaw := 0.0, vel := Vector3.ZERO, spin := Vector3.ZERO) -> RigidBody3D:
	if not defs.has(id):
		return null
	var d: Dictionary = defs[id]
	var b := RigidBody3D.new()
	b.name = "%s_%d" % [id, objects.size()]
	b.mass = float(d.get("mass", 1.0))
	b.collision_layer = LAYER_OBJECT
	b.collision_mask = LAYER_WORLD | LAYER_PUSHER | LAYER_OBJECT
	var pm := PhysicsMaterial.new()
	pm.bounce = float(d.get("bounce", 0.1))
	pm.friction = float(d.get("friction", 0.7))
	b.physics_material_override = pm
	b.continuous_cd = _min_size(d) < 0.15
	var cs := CollisionShape3D.new()
	cs.shape = _shape(id)
	b.add_child(cs)
	b.add_child(_model(id))
	b.set_meta("pid", objects.size())
	b.set_meta("def", id)
	add_child(b)
	b.global_position = at
	b.rotation = Vector3(0, yaw, 0)
	b.linear_velocity = vel
	b.angular_velocity = spin
	objects.append(b)
	return b

## A preset (crate pyramid, domino run, bowling strike...) laid out in a frame: origin on the ground,
## u = screen right, v = away from the camera.
func spawn_preset(id: String, origin: Vector3, u: Vector3) -> Array:
	if not presets.has(id):
		return []
	u = Vector3(u.x, 0, u.z).normalized()
	var v := Vector3.UP.cross(u)
	var p: Dictionary = presets[id]
	var out: Array = []
	var face := atan2(-v.x, -v.z)   # fronts face the camera
	if p.has("domino_run"):
		var n := int(p["domino_run"])
		for i in n:
			var a := Vector2(-1.3 + i * 0.15, 0.28 * sin(i * 0.33))
			var b := Vector2(-1.3 + (i + 1) * 0.15, 0.28 * sin((i + 1) * 0.33))
			var tan := (u * (b.x - a.x) + v * (b.y - a.y)).normalized()
			var pos := origin + u * a.x + v * a.y + Vector3.UP * 0.101
			var spin := Vector3.UP.cross(tan) * 3.0 if i == 0 else Vector3.ZERO
			out.append(spawn("domino", pos, atan2(tan.x, tan.z), Vector3.ZERO, spin))
		return out
	for it: Array in p.get("items", []):
		var pos := origin + u * float(it[1]) + Vector3.UP * float(it[2]) + v * float(it[3])
		var vel := Vector3.ZERO
		if it.size() > 4:
			var lv: Array = it[4]
			vel = u * float(lv[0]) + Vector3.UP * float(lv[1]) + v * float(lv[2])
		out.append(spawn(String(it[0]), pos, face, vel))
	return out

## Where hand-dropped things go: beside the controlled character, on the camera's right.
## Returns [origin on the ground, u = screen right].
func frame_near(n: Node3D, dist := 1.1) -> Array:
	var cam: Camera3D = main.cam
	var u := cam.global_transform.basis.x
	u = Vector3(u.x, 0, u.z).normalized()
	if u.length() < 0.5:
		u = Vector3.RIGHT
	var base: Vector3 = n.global_position if n != null else Vector3.ZERO
	var o := base + u * dist
	o.y = main.world.ground(o.x, o.z) if main.world else 0.0
	return [o, u]

func clear() -> void:
	for b in objects:
		if is_instance_valid(b):
			remove_child(b)
			(b as Node).queue_free()
	objects.clear()
	recordings.clear()
	_last_key = ""

func _model(id: String) -> Node3D:
	var path := "res://assets/props/physics/%s.glb" % id
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var model := (_scenes[path] as PackedScene).instantiate() as Node3D
	Style.restyle(model, "object")
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mat := mi.get_active_material(0)
		if mi.mesh is ArrayMesh and not Style.is_glow(mat) and not Style.is_clear(mat) and mi.mesh.get_aabb().get_longest_axis_size() > 0.03:
			var rim := Ink.rim(mi.mesh as ArrayMesh)
			Ink.calm(rim, Style.color_of(mat))
			mi.add_child(rim)
	return model

func _shape(id: String) -> Shape3D:
	if _shapes.has(id):
		return _shapes[id]
	var d: Dictionary = defs[id]
	var s: Array = d["size"]
	var shape: Shape3D
	match String(d["shape"]):
		"box":
			var b := BoxShape3D.new()
			b.size = Vector3(float(s[0]), float(s[1]), float(s[2]))
			shape = b
		"sphere":
			var sp := SphereShape3D.new()
			sp.radius = float(s[0])
			shape = sp
		"capsule":
			var c := CapsuleShape3D.new()
			c.radius = float(s[0])
			c.height = float(s[1])
			shape = c
		_:
			var cy := CylinderShape3D.new()
			cy.radius = float(s[0])
			cy.height = float(s[1])
			shape = cy
	_shapes[id] = shape
	return shape

static func _min_size(d: Dictionary) -> float:
	var m := INF
	for v in d["size"]:
		m = minf(m, float(v))
	return m

# ── forces ────────────────────────────────────────────────────────────────────────
## Outward burst from a point: objects within radius fly away (and up by `lift`).
func blast(origin: Vector3, radius: float, force: float, lift := 0.5) -> void:
	for b: RigidBody3D in objects:
		var d := b.global_position - origin
		var flat := Vector3(d.x, 0, d.z)
		var dist := flat.length()
		if dist > radius:
			continue
		var fall := 1.0 - dist / radius
		var dir := flat / dist if dist > 0.01 else Vector3.RIGHT
		b.sleeping = false
		b.apply_central_impulse((dir + Vector3.UP * lift) * force * fall * b.mass)
		b.apply_torque_impulse(Vector3(dir.z, 0, -dir.x) * force * fall * b.mass * 0.04)

## A shove in one direction for everything within radius.
func push(origin: Vector3, dir: Vector3, radius: float, force: float) -> void:
	dir = Vector3(dir.x, 0, dir.z).normalized()
	for b: RigidBody3D in objects:
		var d := b.global_position - origin
		if Vector2(d.x, d.z).length() > radius:
			continue
		b.sleeping = false
		b.apply_central_impulse((dir + Vector3.UP * 0.25) * force * b.mass)

## Continuous pull toward a point (call every step with a dt-scaled strength).
func pull(origin: Vector3, radius: float, strength: float) -> void:
	for b: RigidBody3D in objects:
		var d := origin - b.global_position
		var dist := Vector2(d.x, d.z).length()
		if dist > radius or dist < 0.4:
			continue
		b.sleeping = false
		b.apply_central_impulse(Vector3(d.x, 0.15, d.z).normalized() * strength * b.mass)

## Ground shake: small alternating kicks (deterministic from the object id and time).
func shake(origin: Vector3, radius: float, amount: float, now: float) -> void:
	for b: RigidBody3D in objects:
		var d := b.global_position - origin
		if Vector2(d.x, d.z).length() > radius:
			continue
		var k := float(b.get_meta("pid"))
		b.sleeping = false
		b.apply_central_impulse(Vector3(sin(now * 31.0 + k), 0.6, cos(now * 27.0 + k * 1.7)) * amount * b.mass)

## A kick from a character: the nearest object in reach flies off.
func kick_from(n: Node3D) -> bool:
	if n == null:
		return false
	var best: RigidBody3D = null
	var best_d := 1.3
	for b: RigidBody3D in objects:
		var d := b.global_position.distance_to(n.global_position + Vector3.UP * 0.2)
		if d < best_d:
			best_d = d
			best = b
	if best == null:
		return false
	var dir := best.global_position - n.global_position
	dir = Vector3(dir.x, 0, dir.z).normalized()
	best.sleeping = false
	best.apply_central_impulse((dir + Vector3.UP * 0.45) * 4.5 * best.mass)
	best.apply_torque_impulse(Vector3(dir.z, 0, -dir.x) * best.mass * 0.6)
	return true

# ── per physics step: pushers, gravity, water, cleanup ────────────────────────────
func _physics_process(delta: float) -> void:
	_sync_pushers()
	var g := 9.8 * (0.22 if main.lowgrav else 1.0)
	if not is_equal_approx(g, _gravity):
		_gravity = g
		PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, g)
	var water_y := -INF
	if main.water and main.water.visible:
		water_y = main.water.global_position.y
	for b: RigidBody3D in objects.duplicate():
		var p := b.global_position
		if p.y < KILL_Y:
			if not b.freeze:   # fell off the world: park it out of sight
				b.freeze = true
				b.visible = false
			continue
		if p.y < water_y + 0.3:
			var r := _min_size(defs[String(b.get_meta("def"))]) * 0.5 + 0.05
			var sub := clampf((water_y - (p.y - r)) / (2.0 * r), 0.0, 1.0)
			if sub > 0.0:
				b.apply_central_force(Vector3.UP * b.mass * _gravity * 1.7 * sub)
				b.linear_velocity *= 1.0 - minf(1.0, 1.8 * delta * sub)
				b.angular_velocity *= 1.0 - minf(1.0, 1.2 * delta * sub)

func _sync_pushers() -> void:
	var live := {}
	for n: Node3D in main._actors():
		live[n] = true
		if not _pushers.has(n) or not is_instance_valid(_pushers[n]):
			_pushers[n] = _make_pusher(n)
		var pb: AnimatableBody3D = _pushers[n]
		pb.global_position = n.global_position
		pb.visible = n.is_visible_in_tree()
		pb.process_mode = Node.PROCESS_MODE_INHERIT if pb.visible else Node.PROCESS_MODE_DISABLED
	for n in _pushers.keys():
		if not live.has(n):
			if is_instance_valid(_pushers[n]):
				(_pushers[n] as Node).queue_free()
			_pushers.erase(n)

func _make_pusher(n: Node3D) -> AnimatableBody3D:
	var h: float = main.height_of(n)
	var b := AnimatableBody3D.new()
	b.name = "Pusher"
	b.sync_to_physics = true
	b.collision_layer = LAYER_PUSHER
	b.collision_mask = 0
	var cap := CapsuleShape3D.new()
	cap.radius = clampf(h * 0.3, 0.1, 0.42)
	cap.height = maxf(h, cap.radius * 2.0 + 0.01)
	var cs := CollisionShape3D.new()
	cs.shape = cap
	cs.position = Vector3(0, cap.height * 0.5, 0)
	b.add_child(cs)
	add_child(b)
	b.global_position = n.global_position
	return b

## Physics stops while the Director is paused (and runs otherwise).
func set_paused(on: bool) -> void:
	if on == not _active:
		return
	_active = not on
	PhysicsServer3D.set_active(_active)

# ── determinism: snapshots, recording, replay ─────────────────────────────────────
func state() -> Array:
	var out: Array = []
	for b: RigidBody3D in objects:
		out.append([String(b.get_meta("def")), b.global_transform, b.linear_velocity, b.angular_velocity])
	return out

## Back to a snapshot: objects spawned since are removed, the rest go back to their poses.
func restore(s: Array) -> void:
	while objects.size() > s.size():
		var b: RigidBody3D = objects.pop_back()
		remove_child(b)
		b.queue_free()
	for i in s.size():
		var e: Array = s[i]
		if i >= objects.size():
			spawn(String(e[0]), (e[1] as Transform3D).origin)
		_set_pose(objects[i], e[1], e[2], e[3])

## Live play: sample every object's pose (at most RATE times a second of shot time).
func record(key: String, t: float) -> void:
	if key != _last_key:
		_last_key = key
		_last_sample = -1.0
	if _last_sample >= 0.0 and t > _last_sample and t - _last_sample < 1.0 / RATE - 0.0001:
		return
	_last_sample = t
	if objects.is_empty():
		return
	var rec: Dictionary = recordings.get(key, {})
	for b: RigidBody3D in objects:
		var pid: int = b.get_meta("pid")
		var arr: Array = rec.get(pid, [])
		while arr.size() >= 8 and float(arr[arr.size() - 8]) >= t - 0.0001:
			arr.resize(arr.size() - 8)   # re-recording after a scrub replaces what came after
		var q := b.global_transform.basis.get_rotation_quaternion()
		var p := b.global_position
		arr.append_array([t, p.x, p.y, p.z, q.x, q.y, q.z, q.w])
		rec[pid] = arr
	recordings[key] = rec

func has_recording(key: String) -> bool:
	return not (recordings.get(key, {}) as Dictionary).is_empty()

func forget(key: String) -> void:
	recordings.erase(key)

## Puts every recorded object where the recording has it at shot time t.
func replay(key: String, t: float) -> bool:
	var rec: Dictionary = recordings.get(key, {})
	if rec.is_empty():
		return false
	for b: RigidBody3D in objects:
		var arr: Array = rec.get(int(b.get_meta("pid")), [])
		if arr.size() < 8:
			continue
		var pose := _sample(arr, t)
		_set_pose(b, pose[0], pose[1], pose[2])
	return true

## Pose and velocities at time t, interpolated between recorded samples.
static func _sample(arr: Array, t: float) -> Array:
	var n := arr.size() / 8
	var lo := 0
	var hi := n - 1
	if t <= float(arr[0]):
		hi = 0
	elif t >= float(arr[(n - 1) * 8]):
		lo = n - 1
	else:
		while hi - lo > 1:
			var mid := (lo + hi) / 2
			if float(arr[mid * 8]) <= t:
				lo = mid
			else:
				hi = mid
	var i0 := lo
	var i1 := maxi(hi, lo)
	var t0 := float(arr[i0 * 8])
	var t1 := float(arr[i1 * 8])
	var k := 0.0 if t1 <= t0 else clampf((t - t0) / (t1 - t0), 0.0, 1.0)
	var p0 := Vector3(arr[i0 * 8 + 1], arr[i0 * 8 + 2], arr[i0 * 8 + 3])
	var p1 := Vector3(arr[i1 * 8 + 1], arr[i1 * 8 + 2], arr[i1 * 8 + 3])
	var q0 := Quaternion(arr[i0 * 8 + 4], arr[i0 * 8 + 5], arr[i0 * 8 + 6], arr[i0 * 8 + 7]).normalized()
	var q1 := Quaternion(arr[i1 * 8 + 4], arr[i1 * 8 + 5], arr[i1 * 8 + 6], arr[i1 * 8 + 7]).normalized()
	var xf := Transform3D(Basis(q0.slerp(q1, k)), p0.lerp(p1, k))
	var lv := Vector3.ZERO
	var av := Vector3.ZERO
	if t1 > t0:
		lv = (p1 - p0) / (t1 - t0)
		var dq := q1 * q0.inverse()
		if dq.w < 0.0:
			dq = -dq
		var ang := dq.get_angle()
		if ang > 0.0001:
			av = dq.get_axis() * ang / (t1 - t0)
	return [xf, lv, av]

func _set_pose(b: RigidBody3D, xf: Transform3D, lv: Vector3, av: Vector3) -> void:
	var rid := b.get_rid()
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, lv)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, av)
	b.global_transform = xf
	b.linear_velocity = lv
	b.angular_velocity = av
	b.sleeping = false

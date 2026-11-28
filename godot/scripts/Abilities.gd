class_name Abilities
extends Node

## 100 environmental abilities, five per roster character (res://data/abilities.json).
## A cast captures the caster's position and facing and runs its effects for `duration` seconds.
## Every effect is a pure function of the time since the cast, so a recorded cast replays the same
## way when a shot is scrubbed or retaken. Effects that need something a map lacks (for example
## props on a hand-built map) simply do nothing there, so every ability works on every map.
##
## Effect vocabulary:
##   props   blast · magnet · launch · quake · spin_props · push
##   actors  knockback · pull · levitate · spin_actors · hop_actors · shocked
##   world   flood · lowgrav · slip · fog · dim · flash · glitch · shake
##   fx      particles (burst · fountain · ring · rain · spiral · orbit)

var main: Node
var by_id := {}
var by_char := {}        # character id -> Array of 5 abilities (slot order)
var host_alias := {}
var active: Array = []   # {def, caster, origin, facing, t0}
var _cooldown := {}      # "<node id>:<ability id>" -> msec when ready again (human casts only)
var _pool: Array = []    # spare MultiMeshInstance3D for particles

func _init(m: Node) -> void:
	main = m

func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	host_alias = data.get("host_alias", {})
	for a in data["abilities"]:
		by_id[String(a["id"])] = a
		var c := String(a["character"])
		if not by_char.has(c):
			by_char[c] = []
		by_char[c].append(a)
	for c in by_char:
		(by_char[c] as Array).sort_custom(func(a, b): return int(a["slot"]) < int(b["slot"]))

## The five abilities of a character (host robo / frog borrow robo_bear / chaotic_frog).
func for_actor(n: Node3D) -> Array:
	if n == null:
		return []
	var id: String = main.id_of(n)
	if id == "host":
		id = String(host_alias.get(main.host_kind, ""))
	return by_char.get(id, [])

func cooldown_left(n: Node3D, ability_id: String) -> float:
	var key := "%s:%s" % [n.get_instance_id(), ability_id]
	return maxf(0.0, (float(_cooldown.get(key, 0)) - Time.get_ticks_msec()) / 1000.0)

## Casts an ability. Human casts respect the cooldown; Director casts never wait.
func cast(n: Node3D, ability_id: String, human := false) -> bool:
	if n == null or not by_id.has(ability_id):
		return false
	var def: Dictionary = by_id[ability_id]
	if human:
		if cooldown_left(n, ability_id) > 0.0:
			return false
		_cooldown["%s:%s" % [n.get_instance_id(), ability_id]] = Time.get_ticks_msec() + int(float(def["cooldown"]) * 1000.0)
	var yaw: float = main.motion[n]["yaw"] if main._has(n) else n.rotation.y
	_start(def, n, n.global_position, Vector3(sin(yaw), 0, cos(yaw)), main.t)
	main.act(n, String(def.get("emote", "")))
	main.act(n, "expr_%d" % (main.EXPRS.find(String(def.get("expr", "DEADPAN"))) + 1))
	return true

func _start(def: Dictionary, caster: Node3D, origin: Vector3, facing: Vector3, t0: float) -> void:
	var a := {"def": def, "caster": caster, "origin": origin, "facing": facing, "t0": t0, "fx": null, "started": false}
	active.append(a)

## State for shot snapshots: each running cast with its elapsed time.
func state(now: float) -> Array:
	var out: Array = []
	for a in active:
		out.append({"id": a["def"]["id"], "caster": main.id_of(a["caster"]) if is_instance_valid(a["caster"]) else "",
			"origin": a["origin"], "facing": a["facing"], "elapsed": now - float(a["t0"])})
	return out

func restore(s: Array, now: float) -> void:
	clear()
	for c in s:
		if by_id.has(String(c["id"])):
			_start(by_id[String(c["id"])], main.find_actor(String(c["caster"])), c["origin"], c["facing"], now - float(c["elapsed"]))
			active[-1]["started"] = true

## Keeps every cast's elapsed time when the studio clock resets at a shot cut.
func shift_time(delta: float) -> void:
	for a in active:
		a["t0"] = float(a["t0"]) + delta

func clear() -> void:
	for a in active:
		_release_fx(a)
	active.clear()

# ── per step ──────────────────────────────────────────────────────────────────────
func tick(now: float, dt: float) -> void:
	var keep: Array = []
	for a in active:
		var e := now - float(a["t0"])
		var dur := float(a["def"]["duration"])
		if e > dur:
			_release_fx(a)
			continue
		if e < 0.0:
			keep.append(a)
			continue
		if not a["started"]:
			a["started"] = true
			_one_shots(a)
		var env := smoothstep(0.0, 0.2, e) * (1.0 - smoothstep(dur - 0.4, dur, e))
		for fx in a["def"]["fx"]:
			_apply(a, fx, e, dur, env, dt)
		keep.append(a)
	active = keep

## Effects that happen once at the start of a cast.
func _one_shots(a: Dictionary) -> void:
	for fx in a["def"]["fx"]:
		match String(fx["type"]):
			"hop_actors":
				for n in _actors_near(a, float(fx.get("radius", 4.0)), true):
					main.act(n, "hop")
			"shocked":
				for n in _actors_near(a, float(fx.get("radius", 4.0)), false):
					main.act(n, "expr_6")
			# physics objects get real impulses (StudioPhysics)
			"blast":
				main.physics.blast(a["origin"], float(fx.get("radius", 3.0)), float(fx.get("force", 1.6)) * 3.2, 0.55)
			"knockback":
				main.physics.blast(a["origin"], float(fx.get("radius", 3.0)), float(fx.get("force", 1.8)) * 2.4, 0.35)
			"launch":
				main.physics.blast(a["origin"], float(fx.get("radius", 3.0)), 1.2, float(fx.get("height", 1.2)) * 3.5)
			"push":
				main.physics.push(a["origin"], a["facing"], float(fx.get("radius", 3.0)), float(fx.get("strength", 1.8)) * 2.2)

func _props() -> Array:
	var w = main.world
	if not (w is GlbMap):
		return []
	var out: Array = []
	for g in (w as GlbMap).props:
		out.append_array((w as GlbMap).props[g])
	return out

func _actors_near(a: Dictionary, r: float, include_caster: bool) -> Array:
	var out: Array = []
	var o: Vector3 = a["origin"]
	for n in main._actors():
		if not include_caster and n == a["caster"]:
			continue
		var p: Vector3 = main.motion[n]["pos"]
		if Vector2(p.x - o.x, p.z - o.z).length() <= r:
			out.append(n)
	return out

static func _h(n: Object, salt: float) -> float:
	var x := sin(float(n.get_instance_id() % 10007) * 12.9898 + salt * 78.233) * 43758.5453
	return x - floor(x)

func _apply(a: Dictionary, fx: Dictionary, e: float, dur: float, env: float, dt: float) -> void:
	var o: Vector3 = a["origin"]
	var r := float(fx.get("radius", 3.0))
	var type := String(fx["type"])
	match type:
		# ── props ──
		"blast", "magnet", "launch", "quake", "spin_props", "push":
			if type == "magnet":
				main.physics.pull(o, r, 5.0 * dt * env)
			elif type == "quake":
				main.physics.shake(o, r, float(fx.get("amp", 0.25)) * 6.0 * dt * env, e)
			for n in _props():
				var p: Vector3 = (n as Node3D).global_position
				var flat := Vector3(p.x - o.x, 0, p.z - o.z)
				var d := flat.length()
				if d > r:
					continue
				var fall := 1.0 - d / r
				var dir := flat / d if d > 0.01 else Vector3(1, 0, 0)
				var off := Vector3.ZERO
				var spin := 0.0
				match type:
					"blast":
						var u := clampf(e / 0.8, 0.0, 1.0)
						off = dir * float(fx.get("force", 1.6)) * fall * (1.0 - pow(1.0 - u, 2.0)) + Vector3(0, float(fx.get("height", 0.8)) * 4.0 * u * (1.0 - u) * fall, 0)
						spin = u * 6.0 * fall
					"magnet":
						off = -dir * maxf(0.0, d - 0.45) * env + Vector3(0, sin(e * 20.0 + d) * 0.03 * env, 0)
					"launch":
						off = Vector3(0, float(fx.get("height", 1.2)) * fall * env + sin(e * 3.0 + d) * 0.08 * env, 0)
						spin = e * 2.0 * env
					"quake":
						(n as Node3D).rotate_z(sin(e * 25.0 + d * 3.0) * float(fx.get("amp", 0.25)) * env * fall)
					"spin_props":
						spin = e * float(fx.get("speed", 9.0)) * env
					"push":
						off = (a["facing"] as Vector3) * float(fx.get("strength", 1.8)) * fall * env
				(n as Node3D).global_position = p + off * env if type == "blast" else p + off
				if spin != 0.0:
					(n as Node3D).rotate_y(spin)
		# ── actors ──
		"knockback", "pull":
			for n in _actors_near(a, r, false):
				var m: Dictionary = main.motion[n]
				var p: Vector3 = m["pos"]
				var flat := Vector3(p.x - o.x, 0, p.z - o.z)
				var d := flat.length()
				var dir := flat / d if d > 0.01 else Vector3(1, 0, 0)
				var speed := 0.0
				if type == "knockback":
					speed = float(fx.get("force", 1.8)) * 3.0 * maxf(0.0, 1.0 - e / 0.5)
				elif d > 0.7:
					speed = -2.2 * env
				var b: Rect2 = main._bounds()
				p += dir * speed * dt
				p.x = clampf(p.x, b.position.x + 0.3, b.end.x - 0.3)
				p.z = clampf(p.z, b.position.y + 0.3, b.end.y - 0.3)
				m["pos"] = p
		"levitate":
			for n in _actors_near(a, r, true):
				(n as Node3D).position.y += float(fx.get("height", 0.5)) * env + sin(e * 2.5) * 0.04 * env
		"spin_actors":
			for n in _actors_near(a, r, false):
				(n as Node3D).rotation.y += e * 14.0 * env
		# ── world ──
		"flood":
			if float(fx.get("level", 0.3)) * env > main.ability_flood:
				main.ability_flood = float(fx.get("level", 0.3)) * env
				main.ability_liquid = Style.snap(Color(String(fx.get("color", "#9CC3EF"))))
		"lowgrav":
			if env > 0.4:
				main.lowgrav = true
		"slip":
			if env > 0.4:
				main.slippery = true
		"fog":
			main.art.add_fog(Style.snap(Color(String(fx.get("color", "#F5F2EB")))), float(fx.get("density", 0.1)) * env)
		"dim":
			main.light_scale = minf(main.light_scale, lerpf(1.0, float(fx.get("amount", 0.2)), env))
		"flash":
			var every := float(fx.get("every", 1.2))
			var ph := fposmod(e, every)
			var f := 1.0 - ph / 0.12 if ph < 0.12 else (0.7 * (1.0 - (ph - 0.22) / 0.12) if ph > 0.22 and ph < 0.34 else 0.0)
			main.flash = maxf(main.flash, f * float(fx.get("strength", 1.0)) * env)
		"glitch":
			var w = main.world
			var cols: Array = fx.get("colors", ["#FF5F56", "#27C93F", "#4A90E2"])
			if w is GlbMap and not (w as GlbMap)._glows.is_empty():
				var frame := int(floor(e * 10.0))
				var glows: Array = (w as GlbMap)._glows
				for i in glows.size():
					(glows[i] as MeshInstance3D).set_surface_override_material(0, Style.glow(Color(String(cols[(frame + i) % cols.size()]))))
				(w as GlbMap)._glow_dirty = true
			else:
				main.flash = maxf(main.flash, 0.35 * env * (1.0 if fposmod(e, 0.3) < 0.08 else 0.0))
		"shake":
			main.chaos_shake = maxf(main.chaos_shake, float(fx.get("amount", 0.5)) * env)
		"particles":
			_particles(a, fx, e, dur)

# ── particles ─────────────────────────────────────────────────────────────────────
func _release_fx(a: Dictionary) -> void:
	var inst = a.get("fx")
	if inst and is_instance_valid(inst):
		(inst as Node3D).visible = false
		_pool.append(inst)
	a["fx"] = null

func _particles(a: Dictionary, fx: Dictionary, e: float, dur: float) -> void:
	var count := int(fx.get("count", 24))
	var inst: MultiMeshInstance3D = a.get("fx")
	if inst == null:
		inst = _pool.pop_back() if not _pool.is_empty() else null
		if inst == null:
			var mesh := SphereMesh.new()
			mesh.radial_segments = 16
			mesh.rings = 8
			inst = MultiMeshInstance3D.new()
			inst.multimesh = MultiMesh.new()
			inst.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			inst.multimesh.use_colors = true
			inst.multimesh.mesh = mesh
			inst.material_override = Style.toon(Color.WHITE, true)
			add_child(inst)
		inst.multimesh.instance_count = count
		var cols: Array = fx.get("colors", ["#F5F2EB"])
		for i in count:
			inst.multimesh.set_instance_color(i, Style.snap(Color(String(cols[i % cols.size()]))))
		inst.visible = true
		a["fx"] = inst
	var o: Vector3 = a["origin"] + Vector3(0, 0.4, 0)
	var r := float(fx.get("radius", 2.0))
	var h := float(fx.get("height", 1.5))
	var size := float(fx.get("size", 0.06))
	var u := clampf(e / dur, 0.0, 1.0)
	var fade := 1.0 - smoothstep(0.8, 1.0, u)
	for i in count:
		var ph := float(i) / count
		var a1 := ph * TAU * 3.0 + ph * 1.7
		var dir := Vector3(cos(a1), 0, sin(a1))
		var p: Vector3
		match String(fx.get("kind", "burst")):
			"burst":
				var k := 1.0 - pow(1.0 - clampf(e / 0.9, 0.0, 1.0), 3.0)
				p = o + dir * r * k * (0.5 + 0.5 * fposmod(ph * 7.1, 1.0)) + Vector3(0, h * sin(k * PI) * (0.4 + 0.6 * fposmod(ph * 3.3, 1.0)), 0)
			"fountain":
				var cyc := fposmod(e * 0.9 + ph, 1.0)
				p = o + dir * cyc * r + Vector3(0, 4.0 * cyc * (1.0 - cyc) * h, 0)
			"ring":
				p = Vector3(o.x, a["origin"].y + h * 0.5, o.z) + Vector3(cos(ph * TAU), 0, sin(ph * TAU)) * r * clampf(e / 1.2, 0.0, 1.0)
			"rain":
				var fall := fposmod(e * 2.2 + ph * 5.3, 1.0)
				p = Vector3(o.x, a["origin"].y, o.z) + dir * r * fposmod(ph * 13.7, 1.0) + Vector3(0, h * (1.0 - fall), 0)
			"spiral":
				var cyc := fposmod(e * 0.5 + ph, 1.0)
				var ang := e * 5.0 + ph * TAU * 2.0
				p = Vector3(o.x, a["origin"].y, o.z) + Vector3(cos(ang), 0, sin(ang)) * (0.2 + cyc * r) + Vector3(0, cyc * h, 0)
			_: # orbit
				var ang := e * 3.0 + ph * TAU
				p = o + Vector3(cos(ang), 0, sin(ang)) * r + Vector3(0, h * 0.4 + sin(e * 4.0 + i) * 0.15, 0)
		inst.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size * 2.0 * fade), p))

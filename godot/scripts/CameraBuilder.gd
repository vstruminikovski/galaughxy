class_name CameraBuilder
extends Node3D

## Free-View waypoint camera builder.
##   static (1 pin: Point A)        locked tripod
##   slider (2 pins: A -> B)        eased linear dolly
##   drone  (5+ pins: A -> B -> ...) Catmull-Rom spline through every pin, position and rotation
## Aiming happens in free fly: frame the view, Drop Pin, repeat, Finish Path. The path is written
## into the active shot (cam = "custom_path", cam_type, waypoints [{pos, rot, fov}], duration) and
## plays back deterministically through DirectorController. Translucent pins and the curve are drawn
## in the viewport while aiming or editing, and hidden during playback and recording.

const NEEDS := {"static": 1, "slider": 2, "drone": 5}
const PIN_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

signal changed

var main: Node
var aiming := false
var kind := "drone"
var pins: Array = []          # [{pos, rot, fov}]
var duration := 6.0
var previewing := false
var preview_t := 0.0
var _preview_path: Dictionary = {}
var _line: MeshInstance3D
var _pin_nodes: Array = []
var _shown_path: Dictionary = {}

func _init(m: Node) -> void:
	main = m

func _ready() -> void:
	_line = MeshInstance3D.new()
	_line.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(Style.swatch("amber").r, Style.swatch("amber").g, Style.swatch("amber").b, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	_line.material_override = mat
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)

# ── path maths (static, used by the director too) ─────────────────────────────────
static func pin_quat(w: Dictionary) -> Quaternion:
	var r: Array = w["rot"]
	return Basis.from_euler(Vector3(deg_to_rad(float(r[0])), deg_to_rad(float(r[1])), deg_to_rad(float(r[2])))).get_rotation_quaternion()

static func pin_pos(w: Dictionary) -> Vector3:
	var p: Array = w["pos"]
	return Vector3(float(p[0]), float(p[1]), float(p[2]))

static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

## Pose along a path at progress u (0..1): [position, look target, fov].
static func evaluate(path: Dictionary, u: float) -> Array:
	var wps: Array = path.get("waypoints", [])
	if wps.is_empty():
		return []
	var type := String(path.get("cam_type", "static"))
	u = clampf(u, 0.0, 1.0)
	var pos: Vector3
	var q: Quaternion
	var fov: float
	if type == "static" or wps.size() == 1:
		pos = pin_pos(wps[0])
		q = pin_quat(wps[0])
		fov = float(wps[0].get("fov", 40.0))
	elif type == "slider" or wps.size() == 2:
		var k := smoothstep(0.0, 1.0, u)
		pos = pin_pos(wps[0]).lerp(pin_pos(wps[1]), k)
		q = pin_quat(wps[0]).slerp(pin_quat(wps[1]), k)
		fov = lerpf(float(wps[0].get("fov", 40.0)), float(wps[1].get("fov", 40.0)), k)
	else:
		# even speed: map u to the curve by arc length, with a gentle ease at both ends
		var k := 0.5 - 0.5 * cos(u * PI)
		var seg_f := _arc_param(wps, k)
		var n := wps.size()
		var i := clampi(int(floor(seg_f)), 0, n - 2)
		var f := seg_f - i
		var p0 := pin_pos(wps[maxi(i - 1, 0)])
		var p1 := pin_pos(wps[i])
		var p2 := pin_pos(wps[i + 1])
		var p3 := pin_pos(wps[mini(i + 2, n - 1)])
		pos = _cr(p0, p1, p2, p3, f)
		var q0 := pin_quat(wps[maxi(i - 1, 0)])
		var q1 := pin_quat(wps[i])
		var q2 := pin_quat(wps[i + 1])
		var q3 := pin_quat(wps[mini(i + 2, n - 1)])
		q = q1.spherical_cubic_interpolate(q2, q0, q3, f)
		var f0 := float(wps[maxi(i - 1, 0)].get("fov", 40.0))
		var f1 := float(wps[i].get("fov", 40.0))
		var f2 := float(wps[i + 1].get("fov", 40.0))
		var f3 := float(wps[mini(i + 2, n - 1)].get("fov", 40.0))
		fov = _cr(Vector3(f0, 0, 0), Vector3(f1, 0, 0), Vector3(f2, 0, 0), Vector3(f3, 0, 0), f).x
	var fwd := -(Basis(q) * Vector3.FORWARD) * -1.0
	return [pos, pos + fwd * 4.0, fov]

## Segment parameter (i + f) for arc-length fraction k along the Catmull-Rom curve.
static func _arc_param(wps: Array, k: float) -> float:
	var n := wps.size()
	var samples: Array = [0.0]
	var params: Array = [0.0]
	var prev := pin_pos(wps[0])
	var total := 0.0
	for i in n - 1:
		var p0 := pin_pos(wps[maxi(i - 1, 0)])
		var p1 := pin_pos(wps[i])
		var p2 := pin_pos(wps[i + 1])
		var p3 := pin_pos(wps[mini(i + 2, n - 1)])
		for s in range(1, 17):
			var f := s / 16.0
			var p := _cr(p0, p1, p2, p3, f)
			total += p.distance_to(prev)
			prev = p
			samples.append(total)
			params.append(i + f)
	if total <= 0.0:
		return k * (n - 1)
	var target := k * total
	for j in range(1, samples.size()):
		if samples[j] >= target:
			var a: float = samples[j - 1]
			var b: float = samples[j]
			var t := (target - a) / maxf(b - a, 1e-6)
			return lerpf(params[j - 1], params[j], t)
	return float(n - 1)

static func path_of(shot: Dictionary) -> Dictionary:
	return {"cam_type": shot.get("cam_type", "static"), "waypoints": shot.get("waypoints", []), "duration": shot.get("duration", 6.0)}

# ── aiming ────────────────────────────────────────────────────────────────────────
func begin(type: String) -> void:
	kind = type
	pins.clear()
	aiming = true
	previewing = false
	if main.rig != "free":
		main._set_rig("free")
	_redraw()
	changed.emit()

func cancel() -> void:
	aiming = false
	previewing = false
	pins.clear()
	_redraw()
	if main.rig == "free":
		main._set_rig("static")
	changed.emit()

func drop_pin() -> void:
	if not aiming:
		return
	var c: Camera3D = main.cam
	var r := c.global_rotation_degrees
	pins.append({"pos": [snappedf(c.global_position.x, 0.001), snappedf(c.global_position.y, 0.001), snappedf(c.global_position.z, 0.001)],
		"rot": [snappedf(r.x, 0.01), snappedf(r.y, 0.01), snappedf(r.z, 0.01)], "fov": snappedf(c.fov, 0.1)})
	_redraw()
	changed.emit()
	# static and slider finish themselves once they have their pins
	if kind != "drone" and pins.size() >= NEEDS[kind]:
		finish()

func undo_pin() -> void:
	if aiming and not pins.is_empty():
		pins.pop_back()
		_redraw()
		changed.emit()

func can_finish() -> bool:
	return aiming and pins.size() >= NEEDS[kind]

func current_path() -> Dictionary:
	return {"cam_type": kind, "waypoints": pins.duplicate(true), "duration": duration}

## Writes the path into the active shot and leaves aiming mode.
func finish() -> bool:
	if not can_finish():
		return false
	var shot: Dictionary = main.director.active_shot()
	if shot.is_empty():
		return false
	shot["cam"] = "custom_path"
	shot["cam_type"] = kind
	shot["waypoints"] = pins.duplicate(true)
	shot["duration"] = snappedf(duration, 0.1)
	main.director.dirty = true
	aiming = false
	previewing = false
	pins.clear()
	if main.rig == "free":
		main._set_rig("static")
	show_path(shot)
	changed.emit()
	main.director.changed.emit()
	return true

## Plays the pins on the camera for `duration` seconds (camera only).
func preview() -> void:
	var p := current_path() if aiming and pins.size() >= 1 else _shown_path
	if p.get("waypoints", []).is_empty():
		return
	_preview_path = p
	previewing = true
	preview_t = 0.0

func update_preview(cam: Camera3D, dt: float) -> bool:
	if not previewing:
		return false
	preview_t += dt
	var d := maxf(0.1, float(_preview_path.get("duration", duration)))
	var pose := evaluate(_preview_path, preview_t / d)
	if pose.is_empty() or preview_t > d:
		previewing = false
		return false
	cam.position = pose[0]
	cam.look_at(pose[1], Vector3.UP)
	cam.fov = pose[2]
	return true

# ── 3D preview: pins and curve ────────────────────────────────────────────────────
func show_path(shot: Dictionary) -> void:
	_shown_path = path_of(shot) if shot.has("waypoints") else {}
	_redraw()

func _visible_path() -> Dictionary:
	if aiming:
		return current_path()
	return _shown_path

func _process(_dt: float) -> void:
	# never in the shot: hidden while the director plays or records
	visible = (aiming or main.hud.camera_open()) and not (main.director.playing and not main.director.paused)

func _redraw() -> void:
	for p in _pin_nodes:
		p.queue_free()
	_pin_nodes.clear()
	var im := _line.mesh as ImmediateMesh
	im.clear_surfaces()
	var path := _visible_path()
	var wps: Array = path.get("waypoints", [])
	for i in wps.size():
		var pin := Node3D.new()
		pin.position = pin_pos(wps[i])
		var ball := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.09
		s.height = 0.18
		ball.mesh = s
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var c := Style.swatch("coral")
		mat.albedo_color = Color(c.r, c.g, c.b, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		ball.material_override = mat
		pin.add_child(ball)
		# a short stick showing where the pin looks
		var look := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.012
		cyl.bottom_radius = 0.012
		cyl.height = 0.4
		look.mesh = cyl
		look.material_override = mat
		var fwd := Basis(pin_quat(wps[i])) * Vector3.FORWARD
		look.position = fwd * 0.25
		look.basis = Basis(Quaternion(Vector3.UP, fwd.normalized()))
		pin.add_child(look)
		var label := Label3D.new()
		label.text = PIN_LETTERS[i % PIN_LETTERS.length()]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3(0, 0.2, 0)
		label.font_size = 48
		label.pixel_size = 0.004
		label.modulate = Style.swatch("cream")
		label.outline_size = 8
		pin.add_child(label)
		add_child(pin)
		_pin_nodes.append(pin)
	if wps.size() >= 2:
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		var steps := 24 * (wps.size() - 1)
		for k in steps + 1:
			var pose := evaluate(path, float(k) / steps)
			im.surface_add_vertex(pose[0])
		im.surface_end()

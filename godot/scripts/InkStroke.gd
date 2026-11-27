class_name InkStroke
extends MeshInstance3D

## Grease-pencil strokes traced from a mesh's outline.
##
## 1. Contour: each vertex gets g = dot(normal, camera - vertex). The outline is where g = 0.
##    Every triangle whose corners disagree in sign holds exactly one piece of that curve, found by
##    interpolating along its two crossing edges, so the curve is smooth and never branches.
## 2. Strokes: pieces that share a triangle edge are joined into continuous lines, so one line is
##    one stroke and strokes never run over each other.
## 3. Shape: each stroke is smoothed (Chaikin) and drawn as a ribbon with constant screen width.
##    It tapers toward both ends and finishes with a round, blunt cap (see ink_stroke.gdshader).
##
## Strokes are rebuilt at most 12 times a second (on twos), and only when the camera has moved
## relative to the object. Parts hidden inside other parts are removed by the depth test.

const REDRAW_FPS := 12.0
const CAP_STEPS := 8
const MIN_POINTS := 3

static var build_ms := 0.0
static var builds := 0

var _pts := PackedVector3Array()
var _nrm := PackedVector3Array()
var _tris := PackedInt32Array()
var _size := 1.0
var _last_cam := Vector3(INF, INF, INF)
var _clock := 0.0
var _built := false
var _array_mesh := ArrayMesh.new()

func setup(src: ArrayMesh) -> void:
	var slot := {}
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := idx.size() if idx.size() > 0 else verts.size()
		for i in count:
			var v := idx[i] if idx.size() > 0 else i
			var p := verts[v]
			var k := Vector3i(roundi(p.x * 1e4), roundi(p.y * 1e4), roundi(p.z * 1e4))
			if not slot.has(k):
				slot[k] = _pts.size()
				_pts.append(p)
				_nrm.append(Vector3.ZERO)
			var u: int = slot[k]
			_nrm[u] += nrm[v]
			_tris.append(u)
	for i in _nrm.size():
		_nrm[i] = _nrm[i].normalized()
	_size = src.get_aabb().get_longest_axis_size()
	mesh = _array_mesh
	extra_cull_margin = 0.1
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_clock = randf() / REDRAW_FPS # stagger rebuilds across objects

func _process(dt: float) -> void:
	_clock += dt
	if _built and _clock < 1.0 / REDRAW_FPS:
		return
	_clock = fmod(_clock, 1.0 / REDRAW_FPS)
	if not is_visible_in_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := global_transform.affine_inverse() * cam.global_position
	if _built and c.distance_to(_last_cam) < 0.0005 * maxf(c.length(), _size):
		return
	_last_cam = c
	var t0 := Time.get_ticks_usec()
	_rebuild(c)
	build_ms += (Time.get_ticks_usec() - t0) / 1000.0
	builds += 1
	_built = true

func _rebuild(c: Vector3) -> void:
	var n := _pts.size()
	var g := PackedFloat32Array()
	g.resize(n)
	for i in n:
		var d := _nrm[i].dot(c - _pts[i])
		g[i] = d if d != 0.0 else 1e-9
	# contour pieces: one per triangle that straddles g = 0, keyed by the edges it crosses
	var adj := {}
	var pos := {}
	var t := 0
	while t < _tris.size():
		var a := _tris[t]
		var b := _tris[t + 1]
		var d := _tris[t + 2]
		t += 3
		var sa := g[a] > 0.0
		var sb := g[b] > 0.0
		var sd := g[d] > 0.0
		if sa == sb and sb == sd:
			continue
		var keys := []
		for e in [[a, b, sa != sb], [b, d, sb != sd], [d, a, sd != sa]]:
			if not e[2]:
				continue
			var i: int = e[0]
			var j: int = e[1]
			var k := mini(i, j) * n + maxi(i, j)
			if not pos.has(k):
				var f := g[i] / (g[i] - g[j])
				pos[k] = _pts[i].lerp(_pts[j], f)
			keys.append(k)
		if keys.size() != 2 or keys[0] == keys[1]:
			continue
		_link(adj, keys[0], keys[1])
		_link(adj, keys[1], keys[0])
	# join pieces into strokes: open lines first, then closed loops
	var used := {}
	var lines := []
	for k in adj:
		if (adj[k] as Array).size() == 1 and not used.has(k):
			lines.append(_walk(k, adj, pos, used))
	for k in adj:
		if not used.has(k):
			lines.append(_walk(k, adj, pos, used))
	_emit(lines)

static func _link(adj: Dictionary, a: int, b: int) -> void:
	if adj.has(a):
		adj[a].append(b)
	else:
		adj[a] = [b]

static func _walk(start: int, adj: Dictionary, pos: Dictionary, used: Dictionary) -> PackedVector3Array:
	var line := PackedVector3Array()
	var prev := -1
	var cur := start
	while true:
		used[cur] = true
		line.append(pos[cur])
		var nxt := -1
		for nb in adj[cur]:
			if nb != prev and not used.has(nb):
				nxt = nb
				break
		if nxt == -1:
			if line.size() > 2 and (adj[cur] as Array).has(start):
				line.append(pos[start]) # close the loop: both tapered ends meet here
			break
		prev = cur
		cur = nxt
	return line

static func _chaikin(p: PackedVector3Array, iterations: int) -> PackedVector3Array:
	for it in iterations:
		if p.size() < 3:
			break
		var q := PackedVector3Array()
		q.append(p[0])
		for i in p.size() - 1:
			q.append(p[i] * 0.75 + p[i + 1] * 0.25)
			q.append(p[i] * 0.25 + p[i + 1] * 0.75)
		q.append(p[p.size() - 1])
		p = q
	return p

## Ribbon per stroke. VERTEX = point on the line, NORMAL = line direction, UV = offset in the
## stroke's own frame (x along, y across, unit radius), UV2.x = width share for the taper.
func _emit(lines: Array) -> void:
	var v := PackedVector3Array()
	var tn := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var ix := PackedInt32Array()
	for raw in lines:
		var line: PackedVector3Array = raw
		if line.size() < MIN_POINTS:
			continue
		var p := _chaikin(line, 2)
		var m := p.size()
		var arc := PackedFloat32Array()
		arc.resize(m)
		for i in range(1, m):
			arc[i] = arc[i - 1] + p[i].distance_to(p[i - 1])
		var total := arc[m - 1]
		if total <= 0.0:
			continue
		var taper_len := minf(0.3 * total, 0.15 * _size)
		var base := v.size()
		for i in m:
			var dir := p[mini(i + 1, m - 1)] - p[maxi(i - 1, 0)]
			dir = dir.normalized() if dir.length_squared() > 0.0 else Vector3.UP
			var e := clampf(minf(arc[i], total - arc[i]) / maxf(taper_len, 1e-6), 0.0, 1.0)
			var w := 0.3 + 0.7 * sin(e * PI * 0.5)
			for side in [1.0, -1.0]:
				v.append(p[i])
				tn.append(dir)
				uv.append(Vector2(0.0, side))
				uv2.append(Vector2(w, 0.0))
		for i in m - 1:
			var a := base + i * 2
			ix.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
		# round caps: half discs pointing backwards at the start and forwards at the end
		for end in [0, m - 1]:
			var at := p[end]
			var dir := p[mini(end + 1, m - 1)] - p[maxi(end - 1, 0)]
			dir = dir.normalized() if dir.length_squared() > 0.0 else Vector3.UP
			var w0: float = uv2[base + end * 2].x
			var centre := v.size()
			v.append(at)
			tn.append(dir)
			uv.append(Vector2.ZERO)
			uv2.append(Vector2(w0, 0.0))
			var start_a := PI * 0.5 if end == 0 else -PI * 0.5
			for s in CAP_STEPS + 1:
				var ang := start_a + PI * float(s) / CAP_STEPS
				v.append(at)
				tn.append(dir)
				uv.append(Vector2(cos(ang), sin(ang)))
				uv2.append(Vector2(w0, 0.0))
			for s in CAP_STEPS:
				ix.append_array([centre, centre + 1 + s, centre + 2 + s])
	_array_mesh.clear_surfaces()
	if v.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = tn
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = ix
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

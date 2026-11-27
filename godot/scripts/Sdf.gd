class_name Sdf
extends RefCounted

## Signed-distance helpers. A shape is a Callable(Vector3) -> float; f < 0 means inside.
## Voxelize samples integer cells, so every organic shape becomes square voxels.

static func ellipsoid(c: Vector3, r: Vector3) -> Callable:
	return func(p: Vector3) -> float:
		var q := (p - c) / r
		var k0 := q.length()
		var q2 := (p - c) / (r * r)
		var k1 := q2.length()
		return -1.0 if k1 == 0.0 else k0 * (k0 - 1.0) / k1

static func sphere(c: Vector3, r: float) -> Callable:
	return func(p: Vector3) -> float: return (p - c).length() - r

static func capsule(a: Vector3, b: Vector3, r: float) -> Callable:
	return func(p: Vector3) -> float:
		var pa := p - a
		var ba := b - a
		var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
		return (pa - ba * h).length() - r

static func box(c: Vector3, half: Vector3) -> Callable:
	return func(p: Vector3) -> float:
		var q := (p - c).abs() - half
		var outside := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()
		return outside + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)

static func smin(a: Callable, b: Callable, k: float) -> Callable:
	return func(p: Vector3) -> float:
		var d1: float = a.call(p)
		var d2: float = b.call(p)
		var h := maxf(k - absf(d1 - d2), 0.0) / k
		return minf(d1, d2) - h * h * k * 0.25

static func union(fs: Array) -> Callable:
	return func(p: Vector3) -> float:
		var d := INF
		for f: Callable in fs:
			d = minf(d, f.call(p))
		return d

static func minus(a: Callable, b: Callable) -> Callable:
	return func(p: Vector3) -> float:
		return maxf(a.call(p), -b.call(p))

## Sample every integer cell in [lo, hi] (inclusive). paint(cell) -> {"c": Color, "e": bool} or null.
static func voxelize(f: Callable, lo: Vector3i, hi: Vector3i, paint: Callable) -> Dictionary:
	var out := {}
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var c := Vector3i(x, y, z)
				if f.call(Vector3(x, y, z)) > 0.0:
					continue
				var v = paint.call(c)
				if v != null:
					out[c] = v
	return out

static func hash3(x: float, y: float, z: float) -> float:
	var n := sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453
	return n - floor(n)

## Rounded box: a box of half-size `half` with corners rounded by `r`.
static func rbox(c: Vector3, half: Vector3, r: float) -> Callable:
	return func(p: Vector3) -> float:
		var q := (p - c).abs() - half + Vector3(r, r, r)
		var outside := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()
		return outside + minf(maxf(q.x, maxf(q.y, q.z)), 0.0) - r

## Cylinder along Y (flat caps, rounded rim).
static func cyl(c: Vector3, radius: float, half_h: float) -> Callable:
	return func(p: Vector3) -> float:
		var q := p - c
		var d := Vector2(Vector2(q.x, q.z).length() - radius, absf(q.y) - half_h)
		return minf(maxf(d.x, d.y), 0.0) + Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()

## Torus lying flat (ring around the Y axis): major radius R, tube radius r.
static func torus(c: Vector3, major: float, minor: float) -> Callable:
	return func(p: Vector3) -> float:
		var q := p - c
		return Vector2(Vector2(q.x, q.z).length() - major, q.y).length() - minor

## Smooth intersection (rounded where the two shapes meet).
static func smax(a: Callable, b: Callable, k: float) -> Callable:
	return func(p: Vector3) -> float:
		var da: float = a.call(p)
		var db: float = b.call(p)
		var h := clampf(0.5 - 0.5 * (db - da) / k, 0.0, 1.0)
		return lerpf(db, da, h) + k * h * (1.0 - h)

## Half-space below a plane through `at` with normal `n` (inside where dot(p - at, n) < 0).
static func plane(at: Vector3, n: Vector3) -> Callable:
	var nn := n.normalized()
	return func(p: Vector3) -> float: return (p - at).dot(nn)

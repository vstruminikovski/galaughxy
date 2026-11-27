class_name PondWorld
extends RefCounted

## Pond Life: terrain from a height field, then rocks, trees, reeds, lily pads and mushrooms,
## all as 0.1 m square voxels. Ported from scenes/pond-life/world.ts (same constants).

const V := 0.1
const WATER_TOP_CELL := -1
const WATER := Color("#2f6f8a")
const WATER_DEEP := Color("#22566b")
const GRASS := [Color("#3f5f22"), Color("#6b8834"), Color("#8f9145"), Color("#2f4a1c")]
const DIRT := Color("#6a5236")
const MUD := [Color("#4d3d27"), Color("#2e2618")]
const ROCK := [Color("#80796c"), Color("#4d4942"), Color("#6d6a60")]
const LICHEN := Color("#b3ad72")
const BARK := [Color("#5b4431"), Color("#2d2118")]
const LEAF := [Color("#3e6b23"), Color("#7a9a3a"), Color("#1d3312")]
const PAD := [Color("#3c6e2a"), Color("#7aa344")]
const PINK := Color("#f7c6d6")
const REED := Color("#9b9a55")
const CATTAIL := Color("#5a3a1e")
const MUSH_CAP := Color("#b8452a")
const MUSH_STEM := Color("#efe3c8")

var voxels := {}
var solid_top := {}

static func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func _vnoise(x: float, y: float) -> float:
	var xi := floorf(x)
	var yi := floorf(y)
	var xf := x - xi
	var yf := y - yi
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := yf * yf * (3.0 - 2.0 * yf)
	var a := Sdf.hash3(xi, yi, 17)
	var b := Sdf.hash3(xi + 1, yi, 17)
	var c := Sdf.hash3(xi, yi + 1, 17)
	var d := Sdf.hash3(xi + 1, yi + 1, 17)
	return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v - 0.5

static func _fbm(x: float, y: float, o := 4) -> float:
	var v := 0.0
	var a := 0.5
	var f := 1.0
	for i in o:
		v += a * _vnoise(x * f, y * f)
		a *= 0.5
		f *= 2.0
	return v

## Height in metres at world (x, z). Same layout as the Three.js version.
static func height(x: float, z: float) -> float:
	var y := -z
	var h := _fbm(x * 0.22 + 3.1, y * 0.22) * 0.32 + _fbm(x * 0.9 + 4.0, y * 0.9 + 4.0) * 0.05
	h += _smooth(1.8, 5.0, y) * 1.5
	h += _smooth(-3.0, -6.0, x) * 0.45
	h += _smooth(3.5, 6.0, x) * 0.35
	var d := sqrt(pow((x - 0.6) / 3.1, 2) + pow((y - 1.5) / 1.7, 2))
	h -= 0.62 * _smooth(1.05, 0.25, d)
	h *= 1.0 - 0.75 * _smooth(1.4, 0.0, Vector2(x + 0.3, y + 1.2).length())
	return h

func build() -> void:
	var surf := {}
	for ix in range(-60, 61):
		for iz in range(-50, 51):
			var x := ix * V
			var z := iz * V
			var s := roundi(height(x, z) / V)
			var under := s < WATER_TOP_CELL
			surf[Vector3i(ix, 0, iz)] = s
			var pick := int(Sdf.hash3(ix, 0, iz) * 4.0) % 4
			var top: Color
			if under:
				top = MUD[pick % 2]
			elif _smooth(0.25, 0.45, _fbm(x * 0.6 + 5.0, -z * 0.6) + 0.5) > 0.5:
				top = DIRT
			else:
				top = GRASS[pick]
			for y in range(-8, s):
				voxels[Vector3i(ix, y, iz)] = {"c": DIRT if y >= s - 2 else MUD[1], "e": false}
			voxels[Vector3i(ix, s, iz)] = {"c": top, "e": false}
			solid_top[Vector3i(ix, 0, iz)] = s
			if under:
				for y in range(s + 1, WATER_TOP_CELL + 1):
					voxels[Vector3i(ix, y, iz)] = {"c": WATER if y == WATER_TOP_CELL else WATER_DEEP, "e": false}
	# lily pads on the water
	for ix in range(-60, 61):
		for iz in range(-50, 51):
			var s: int = surf[Vector3i(ix, 0, iz)]
			if s >= WATER_TOP_CELL or Sdf.hash3(ix, 9, iz) < 0.955:
				continue
			for dx in range(-2, 3):
				for dz in range(-2, 3):
					if dx * dx + dz * dz <= 4:
						voxels[Vector3i(ix + dx, 0, iz + dz)] = {"c": PAD[0], "e": false}
			if Sdf.hash3(iz, 4, ix) > 0.5:
				voxels[Vector3i(ix, 1, iz)] = {"c": PINK, "e": false}
	# rocks
	for r in [[-2.6, 0.6, 0.45], [-2.0, 1.2, 0.25], [3.4, 0.9, 0.55], [3.9, 1.7, 0.3], [2.2, 3.0, 0.4], [-1.0, 3.1, 0.6], [4.6, -1.5, 0.35], [-4.4, -1.0, 0.5]]:
		var cx := roundi(r[0] / V)
		var cz := roundi(-r[1] / V)
		var rad := maxi(2, roundi(r[2] / V))
		var cy: int = surf.get(Vector3i(cx, 0, cz), 0) + roundi(rad * 0.3)
		var f := Sdf.ellipsoid(Vector3(cx, cy, cz), Vector3(rad, rad * 0.7, rad))
		var cells := Sdf.voxelize(f, Vector3i(cx - rad, cy - rad, cz - rad), Vector3i(cx + rad, cy + rad, cz + rad), func(c: Vector3i):
			return {"c": LICHEN if Sdf.hash3(c.x, c.y, c.z) > 0.93 else ROCK[int(Sdf.hash3(c.x + c.y, c.z, 0) * 3) % 3], "e": false})
		for c in cells:
			voxels[c] = cells[c]
	# log along the bank
	for x in range(-36, -3):
		var s: int = surf.get(Vector3i(x, 0, 2), 0)
		for z in range(1, 4):
			for y in range(1, 3):
				voxels[Vector3i(x, s + y, z)] = {"c": BARK[1] if (y == 2 and z == 2) else BARK[0], "e": false}
	# trees: trunk + leafy crown of spheres
	for t in [[-4.6, 3.6, 4.2], [-1.8, 4.4, 5.0], [1.2, 4.6, 4.4], [3.9, 4.0, 5.2], [5.4, 2.0, 3.6], [-5.4, 0.6, 3.4]]:
		var cx := roundi(t[0] / V)
		var cz := roundi(-t[1] / V)
		var s: int = surf.get(Vector3i(cx, 0, cz), 0)
		var trunk := roundi(t[2] * 6.0)
		for y in range(s + 1, s + trunk + 1):
			voxels[Vector3i(cx, y, cz)] = {"c": BARK[int(Sdf.hash3(cx, y, cz) * 2) % 2], "e": false}
		var top := s + trunk
		var blobs := []
		for k in 9:
			var a := Sdf.hash3(cx, k, cz) * TAU
			var rr := 1.0 + Sdf.hash3(k, cz, cx) * 5.0
			blobs.append(Sdf.sphere(Vector3(cx + cos(a) * rr, top + 2 + Sdf.hash3(cz, k, 3) * 4.0, cz + sin(a) * rr), 3.0 + Sdf.hash3(k, 7, cx) * 1.5))
		var crown := Sdf.voxelize(Sdf.union(blobs), Vector3i(cx - 9, top - 1, cz - 9), Vector3i(cx + 9, top + 9, cz + 9), func(c: Vector3i):
			return {"c": LEAF[int(Sdf.hash3(c.x + c.y, c.z, 0) * 3) % 3], "e": false})
		for c in crown:
			voxels[c] = crown[c]
	# cattail reeds on the shore
	for ix in range(-60, 61):
		for iz in range(-50, 51):
			var s: int = surf.get(Vector3i(ix, 0, iz), 0)
			if s < WATER_TOP_CELL or s > 1 or Sdf.hash3(ix, 1, iz) < 0.72:
				continue
			var near_water := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if int(surf.get(Vector3i(ix + d.x, 0, iz + d.y), 0)) < WATER_TOP_CELL:
					near_water = true
			if not near_water:
				continue
			var hgt := 4 + int(Sdf.hash3(iz, 2, ix) * 4.0)
			for k in range(1, hgt + 1):
				voxels[Vector3i(ix, s + k, iz)] = {"c": REED, "e": false}
			voxels[Vector3i(ix, s + hgt + 1, iz)] = {"c": CATTAIL, "e": false}
	# ground lookup: highest non-water voxel per column (grass and reeds count as ground)
	for c in voxels:
		var col: Color = voxels[c]["c"]
		if col == WATER or col == WATER_DEEP:
			continue
		var k := Vector3i(c.x, 0, c.z)
		if c.y > int(solid_top.get(k, -99)):
			solid_top[k] = c.y

## Metres to stand at above world (x, z).
func ground(x: float, z: float) -> float:
	var k := Vector3i(roundi(x / V), 0, roundi(z / V))
	return (float(solid_top[k]) + 1.0) * V if solid_top.has(k) else 0.0

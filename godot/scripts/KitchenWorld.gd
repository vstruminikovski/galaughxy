class_name KitchenWorld
extends RefCounted

## The Overflowing Kitchen: checker floor, two walls with a window, plus the starter props.
## Ported from scenes/overflowing-kitchen/room.ts and props/seeds.ts.

const WALL_TEAL := Color("#5fa8a0")
const WALL_GREEN := Color("#9fd3c7")
const WALL_YELLOW := Color("#f4c97a")
const TRIM := Color("#29e6ff")
const FLOOR_A := Color("#f1e6d0")
const FLOOR_B := Color("#cdb894")
const WOOD := Color("#b97a46")
const WHITE := Color("#efe9dc")

static func room() -> Dictionary:
	var v := {}
	for x in range(-30, 30):
		for z in range(-25, 25):
			var checker := (int(floor((x + 30) / 5.0)) + int(floor((z + 25) / 5.0))) % 2 == 0
			v[Vector3i(x, -1, z)] = {"c": FLOOR_A if checker else FLOOR_B, "e": false}
	# back wall (z = -26) with a window cut-out
	for x in range(-31, 30):
		for y in range(0, 30):
			if x >= -4 and x <= 7 and y >= 15 and y <= 22:
				continue
			var frame := x >= -5 and x <= 8 and y >= 14 and y <= 23
			var c := Color("#ffffff") if frame else _wall_colour(y, WALL_GREEN)
			v[Vector3i(x, y, -26)] = {"c": c, "e": (y == 11 and not frame)}
	# left wall (x = -31)
	for z in range(-26, 25):
		for y in range(0, 30):
			v[Vector3i(-31, y, z)] = {"c": _wall_colour(y, WALL_YELLOW), "e": y == 11}
	return v

static func _wall_colour(y: int, base: Color) -> Color:
	if y == 0:
		return Color("#5a3b24")
	if y == 11:
		return TRIM
	return WALL_TEAL if y < 11 else base

## Props as {name, voxels, pos (metres)}. Simple original shapes built from boxes.
static func props() -> Array:
	return [
		{"name": "counter", "pos": Vector3(0.2, 0, -2.1), "v": _counter()},
		{"name": "stove", "pos": Vector3(-1.4, 0, -2.1), "v": _stove()},
		{"name": "fridge", "pos": Vector3(-2.4, 0, -2.1), "v": _fridge()},
		{"name": "plant", "pos": Vector3(2.6, 0, -2.1), "v": _plant()},
		{"name": "bucket", "pos": Vector3(1.9, 0, -0.6), "v": _bucket()},
		{"name": "duck", "pos": Vector3(-0.9, 0, 0.9), "v": _duck()},
	]

static func _counter() -> Dictionary:
	var v := {}
	VoxelBuild.box(v, -12, 11, 0, 7, -3, 3, WOOD)
	VoxelBuild.box(v, -12, 11, 8, 8, -4, 3, WHITE)
	return v

static func _stove() -> Dictionary:
	var v := {}
	VoxelBuild.box(v, -4, 3, 0, 8, -3, 3, Color("#f2f2ee"))
	VoxelBuild.box(v, -4, 3, 9, 9, -3, 3, Color("#26262b"))
	VoxelBuild.box(v, -3, 2, 2, 5, 4, 4, Color("#3a3f48"))
	return v

static func _fridge() -> Dictionary:
	var v := {}
	VoxelBuild.box(v, -4, 3, 0, 18, -3, 3, Color("#dfe8ef"))
	VoxelBuild.box(v, -4, 3, 12, 12, 4, 4, Color("#aab6bf"))
	VoxelBuild.box(v, -3, -2, 15, 16, 4, 4, Color("#ff5f87"), true)
	return v

static func _plant() -> Dictionary:
	var v := {}
	VoxelBuild.box(v, -1, 1, 0, 2, -1, 1, Color("#c8643b"))
	VoxelBuild.box(v, 0, 0, 3, 6, 0, 0, Color("#3e8f3e"))
	VoxelBuild.box(v, -2, 2, 5, 5, 0, 0, Color("#5bbf5b"))
	return v

static func _bucket() -> Dictionary:
	var v := {}
	VoxelBuild.box(v, -2, 2, 0, 3, -2, 2, Color("#3d8bd4"))
	return v

static func _duck() -> Dictionary:
	var v := {}
	VoxelBuild.box(v, -2, 1, 0, 1, -1, 1, Color("#ffd23f"))
	VoxelBuild.box(v, 0, 1, 2, 3, -1, 0, Color("#ffd23f"))
	v[Vector3i(1, 3, 1)] = {"c": Color("#20e3ff"), "e": true}
	return v

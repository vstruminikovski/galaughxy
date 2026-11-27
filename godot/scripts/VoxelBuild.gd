class_name VoxelBuild
extends RefCounted

## Helpers that fill voxel dictionaries (Vector3i -> {"c": Color, "e": bool}).

static func box(v: Dictionary, x0: int, x1: int, y0: int, y1: int, z0: int, z1: int, c: Color, glow := false) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		for y in range(mini(y0, y1), maxi(y0, y1) + 1):
			for z in range(mini(z0, z1), maxi(z0, z1) + 1):
				v[Vector3i(x, y, z)] = {"c": c, "e": glow}

## Deterministic hash in [0,1) for stable per-cell colour variation.
static func hash3(x: int, y: int, z: int) -> float:
	var n := sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453
	return n - floor(n)

static func pick(arr: Array, x: int, z: int) -> Color:
	return arr[int(hash3(x, 0, z) * arr.size()) % arr.size()]

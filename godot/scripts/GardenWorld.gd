class_name GardenWorld
extends RefCounted

## Backyard Garden, built from the same 0.1 m square voxels as the Three.js version.
const SOIL := Color("#5a4228")
const WOOD := Color("#a6743f")
const WOOD_DARK := Color("#7a5230")
const BARK := Color("#5b4431")
const TABLE := Color("#c79a5e")
const MUG := Color("#e2574c")
const GRASS := [Color("#4f7a2a"), Color("#5d8a33"), Color("#466f25")]
const STONE := [Color("#9a9790"), Color("#8a877f")]
const LEAF := [Color("#3e6b23"), Color("#4f8030"), Color("#2f5a1c")]
const FLOWERS := [Color("#ff5f87"), Color("#ffd23a"), Color("#9b6bff"), Color("#ffffff"), Color("#ff8a3d")]

static func build() -> Dictionary:
	var v := {}
	# lawn
	for x in range(-55, 56):
		for z in range(-45, 46):
			for y in range(-4, -1):
				v[Vector3i(x, y, z)] = {"c": SOIL, "e": false}
			var stripe := (int(floor((x + 60) / 6.0)) + int(floor((z + 60) / 6.0))) % 2
			var g: Color = GRASS[0] if stripe == 1 else VoxelBuild.pick(GRASS, x, z)
			v[Vector3i(x, -1, z)] = {"c": g, "e": false}
	# fence
	for x in range(-55, 56):
		if absi(x) % 5 == 0:
			for y in range(0, 9):
				v[Vector3i(x, y, -45)] = {"c": WOOD_DARK, "e": false}
				v[Vector3i(x, y, 45)] = {"c": WOOD_DARK, "e": false}
		for y in [3, 6]:
			v[Vector3i(x, y, -45)] = {"c": WOOD, "e": false}
			v[Vector3i(x, y, 45)] = {"c": WOOD, "e": false}
	for z in range(-45, 46):
		if absi(z) % 5 == 0:
			for y in range(0, 9):
				v[Vector3i(-55, y, z)] = {"c": WOOD_DARK, "e": false}
				v[Vector3i(55, y, z)] = {"c": WOOD_DARK, "e": false}
		for y in [3, 6]:
			v[Vector3i(-55, y, z)] = {"c": WOOD, "e": false}
			v[Vector3i(55, y, z)] = {"c": WOOD, "e": false}
	# stepping-stone path
	var z := -40
	while z <= 20:
		for x in range(-1, 2):
			for zz in range(z, z + 2):
				v[Vector3i(x, 0, zz)] = {"c": VoxelBuild.pick(STONE, z, 2), "e": false}
		z += 3
	# flower bed (left)
	for x in range(-45, -29):
		for zz in range(-30, -19):
			v[Vector3i(x, 0, zz)] = {"c": SOIL, "e": false}
			if VoxelBuild.hash3(x, 7, zz) > 0.45:
				v[Vector3i(x, 1, zz)] = {"c": VoxelBuild.pick(FLOWERS, x, zz), "e": false}
	# tree (far left)
	var tx := -36
	var tz := -6
	for y in range(0, 23):
		v[Vector3i(tx, y, tz)] = {"c": BARK, "e": false}
		if y < 4:
			v[Vector3i(tx + 1, y, tz)] = {"c": BARK, "e": false}
	for k in 8:
		var a := VoxelBuild.hash3(k, 1, 2) * TAU
		var cx := tx + cos(a) * 5.0
		var cz := tz + sin(a) * 5.0
		var cy := 22.0 + VoxelBuild.hash3(k, 4, 1) * 3.0
		var r := 5.0 + VoxelBuild.hash3(k, 9, 3) * 2.0
		for x in range(int(cx - r) - 1, int(cx + r) + 2):
			for y in range(int(cy - r) - 1, int(cy + r) + 2):
				for zz in range(int(cz - r) - 1, int(cz + r) + 2):
					var d := Vector3(x - cx, y - cy, zz - cz).length()
					if d <= r and not v.has(Vector3i(x, y, zz)):
						v[Vector3i(x, y, zz)] = {"c": VoxelBuild.pick(LEAF, x + y, zz), "e": false}
	# garden table with legs, mug, glowing lantern
	VoxelBuild.box(v, 14, 26, 6, 7, -14, -6, TABLE)
	for lx in [14, 26]:
		for lz in [-14, -6]:
			VoxelBuild.box(v, lx, lx, 0, 5, lz, lz, WOOD_DARK)
	VoxelBuild.box(v, 21, 22, 8, 9, -10, -10, MUG)
	VoxelBuild.box(v, 18, 18, 8, 9, -10, -10, Color("#ffd23a"), true)
	return v

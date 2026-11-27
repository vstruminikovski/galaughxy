class_name FrogModel
extends RefCounted

## Bog the frog: hybrid organic body (smooth-blended squares) with robot parts
## (LED side strip, antenna beacon, glowing lenses). Each part is a voxel dictionary
## with its pivot, so the rig can rotate jaw, lids and limbs. Ported from frogModel.ts.

const SKIN := Color("#5f9a3a")
const DARK := Color("#3c6a24")
const LIGHT := Color("#9cc35a")
const BELLY := Color("#e6dca0")
const GOLD := Color("#e6b52a")
const BLACK := Color("#0b0b0b")
const METAL := Color("#4a5160")
const LED := Color("#ff3d7f")
const LIP := Color("#c9c27f")
const SIZE := 0.03

static func skin(x: int, y: int, z: int) -> Color:
	var r := Sdf.hash3(x, y, z)
	return DARK if r < 0.2 else (SKIN if r < 0.82 else LIGHT)

static func parts() -> Dictionary:
	var out := {}
	# torso + head: one organic blend, with the mouth carved out
	var torso := Sdf.smin(Sdf.ellipsoid(Vector3(0, 7, 0), Vector3(7, 5, 9)), Sdf.ellipsoid(Vector3(0, 9, 6), Vector3(6, 4.5, 5)), 2.5)
	var mouth := Sdf.ellipsoid(Vector3(0, 6.6, 9.6), Vector3(4.6, 1.4, 3.2))
	var body := Sdf.voxelize(Sdf.minus(torso, mouth), Vector3i(-12, -1, -12), Vector3i(12, 20, 14), func(c: Vector3i):
		if absi(c.x) == 6 and c.y == 7 and c.z % 3 == 0:
			return {"c": LED, "e": true}
		return {"c": BELLY if c.y <= 3 else skin(c.x, c.y, c.z), "e": false})
	body.merge(Sdf.voxelize(Sdf.capsule(Vector3(0, 14, 4), Vector3(0, 19, 4), 0.7), Vector3i(-2, 13, 2), Vector3i(2, 21, 6), func(_c): return {"c": METAL, "e": false}))
	body.merge(Sdf.voxelize(Sdf.sphere(Vector3(0, 19.6, 4), 1.2), Vector3i(-2, 18, 2), Vector3i(2, 22, 6), func(_c): return {"c": LED, "e": true}))
	out["body"] = {"v": body, "pivot": Vector3i(0, 0, 0)}

	# eyes (glowing lenses with a slit pupil) and their lids
	for s in [1, -1]:
		var ex: int = 4 * s
		var pv := Vector3i(ex, 12, 8)
		var ball := Sdf.voxelize(Sdf.sphere(Vector3(pv), 2.4), pv - Vector3i(3, 3, 3), pv + Vector3i(3, 3, 3), func(c: Vector3i):
			var front := c.z > pv.z + 1 and absi(c.x - ex) <= 0.8 and absi(c.y - 12) <= 1
			return {"c": BLACK if front else GOLD, "e": not front})
		var shell_sdf := Sdf.minus(Sdf.sphere(Vector3(pv), 3.3), Sdf.sphere(Vector3(pv), 2.2))
		var shell := Sdf.voxelize(shell_sdf, Vector3i(ex - 4, 12, 4) + Vector3i(0, 0, 4), Vector3i(ex + 4, 16, 12), func(c: Vector3i): return {"c": skin(c.x, 12, c.z), "e": false})
		out["eye" + ("L" if s == 1 else "R")] = {"v": ball, "pivot": pv}
		out["lid" + ("L" if s == 1 else "R")] = {"v": shell, "pivot": pv}

	# lower jaw hinged behind the mouth
	var jaw := Sdf.voxelize(Sdf.ellipsoid(Vector3(0, 5.2, 8.5), Vector3(4.2, 1.5, 3.6)), Vector3i(-6, 2, 4), Vector3i(6, 9, 13), func(c: Vector3i):
		return {"c": LIP if c.z >= 10 else BELLY, "e": false})
	out["jaw"] = {"v": jaw, "pivot": Vector3i(0, 6, 4)}

	# legs and arms, with robot joint caps at the pivots
	for s in [1, -1]:
		var hip := Vector3(6 * s, 4, -4)
		var leg := Sdf.union([Sdf.ellipsoid(hip, Vector3(3.2, 3, 4.5)), Sdf.box(Vector3(6 * s, 1, -1), Vector3(2.4, 1, 2.6))])
		var legv := Sdf.voxelize(leg, Vector3i(6 * s - 6, -1, -11), Vector3i(6 * s + 6, 9, 2), func(c: Vector3i):
			if c.y >= 6 and absi(c.x - 6 * s) <= 1:
				return {"c": METAL, "e": false}
			return {"c": skin(c.x, c.y, c.z), "e": false})
		var arm := Sdf.union([Sdf.capsule(Vector3(5 * s, 4, 4), Vector3(7.5 * s, 1.5, 8), 1.5), Sdf.box(Vector3(7.5 * s, 1, 9), Vector3(1.8, 0.8, 1.6))])
		var armv := Sdf.voxelize(arm, Vector3i(5 * s - 3, -1, 1), Vector3i(5 * s + 4, 7, 12), func(c: Vector3i):
			if c.y >= 4 and absi(c.x - 5 * s) <= 1 and c.z <= 5:
				return {"c": METAL, "e": false}
			return {"c": skin(c.x, c.y, c.z), "e": false})
		var side := "L" if s == 1 else "R"
		out["leg" + side] = {"v": legv, "pivot": Vector3i(int(hip.x), int(hip.y), int(hip.z))}
		out["arm" + side] = {"v": armv, "pivot": Vector3i(5 * s, 5, 4)}
	return out

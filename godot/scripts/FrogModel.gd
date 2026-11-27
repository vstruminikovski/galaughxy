class_name FrogModel
extends RefCounted

## Bog the frog: smooth stylised body (blended ellipsoids), glowing gold lenses with slit pupils,
## robot details (LED strip, antenna beacon). Units are cells: the node is scaled by FROG_SCALE.
## Each part has its pivot at a joint so the rig can rotate jaw, lids and limbs.

const FROG_SCALE := 0.03
const SKIN := Color("#27C93F")
const DARK := Color("#1B892B")
const LIGHT := Color("#82E090")
const BELLY := Color("#F5F2EB")
const GOLD := Color("#FFBD2E")
const BLACK := Color("#2C2E33")
const METAL := Color("#E5E7EB")
const LED := Color("#FF5F56")
const LIP := Color("#F5F2EB")

static func _skin(p: Vector3) -> Color:
	# two flat tones: a darker cap over the back and head, the body colour below
	return DARK if p.y > 9.5 else SKIN

## Body ellipsoids (model space) that hide limb and feature outlines inside the body.
static func occluders() -> Dictionary:
	return {
		"c": [Vector4(0, 7, 0, 0), Vector4(0, 9, 6, 0)],
		"r": [Vector4(7, 5, 9, 0), Vector4(6, 4.5, 5, 0)],
	}

static func parts() -> Dictionary:
	var torso := Sdf.smin(Sdf.ellipsoid(Vector3(0, 7, 0), Vector3(7, 5, 9)), Sdf.ellipsoid(Vector3(0, 9, 6), Vector3(6, 4.5, 5)), 2.5)
	var mouth := Sdf.ellipsoid(Vector3(0, 6.6, 9.6), Vector3(4.6, 1.4, 3.2))
	var out := {}
	out["body"] = {
		"sdf": Sdf.minus(torso, mouth), "lo": Vector3(-12, -1, -12), "hi": Vector3(12, 21, 15),
		"color": func(p: Vector3) -> Color: return BELLY if p.y <= 3.5 else _skin(p),
		"pivot": Vector3.ZERO, "glow": false,
	}
	out["strip"] = {
		"sdf": Sdf.union([Sdf.sphere(Vector3(6.6, 7, 0), 0.7), Sdf.sphere(Vector3(-6.6, 7, 0), 0.7), Sdf.sphere(Vector3(6.6, 7, 4), 0.7), Sdf.sphere(Vector3(-6.6, 7, 4), 0.7)]),
		"lo": Vector3(-8, 5, -2), "hi": Vector3(8, 9, 6), "color": SmoothMesh.solid(LED), "pivot": Vector3.ZERO, "glow": true,
	}
	out["antenna"] = {
		"sdf": Sdf.capsule(Vector3(0, 14, 4), Vector3(0, 19, 4), 0.7), "lo": Vector3(-2, 13, 2), "hi": Vector3(2, 21, 6),
		"color": SmoothMesh.solid(METAL), "pivot": Vector3.ZERO, "glow": false,
	}
	out["beacon"] = {
		"sdf": Sdf.sphere(Vector3(0, 19.6, 4), 1.2), "lo": Vector3(-2, 18, 2), "hi": Vector3(2, 22, 6),
		"color": SmoothMesh.solid(LED), "pivot": Vector3.ZERO, "glow": true,
	}
	for s in [1, -1]:
		var side := "L" if s == 1 else "R"
		var ex: float = 4.0 * s
		var pv := Vector3(ex, 12, 8)
		out["eye" + side] = {
			"sdf": Sdf.sphere(pv, 2.4), "lo": pv - Vector3(3, 3, 3), "hi": pv + Vector3(3, 3, 3),
			"color": func(p: Vector3) -> Color:
				var q: Vector3 = p - pv
				return BLACK if (q.z > 1.0 and absf(q.x) < 0.8 and absf(q.y) < 1.2) else GOLD,
			"pivot": pv, "glow": false,
		}
		var shell := Sdf.minus(Sdf.sphere(pv, 3.3), Sdf.sphere(pv, 2.2))
		var upper := func(p: Vector3) -> float: return maxf(shell.call(p), pv.y - p.y)
		out["lid" + side] = {
			"sdf": upper, "lo": pv - Vector3(4, 0, 4), "hi": pv + Vector3(4, 4, 4), "color": SmoothMesh.solid(_skin(pv)), "pivot": pv, "glow": false,
		}
	out["jaw"] = {
		"sdf": Sdf.ellipsoid(Vector3(0, 5.2, 8.5), Vector3(4.2, 1.5, 3.6)), "lo": Vector3(-6, 2, 4), "hi": Vector3(6, 9, 13),
		"color": func(p: Vector3) -> Color: return LIP if p.z >= 6.0 else BELLY,
		"pivot": Vector3(0, 6, 4), "glow": false,
	}
	for s in [1, -1]:
		var side := "L" if s == 1 else "R"
		var hip := Vector3(6.0 * s, 4, -4)
		out["leg" + side] = {
			"sdf": Sdf.union([Sdf.ellipsoid(hip, Vector3(3.2, 3, 4.5)), Sdf.rbox(Vector3(6.0 * s, 1, -1), Vector3(2.4, 1, 2.6), 0.8)]),
			"lo": Vector3(6.0 * s - 6, -2, -10), "hi": Vector3(6.0 * s + 6, 9, 3), "color": SmoothMesh.solid(SKIN), "pivot": hip, "glow": false,
		}
		out["arm" + side] = {
			"sdf": Sdf.union([Sdf.capsule(Vector3(5.0 * s, 4, 4), Vector3(7.5 * s, 1.5, 8), 1.5), Sdf.rbox(Vector3(7.5 * s, 1, 9), Vector3(1.8, 0.8, 1.6), 0.6)]),
			"lo": Vector3(5.0 * s - 5.5, -1, -2), "hi": Vector3(5.0 * s + 5.5, 8, 12), "color": SmoothMesh.solid(SKIN), "pivot": Vector3(5.0 * s, 5, 4), "glow": false,
		}
	return out

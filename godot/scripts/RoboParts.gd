class_name RoboParts
extends RefCounted

## Robo character, smooth stylised parts (metres). Each part has a pivot, a signed-distance
## shape in local space, a bounding box, and a colour function. Glow parts are emissive.

const DARK := Color("#1b1f2a")
const TRIM := Color("#f4f6f8")
const METAL := Color("#8c96a6")
const LED := Color("#ffcc33")
const BEACON := Color("#ff3d7f")

static func parts(body_color: Color) -> Dictionary:
	var body_sdf := Sdf.union([
		Sdf.rbox(Vector3(0, 0.26, 0), Vector3(0.2, 0.2, 0.15), 0.07),
		Sdf.rbox(Vector3(-0.1, 0.03, 0.0), Vector3(0.07, 0.04, 0.1), 0.03),
		Sdf.rbox(Vector3(0.1, 0.03, 0.0), Vector3(0.07, 0.04, 0.1), 0.03),
	])
	var body := {
		"sdf": body_sdf, "lo": Vector3(-0.3, -0.02, -0.25), "hi": Vector3(0.3, 0.5, 0.25),
		"color": func(p: Vector3) -> Color: return DARK if p.y < 0.07 else body_color,
		"pivot": Vector3.ZERO, "glow": false,
	}
	var led := {
		"sdf": Sdf.sphere(Vector3(0, 0.26, 0.16), 0.03), "lo": Vector3(-0.05, 0.2, 0.1), "hi": Vector3(0.05, 0.32, 0.2),
		"color": SmoothMesh.solid(LED), "pivot": Vector3.ZERO, "glow": true,
	}
	# head pivots at the neck so the head can bob and tilt
	var neck := Vector3(0, 0.5, 0)
	var head_sdf := Sdf.union([Sdf.rbox(neck + Vector3(0, 0.16, 0), Vector3(0.2, 0.16, 0.16), 0.07)])
	var head := {
		"sdf": head_sdf, "lo": Vector3(-0.3, 0.3, -0.25), "hi": Vector3(0.3, 0.9, 0.25),
		"color": func(p: Vector3) -> Color:
			var q := p - neck
			return DARK if (q.z > 0.1 and absf(q.x) < 0.14 and absf(q.y - 0.16) < 0.1) else body_color,
		"pivot": neck, "glow": false,
	}
	var antenna := {
		"sdf": Sdf.capsule(neck + Vector3(0, 0.3, 0), neck + Vector3(0, 0.46, 0), 0.018), "lo": Vector3(-0.05, 0.5, -0.05), "hi": Vector3(0.05, 0.85, 0.05),
		"color": SmoothMesh.solid(METAL), "pivot": neck, "glow": false,
	}
	var beacon := {
		"sdf": Sdf.sphere(neck + Vector3(0, 0.5, 0), 0.03), "lo": Vector3(-0.05, 0.42, -0.05), "hi": Vector3(0.05, 0.6, 0.05),
		"color": SmoothMesh.solid(BEACON), "pivot": neck, "glow": true,
	}
	return {"body": body, "led": led, "head": head, "antenna": antenna, "beacon": beacon}

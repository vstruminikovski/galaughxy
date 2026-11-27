class_name RoboParts
extends RefCounted

## The robo character, as voxel parts (ported from the Three.js RoboActor).
const TRIM := Color("#f4f6f8")
const DARK := Color("#1b1f2a")
const METAL := Color("#2c3442")

static func build(color: Color) -> Dictionary:
	var body := {}
	VoxelBuild.box(body, -3, 2, 0, 5, -2, 1, color)
	VoxelBuild.box(body, -2, 1, 1, 3, 2, 2, DARK)
	VoxelBuild.box(body, -1, 0, 2, 2, 2, 2, Color("#ffcc33"), true)
	VoxelBuild.box(body, -3, 2, 0, 0, -2, 1, METAL)
	var head := {}
	VoxelBuild.box(head, -5, 4, 0, 9, -4, 3, color)
	VoxelBuild.box(head, -4, 3, 1, 8, 3, 3, DARK)
	VoxelBuild.box(head, -6, -6, 3, 6, -1, 0, TRIM)
	VoxelBuild.box(head, 5, 5, 3, 6, -1, 0, TRIM)
	VoxelBuild.box(head, 0, 0, 10, 12, 0, 0, Color("#9aa4b2"))
	VoxelBuild.box(head, 0, 0, 13, 13, 0, 0, Color("#ff3d7f"), true)
	return {"body": body, "head": head}

## Flatten parts into one voxel dictionary with the head lifted to sit on the body.
static func assembled(color: Color) -> Dictionary:
	var p := build(color)
	var out := {}
	for k in p["body"]: out[k] = p["body"][k]
	for k in p["head"]:
		out[k + Vector3i(0, 6, 0)] = p["head"][k]
	return out

class_name VoxelMesh
extends RefCounted

## Builds a single ArrayMesh from voxel cells.
## voxels: Dictionary  Vector3i -> {"c": Color, "e": bool}
## Only faces that border empty space are emitted (hidden-face culling).
## Surface 0 = lit voxels, surface 1 = emissive (glowing) voxels.

const DIRS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

static func build(voxels: Dictionary, size: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var lit := SurfaceTool.new()
	var glow := SurfaceTool.new()
	lit.begin(Mesh.PRIMITIVE_TRIANGLES)
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_glow := false
	for cell: Vector3i in voxels:
		var v: Dictionary = voxels[cell]
		var st: SurfaceTool = glow if v.get("e", false) else lit
		if v.get("e", false):
			has_glow = true
		for d: Vector3i in DIRS:
			if voxels.has(cell + d):
				continue
			_quad(st, cell, d, size, v["c"])
	var lit_arrays := lit.commit_to_arrays()
	if lit_arrays[Mesh.ARRAY_VERTEX] != null:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lit_arrays)
	if has_glow:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, glow.commit_to_arrays())
	return mesh

static func _quad(st: SurfaceTool, cell: Vector3i, d: Vector3i, size: float, col: Color) -> void:
	var n := Vector3(d)
	var center := (Vector3(cell) + Vector3(0.5, 0.5, 0.5) + n * 0.5) * size
	var u := Vector3(0, 1, 0) if absf(n.y) < 0.5 else Vector3(1, 0, 0)
	var t1 := n.cross(u).normalized()
	var t2 := n.cross(t1).normalized()
	var h := size * 0.5
	var a := center - t1 * h - t2 * h
	var b := center + t1 * h - t2 * h
	var c := center + t1 * h + t2 * h
	var e := center - t1 * h + t2 * h
	# Godot treats clockwise as front; emit the two triangles so they face along the normal.
	var tri := [a, c, b, a, e, c]
	for p in tri:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(p)

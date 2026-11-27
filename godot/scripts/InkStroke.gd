class_name InkStroke
extends MeshInstance3D

## Grease-pencil outline traced on the GPU, every frame, from the current camera.
##
## For every triangle that can hold part of the outline, setup() emits one quad whose four
## corners each carry the whole triangle (3 positions + 3 normals). The vertex shader
## (ink_contour.gdshader) computes g = dot(normal, camera - point) at the three corners; where g
## changes sign, the outline crosses the triangle. The two crossing points become a screen-space
## segment with round caps. Neighbouring triangles compute the same crossing on their shared edge,
## so the segments join into one continuous line that is always glued to the true silhouette, at
## any angle and while anything moves. Nothing is rebuilt on the CPU after setup.
##
## Flat regions (all three normals within ~2 degrees) can never hold an outline from a normal
## viewpoint, so their triangles are skipped: walls and floors cost almost nothing.

const FLAT_COS := 0.9994

static var build_ms := 0.0
static var builds := 0

func setup(src: ArrayMesh) -> void:
	var t0 := Time.get_ticks_usec()
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var c2 := PackedFloat32Array()
	var uv := PackedVector2Array()
	var ix := PackedInt32Array()
	var corners := [Vector2(0, -1), Vector2(0, 1), Vector2(1, -1), Vector2(1, 1)]
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if norms.size() != verts.size():
			continue
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := idx.size() if idx.size() > 0 else verts.size()
		var k := 0
		while k + 2 < count:
			var a := idx[k] if idx.size() > 0 else k
			var b := idx[k + 1] if idx.size() > 0 else k + 1
			var c := idx[k + 2] if idx.size() > 0 else k + 2
			k += 3
			var na := norms[a]
			var nb := norms[b]
			var nc := norms[c]
			if na.dot(nb) > FLAT_COS and nb.dot(nc) > FLAT_COS and na.dot(nc) > FLAT_COS:
				continue
			var p0 := verts[a]
			var p1 := verts[b]
			var p2 := verts[c]
			var base := v.size()
			for corner in corners:
				v.append(p0)
				nr.append(na)
				c0.append_array([p1.x, p1.y, p1.z, nb.x])
				c1.append_array([nb.y, nb.z, p2.x, p2.y])
				c2.append_array([p2.z, nc.x, nc.y, nc.z])
				uv.append(corner)
			ix.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var m := ArrayMesh.new()
	if not v.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nr
		arr[Mesh.ARRAY_CUSTOM0] = c0
		arr[Mesh.ARRAY_CUSTOM1] = c1
		arr[Mesh.ARRAY_CUSTOM2] = c2
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_INDEX] = ix
		var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	mesh = m
	custom_aabb = src.get_aabb().grow(0.05)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	build_ms += (Time.get_ticks_usec() - t0) / 1000.0
	builds += 1

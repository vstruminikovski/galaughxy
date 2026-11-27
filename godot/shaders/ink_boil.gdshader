shader_type spatial;
// Grease-pencil style ink. One smooth line per outer edge: an inverted hull drawn with front faces
// culled. The line waves on a slow harmonic (smooth in time, not stepped), so it reads as one pencil
// stroke that breathes. Limb rims are cut where they enter the body volume (occluders), so no
// intersecting lines are drawn.
render_mode cull_front, unshaded, depth_draw_opaque;

uniform vec4 ink_color : source_color = vec4(0.48, 0.12, 0.12, 1.0);
uniform float thickness = 0.006;
uniform float boil_amount = 0.25;   // fraction of the width the line swells and thins by
uniform float wave_hz = 0.9;        // slow harmonic, almost invisible
uniform int occ_n = 0;              // number of body ellipsoids that hide this rim
uniform vec4 occ_c[4];              // ellipsoid centres (body space)
uniform vec4 occ_r[4];              // ellipsoid radii (body space)
uniform mat4 to_body = mat4(1.0);   // world -> body space, set per frame

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// a single wave that travels along the line: smooth in space and time
	float along = dot(VERTEX, vec3(0.8, 0.5, 0.33)) / max(thickness * 60.0, 1e-5);
	float ph = TIME * 6.2831853 * wave_hz;
	float wave = 0.75 * sin(along + ph) + 0.25 * sin(along * 0.5 - ph * 0.6);
	VERTEX += NORMAL * thickness * boil_amount * wave;
}

void fragment() {
	for (int i = 0; i < 4; i++) {
		if (i >= occ_n) break;
		vec3 q = (((to_body * vec4(wpos, 1.0)).xyz) - occ_c[i].xyz) / occ_r[i].xyz;
		if (dot(q, q) < 1.0) discard; // inside the body: no line here
	}
	ALBEDO = ink_color.rgb;
	ALPHA = ink_color.a;
}

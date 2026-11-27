shader_type spatial;
// Grease-pencil style ink. One line per outer edge: an inverted hull drawn with front faces culled.
// The boil moves the line sideways (never swells it), redrawn 12 times a second like pencil on
// twos, with a spatially smooth wave so neighbouring points move together. Limb rims are cut where
// they enter the body volume (occluders).
render_mode cull_front, unshaded, depth_draw_opaque;

uniform vec4 ink_color : source_color = vec4(0.48, 0.12, 0.12, 1.0);
uniform float thickness = 0.006;
uniform float boil_amount = 0.35;   // sideways wobble as a share of the line width
uniform float boil_fps = 12.0;      // redraw rate ("on twos")
uniform int occ_n = 0;              // number of body ellipsoids that hide this rim
uniform vec4 occ_c[4];              // ellipsoid centres (body space)
uniform vec4 occ_r[4];              // ellipsoid radii (body space)
uniform mat4 to_body = mat4(1.0);   // world -> body space, set per frame

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float tq = floor(TIME * boil_fps) / boil_fps; // the drawing is held for 1/12 s
	float along = dot(VERTEX, vec3(0.8, 0.5, 0.33)) / max(thickness * 60.0, 1e-5);
	float wave = 0.7 * sin(along + tq * 5.2) + 0.3 * sin(along * 0.5 - tq * 7.8);
	// taper: the line swells and thins along its length and pinches to nothing at blunt, rounded
	// points (slow drift so the pinch points move gently rather than pulsing)
	float taper = pow(clamp(0.5 + 0.5 * sin(along * 0.45 + tq * 0.9 + 1.7), 0.0, 1.0), 0.6);
	VERTEX -= NORMAL * thickness * (1.0 - taper);
	// sideways direction: perpendicular to the normal, so the width stays constant
	vec3 s1 = cross(NORMAL, vec3(0.31, 0.77, 0.56));
	vec3 s2 = cross(NORMAL, vec3(0.9, 0.1, 0.2));
	vec3 side = length(s1) > length(s2) ? normalize(s1) : normalize(s2);
	VERTEX += side * thickness * boil_amount * wave;
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

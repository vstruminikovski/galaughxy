shader_type spatial;
// Grease-pencil style ink: an inverted hull drawn with front faces culled, so only the rim shows.
// The line "boils": every vertex is pushed by a hash that is re-rolled 12 times a second
// (on twos), and each vertex has a fixed pressure so strokes swell and thin along their length.
render_mode cull_front, unshaded, depth_draw_opaque;

uniform vec4 ink_color : source_color = vec4(0.48, 0.12, 0.12, 1.0);
uniform float thickness = 0.012;
uniform float boil_amount = 0.35;   // fraction of the rim width the line wobbles by
uniform float boil_fps = 12.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	float frame = floor(TIME * boil_fps);
	vec3 cell = floor(VERTEX * 400.0);            // stable per point on the surface
	float pressure = 0.55 + 0.45 * hash13(cell);  // sensitivity: thicker and thinner along the line
	vec3 j = vec3(hash13(cell + frame * 0.731), hash13(cell + 17.3 + frame * 1.17), hash13(cell + 5.1 + frame * 0.419)) - 0.5;
	VERTEX += NORMAL * (thickness * pressure * (1.0 + boil_amount * j.x)) + j * thickness * boil_amount * 0.5;
}

void fragment() {
	ALBEDO = ink_color.rgb;
	ALPHA = ink_color.a;
}

shader_type spatial;
// Grease-pencil style ink, drawn as a thin line of constant screen width.
// - The rim is an inverted hull pushed out in screen pixels along smoothed normals, so the line
//   is equally thin near and far and its path follows the surface smoothly.
// - Width varies gently along the line (pressure), never down to a point.
// - Boil works like Blender's Noise modifier with a step: the line is redrawn 12 times a second
//   with a new noise seed, shifting a fraction of a pixel sideways. The width never changes in
//   time, so it does not pulse.
// - Limb rims are cut where they enter the body volume (occluders).
render_mode cull_front, unshaded, depth_draw_opaque, skip_vertex_transform;

uniform vec4 ink_color : source_color = vec4(0.48, 0.12, 0.12, 1.0);
uniform float thickness = 0.006;    // unused for width; kept for the API
uniform float width_px = 2.4;       // line width at 1080p (scales with frame height)
uniform float pressure_min = 0.6;   // thinnest point along a line, as a share of width_px
uniform float boil_px = 0.7;        // sideways boil, pixels at 1080p
uniform float boil_fps = 12.0;
uniform float noise_scale = 9.0;    // noise features per metre along the line
uniform int occ_n = 0;
uniform vec4 occ_c[4];
uniform vec4 occ_r[4];
uniform mat4 to_body = mat4(1.0);

varying vec3 wpos;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// smooth value noise in 0..1
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 nview = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 dir = (PROJECTION_MATRIX * vec4(nview, 0.0)).xy;
	dir = length(dir) > 1e-6 ? normalize(dir) : vec2(0.0);
	float px = VIEWPORT_SIZE.y / 1080.0;
	// pressure: a fixed, smooth thickness profile along the line (does not change in time)
	float pressure = mix(pressure_min, 1.0, vnoise(wpos * noise_scale * 0.5 + 11.0));
	// boil: a new noise seed 12 times a second, smooth along the line
	float frame = floor(TIME * boil_fps);
	float jitter = vnoise(wpos * noise_scale + vec3(frame * 7.13, frame * 3.71, frame * 5.29)) - 0.5;
	float offset = (width_px * pressure + jitter * 2.0 * boil_px) * px;
	clip.xy += dir * offset * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
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

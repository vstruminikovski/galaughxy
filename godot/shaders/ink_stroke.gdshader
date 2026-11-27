shader_type spatial;
// Grease-pencil stroke drawn from a traced outline (see InkStroke.gd).
// - Constant screen width: the ribbon is expanded in pixels, so the line is equally thin near and far.
// - Round caps: each stroke end is a half disc; the taper (UV2.x) makes the ends small and blunt.
// - Smooth edges: the line's edge is faded over one pixel (analytic anti-aliasing).
// - Boil, like Blender's Noise modifier with a step: a new noise seed 12 times a second shifts
//   the line a fraction of a pixel sideways. The width never changes in time, so it does not pulse.
// - Limb strokes are cut where they enter the body volume (occluders).
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, skip_vertex_transform, shadows_disabled;

uniform vec4 ink_color : source_color = vec4(0.48, 0.12, 0.12, 1.0);
uniform float width_px = 2.2;       // full line width at 1080p (scales with frame height)
uniform float pressure_min = 0.8;   // gentle width variation along a line
uniform float boil_px = 0.6;        // sideways boil, pixels at 1080p
uniform float boil_fps = 12.0;
uniform float noise_scale = 9.0;    // noise features per metre
uniform float depth_bias = 0.004;   // pull the line toward the camera (share of distance)
uniform int occ_n = 0;
uniform vec4 occ_c[4];
uniform vec4 occ_r[4];
uniform mat4 to_body = mat4(1.0);

varying vec3 wpos;
varying vec2 off;
varying float half_w;   // half line width, pixels
varying float reach;    // half width of the drawn geometry, pixels (line + 1 px fringe)

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

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
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 vt = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	vp.xyz *= (1.0 - depth_bias);
	vec4 c0 = PROJECTION_MATRIX * vp;
	vec4 c1 = PROJECTION_MATRIX * (vp + vec4(vt * 0.01 * abs(vp.z), 0.0));
	vec2 t = (c1.xy / c1.w - c0.xy / c0.w) * VIEWPORT_SIZE;
	t = length(t) > 1e-6 ? normalize(t) : vec2(1.0, 0.0);
	vec2 across = vec2(-t.y, t.x);
	float px = VIEWPORT_SIZE.y / 1080.0;
	float pressure = mix(pressure_min, 1.0, vnoise(wpos * noise_scale * 0.5 + 11.0));
	half_w = 0.5 * width_px * px * UV2.x * pressure;
	reach = half_w + 1.0;
	float frame = floor(TIME * boil_fps);
	float jitter = (vnoise(wpos * noise_scale + frame * vec3(7.13, 3.71, 5.29)) - 0.5) * 2.0 * boil_px * px;
	vec2 o = (t * UV.x + across * UV.y) * reach + across * jitter;
	c0.xy += o * 2.0 / VIEWPORT_SIZE * c0.w;
	POSITION = c0;
	off = UV;
}

void fragment() {
	for (int i = 0; i < 4; i++) {
		if (i >= occ_n) break;
		vec3 q = (((to_body * vec4(wpos, 1.0)).xyz) - occ_c[i].xyz) / occ_r[i].xyz;
		if (dot(q, q) < 1.0) discard; // inside the body: no line here
	}
	float d = length(off) * reach;              // distance from the line's centre, pixels
	float a = clamp(half_w - d + 0.5, 0.0, 1.0); // one-pixel soft edge
	if (a <= 0.0) discard;
	ALBEDO = ink_color.rgb;
	ALPHA = ink_color.a * a;
}

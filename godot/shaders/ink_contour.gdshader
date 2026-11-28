shader_type spatial;
// Grease-pencil outline, traced per frame on the GPU (see InkStroke.gd).
// Each quad carries one triangle. Where dot(normal, camera - point) changes sign across the
// triangle, the silhouette passes through it: the two crossing points become a screen-space
// segment of constant pixel width with round caps and a one-pixel soft edge. Neighbouring
// triangles produce the same crossing on their shared edge, so segments join into one line.
// Width varies gently along the line (pressure noise fixed to the surface). The boil moves the
// line a fraction of a pixel sideways with a new noise seed 12 times a second, like Blender's
// Noise modifier with a step; the line never changes width in time.
// Illustrated Ink (light_weight / rim_line = 1): lines swell on the side turned away from the key
// light and thin where it hits; silhouettes that face a light behind the subject turn into a warm
// glowing line ("the light eats the line"); far lines get thinner. The line writes depth so depth of
// field keeps it as sharp as the object it outlines.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_always, skip_vertex_transform, shadows_disabled;

uniform vec4 ink_color : source_color = vec4(0.48, 0.12, 0.12, 1.0);
uniform float width_px = 2.4;       // full line width at 1080p (scales with frame height)
uniform float pressure_min = 0.85;
uniform float boil_px = 0.35;
uniform float boil_fps = 12.0;
uniform float noise_scale = 9.0;
uniform float depth_bias = 0.004;   // pull the line toward the camera (share of distance)
uniform int occ_n = 0;
uniform vec4 occ_c[4];
uniform vec4 occ_r[4];
uniform mat4 to_body = mat4(1.0);
uniform float light_weight = 0.0;   // 1 = Illustrated Ink weight and glow (see above)
uniform float rim_line = 0.0;
uniform float use_global_ink = 0.0; // 1 = take the ink colour from the mood (ill_ink)

global uniform vec3 ill_sun_dir;
global uniform vec3 ill_rim_color;
global uniform vec4 ill_ink;

varying vec3 wpos;
varying vec2 seg_uv;     // x along the segment, y across, in pixels
varying float seg_len;   // segment length, pixels
varying float half_w;    // half line width here, pixels
varying float v_rim;     // 0 = ink, 1 = warm rim-light line

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

// Crossing point on edge (a, b), always computed from the same end so both triangles that
// share the edge get exactly the same point. w = how far along a -> b (for the normal there).
vec4 cross_t(vec3 pa, float ga, vec3 pb, float gb) {
	bool swap = pa.x > pb.x || (pa.x == pb.x && (pa.y > pb.y || (pa.y == pb.y && pa.z > pb.z)));
	vec3 qa = swap ? pb : pa;
	vec3 qb = swap ? pa : pb;
	float fa = swap ? gb : ga;
	float fb = swap ? ga : gb;
	float t = fa / (fa - fb);
	return vec4(mix(qa, qb, t), swap ? 1.0 - t : t);
}

void vertex() {
	vec3 p0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 p1 = (MODEL_MATRIX * vec4(CUSTOM0.xyz, 1.0)).xyz;
	vec3 p2 = (MODEL_MATRIX * vec4(CUSTOM1.zw, CUSTOM2.x, 1.0)).xyz;
	vec3 n0 = MODEL_NORMAL_MATRIX * NORMAL;
	vec3 n1 = MODEL_NORMAL_MATRIX * vec3(CUSTOM0.w, CUSTOM1.xy);
	vec3 n2 = MODEL_NORMAL_MATRIX * CUSTOM2.yzw;
	vec3 eye = CAMERA_POSITION_WORLD;
	float g0 = dot(n0, eye - p0);
	float g1 = dot(n1, eye - p1);
	float g2 = dot(n2, eye - p2);
	bool s0 = g0 > 0.0;
	bool s1 = g1 > 0.0;
	bool s2 = g2 > 0.0;
	seg_uv = vec2(0.0);
	seg_len = 0.0;
	half_w = 0.0;
	v_rim = 0.0;
	wpos = p0;
	if (s0 == s1 && s1 == s2) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0); // no outline here: collapse outside the screen
	} else {
		vec4 ca4;
		vec4 cb4;
		vec3 na;
		vec3 nb;
		if (s0 != s1) {
			ca4 = cross_t(p0, g0, p1, g1);
			na = mix(n0, n1, ca4.w);
			if (s1 != s2) {
				cb4 = cross_t(p1, g1, p2, g2);
				nb = mix(n1, n2, cb4.w);
			} else {
				cb4 = cross_t(p2, g2, p0, g0);
				nb = mix(n2, n0, cb4.w);
			}
		} else {
			ca4 = cross_t(p1, g1, p2, g2);
			na = mix(n1, n2, ca4.w);
			cb4 = cross_t(p2, g2, p0, g0);
			nb = mix(n2, n0, cb4.w);
		}
		vec3 a = ca4.xyz;
		vec3 b = cb4.xyz;
		vec4 va = VIEW_MATRIX * vec4(a, 1.0);
		vec4 vb = VIEW_MATRIX * vec4(b, 1.0);
		va.xyz *= (1.0 - depth_bias);
		vb.xyz *= (1.0 - depth_bias);
		vec4 ca = PROJECTION_MATRIX * va;
		vec4 cb = PROJECTION_MATRIX * vb;
		if (ca.w <= 0.0 || cb.w <= 0.0) {
			POSITION = vec4(2.0, 2.0, 2.0, 1.0);
		} else {
			float px = VIEWPORT_SIZE.y / 1080.0;
			float frame = floor(TIME * boil_fps);
			vec3 seed = frame * vec3(7.13, 3.71, 5.29);
			vec2 sa = (ca.xy / ca.w * 0.5 + 0.5) * VIEWPORT_SIZE;
			vec2 sb = (cb.xy / cb.w * 0.5 + 0.5) * VIEWPORT_SIZE;
			vec2 d = sb - sa;
			float len = length(d);
			vec2 t = len > 1e-4 ? d / len : vec2(1.0, 0.0);
			vec2 nrm = vec2(-t.y, t.x);
			bool at_b = UV.x > 0.5;
			vec3 end_w = at_b ? b : a;
			float pressure = mix(pressure_min, 1.0, vnoise(end_w * noise_scale * 0.5 + 11.0));
			float hw = 0.5 * width_px * px * pressure;
			if (light_weight > 0.0) {
				vec3 n_end = normalize(at_b ? nb : na);
				vec3 L = normalize(ill_sun_dir);
				vec3 V = normalize(eye - end_w);
				float facing = dot(n_end, L);
				float weight = mix(0.72, 1.3, 1.0 - smoothstep(-0.35, 0.45, facing));
				float far = smoothstep(5.0, 18.0, length(eye - end_w));
				hw *= mix(1.0, weight * mix(1.0, 0.62, far), light_weight);
				float back = smoothstep(-0.35, 0.6, -dot(L, V));
				v_rim = rim_line * back * smoothstep(0.12, 0.5, facing);
			}
			float jitter = (vnoise(end_w * noise_scale + seed) - 0.5) * 2.0 * boil_px * px;
			float reach = hw + 1.0;
			vec2 s = (at_b ? sb : sa) + nrm * jitter + t * (at_b ? reach : -reach) + nrm * UV.y * reach;
			vec4 c = at_b ? cb : ca;
			POSITION = vec4(s / VIEWPORT_SIZE * 2.0 - 1.0, c.z / c.w, 1.0);
			seg_uv = vec2(at_b ? len + reach : -reach, UV.y * reach);
			seg_len = len;
			half_w = hw;
			wpos = end_w;
		}
	}
}

void fragment() {
	for (int i = 0; i < 4; i++) {
		if (i >= occ_n) break;
		vec3 q = (((to_body * vec4(wpos, 1.0)).xyz) - occ_c[i].xyz) / occ_r[i].xyz;
		if (dot(q, q) < 1.0) discard; // inside the body: no line here
	}
	float u = seg_uv.x;
	float d = length(vec2(max(0.0, max(-u, u - seg_len)), seg_uv.y));
	float a = clamp(half_w - d + 0.5, 0.0, 1.0);
	if (a <= 0.0) discard;
	vec3 ink = mix(ink_color.rgb, ill_ink.rgb, use_global_ink);
	ALBEDO = mix(ink, ill_rim_color, clamp(v_rim, 0.0, 1.0));
	ALPHA = ink_color.a * a;
}

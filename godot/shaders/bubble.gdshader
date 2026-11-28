shader_type spatial;
// Comic reaction bubble over a character's head (CLAUDE.md section 25; after DOGWALK's emote
// bubbles, Blender Studio, CC-BY 4.0). It always faces the camera.
// - The bubble is a paper disc with a tail, outlined in the mood's ink.
// - The icon inside is one of ten shapes, each drawn from signed distance functions: no bitmaps.
// - Icons animate from `age` (seconds since the bubble appeared), so scrubbing replays them exactly.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque, skip_vertex_transform;

uniform int icon = 0;      // 0 ! · 1 ? · 2 heart · 3 sweat · 4 anger · 5 dizzy · 6 dots · 7 idea · 8 note · 9 sparkle
uniform float age = 0.0;
uniform float tilt = 0.0;
uniform float side = 1.0;  // tail toward the head: +1 = lower left, -1 = lower right
uniform vec4 paper : source_color = vec4(1.0, 0.985, 0.95, 1.0);
uniform vec4 tint : source_color = vec4(0.886, 0.345, 0.243, 1.0);

global uniform vec4 ill_ink;

varying vec2 v_p;

float dot2(vec2 v) { return dot(v, v); }

float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float sd_triangle(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
	vec2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
	vec2 v0 = p - p0, v1 = p - p1, v2 = p - p2;
	vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float s = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
					 vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
					 vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// arc of radius ra around +Y with half-aperture given by sc = (sin, cos), thickness rb
float sd_arc(vec2 p, vec2 sc, float ra, float rb) {
	p.x = abs(p.x);
	return ((sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : abs(length(p) - ra)) - rb;
}

float sd_heart(vec2 p) {
	p.x = abs(p.x);
	if (p.y + p.x > 1.0) {
		return sqrt(dot2(p - vec2(0.25, 0.75))) - sqrt(2.0) / 4.0;
	}
	return sqrt(min(dot2(p - vec2(0.0, 1.0)), dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

float sd_uneven_capsule(vec2 p, float r1, float r2, float h) {
	p.x = abs(p.x);
	float b = (r1 - r2) / h;
	float a = sqrt(1.0 - b * b);
	float k = dot(p, vec2(-b, a));
	if (k < 0.0) return length(p) - r1;
	if (k > a * h) return length(p - vec2(0.0, h)) - r2;
	return dot(p, vec2(a, b)) - r1;
}

vec2 rot(vec2 p, float a) {
	float c = cos(a), s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float icon_sdf(vec2 q) {
	float t = age;
	if (icon == 0) {                       // ! (shakes as it lands)
		q = rot(q, sin(t * 30.0) * 0.12 * exp(-t * 5.0));
		return min(sd_uneven_capsule(q - vec2(0.0, 0.03), 0.075, 0.115, 0.3), length(q - vec2(0.0, -0.22)) - 0.095);
	}
	if (icon == 1) {                       // ? (a hook open at the lower left, a stem and a dot)
		q = rot(q, sin(t * 4.0) * 0.08);
		float hook = sd_arc(rot(q - vec2(0.0, 0.17), 0.26), vec2(0.819, -0.574), 0.165, 0.058);
		float stem = sd_segment(q, vec2(0.106, 0.044), vec2(0.0, -0.04)) - 0.058;
		stem = min(stem, sd_segment(q, vec2(0.0, -0.04), vec2(0.0, -0.08)) - 0.058);
		return min(min(hook, stem), length(q - vec2(0.0, -0.26)) - 0.075);
	}
	if (icon == 2) {                       // heart (beats)
		float beat = 1.0 + 0.12 * pow(max(0.0, sin(t * 9.0)), 6.0);
		vec2 h = (q - vec2(0.0, -0.3)) / (0.62 * beat);
		return sd_heart(h) * 0.62 * beat;
	}
	if (icon == 3) {                       // sweat drop (slides down a little)
		vec2 d = q - vec2(0.0, -0.12 - min(t, 1.2) * 0.04);
		return sd_uneven_capsule(d, 0.2, 0.025, 0.42);
	}
	if (icon == 4) {                       // anger mark: four bent ticks (throbs)
		float s = 1.0 + 0.1 * sin(t * 14.0);
		float d = 1e5;
		for (int k = 0; k < 4; k++) {
			vec2 r = rot(q / s, float(k) * 1.5708);
			vec2 c = r - vec2(0.25, 0.25);
			d = min(d, sd_arc(rot(c, 2.356), vec2(0.766, 0.643), 0.17, 0.058));
		}
		return d * s;
	}
	if (icon == 5) {                       // dizzy spiral (spins)
		vec2 r = rot(q, -t * 5.0);
		float rr = length(r);
		float a = atan(r.y, r.x);
		float k = 0.11;
		float tt = (rr - k * (a + 3.1416) / 6.2832) / k;
		float d = (abs(fract(tt) - 0.5) * k) - 0.026;
		return max(d, rr - 0.36);
	}
	if (icon == 6) {                       // ... (dots appear one by one)
		float d = 1e5;
		for (int k = 0; k < 3; k++) {
			float appear = clamp((t - float(k) * 0.18) * 6.0, 0.0, 1.0);
			float hop = sin(clamp((t - float(k) * 0.18) * 6.0, 0.0, 3.1416)) * 0.05;
			d = min(d, length(q - vec2(-0.25 + float(k) * 0.25, -0.03 + hop)) - 0.075 * appear);
		}
		return d;
	}
	if (icon == 7) {                       // idea bulb with three glints
		float bulb = length(q - vec2(0.0, 0.06)) - 0.17;
		float neck = sd_segment(q, vec2(-0.045, -0.16), vec2(0.045, -0.16)) - 0.05;
		float d = smin(bulb, neck, 0.07);
		float glint = 1e5;
		for (int k = 0; k < 3; k++) {
			float a = 0.75 + float(k) * 0.82;
			vec2 dir = vec2(cos(a), sin(a));
			float pulse = 0.025 * sin(t * 8.0 + float(k) * 2.0);
			glint = min(glint, sd_segment(q - vec2(0.0, 0.06), dir * (0.26 + pulse), dir * (0.34 + pulse)) - 0.026);
		}
		return min(d, glint);
	}
	if (icon == 8) {                       // music note (bobs)
		vec2 r = q - vec2(0.0, sin(t * 6.0) * 0.03);
		vec2 hq = rot(r - vec2(-0.08, -0.2), 0.45) / vec2(1.0, 0.72);
		float head = (length(hq) - 0.13) * 0.72;
		float stem = sd_segment(r, vec2(0.04, -0.18), vec2(0.04, 0.3)) - 0.035;
		float flag = sd_segment(r, vec2(0.04, 0.3), vec2(0.2, 0.1)) - 0.035;
		return min(head, min(stem, flag));
	}
	// sparkle: a four-point star and a small one (twinkle)
	float tw = 1.0 + 0.15 * sin(t * 10.0);
	vec2 a1 = abs(q / tw);
	float s1 = (sqrt(a1.x) + sqrt(a1.y) - sqrt(0.36)) * 0.42 * tw;
	vec2 a2 = abs((q - vec2(0.24, 0.22)) / (0.4 * (2.0 - tw)));
	float s2 = (sqrt(a2.x) + sqrt(a2.y) - sqrt(0.36)) * 0.42 * 0.4;
	return min(s1, s2);
}

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sc = length(MODEL_MATRIX[0].xyz);
	vec2 v = rot(VERTEX.xy, tilt);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 wp = origin + (right * v.x + up * v.y) * sc;
	// pull toward the camera a little so the head never cuts into the bubble
	wp += normalize(CAMERA_POSITION_WORLD - wp) * 0.08 * sc;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));
	v_p = VERTEX.xy * 2.0;
}

void fragment() {
	vec2 p = v_p;
	float body = length(p - vec2(0.0, 0.14)) - 0.7;
	float tail = sd_triangle(p, vec2(-0.36 * side, -0.38), vec2(-0.08 * side, -0.5), vec2(-0.6 * side, -0.94));
	float d = smin(body, tail, 0.1);
	float aa = fwidth(d) * 0.75;
	float w = 0.055;
	float outside = smoothstep(-aa, aa, d - w);
	if (outside >= 0.999) {
		discard;
	}
	vec3 col = paper.rgb;
	col = mix(col, ill_ink.rgb, smoothstep(-aa, aa, d + w));          // bubble outline
	float di = icon_sdf(p - vec2(0.0, 0.14));
	float ai = fwidth(di) * 0.75;
	col = mix(col, ill_ink.rgb, 1.0 - smoothstep(-ai, ai, di - 0.032));  // icon outline
	col = mix(col, tint.rgb, 1.0 - smoothstep(-ai, ai, di));             // icon fill
	ALBEDO = col;
	ALPHA = 1.0 - outside;
}

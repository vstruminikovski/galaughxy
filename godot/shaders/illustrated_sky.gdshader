shader_type sky;
// Painted sky for Illustrated Ink (CLAUDE.md section 24).
// - A soft gradient from horizon to zenith, with a warm glow around the sun near the horizon.
// - A pale haze band on the horizon and the sun disc.
// - Flat two-tone clouds with crisp edges: lit on the side that faces the sun, cool underneath.
// Every colour comes from the mood (res://data/moods.json) and drifts with the studio clock,
// so movie exports stay deterministic.

uniform vec3 zenith : source_color = vec3(0.24, 0.31, 0.59);
uniform vec3 horizon : source_color = vec3(0.94, 0.65, 0.5);        // horizon toward the sun
uniform vec3 horizon_away : source_color = vec3(0.72, 0.64, 0.83);  // horizon away from the sun
uniform vec3 ground : source_color = vec3(0.17, 0.2, 0.36);
uniform vec3 sun_disc : source_color = vec3(1.0, 0.86, 0.68);
uniform vec3 sun_glow : source_color = vec3(1.0, 0.62, 0.36);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.77, 0.63);
uniform vec3 cloud_shade : source_color = vec3(0.49, 0.5, 0.73);
uniform float cloud_cover = 0.42;
uniform float haze = 0.45;
uniform float sun_size = 0.035;
uniform float glow_size = 8.0;
uniform float exposure = 1.0;
uniform float flash = 0.0;

global uniform float ill_time;

float h21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * n2(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 L = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : normalize(vec3(0.4, 0.25, -0.9));
	float h = d.y;
	float up = clamp(h, 0.0, 1.0);
	float toward = smoothstep(-0.3, 1.0, dot(normalize(d.xz + vec2(1e-5)), normalize(L.xz + vec2(1e-5))));
	vec3 hor = mix(horizon_away, horizon, toward);
	vec3 col = mix(hor, zenith, pow(smoothstep(0.0, 0.42, up), 0.75));
	// warm glow around the sun, strongest near the horizon
	float sd = dot(d, L);
	float g = pow(clamp(sd * 0.5 + 0.5, 0.0, 1.0), glow_size);
	col = mix(col, sun_glow, clamp(g * (1.0 - smoothstep(0.0, 0.6, up)) * 0.9, 0.0, 1.0));
	// pale haze on the horizon, the ground below it
	col = mix(col, mix(hor, vec3(1.0), 0.2), haze * (1.0 - smoothstep(0.0, 0.07, abs(h))));
	if (h < 0.0) {
		col = mix(col, ground, smoothstep(0.0, 0.3, -h));
	}
	// painted clouds: flat lit and shaded shapes with crisp edges
	float cover = 0.0;
	if (h > 0.0 && cloud_cover > 0.001) {
		// big, slow cumulus: low frequency shapes, flattened toward the horizon
		vec2 uv = d.xz / (h + 0.2) * 0.32 + vec2(ill_time * 0.002, ill_time * 0.0008);
		float n = fbm(uv);
		float th = 1.0 - cloud_cover;
		cover = smoothstep(th, th + 0.01, n) * smoothstep(0.03, 0.2, h);
		vec2 ts = normalize(L.xz + vec2(1e-4)) * 0.06;
		float nt = fbm(uv + ts);
		float lit = smoothstep(-0.006, 0.006, n - nt + 0.012);
		vec3 cc = mix(cloud_shade, cloud_lit, lit);
		// clouds near the sun catch its colour
		cc = mix(cc, sun_glow, clamp(g * 0.55, 0.0, 0.6) * lit);
		col = mix(col, cc, cover);
	}
	float disc = smoothstep(cos(sun_size * 1.12), cos(sun_size), sd);
	col = mix(col, sun_disc * 1.8, disc * (1.0 - cover * 0.9));
	COLOR = col * exposure + vec3(flash);
}

shader_type canvas_item;
// Illustrated Ink finishing pass (CLAUDE.md section 24), drawn over the 3D view under the HUD:
// - a split-tone grade: shadows lean to the mood's cool tint, lights to its warm tint
// - a soft vignette
// - fine monochrome film grain that changes 12 times a second (from the studio clock)

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.04;
uniform float vignette = 0.22;
uniform vec3 shadow_tint = vec3(0.32, 0.37, 0.66);   // overlay colours: 0.5 = neutral
uniform vec3 light_tint = vec3(0.62, 0.55, 0.47);
uniform float grade = 0.2;

global uniform float ill_time;

float h12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

vec3 overlay(vec3 a, vec3 b) {
	return mix(2.0 * a * b, 1.0 - 2.0 * (1.0 - a) * (1.0 - b), step(0.5, a));
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(c, overlay(c, shadow_tint), grade * (1.0 - smoothstep(0.05, 0.6, lum)));
	c = mix(c, overlay(c, light_tint), grade * smoothstep(0.4, 1.0, lum));
	vec2 q = (SCREEN_UV - 0.5) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float v = smoothstep(0.3, 1.0, length(q) * 1.1) * vignette;
	c = mix(c, c * vec3(0.78, 0.8, 0.92), v);
	float frame = floor(ill_time * 12.0);
	float g = h12(FRAGCOORD.xy + frame * vec2(37.0, 17.0)) + h12(FRAGCOORD.yx * 1.3 + frame * vec2(11.0, 53.0)) - 1.0;
	c += g * grain * (1.0 - lum * 0.55);
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}

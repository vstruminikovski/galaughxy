// Shared by the Illustrated Ink surface and ink shaders (CLAUDE.md sections 24 and 25).
// Wind and the near-lens dissolve follow DOGWALK (Blender Studio, CC-BY 4.0). The wind is smooth
// here rather than stepped. Both shaders displace the same rest positions with the same function,
// so the ink stays glued to a swaying leaf.

global uniform float ill_wind;        // sway at the top of a plant, metres (0 = still air)
global uniform float ill_near_fade;   // geometry closer than this to the lens dissolves (0 = off)

// Leaves sway in layered gusts. wp = rest world position, weight 0..1, t = studio clock.
vec3 ill_wind_offset(vec3 wp, float weight, float t) {
	if (ill_wind <= 0.0 || weight <= 0.0) {
		return vec3(0.0);
	}
	float h = clamp(wp.y / 1.6, 0.0, 1.0);
	float ph = dot(wp.xz, vec2(0.71, 0.53));
	float s = sin(t * 1.35 + ph) * 0.6 + sin(t * 2.9 + ph * 1.9) * 0.28 + sin(t * 6.1 + ph * 3.7 + wp.y * 4.0) * 0.12;
	float c = cos(t * 1.1 + ph * 1.3) * 0.5;
	return vec3(0.86 * s, 0.0, 0.5 * c) * ill_wind * weight * h;
}

// How green a (raw sRGB) colour is: leaves sway, trunks and pots stay put.
float ill_leafiness(vec3 c) {
	return smoothstep(0.02, 0.06, c.g - max(c.r, c.b));
}

// 4x4 ordered dither threshold for this pixel.
float ill_bayer4(vec2 fc) {
	int x = int(mod(fc.x, 4.0));
	int y = int(mod(fc.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

// True when this fragment should dissolve because it sits right in front of the lens.
bool ill_near_discard(float dist, vec2 fc) {
	if (ill_near_fade <= 0.0) {
		return false;
	}
	float k = (dist - ill_near_fade * 0.35) / (ill_near_fade * 0.65);
	return k < 1.0 && k < ill_bayer4(fc);
}

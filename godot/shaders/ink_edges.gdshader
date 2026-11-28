shader_type spatial;
// Ink for hard-edged, faceted meshes: the converted 0 A.D. buildings (InkEdges.gd).
// Each quad carries one mesh edge (both ends) and the normals of the two faces that meet there.
// - Silhouette: one face turned toward the camera and the other away. Drawn bold.
// - Crease: a sharp fold (over ~35 degrees) on the visible side. Drawn thin, like an architect's line.
// - Open edge: the border of an open sheet. Drawn like a crease.
// Lines are constant-width screen segments with round caps, still (no boil), and write depth like the
// contour ink, so depth of field keeps them as sharp as their walls.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_always, skip_vertex_transform, shadows_disabled;

#include "res://shaders/ill_common.gdshaderinc"

uniform vec4 ink_color : source_color = vec4(0.11, 0.1, 0.15, 1.0);
uniform float width_px = 2.8;       // silhouettes, at 1080p
uniform float crease_px = 1.3;      // creases and open edges
uniform float depth_bias = 0.006;
uniform float use_global_ink = 1.0;
uniform float light_weight = 1.0;

global uniform vec4 ill_ink;
global uniform vec3 ill_sun_dir;

varying vec3 wpos;
varying vec2 seg_uv;
varying float seg_len;
varying float half_w;
varying float v_alpha;

void vertex() {
	vec3 a = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 b = (MODEL_MATRIX * vec4(CUSTOM0.xyz, 1.0)).xyz;
	vec3 na = normalize(MODEL_NORMAL_MATRIX * CUSTOM1.xyz);
	vec3 nb = normalize(MODEL_NORMAL_MATRIX * CUSTOM2.xyz);
	bool two = CUSTOM1.w > 0.5;
	bool crease = CUSTOM0.w > 0.5;
	vec3 eye = CAMERA_POSITION_WORLD;
	vec3 mid = (a + b) * 0.5;
	float fa = dot(na, eye - mid);
	float fb = two ? dot(nb, eye - mid) : -1.0;
	bool silhouette = two && ((fa > 0.0) != (fb > 0.0));
	bool show = silhouette || ((crease || !two) && (fa > 0.0 || fb > 0.0));
	seg_uv = vec2(0.0);
	seg_len = 0.0;
	half_w = 0.0;
	v_alpha = 0.0;
	wpos = a;
	if (!show) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	} else {
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
			vec2 sa = (ca.xy / ca.w * 0.5 + 0.5) * VIEWPORT_SIZE;
			vec2 sb = (cb.xy / cb.w * 0.5 + 0.5) * VIEWPORT_SIZE;
			vec2 d = sb - sa;
			float len = length(d);
			vec2 t = len > 1e-4 ? d / len : vec2(1.0, 0.0);
			vec2 nrm = vec2(-t.y, t.x);
			bool at_b = UV.x > 0.5;
			vec3 end_w = at_b ? b : a;
			float hw = 0.5 * (silhouette ? width_px : crease_px) * px;
			if (light_weight > 0.0) {
				float facing = dot(normalize(na + nb), normalize(ill_sun_dir));
				float far = smoothstep(6.0, 30.0, length(eye - end_w));
				hw *= mix(0.85, 1.2, 1.0 - smoothstep(-0.3, 0.4, facing)) * mix(1.0, 0.55, far);
			}
			float reach = hw + 1.0;
			vec2 s = (at_b ? sb : sa) + t * (at_b ? reach : -reach) + nrm * UV.y * reach;
			vec4 c = at_b ? cb : ca;
			POSITION = vec4(s / VIEWPORT_SIZE * 2.0 - 1.0, c.z / c.w, 1.0);
			seg_uv = vec2(at_b ? len + reach : -reach, UV.y * reach);
			seg_len = len;
			half_w = hw;
			v_alpha = 1.0;
			wpos = end_w;
		}
	}
}

void fragment() {
	if (ill_near_discard(length(wpos - CAMERA_POSITION_WORLD), FRAGCOORD.xy)) {
		discard;
	}
	float u = seg_uv.x;
	float d = length(vec2(max(0.0, max(-u, u - seg_len)), seg_uv.y));
	float a = clamp(half_w - d + 0.5, 0.0, 1.0) * v_alpha;
	if (a <= 0.0) {
		discard;
	}
	ALBEDO = mix(ink_color.rgb, ill_ink.rgb, use_global_ink);
	ALPHA = ink_color.a * a;
}

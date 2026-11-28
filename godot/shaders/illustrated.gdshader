shader_type spatial;
// Illustrated Ink surface (CLAUDE.md section 24): the look of a hand-inked, flat-coloured
// illustration lit at dusk.
// - One warm key light over a cool ambient. Shadow sides take the mood's blue-violet tint
//   (ambient light); lit sides sit on the local colour. The terminator and cast shadows are
//   crisp, so every form reads as two flat tones.
// - A warm rim on edges that face the light, strongest when the light is behind the subject.
// - Sparse hand-drawn hatch strokes gather in the shadows, with a few on lit cloth.
//   * Strokes belong to the object (object space), so they never swim when it moves.
//   * They stay about 10 px apart on screen at any distance: stroke families an octave apart
//     fade into each other, so there is no moire far away and no blow-up close in.
//   * Each stroke tapers at both ends.
render_mode cull_back;
//VARIANT

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vcol = false;       // vertex / MultiMesh instance colours (sRGB) as the local colour
uniform float hatch_amt = 1.0;       // shadow hatching strength
uniform float texture_amt = 0.3;     // sparse strokes on lit areas (cloth, fur)
uniform float stroke_len = 0.045;    // typical stroke length in metres (object scale)
uniform float gloss = 0.0;           // toon highlight
uniform float stroke_seed = 0.0;

global uniform vec3 ill_sun_dir;     // toward the key light, world space
global uniform vec4 ill_ink;         // ink colour (linear rgb) and stroke opacity
global uniform float ill_rim;        // rim light strength
global uniform float ill_hatch;      // global hatch strength (0 = off)
global uniform float ill_time;       // studio clock (deterministic)
global uniform float ill_boil;       // stroke boil (0 = still)

varying vec3 v_obj;                  // object-space position in metres

const float SPACING_PX = 11.0;                // screen distance between strokes at 1080p
const vec3 D1 = vec3(-0.596, 0.776, 0.206);   // "/" strokes
const vec3 A1 = vec3(0.793, 0.609, 0.0);
const vec3 D2 = vec3(0.856, 0.453, 0.249);    // cross strokes for deep shadow
const vec3 A2 = vec3(-0.468, 0.884, 0.0);

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

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

// One family of strokes across `x` (metres along the stroke normal), `y` along the strokes.
// fw = metres per pixel across the strokes (from fwidth, taken in uniform control flow).
float strokes(float x, float y, float fw, float coverage, float seed, float px) {
	fw = max(fw, 1e-6);
	float lvl = log2(fw * SPACING_PX * px / 0.0005); // the octave whose spacing is ~SPACING_PX
	float k = floor(lvl);
	float blend = lvl - k;
	float s = 0.0005 * exp2(k);                   // stroke spacing at this octave, metres
	float boil = (hash13(vec3(floor(ill_time * 12.0), seed, 3.1)) - 0.5) * 0.35 * ill_boil;
	float c = x / s + boil;
	float i = floor(c + 0.5);
	float d_px = abs(c - i) * s / fw;             // distance to the stroke centre, pixels
	float fade = mod(i, 2.0) > 0.5 ? 1.0 - blend : 1.0;   // in-between strokes fade out with distance
	// a line's identity is its world offset (i * s), so neighbouring octaves agree on the breaks
	float n = vnoise(vec3(y / stroke_len + seed * 7.0, i * s * 37.0, seed * 1.7));
	float keep = smoothstep(1.0 - coverage - 0.08, 1.0 - coverage + 0.08, n);
	float hw = (0.38 + 0.55 * keep) * px;         // half width: tapers toward both stroke ends
	return clamp(hw - d_px + 0.5, 0.0, 1.0) * fade * step(0.03, keep);
}

void vertex() {
	v_obj = VERTEX * length(MODEL_MATRIX[0].xyz);
}

void fragment() {
	vec3 base = albedo.rgb;
	if (use_vcol) {
		base *= to_linear(COLOR.rgb);
	}
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float ndl = dot(nw, normalize(ill_sun_dir));
	float dark = 1.0 - smoothstep(-0.2, 0.24, ndl);
	// strokes gather just inside the terminator (the half-tone band), thin out in deep shadow
	float band = exp(-pow((ndl + 0.04) / 0.2, 2.0));
	float px = VIEWPORT_SIZE.y / 1080.0;
	float dist = length(VERTEX);
	// stroke coordinates and their screen derivatives (uniform control flow)
	float x1 = dot(v_obj, D1);
	float y1 = dot(v_obj, A1);
	float x2 = dot(v_obj, D2);
	float y2 = dot(v_obj, A2);
	float fw1 = fwidth(x1);
	float fw2 = fwidth(x2);
	float amt = ill_hatch * hatch_amt * (1.0 - smoothstep(16.0, 34.0, dist));
	float cov1 = amt * (texture_amt * 0.5 * (1.0 - dark) + 0.34 * band + 0.1 * dark);
	float cov2 = amt * 0.16 * smoothstep(0.85, 1.0, dark) * step(0.01, texture_amt);
	float h = strokes(x1, y1, fw1, cov1, stroke_seed, px);
	h = max(h, strokes(x2, y2, fw2, cov2, stroke_seed + 3.7, px));
	h *= step(0.002, amt);
	float op = ill_ink.a * mix(0.5, 1.0, dark);
	ALBEDO = mix(base, ill_ink.rgb, h * op);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
#ifdef USE_ALPHA
	ALPHA = albedo.a;
#endif
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float sh = smoothstep(0.3, 0.7, ATTENUATION);            // crisp cast shadows
	float lit = smoothstep(-0.01, 0.05, ndl) * sh;            // crisp terminator
	vec3 lc = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += lit * lc;
	if (LIGHT_IS_DIRECTIONAL) {
		// warm rim on silhouettes that face the light; back light makes it strongest
		float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float back = smoothstep(-0.4, 0.7, -dot(LIGHT, VIEW));
		float rim = smoothstep(0.5, 0.64, fres) * smoothstep(0.0, 0.3, ndl) * mix(0.3, 1.0, back) * sh;
		DIFFUSE_LIGHT += rim * ill_rim * lc * 1.1;
		SPECULAR_LIGHT += rim * ill_rim * lc * 0.16;
	}
	if (gloss > 0.0) {
		vec3 hv = normalize(LIGHT + VIEW);
		float s = smoothstep(0.984, 0.99, dot(NORMAL, hv)) * gloss * sh;
		SPECULAR_LIGHT += s * lc * 0.8;
	}
}

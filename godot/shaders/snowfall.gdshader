shader_type spatial;
// Falling snow for the Snowfall mood (CLAUDE.md section 25; after DOGWALK's snow, Blender Studio,
// CC-BY 4.0). Every flake is one instance of a small quad, placed entirely on the GPU:
// - its height falls with the studio clock, and it drifts sideways in a slow sway
// - it wraps inside a box that follows the camera, so snow is always around the lens
// - nothing is stored or updated on the CPU, and the same second always shows the same flakes
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque, skip_vertex_transform;

global uniform float ill_time;
global uniform float ill_snow;

uniform vec3 box = vec3(16.0, 9.0, 16.0);
uniform vec4 flake_color : source_color = vec4(0.97, 0.98, 1.0, 0.92);

varying float v_alpha;

float h1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	float id = float(INSTANCE_ID);
	vec3 seed = vec3(h1(id), h1(id + 17.13), h1(id + 33.71));
	float speed = mix(0.32, 0.75, h1(id + 5.31));
	vec3 p = seed * box;
	p.y -= ill_time * speed;
	p.x += sin(ill_time * mix(0.5, 1.3, h1(id + 2.1)) + id) * 0.22;
	p.z += cos(ill_time * mix(0.4, 1.1, h1(id + 9.3)) + id * 1.7) * 0.22;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 rel = mod(p - cam + box * 0.5, box) - box * 0.5;
	vec3 wp = cam + rel;
	float s = mix(0.55, 1.35, h1(id + 7.7));
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = wp + (right * VERTEX.x + up * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
	// thin the flakes with the snow amount; fade the ones right at the lens or far away
	v_alpha = step(h1(id + 3.3), ill_snow) * (1.0 - smoothstep(6.0, 8.0, length(rel))) * smoothstep(0.25, 0.6, length(rel));
	if (v_alpha <= 0.0) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	}
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float a = 1.0 - smoothstep(0.55, 1.0, length(q));
	if (a * v_alpha < 0.02) {
		discard;
	}
	ALBEDO = flake_color.rgb;
	ALPHA = a * v_alpha * flake_color.a;
}

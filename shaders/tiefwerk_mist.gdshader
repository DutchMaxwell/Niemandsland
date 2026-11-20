shader_type spatial;
render_mode cull_disabled, depth_draw_never, specular_disabled;
// Low ground mist of a generated board (BoardgenMist): three translucent planes, one per instance layer (INSTANCE_CUSTOM.x), a
// drifting noise cloud on each. The density comes from a one-texel-per-cell texture (R = thickness, G = toxic), filtered, so the mist
// pools in wells and over sumps and thins out at a tier wall. It fades where it meets geometry (soft depth), and stays thin.

uniform sampler2D cells : filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec2 board_in = vec2(48.0);
uniform float strength = 0.3;

varying vec2 bpos;   // board inches off the centre
varying flat float layer;

const float IN = 0.0254;

void vertex() {
	bpos = VERTEX.xz / IN;
	layer = INSTANCE_CUSTOM.x;
}

float h21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = bpos / board_in + 0.5;
	vec4 c = texture(cells, clamp(uv, 0.0, 1.0));
	float edge = smoothstep(0.0, 0.04, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));   // thins out over the table edge
	// Each layer drifts its own way, a slow warp makes it waft instead of slide.
	vec2 wind = vec2(0.05 + 0.02 * layer, 0.02 - 0.015 * layer) * TIME;
	vec2 q = bpos * 0.12 + wind + layer * 7.3;
	q += (vec2(vnoise(q * 0.8 + TIME * 0.03), vnoise(q * 0.8 + 31.0 - TIME * 0.025)) - 0.5) * 1.1;
	float n = 0.55 * vnoise(q) + 0.3 * vnoise(q * 2.3 + 5.0) + 0.15 * vnoise(q * 5.1 + 11.0);
	float cloud = smoothstep(0.5, 0.74, n);
	float lower = (1.0 - 0.28 * layer) * (1.0 - 0.5 * c.g * layer * 0.5);   // the layer at the ankles is the thickest; over a sump the mist hugs the liquid
	float a = cloud * lower * strength * edge * (0.4 + 0.6 * c.r);   // sumps and wells run thicker
	// Soft depth: no hard line where the plane meets a wall, a crate or a base.
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	a *= smoothstep(0.0, 0.006, -up.z / up.w + VERTEX.z);
	if (a < 0.004) {
		discard;
	}
	ALBEDO = mix(vec3(0.52, 0.58, 0.60), vec3(0.40, 0.80, 0.28), c.g * 0.8);
	EMISSION = vec3(0.5, 1.0, 0.3) * c.g * cloud * 0.05;   // over a sump the mist takes up a little of its glow
	ROUGHNESS = 1.0;
	ALPHA = clamp(a, 0.0, 0.5);
}

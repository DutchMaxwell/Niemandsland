shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// Steam from a wall vent (BoardgenSteam): PUFFS round sprites per vent, each on its own cycle (INSTANCE_CUSTOM: x = the vent's phase,
// y = the puff's place in the cycle, zw = the way out from the wall). A puff is born at the grille, rises, drifts out, swells and fades
// (billowing, not a ribbon). Sprites always face the camera, so a plume is never edge-on. Lit by the wall lamps near it (a warm backlight
// when a lamp stands behind it). Soft depth where a puff meets the wall, thinner as the camera comes close.

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 board_origin;
uniform vec3 lamps[8];   // board-local metres; unused slots far away

varying vec3 centre;   // world position of the puff
varying vec2 info;     // x = phase, y = life 0..1
varying float view_depth;

const float IN = 0.0254;

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float t = fract(TIME * 0.16 + phase + INSTANCE_CUSTOM.y);
	vec2 out_dir = INSTANCE_CUSTOM.zw;
	vec2 side = vec2(-out_dir.y, out_dir.x);
	vec3 c = MODEL_MATRIX[3].xyz;
	c.xz += out_dir * (0.15 + 1.7 * t) * IN + side * sin(TIME * 0.7 + phase * 6.28 + t * 3.5) * 0.45 * t * IN;
	c.y += (0.1 + 5.2 * pow(t, 0.8)) * IN;
	float size = mix(0.8, 3.0, pow(t, 0.6)) * IN;
	vec3 world = c + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * size;
	vec4 v = VIEW_MATRIX * vec4(world, 1.0);
	view_depth = -v.z;
	centre = c;
	info = vec2(phase, t);
	POSITION = PROJECTION_MATRIX * v;
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
	float t = info.y;
	vec2 q = UV * 2.0 - 1.0;
	// A lumpy, billowing edge: noise eats into the disc, more as the puff ages.
	float n = 0.6 * vnoise(q * 2.2 + info.x * 17.0 + t * 1.6) + 0.4 * vnoise(q * 4.6 - info.x * 9.0 - t);
	float blob = smoothstep(1.0, 0.15, length(q) + (n - 0.5) * (0.7 + 0.5 * t));
	float a = blob * smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.45, 1.0, t)) * 0.6;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	a *= smoothstep(0.0, 0.008, -up.z / up.w - view_depth) * smoothstep(0.04, 0.16, view_depth);
	if (a < 0.004) {
		discard;
	}
	vec3 col = vec3(0.46, 0.50, 0.53) * (0.75 + 0.25 * (q.y * 0.5 + 0.5)) * (0.85 + 0.3 * n);   // paler on top, lumpy inside
	vec3 view_dir = normalize(centre - INV_VIEW_MATRIX[3].xyz);
	for (int i = 0; i < 8; i++) {
		vec3 to_lamp = board_origin + lamps[i] - centre;
		float att = pow(clamp(1.0 - length(to_lamp) / 0.4, 0.0, 1.0), 2.0);
		float back = pow(max(dot(normalize(to_lamp), view_dir), 0.0), 2.0);   // the lamp behind the puff: the rim lights up
		col += vec3(1.0, 0.6, 0.25) * att * (0.3 + 1.3 * back);
	}
	ALBEDO = col;
	ALPHA = a;
}

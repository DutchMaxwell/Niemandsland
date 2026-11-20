shader_type spatial;
render_mode cull_disabled, depth_draw_never, specular_disabled;
// Low ground mist of a generated board (BoardgenMist): three translucent planes, one per instance layer (INSTANCE_CUSTOM.x), a
// drifting noise cloud on each. The density comes from a one-texel-per-cell texture (R = thickness, G = toxic), filtered, so the mist
// pools in wells and over sumps and thins out at a tier wall. It fades where it meets geometry (soft depth), and stays thin.

uniform sampler2D cells : filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec2 board_in = vec2(48.0);
uniform float strength = 0.5;

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
	// Wisps, not a film: each layer drifts along its own wind and is stretched along it (tendrils), and a warp curls them as they drift.
	float ang = 0.35 + 0.9 * layer;
	vec2 wdir = vec2(cos(ang), sin(ang));
	vec2 p = bpos * 0.19 + wdir * TIME * (0.035 + 0.012 * layer) + layer * 7.3;
	p += (vec2(vnoise(p * 0.7 + TIME * 0.02), vnoise(p * 0.7 + 31.0 - TIME * 0.018)) - 0.5) * 1.7;
	vec2 pr = vec2(dot(p, wdir) * 0.7, dot(p, vec2(-wdir.y, wdir.x)) * 1.2);
	float n = 0.55 * vnoise(pr) + 0.3 * vnoise(pr * 2.1 + 5.0) + 0.15 * vnoise(pr * 4.3 + 11.0);
	n += 0.07 * pow(1.0 - abs(2.0 * vnoise(pr * vec2(0.8, 2.0) + 3.0) - 1.0), 2.0) - 0.02;   // faint filaments along the wind (never a hard streak)
	// Where the mist is thin (an open street) only the peaks of the noise show, so most of the floor stays clear; where it is thick (against
	// a wall, in a well, over a sump or in front of a vent) most of it does.
	float thr = mix(0.60, 0.50, c.r) + 0.04 * layer;
	float cloud = pow(smoothstep(thr, thr + 0.2, n), 1.6);   // soft shoulders, a core that thickens: no flat plateau
	float a = cloud * strength * (0.5 + 0.5 * c.r) * (1.0 - 0.2 * layer) * edge;   // the layer at the ankles is the thickest
	a *= 1.0 - 0.6 * c.g;   // over a sump and round it the mist is thinner: it must not hide the liquid (a feathered cap, no hard streak)
	// Soft depth: no hard line where the plane meets a wall, a crate or a base.
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	a *= smoothstep(0.0, 0.014, -up.z / up.w + VERTEX.z);   // wide: the plane meets the sump kerb and the walls without a hard line
	if (a < 0.004) {
		discard;
	}
	ALBEDO = mix(vec3(0.40, 0.46, 0.49), vec3(0.30, 0.52, 0.30), c.g * 0.85);   // cool grey, grey-green near a sump
	EMISSION = vec3(0.4, 0.9, 0.3) * c.g * cloud * 0.04;
	ROUGHNESS = 1.0;
	ALPHA = clamp(a, 0.0, mix(0.3, 0.14, c.g));
}

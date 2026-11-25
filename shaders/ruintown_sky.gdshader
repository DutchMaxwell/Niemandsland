shader_type sky;
// The ruin town's blue-hour sky (plan PLAN_RUINTOWN_TARGET_C, S1; lead call D-C2): the colour by elevation lives in ruintown_sky.gdshaderinc, shared with the table round the board.
// A pure backdrop: the town's ambient light is a colour and its reflections are off, so this sky lights nothing (BoardgenMood.town_sky).
// (look review 3) The key light's disc sits exactly where its light comes from (LIGHT0_DIRECTION): a pale moon for a cool key, a warm sun with a wider glow for a warm one.
// The night layers: stars, a broken cloud deck lit from the moon's side and a pale haze where the sky meets the land. The shader never
// reads the frame clock (a sky that does re-renders its radiance map every frame) and adds nothing in the cube-map pass (the radiance lights nothing).
#include "res://shaders/ruintown_sky.gdshaderinc"

uniform float disc_strength = 1.0;   // 0 = no disc
uniform float star_strength = 1.0;
uniform float cloud_strength = 0.85;
uniform float haze_strength = 0.35;
const float MOON_COS = 0.99962;
const float SUN_COS = 0.99945;

float h31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vn(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h31(vec3(i, 1.0)), b = h31(vec3(i + vec2(1.0, 0.0), 1.0)), c = h31(vec3(i + vec2(0.0, 1.0), 1.0)), d = h31(vec3(i + vec2(1.0, 1.0), 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vn(p);
		p = p * 2.03 + vec2(17.3, 5.1);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 col = town_sky(EYEDIR);
	float m = LIGHT0_ENABLED ? max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0) : 0.0;
	vec3 tint = LIGHT0_ENABLED ? LIGHT0_COLOR / max(max(LIGHT0_COLOR.r, LIGHT0_COLOR.g), max(LIGHT0_COLOR.b, 0.001)) : vec3(1.0);
	float warm = smoothstep(0.0, 0.25, tint.r - tint.b);   // 0 = a cool moon, 1 = a warm sun
	float cover = 0.0;
	if (!AT_CUBEMAP_PASS && EYEDIR.y > 0.0) {
		// a broken cloud deck, lit from the moon's side: the plane projection thins towards the zenith and stacks into bands at the horizon
		vec2 uv = EYEDIR.xz / (EYEDIR.y + 0.22);
		float n = fbm(uv * 1.35 + vec2(3.7, 9.2));
		cover = smoothstep(0.50, 0.74, n) * smoothstep(0.015, 0.16, EYEDIR.y) * cloud_strength;
		float rim = smoothstep(0.50, 0.60, n) * (1.0 - smoothstep(0.60, 0.80, n));   // the thin edge of a cloud catches the light
		vec3 cloud = mix(below, horizon, 0.35 + 0.45 * pow(m, 2.0)) * gain * (0.75 + 0.9 * rim * (0.35 + pow(m, 6.0) * 2.0));
		// stars: one jittered point per cell of a grid the view sphere cuts through; the cut gives discs of different sizes
		vec3 q = EYEDIR * 95.0;
		vec3 c = floor(q);
		float h = h31(c);
		vec3 p = c + 0.5 + (vec3(h31(c + 1.7), h31(c + 5.3), h31(c + 9.1)) - 0.5) * 0.6;
		float star = smoothstep(0.13, 0.02, length(q - p)) * step(0.90, h) * mix(0.35, 1.0, h31(c + 3.3));
		star *= smoothstep(0.03, 0.22, EYEDIR.y) * (1.0 - warm) * (1.0 - smoothstep(0.90, 0.995, m));   // none in the haze, by day or in the moon's glare
		col += vec3(0.85, 0.9, 1.0) * star * star_strength * (1.0 - cover) * 0.9;
		col = mix(col, cloud, cover);
	}
	col += horizon * gain * haze_strength * exp(-abs(EYEDIR.y) * 16.0) * (0.6 + 0.8 * pow(m, 2.0));   // a pale band of haze where the sky meets the land
	if (disc_strength > 0.0 && LIGHT0_ENABLED) {
		float edge = mix(MOON_COS, SUN_COS, warm);
		float disc = smoothstep(edge - 0.00008, edge + 0.00008, m);
		float halo = pow(m, mix(400.0, 120.0, warm)) * mix(0.25, 0.6, warm) + pow(m, 24.0) * mix(0.03, 0.12, warm);
		col += tint * (disc * mix(1.6, 3.0, warm) * (1.0 - 0.7 * cover) + halo) * disc_strength;
	}
	COLOR = col;
}

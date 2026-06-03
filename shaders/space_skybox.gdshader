shader_type sky;
render_mode use_debanding;
// Deep, calm cosmos backdrop: a distant domain-warped nebula, a fine star haze, and a
// few isolated bright stars. No sun disc, no planets (removed per feedback). Dithered
// in the dark to kill the banding/blocky "kinks" the smooth gradient showed.

// === Deep space ===
uniform vec3 space_top : source_color = vec3(0.002, 0.003, 0.008);
uniform vec3 space_bottom : source_color = vec3(0.008, 0.010, 0.024);

// === Distant nebula ===
uniform vec3 nebula_color_a : source_color = vec3(0.13, 0.04, 0.24);
uniform vec3 nebula_color_b : source_color = vec3(0.02, 0.10, 0.17);
uniform float nebula_intensity : hint_range(0.0, 2.0) = 0.95;
uniform float nebula_scale = 2.6;

// === Stars ===
uniform float star_density : hint_range(0.0, 1.0) = 0.5;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.5;
uniform float bright_star_chance : hint_range(0.0, 0.2) = 0.04;
uniform float bright_star_brightness : hint_range(0.0, 16.0) = 10.0;
uniform float twinkle_speed : hint_range(0.0, 5.0) = 0.8;

// Per-pixel dither amplitude (in 1/255 units) to break banding in the dark.
uniform float dither_amount = 1.5;

// === Noise ===
float hash13(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		v += a * noise3d(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// Domain-warped FBM -> organic clouds with no blocky low-frequency cells.
float nebula_fbm(vec3 p) {
	vec3 q = vec3(fbm(p + vec3(0.0)), fbm(p + vec3(5.2, 1.3, 2.8)), fbm(p + vec3(2.4, 7.1, 4.6)));
	return fbm(p + 1.2 * q);
}

// Fine background star haze (dense, subtle, twinkling).
vec3 starfield(vec3 dir, float time) {
	vec3 c = vec3(0.0);
	for (int layer = 0; layer < 3; layer++) {
		float scale = 110.0 + float(layer) * 60.0;
		vec3 cell = floor(dir * scale);
		vec3 uv = fract(dir * scale);
		float rnd = hash13(cell + float(layer) * 100.0);
		if (rnd < star_density * (0.3 + float(layer) * 0.15)) {
			vec3 sp = vec3(hash13(cell * 1.1), hash13(cell * 2.3), hash13(cell * 3.7)) * 0.7 + 0.15;
			float dist = length(uv - sp);
			float size = (0.010 + hash13(cell * 1.7) * 0.016) / (1.0 + float(layer) * 0.5);
			float twk = 0.65 + 0.35 * sin(time * (0.3 + hash13(cell * 4.2) * twinkle_speed) + hash13(cell * 3.7) * 6.28);
			float core = smoothstep(size, 0.0, dist);
			c += vec3(0.85, 0.88, 1.0) * core * twk;
		}
	}
	return c;
}

// A few isolated, bright, glowing stars.
vec3 bright_stars(vec3 dir, float time) {
	vec3 c = vec3(0.0);
	float scale = 26.0;
	vec3 cell = floor(dir * scale);
	vec3 uv = fract(dir * scale);
	float rnd = hash13(cell + vec3(7.0));
	if (rnd < bright_star_chance) {
		vec3 sp = vec3(hash13(cell * 1.7), hash13(cell * 2.9), hash13(cell * 4.3)) * 0.6 + 0.2;
		float dist = length(uv - sp);
		float twk = 0.7 + 0.3 * sin(time * (0.4 + hash13(cell * 5.1)) + hash13(cell * 2.2) * 6.28);
		float core = smoothstep(0.03, 0.0, dist);
		float glow = smoothstep(0.18, 0.0, dist) * 0.25;
		vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.92, 0.78), hash13(cell * 6.6));
		c += tint * (core + glow) * twk;
	}
	return c;
}

void sky() {
	vec3 dir = EYEDIR;

	// Deep-space gradient (slightly darker near zenith).
	float up = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(space_bottom, space_top, up);

	// Distant nebula — soft, domain-warped, no blocky cells.
	float n = nebula_fbm(dir * nebula_scale + vec3(11.0, 5.0, 23.0));
	float tint = fbm(dir * nebula_scale * 1.8 + vec3(47.0));
	float mask = smoothstep(0.42, 0.95, n);
	col += mix(nebula_color_a, nebula_color_b, tint) * mask * nebula_intensity;

	// Stars: fine haze + isolated bright ones.
	col += starfield(dir, TIME) * star_brightness;
	col += bright_stars(dir, TIME) * bright_star_brightness;

	// Dither to kill banding in the very dark values.
	float d = hash13(dir * 8888.0) - 0.5;
	col += d * (dither_amount / 255.0);

	COLOR = max(col, vec3(0.0));
}

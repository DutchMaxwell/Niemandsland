shader_type sky;
render_mode use_debanding;
// Deep, calm cosmos backdrop: a colourful distant domain-warped nebula and a field of
// small twinkling stars (a few a touch brighter, but small — no sun discs, no planets).
// Heavily dithered in the dark so the smooth gradient shows no banding/blocky "kinks".

// === Deep space ===
uniform vec3 space_top : source_color = vec3(0.002, 0.003, 0.008);
uniform vec3 space_bottom : source_color = vec3(0.008, 0.010, 0.024);

// === Distant nebula ===
// Desaturated on purpose: this sky drives the gameplay scene's lighting
// (Environment ambient_light_source = Sky, IBL reflections, and SDFGI sky-light on
// the ULTRA preset). The previous strongly-magenta nebula_color_a (0.30,0.07,0.42 —
// green ~0) flooded every surface with magenta radiance once the sun was dim or the
// atmosphere "Night/Sunset" moods raised nebula_intensity, turning the whole table
// magenta (worst on bright biomes like desert). Keeping the green channel non-trivial
// and the luminance modest stops the sky from tinting lit materials magenta while
// still reading as a coloured nebula in the sky itself.
uniform vec3 nebula_color_a : source_color = vec3(0.18, 0.13, 0.24);
uniform vec3 nebula_color_b : source_color = vec3(0.06, 0.16, 0.22);
uniform vec3 nebula_color_c : source_color = vec3(0.24, 0.14, 0.10);
uniform float nebula_intensity : hint_range(0.0, 2.0) = 0.5;
uniform float nebula_scale = 2.6;

// === Stars (small) ===
uniform float star_density : hint_range(0.0, 1.0) = 0.55;
uniform float star_brightness : hint_range(0.0, 4.0) = 2.2;
uniform float twinkle_speed : hint_range(0.0, 5.0) = 0.8;

// Per-pixel dither amplitude (in 1/255 units) to break banding in the dark.
uniform float dither_amount = 4.5;

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
	return fbm(p + 1.4 * q);
}

// Small twinkling stars across several layers; a few are a touch brighter but stay small.
vec3 starfield(vec3 dir, float time) {
	vec3 c = vec3(0.0);
	for (int layer = 0; layer < 3; layer++) {
		float scale = 55.0 + float(layer) * 42.0;
		vec3 cell = floor(dir * scale);
		vec3 uv = fract(dir * scale);
		float rnd = hash13(cell + float(layer) * 100.0);
		if (rnd < star_density * (0.32 + float(layer) * 0.12)) {
			vec3 sp = vec3(hash13(cell * 1.1), hash13(cell * 2.3), hash13(cell * 3.7)) * 0.6 + 0.2;
			float dist = length(uv - sp);
			float bright = hash13(cell * 5.1);                 // some stars brighter
			float size = (0.05 + bright * 0.05) / (1.0 + float(layer) * 0.4);
			float twk = 0.65 + 0.35 * sin(time * (0.3 + hash13(cell * 4.2) * twinkle_speed) + hash13(cell * 3.7) * 6.28);
			float core = smoothstep(size, 0.0, dist);
			float glow = smoothstep(size * 2.2, 0.0, dist) * 0.2;
			vec3 tint = mix(vec3(0.82, 0.86, 1.0), vec3(1.0, 0.93, 0.82), hash13(cell * 6.6));
			c += tint * (core + glow) * twk * (0.6 + bright * 0.9);
		}
	}
	return c;
}

void sky() {
	vec3 dir = EYEDIR;

	// Deep-space gradient (slightly darker near zenith).
	float up = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(space_bottom, space_top, up);

	// Distant nebula — soft, domain-warped, three-way colour blend for richness.
	float n = nebula_fbm(dir * nebula_scale + vec3(11.0, 5.0, 23.0));
	float t1 = fbm(dir * nebula_scale * 1.8 + vec3(47.0));
	float t2 = fbm(dir * nebula_scale * 1.3 + vec3(91.0, 17.0, 3.0));
	float mask = smoothstep(0.48, 1.0, n);
	vec3 neb = mix(mix(nebula_color_a, nebula_color_b, t1), nebula_color_c, t2 * 0.6);
	col += neb * mask * nebula_intensity;

	// Small stars.
	col += starfield(dir, TIME) * star_brightness;

	// Strong dither to kill banding in the very dark values.
	float d = hash13(dir * 8888.0) - 0.5;
	col += d * (dither_amount / 255.0);

	COLOR = max(col, vec3(0.0));
}

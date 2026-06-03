shader_type sky;
render_mode use_debanding;
// Upgraded cosmos backdrop for the tabletop: deep-space gradient, FBM nebulae,
// multi-layer twinkling starfield, a bright star/sun aligned to the scene's
// DirectionalLight (LIGHT0), and a few distant lit planets. Procedural — no assets.

// === Deep space + nebula ===
uniform vec3 horizon_color : source_color = vec3(0.018, 0.022, 0.045);
uniform vec3 zenith_color : source_color = vec3(0.004, 0.005, 0.012);
uniform vec3 nebula_color_a : source_color = vec3(0.16, 0.05, 0.28);
uniform vec3 nebula_color_b : source_color = vec3(0.02, 0.12, 0.20);
uniform float nebula_intensity : hint_range(0.0, 3.0) = 1.4;
uniform float nebula_scale = 1.7;

// === Stars ===
uniform float star_density : hint_range(0.0, 1.0) = 0.6;
uniform float star_brightness : hint_range(0.0, 8.0) = 3.5;
uniform float twinkle_speed : hint_range(0.0, 5.0) = 1.0;

// === Star / sun corona (drawn at the DirectionalLight direction) ===
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.82);
uniform float sun_size : hint_range(0.0, 0.2) = 0.02;
uniform float sun_glow : hint_range(0.0, 6.0) = 2.2;

// === Distant planets ===
uniform vec3 planet1_dir = vec3(-0.55, 0.18, -0.82);
uniform float planet1_size : hint_range(0.0, 0.6) = 0.17;
uniform vec3 planet1_color : source_color = vec3(0.55, 0.40, 0.26);
uniform vec3 planet2_dir = vec3(0.7, 0.42, 0.58);
uniform float planet2_size : hint_range(0.0, 0.6) = 0.085;
uniform vec3 planet2_color : source_color = vec3(0.32, 0.50, 0.62);

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
	for (int i = 0; i < 5; i++) {
		v += a * noise3d(p);
		p *= 2.02;
		a *= 0.5;
	}
	return v;
}

// Multi-layer twinkling stars.
vec3 starfield(vec3 dir, float time) {
	vec3 c = vec3(0.0);
	for (int layer = 0; layer < 3; layer++) {
		float scale = 90.0 + float(layer) * 55.0;
		vec3 cell = floor(dir * scale);
		vec3 uv = fract(dir * scale);
		float rnd = hash13(cell + float(layer) * 100.0);
		if (rnd < star_density * (0.35 + float(layer) * 0.18)) {
			vec3 sp = vec3(hash13(cell * 1.1), hash13(cell * 2.3), hash13(cell * 3.7)) * 0.7 + 0.15;
			float dist = length(uv - sp);
			float size = (0.012 + hash13(cell * 1.7) * 0.02) / (1.0 + float(layer) * 0.5);
			float twk = 0.6 + 0.4 * sin(time * (0.3 + hash13(cell * 4.2) * twinkle_speed) + hash13(cell * 3.7) * 6.28);
			float core = smoothstep(size, 0.0, dist);
			float glow = smoothstep(size * 4.0, 0.0, dist) * 0.4;
			vec3 tint = mix(vec3(0.8, 0.85, 1.0), vec3(1.0, 0.9, 0.75), hash13(cell * 5.1));
			c += tint * (core + glow) * twk;
		}
	}
	return c;
}

// A distant lit planet rendered as a shaded disc.
vec3 planet(vec3 col, vec3 dir, vec3 pdir, float psize, vec3 pcol, vec3 sundir) {
	pdir = normalize(pdir);
	float d = dot(dir, pdir);
	float edge = cos(psize);
	if (d < edge) {
		return col;
	}
	vec3 right = normalize(cross(pdir, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(right, pdir);
	float ang = acos(clamp(d, -1.0, 1.0)) / psize;       // 0 centre .. 1 rim
	vec2 off = vec2(dot(dir, right), dot(dir, up));
	off = (length(off) > 1e-5) ? normalize(off) * ang : vec2(0.0);
	float r = clamp(length(off), 0.0, 1.0);
	float z = sqrt(max(0.0, 1.0 - r * r));
	vec3 n = normalize(right * off.x + up * off.y + pdir * z);
	float ndl = clamp(dot(n, sundir), 0.0, 1.0);
	float surf = fbm(n * 5.0) * 0.5 + 0.7;               // banding / continents
	vec3 surface = pcol * surf;
	vec3 lit = surface * (ndl * 1.25 + 0.03);            // day side + faint night
	float rim = pow(1.0 - z, 2.0) * pow(ndl, 0.4);       // lit atmosphere rim
	lit += pcol * 0.35 * rim;
	float aa = smoothstep(edge, mix(edge, 1.0, 0.04), d);
	return mix(col, lit, aa);
}

void sky() {
	vec3 dir = EYEDIR;

	// Background gradient by elevation.
	float up = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(horizon_color, zenith_color, up);

	// Nebula clouds.
	float n = fbm(dir * nebula_scale + vec3(11.0, 5.0, 23.0));
	float n2 = fbm(dir * nebula_scale * 2.3 + vec3(47.0));
	float mask = pow(clamp(n, 0.0, 1.0), 1.6);
	col += mix(nebula_color_a, nebula_color_b, n2) * mask * nebula_intensity;

	// Stars.
	col += starfield(dir, TIME) * star_brightness;

	// Sun / star + planets, aligned to the scene's directional light.
	vec3 sun_pos = vec3(0.4, 0.7, 0.55);                 // fallback if no light
	if (LIGHT0_ENABLED) {
		sun_pos = -LIGHT0_DIRECTION;                     // direction TO the star
	}
	vec3 sundir = normalize(sun_pos);

	col = planet(col, dir, planet1_dir, planet1_size, planet1_color, sundir);
	col = planet(col, dir, planet2_dir, planet2_size, planet2_color, sundir);

	// Star disc + corona glow.
	float s = clamp(dot(dir, sundir), 0.0, 1.0);
	float disc = smoothstep(cos(sun_size), cos(sun_size * 0.4), s);
	float glow = pow(s, 220.0) * 0.5 + pow(s, 24.0) * 0.18;
	col += sun_color * (disc * 6.0 + glow * sun_glow);

	COLOR = col;
}

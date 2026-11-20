// Noise and shape helpers of the board shader (AAA step 2: moved out of tiefwerk_board.gdshader, no change): hash, value noise, fbm, seam line, round hatch.

// A hash without lattice correlation (the old one left near-equal values in neighbouring lattice cells, so the value noise showed
// axis-aligned rectangular patches: the "square puddles").
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

float fbm(vec2 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + 17.1;
		a *= 0.5;
	}
	return s;
}

// A thin line every `step_in` inches (0 on the line, 1 off it).
float seam(float v, float step_in, float w) {
	return smoothstep(0.0, w, abs(fract(v / step_in + 0.5) - 0.5) * step_in);
}

// A round inset hatch of radius R at the origin of fp (inches): rgb = its paint, a = how much of the surface it covers (lid and groove).
vec4 hatch(vec2 fp, float R, float n) {
	float rr = length(fp) / R;
	float groove = smoothstep(0.07, 0.0, abs(rr - 1.04));
	float arc = (fract(atan(fp.y, fp.x) / 0.7854 + 0.5) - 0.5) * 0.7854 * rr;   // eight bolts on a ring
	float bolt = smoothstep(0.1, 0.06, length(vec2(rr - 0.78, arc)));
	float handle = step(abs(fp.y / R), 0.06) * step(abs(fp.x / R), 0.38);
	return vec4(vec3(0.27, 0.26, 0.25) * mix(0.8, 1.1, n) * (1.0 + 0.4 * bolt) * (1.0 - 0.5 * handle) * (1.0 - 0.6 * groove), max(smoothstep(0.98, 0.94, rr), groove));
}

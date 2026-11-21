// --- Micro tier (AAA step 7) ---
// Sharp cellular chipping (cells 0.02-0.05 in), thin vertical streaks and dust in recesses: the scale of a painted model's paint chips.
// All of it fades out below ~2 px per feature (px = inches per pixel), so the play camera sees none of it and nothing shimmers; the
// wall and macro cameras see crisp chips.

// How much of the micro tier is visible at this pixel size: 1 close up, 0 from 0.025 in per pixel on (a 0.05 in chip is 2 px there).
float micro_amount(float px) {
	return 1.0 - smoothstep(0.012, 0.025, px);
}

// Cellular chips: 1 inside a chip, 0 outside, a hard edge one pixel wide. Every cell carries one irregular chip (radius 0.2-0.46 of the
// cell, a squash 0.6-1.4, jittered inside its cell), so a threshold on a coarse noise decides WHERE chips show; the nearest 2x2 cells are tested.
float chips(vec2 uv, float size, float px) {
	vec2 g = uv / size;
	vec2 i = floor(g);
	vec2 f = fract(g);
	vec2 s = vec2(f.x < 0.5 ? -1.0 : 1.0, f.y < 0.5 ? -1.0 : 1.0);   // the neighbour cells on the side f lies on
	float w = px / size;
	float m = 0.0;
	for (int j = 0; j < 2; j++) {
		for (int k = 0; k < 2; k++) {
			vec2 o = vec2(float(k), float(j)) * s;
			vec2 c = i + o;
			vec2 fp = o + vec2(0.25) + vec2(h21(c + 3.1), h21(c + 8.3)) * 0.5;   // the chip's centre, in the cell f is measured in
			vec2 q = (f - fp) * vec2(1.0, 0.6 + 0.8 * h21(c + 5.9));
			float rad = 0.2 + 0.26 * h21(c + 5.5);
			m = max(m, smoothstep(rad + w, rad - w, length(q)));
		}
	}
	return m;
}

// Thin vertical streaks, stretched 1:12 down a wall (uv.y is the height): 1 on a streak, sparse.
float streaks(vec2 uv, float px) {
	float s = vnoise(vec2(uv.x * 24.0, uv.y * 2.0));
	float sparse = smoothstep(0.45, 0.7, vnoise(vec2(uv.x * 3.0, uv.y * 0.3) + 11.0));
	return smoothstep(0.62, 0.78, s) * sparse * smoothstep(px * 0.7, px * 2.5, 0.04);
}

// Dust settles where the relief lies below the surface (h < 0 in inches): the recess lifts toward a dusty grey.
vec3 dust(vec3 alb, float h, float n, float amount) {
	float d = smoothstep(-0.004, -0.03, h) * mix(0.5, 1.0, n) * amount;
	return mix(alb, vec3(0.36, 0.34, 0.31) * (0.6 + luma(alb)), d * 0.3);
}

// Paint that is worn through: where `wear` (0 intact .. 1 gone, a coarse field) is in its transition band the chips decide, with hard
// edges; above the band the paint is gone, below it intact. Far away (micro 0) it is the old soft blend.
float chipped_wear(float t, float lo, float hi, vec2 uv, float px) {
	float soft = smoothstep(lo, hi, t);
	float micro = micro_amount(px);
	if (micro <= 0.0) {
		return soft;
	}
	float hard = max(step(hi, t), chips(uv, 0.045, px) * step(lo, t));
	return mix(soft, hard, micro);
}

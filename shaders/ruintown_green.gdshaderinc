// ruintown_green.gdshaderinc - ONE green for the ruin town: the soil's painted cover (ruintown_board.gdshader, earth and plot
// branches) and every later plant that stands on it read the same macro colour and the same clump break, so blades and the
// ground under them never disagree. Needs vnoise() / fbm() (tiefwerk_noise.gdshaderinc). Both are FOLDED by the half turn:
// a point and its half-turn twin get the same value, so neither side of the table sees a greener board (fairness, D-G5).

const vec3 GREEN_COVER = vec3(0.13, 0.16, 0.10);   // a dull dark yellow-grey green: the cover between the tufts

vec2 green_fold(vec2 xz_in) {
	return xz_in.y >= 0.0 ? -xz_in : xz_in;
}

// The dry / green drift over 3-8 in as a tint (1 = neutral): straw patches and greener ones.
vec3 green_drift(vec2 xz_in, float seed) {
	float dry = smoothstep(0.35, 0.65, vnoise(green_fold(xz_in) * 0.2 + seed * 2.3));
	return mix(vec3(0.9, 1.04, 0.88), vec3(1.1, 1.0, 0.78), dry);
}

// The macro colour of the cover at a point (linear albedo).
vec3 green_tone(vec2 xz_in, float seed) {
	return GREEN_COVER * green_drift(xz_in, seed);
}

// The clump term at 5.5 per in: low = a dark hollow between the clumps.
float green_break(vec2 xz_in, float seed) {
	return fbm(green_fold(xz_in) * 5.5 + seed * 3.1);
}

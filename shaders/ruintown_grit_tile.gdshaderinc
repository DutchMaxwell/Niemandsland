// THE PERIOD BREAKER of the ruin town (plan PLAN_RUINTOWN_GRIT W0, maintainer 21.11.: "the pattern repeats too quickly"): an authored set repeats every tile (coursed stone 1.3 in), so
// a wall was one wallpaper. Stochastic tiling on a triangle grid (after Heitz and Neyret's by-example blending): every grid vertex takes the set at its own random offset ALONG the
// courses (x only: the bed joints stay level, so a blend never doubles a course line) and maybe mirrored; three samples are blended with sharpened barycentric weights. The stone
// SIZE does not change (decision D-R2), only its period. Included by ruintown_board.gdshader before use_stone(); needs h21() (tiefwerk_noise).
const float GRIT_HEX = 1.15;   // triangle grid per tile: a vertex about every tile

// The three grid vertices round `st` (tile units) with their weights (sharpened, sum 1).
void grit_tri(vec2 st, out vec2 v1, out vec2 v2, out vec2 v3, out vec3 w) {
	vec2 sk = vec2(st.x, -0.57735027 * st.x + 1.15470054 * st.y) * GRIT_HEX;
	vec2 b = floor(sk);
	vec2 f = fract(sk);
	float z = 1.0 - f.x - f.y;
	if (z > 0.0) {
		w = vec3(z, f.y, f.x);
		v1 = b;
		v2 = b + vec2(0.0, 1.0);
		v3 = b + vec2(1.0, 0.0);
	} else {
		w = vec3(-z, 1.0 - f.y, 1.0 - f.x);
		v1 = b + vec2(1.0);
		v2 = b + vec2(1.0, 0.0);
		v3 = b + vec2(0.0, 1.0);
	}
	w = pow(w, vec3(6.0));
	w /= w.x + w.y + w.z;
}

// A vertex's take on the set: a random offset along x, and a mirror for half of them.
vec2 grit_take(vec2 st, vec2 v) {
	float h = h21(v + 37.0);
	return vec2((fract(h * 7.13) < 0.5 ? st.x : -st.x) + h * 17.0, st.y);
}

// The set `t` at `st` (tile units) without its period: the albedo (rgb) blended over the three takes.
vec3 grit_albedo(sampler2D t, vec2 st) {
	vec2 v1;
	vec2 v2;
	vec2 v3;
	vec3 w;
	grit_tri(st, v1, v2, v3, w);
	vec2 dx = dFdx(st);
	vec2 dy = dFdy(st);
	return textureGrad(t, grit_take(st, v1), dx, dy).rgb * w.x + textureGrad(t, grit_take(st, v2), dx, dy).rgb * w.y + textureGrad(t, grit_take(st, v3), dx, dy).rgb * w.z;
}

// The same for a normal map (tangent space, -1..1): a mirrored take flips x.
vec3 grit_normal(sampler2D n, vec2 st) {
	vec2 v1;
	vec2 v2;
	vec2 v3;
	vec3 w;
	grit_tri(st, v1, v2, v3, w);
	vec2 dx = dFdx(st);
	vec2 dy = dFdy(st);
	vec3 a = textureGrad(n, grit_take(st, v1), dx, dy).xyz * 2.0 - 1.0;
	vec3 b = textureGrad(n, grit_take(st, v2), dx, dy).xyz * 2.0 - 1.0;
	vec3 c = textureGrad(n, grit_take(st, v3), dx, dy).xyz * 2.0 - 1.0;
	a.x *= fract(h21(v1 + 37.0) * 7.13) < 0.5 ? 1.0 : -1.0;
	b.x *= fract(h21(v2 + 37.0) * 7.13) < 0.5 ? 1.0 : -1.0;
	c.x *= fract(h21(v3 + 37.0) * 7.13) < 0.5 ? 1.0 : -1.0;
	return normalize(a * w.x + b * w.y + c * w.z);
}

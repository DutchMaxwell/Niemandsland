// ruintown_soil.gdshaderinc - the town's ground as a MATERIAL (LOOK5 R20, Lane S v2 step S4: inert, called nowhere yet).
// Four soil layers in three texture arrays (layer 0 bare, 1 mud, 2 grass, 3 verge / wet): albedo, tangent normal, and ORH
// (R ambient occlusion, G roughness, B height). COLOUR = the REAL albedo with a SCALAR gain: each set keeps its hue and its inner
// contrast, only its average brightness is pinned - to SOIL_RANK x the board's reference earth (the caller multiplies by it); no
// ceiling (S6 v3: it squashed the bare mean, the readability gate guards the top). One textureGrad per map and layer (explicit
// gradients: the per-layer tile changes at a layer seam), only the two heaviest layers are read, blended by height inside
// SOIL_BAND with a contact shadow on their shared rim (only where the weights hand over within ~1 in, never on an evenly mixed field). Needs nothing from the board shader.

uniform sampler2DArray soil_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray soil_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray soil_orh : filter_linear_mipmap, repeat_enable;
uniform float soil_on = 0.0;   // 1 at Medium and up outside gl_compatibility when all four sets are cached (S2)
uniform float soil_tile = 6.0;   // board inches one bare tile covers
uniform vec3 soil_mean[4];   // the mean linear albedo of each set: its luma sets the scalar gain
uniform float soil_tier = 1.0;   // 1 Medium, 2 High (the second layer's normal too), 3 Ultra
uniform float soil_fill_sat = 0.35;   // how much colour the unlit Night fill keeps (D-GRASS-NIGHT; read by the caller)

const vec4 SOIL_RANK = vec4(1.15, 0.92, 0.85, 0.75);   // bare, mud, grass, verge / wet: x the board's reference earth luma
const vec4 SOIL_SCALE = vec4(1.0, 0.75, 1.2, 1.0);   // uv multipliers: bare 6 in, mud 8 in, grass 5 in, verge 6 in (periods never line up)
const float SOIL_EXPOSURE = 1.0;   // the one brightness knob of all four
const float SOIL_BAND = 0.10;   // the height-blend window
const float SOIL_NRM_GAIN = 1.0;   // the normal map's slope, before the normalise
const vec3 SOIL_LUMA = vec3(0.2126, 0.7152, 0.0722);

struct SoilSample {
	vec3 c;   // linear colour relative to the board's reference earth luma
	vec3 n;   // tangent-space normal
	float rough;
	float ao;
	float h;
	vec2 k;   // the weights of the (up to) two layers read
};

SoilSample soil_layer(float i, vec2 xz_in, bool want_n) {
	int ii = int(i + 0.5);
	float sc = SOIL_SCALE[ii] / soil_tile;
	vec2 uv = xz_in * sc;
	vec2 gx = dFdx(xz_in) * sc;
	vec2 gy = dFdy(xz_in) * sc;
	vec3 a = textureGrad(soil_alb, vec3(uv, i), gx, gy).rgb;
	vec3 o = textureGrad(soil_orh, vec3(uv, i), gx, gy).rgb;
	float la = max(dot(a, SOIL_LUMA), 0.0005);
	float l = la * SOIL_RANK[ii] / max(dot(soil_mean[ii], SOIL_LUMA), 0.0005) * SOIL_EXPOSURE;
	SoilSample r;
	r.c = a * (l / la);   // a scalar gain: the set's hue and grain survive
	r.n = vec3(0.0, 0.0, 1.0);
	if (want_n) {
		vec3 n = textureGrad(soil_nrm, vec3(uv, i), gx, gy).rgb * 2.0 - 1.0;
		n.xy *= SOIL_NRM_GAIN;
		r.n = normalize(n);
	}
	r.ao = o.r;
	r.rough = o.g;
	r.h = o.b;
	r.k = vec2(1.0, 0.0);
	return r;
}

// The height blend of the two heaviest of the four weights w (bare, mud, grass, verge; any scale, 0 = absent).
SoilSample soil_blend(vec4 w, vec2 xz_in) {
	float i0 = 0.0;
	float w0 = w.x;
	for (int j = 1; j < 4; j++) {
		if (w[j] > w0) {
			i0 = float(j);
			w0 = w[j];
		}
	}
	float i1 = i0;
	float w1 = -1.0;
	for (int j = 0; j < 4; j++) {
		if (float(j) != i0 && w[j] > w1) {
			i1 = float(j);
			w1 = w[j];
		}
	}
	float rim = smoothstep(0.5, 1.5, fwidth(w0 - w1) / max(fwidth(xz_in.x) + fwidth(xz_in.y), 0.0001));   // the weights' hand-over per inch: a rim, not a mixed field
	SoilSample a = soil_layer(i0, xz_in, true);
	if (w1 < 0.02) {   // one layer only: the second is not read
		return a;
	}
	SoilSample b = soil_layer(i1, xz_in, soil_tier >= 2.0);
	float s0 = w0 + a.h;
	float s1 = w1 + b.h;
	float best = max(s0, s1);
	vec2 k = max(vec2(s0, s1) - (best - SOIL_BAND), vec2(0.0));
	k /= max(k.x + k.y, 0.0001);
	SoilSample r;
	r.c = (a.c * k.x + b.c * k.y) * (1.0 - 0.35 * rim * 4.0 * k.x * k.y);   // a contact shadow on the shared rim
	r.n = normalize(a.n * k.x + b.n * k.y);
	r.rough = a.rough * k.x + b.rough * k.y;
	r.ao = a.ao * k.x + b.ao * k.y;
	r.h = a.h * k.x + b.h * k.y;
	r.k = k;
	return r;
}

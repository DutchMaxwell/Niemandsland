// ruintown_soil.gdshaderinc - the town's ground as a MATERIAL (LOOK5 R20, step S1: inert, called nowhere yet).
// Four soil layers in three texture arrays (layer 0 bare, 1 mud, 2 grass, 3 verge): albedo, tangent normal, and ORH
// (R ambient occlusion, G roughness, B height). Each layer is read twice - at its tile and at 0.37 x that scale turned
// 37 degrees - and the two mix by a folded 12 in noise, so the tile does not repeat and both sides of the table see the
// same ground (green_fold: fairness, D-G5). The layers blend by HEIGHT (score = weight + height; layers within SOIL_BAND
// of the best score share, the rest drop out), so mud fills the hollows and grass stands on the crowns.
// Albedo comes back as a RATIO (texture / the set's mean linear albedo): the caller keeps its palette tone and the
// readability budget, the texture adds only detail. Needs vnoise() (tiefwerk_noise) and green_fold() (ruintown_green).

uniform sampler2DArray soil_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray soil_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray soil_orh : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float soil_on = 0.0;   // 1 at Medium and up outside gl_compatibility when all four sets are cached (S2)
uniform float soil_tile = 6.0;   // board inches one tile covers
uniform vec3 soil_mean[4];   // the mean linear albedo of each set (the ratio's denominator)

const float SOIL_BAND = 0.2;   // the height-blend window
const float SOIL_FAR_SCALE = 0.37;
const float SOIL_FAR_TURN = 0.6458;   // 37 degrees

struct SoilSample {
	vec3 ratio;   // albedo / the set's mean
	vec3 n;   // tangent-space normal
	float rough;
	float ao;
	float h;
};

SoilSample soil_layer(int i, vec2 xz_in) {
	vec2 uv = xz_in / soil_tile;
	float c = cos(SOIL_FAR_TURN), s = sin(SOIL_FAR_TURN);
	vec2 uv_far = mat2(vec2(c, s), vec2(-s, c)) * uv * SOIL_FAR_SCALE;
	float m = vnoise(green_fold(xz_in) * 0.083);
	vec3 a = mix(texture(soil_alb, vec3(uv, float(i))).rgb, texture(soil_alb, vec3(uv_far, float(i))).rgb, m);
	vec3 n = mix(texture(soil_nrm, vec3(uv, float(i))).rgb, texture(soil_nrm, vec3(uv_far, float(i))).rgb, m);
	vec3 o = mix(texture(soil_orh, vec3(uv, float(i))).rgb, texture(soil_orh, vec3(uv_far, float(i))).rgb, m);
	SoilSample r;
	r.ratio = a / max(soil_mean[i], vec3(0.004));
	r.n = normalize(n * 2.0 - 1.0);
	r.ao = o.r;
	r.rough = o.g;
	r.h = o.b;
	return r;
}

// The height blend of the four layers under weights w (bare, mud, grass, verge; any scale, 0 = absent).
SoilSample soil_blend(vec4 w, vec2 xz_in) {
	SoilSample l0 = soil_layer(0, xz_in);
	SoilSample l1 = soil_layer(1, xz_in);
	SoilSample l2 = soil_layer(2, xz_in);
	SoilSample l3 = soil_layer(3, xz_in);
	vec4 h = vec4(l0.h, l1.h, l2.h, l3.h);
	vec4 has = step(vec4(0.0001), w);
	vec4 score = w + h * has;
	float best = max(max(score.x, score.y), max(score.z, score.w));
	vec4 k = max(score - (best - SOIL_BAND), vec4(0.0)) * has;
	k /= max(k.x + k.y + k.z + k.w, 0.0001);
	SoilSample r;
	r.ratio = l0.ratio * k.x + l1.ratio * k.y + l2.ratio * k.z + l3.ratio * k.w;
	r.n = normalize(l0.n * k.x + l1.n * k.y + l2.n * k.z + l3.n * k.w);
	r.rough = dot(vec4(l0.rough, l1.rough, l2.rough, l3.rough), k);
	r.ao = dot(vec4(l0.ao, l1.ao, l2.ao, l3.ao), k);
	r.h = dot(h, k);
	return r;
}

// The town's standing water (fountain basin, pond): a flat plane in its own frame, centred on the shape. Opaque, no depth or screen
// texture. Two value noises scrolling against each other (plus optional rings from the centre) bend the normal; the albedo runs deep ->
// shallow over the bank; scum patches go rough. EMISSION = an analytic sky mirror (sky_tint x fresnel): the surface is never a hole
// where the reflection probe is black. All noise is folded by the half turn (as the board shader is): both sides see the same water.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx, shadows_disabled;

#include "res://shaders/tiefwerk_noise.gdshaderinc"

const float IN = 0.0254;

uniform vec3 deep : source_color = vec3(0.010, 0.018, 0.022);
uniform vec3 shallow : source_color = vec3(0.05, 0.07, 0.06);
uniform vec3 sky_tint : source_color = vec3(0.10, 0.14, 0.22);
uniform float sky_energy = 1.0;
uniform vec2 half_in = vec2(2.0, 2.0);   // the rectangle's half size in inches; for an octagon x = its apothem
uniform bool octagon = false;
uniform float bank_in = 0.0;   // the band along the edge where wet stones show through the shallow water
uniform float ring_strength = 0.0;   // concentric rings from the centre (a spout dripping into it)
uniform float scum = 0.25;   // the share of the surface under a rough scum mat (densest along the edge)
uniform float clock = 1.0;   // 0 = frozen (stills)
// Stylised, not physical: a night basin read at the play pitch (40-50 deg down) reflects almost nothing (Schlick ~0.02), so the
// mirror term gets a floor (F0 0.08), the ripples are strong enough to break the lamps' glints into streaks, and a faint sheen
// lifts the surface - readable water, as night water is drawn in games, never brighter than the setts round it.
uniform float fresnel_floor = 0.08;
uniform float ripple_slope = 0.22;   // the ripple normal's strength (0.035 = physically calm water)
uniform float sheen = 0.3;   // the faint sky / moon sheen, a little stronger on the ripple flanks (kept under the setts' luma round the basin)

varying vec2 lp;   // inches off the shape's centre

void vertex() {
	lp = VERTEX.xz / IN;
}

// Inches from the shape's edge (positive inside).
float edge_in(vec2 p) {
	vec2 a = abs(p);
	if (octagon) {
		return half_in.x - max(max(a.x, a.y), (a.x + a.y) * 0.70710678);
	}
	return min(half_in.x - a.x, half_in.y - a.y);
}

float ripples(vec2 q, float t) {
	return vnoise(q * 0.9 + vec2(t, 0.6 * t) * 0.9) + 0.5 * vnoise(q * 2.3 - vec2(0.7 * t, t) * 2.3);
}

void fragment() {
	float d = edge_in(lp);
	if (d < 0.0) {
		discard;
	}
	vec2 q = lp.y >= 0.0 ? -lp : lp;   // folded by the half turn
	float t = TIME * 0.03 * clock;
	float e = 0.05;
	vec2 grad = vec2(ripples(q + vec2(e, 0.0), t) - ripples(q - vec2(e, 0.0), t), ripples(q + vec2(0.0, e), t) - ripples(q - vec2(0.0, e), t)) / (2.0 * e) * ripple_slope;
	float r = length(lp);
	if (ring_strength > 0.0 && r > 0.001) {
		float k = 6.2831853 / 0.35;
		float slope = cos(k * (r - TIME * 0.25 * clock)) * k * 0.012 * ring_strength * exp(-r * 0.6);
		grad += lp / r * slope;
	}
	vec3 n_world = normalize(vec3(-grad.x, 1.0, -grad.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float bank = bank_in > 0.0 ? 1.0 - smoothstep(0.0, bank_in, d) : 0.0;
	vec3 col = mix(deep, shallow, bank);
	vec2 cell = floor(q / 0.3);
	col = mix(col, shallow * 0.6 * (0.6 + 0.8 * h21(cell)), bank * 0.7);   // wet dark stones under the shallow edge
	float edge_bias = 1.0 - smoothstep(0.0, 0.4, d);
	float s = step(1.0 - scum - 0.25 * edge_bias * scum, fbm(q * 1.4 + 3.7));
	ALBEDO = mix(col, col * 1.6 + vec3(0.012, 0.014, 0.006), s);
	ROUGHNESS = mix(0.035, 0.45, s);
	SPECULAR = 0.8;
	METALLIC = 0.0;
	AO = 1.0;
	float fres = fresnel_floor + (1.0 - fresnel_floor) * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	float crest = smoothstep(0.02, 0.12, length(grad));   // the steep flanks catch the sky
	EMISSION = sky_tint * sky_energy * (fres + sheen * (0.7 + 0.3 * crest)) * (1.0 - s);
}

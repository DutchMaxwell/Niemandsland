// GRIT of the ruin town (plan PLAN_RUINTOWN_GRIT): wear, mud, water and damage on the ground, each with a CAUSE read from the baked grit map (BoardgenTownGrit.map: R = distance from the
// street's edge, G = wet / mud, B = kennel and rut offsets, A = damage). Included by ruintown_board.gdshader after ground_at(); needs its cell_in / board_cells. Own work, no third-party
// source. `grit_on` = 0 (no map) keeps the board exactly as before.
uniform sampler2D grit_map : filter_linear, repeat_disable;
uniform float grit_on = 0.0;
// The instrument (tools/boardgen/grit_metrics.py): 1 = every street pixel in the flat colour of its grit class, everything else black (emission only: the capture turns the lights off and the
// tonemap linear); 2 = the raw map (R edge distance, G wet / mud) on the open ground. 0 = the look.
uniform int grit_debug = 0;

const float GRIT_EDGE_CAP = 3.0;   // R: 0..1 = 0..3 in from the street's edge
const float GD_MID = 0.2;   // the debug's middle channel level (linear; ~0.48 after the sRGB encode)

vec4 grit_at(vec2 xz) {
	return texture(grit_map, clamp(xz / (cell_in * board_cells) + 0.5, vec2(0.0), vec2(1.0)));
}

// The debug colour of a street fragment from its class (the colours of grit_metrics.py CLASSES).
vec3 grit_class_colour(int c) {
	// 0 pristine, 1 worn, 2 mud, 3 wet, 4 puddle, 5 soot, 6 moss, 7 missing, 8 sunken, 9 cracked, 10 repair
	const vec3 COLS[11] = vec3[11](vec3(1.0), vec3(GD_MID), vec3(GD_MID, GD_MID, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, GD_MID, 1.0), vec3(GD_MID, 0.0, GD_MID), vec3(0.0, 1.0, 0.0),
		vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 0.0, 1.0), vec3(1.0, 1.0, 0.0));
	return COLS[clamp(c, 0, 10)];
}

// COLD STONE, WARM LIGHT (style bible 3, plan G2): the setts are a grey family - 60 % cool grey, 25 % brown-grey, 15 % ochre / rust, each sett its own value 0.6-1.2 - and the lamps bring
// the warmth. GRIT_MEAN is the family's mean; GRIT_TONE pins the street's mean luminance to the warm road's of the 21.11. gate (no grit term may make the street brighter).
const vec3 GRIT_COOL = vec3(0.180, 0.203, 0.245);
const vec3 GRIT_BROWN = vec3(0.208, 0.203, 0.198);
const vec3 GRIT_OCHRE = vec3(0.236, 0.202, 0.160);
const vec3 GRIT_MEAN = GRIT_COOL * 0.6 + GRIT_BROWN * 0.25 + GRIT_OCHRE * 0.15;
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
const float GRIT_TONE = 0.93;

// The street's base tint: the family's mean at the warm road's own luminance (the palette and GROUND_COBBLE keep deciding the value) with the map, the warm road without it.
vec3 grit_street_tint(vec3 warm) {
	return grit_on > 0.5 ? GRIT_MEAN * (dot(warm, LUMA) / dot(GRIT_MEAN, LUMA) * GRIT_TONE) : warm;
}

// One sett's colour from its hash `h` (the old tone spread without the map).
vec3 grit_sett_tint(vec3 tint, float h) {
	if (grit_on < 0.5) {
		return tint * mix(0.7, 1.15, h);
	}
	float fam = fract(h * 7.31);
	vec3 c = fam < 0.6 ? GRIT_COOL : (fam < 0.85 ? GRIT_BROWN : GRIT_OCHRE);
	return tint / GRIT_MEAN * c * mix(0.6, 1.2, fract(h * 3.17));
}

// The street's grit at a point: `xz` inches off the board centre, `w` the noise-bent lookup point of the earth / street border, `sett` from cobble() (hash, stone mask, point in the
// sett). Changes the albedo; returns the debug colour of the fragment. G2: a low-frequency tone drift (1-4 in patches, value and a little hue) so the ground has detail between the
// sett and the street.
vec3 grit_street(vec2 xz, vec2 w, vec4 sett, inout vec3 alb) {
	if (grit_on < 0.5) {
		return grit_class_colour(0);
	}
	alb *= mix(0.8, 1.2, vnoise(xz * 0.45 + 5.0)) * mix(vec3(1.03, 1.0, 0.95), vec3(0.96, 0.99, 1.05), vnoise(xz * 0.3 + 17.0));
	return grit_class_colour(0);
}

// The debug colour of an open-ground fragment for grit_debug = 2: the raw map.
vec3 grit_map_colour(vec2 w) {
	vec4 g = grit_at(w);
	return vec3(g.r, g.g, 0.0);
}

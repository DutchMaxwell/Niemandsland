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

// The street's grit at a point (`w` = the noise-bent lookup point of the earth / street border): changes nothing yet (plan G1), returns the debug colour of the fragment.
vec3 grit_street(vec2 w) {
	return grit_class_colour(0);
}

// The debug colour of an open-ground fragment for grit_debug = 2: the raw map.
vec3 grit_map_colour(vec2 w) {
	vec4 g = grit_at(w);
	return vec3(g.r, g.g, 0.0);
}

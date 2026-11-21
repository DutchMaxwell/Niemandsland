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
const vec3 GRIT_COOL = vec3(0.184, 0.204, 0.238);
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

// MUD (style bible 2 and 7, plan G3): never noise alone - the map's WET / MUD (a distance to an earth border, a well, the fountain) times noise. It fills the joints (the joint colour from
// the earth, the joint raised to the sett's shoulder) and lays a broken film over the setts that never hides more than GRIT_MUD_COVER of them (it must not read as a plot or rough ground).
const float GRIT_MUD_COVER = 0.4;

// Wet dark mud: the earth's colour, darker and greyer.
vec3 grit_mud_colour() {
	vec3 earth = palette[0].rgb * GROUND_EARTH;
	return mix(earth, vec3(dot(earth, LUMA)), 0.5) * 0.62;
}

// The mud amount at a point from the map's WET / MUD, broken up by noise (0..1).
float grit_mud(float wet, vec2 xz) {
	return clamp(clamp((wet - 0.1) / 0.5, 0.0, 1.0) * mix(0.55, 1.3, vnoise(xz * 1.1 + 3.0)), 0.0, 1.0);
}

// The kennel (style bible 7): a dark wet drain line 0.3 in wide down the middle of a lane, 0.5 in off the frontage of an artery. `g` = the map, `run` = the ground map's run (0.5 = a junction:
// none there). 1 on the line.
float grit_kennel(vec4 g, float run) {
	float b = g.b * 255.0;
	bool artery = b > 127.5;
	float off = (b - (artery ? 192.0 : 64.0)) / 16.0;
	float d = artery ? abs(g.r * GRIT_EDGE_CAP - 0.5) : abs(off);
	return (1.0 - smoothstep(0.1, 0.17, d)) * step(0.25, abs(run - 0.5)) * step(b, 254.5);
}

// BROKEN PAVING (style bible 6, plan G4): each sett's fate from its own hash against odds raised by the map's DAMAGE (patches, ruts) and wetness, lowered in the wear lane: 1 missing (mud
// in the hole), 2 sunken (lower, darker), 3 cracked (a dark line across it), 4 an odd pale repair stone, 0 sound. The odds are BoardgenTownGrit's (ODDS_*, LANE_KEEP; its
// expected_shares() checks them against the style bible on the map itself): missing / sunken / cracked / repair.
uniform vec4 grit_odds_base = vec4(0.032, 0.125, 0.08, 0.04);
uniform vec4 grit_odds_damage = vec4(0.65, 0.35, 0.12, 0.0);
uniform vec2 grit_lane_keep = vec2(0.35, 0.5);

int grit_fate(float h, float dmg, float wet, float lane) {
	float u = fract(h * 13.71);
	float pm = (grit_odds_base.x + grit_odds_damage.x * dmg) * mix(1.0, grit_lane_keep.x, lane);
	float ps = (grit_odds_base.y + grit_odds_damage.y * dmg + 0.08 * wet) * mix(1.0, grit_lane_keep.y, lane);
	float pc = grit_odds_base.z + grit_odds_damage.z * dmg;
	float pr = grit_odds_base.w + grit_odds_damage.w * dmg;
	return u < pm ? 1 : (u < pm + ps ? 2 : (u < pm + ps + pc ? 3 : (u < pm + ps + pc + pr ? 4 : 0)));
}

// The street's grit at a point: `xz` inches off the board centre, `w` the noise-bent lookup point of the earth / street border, `sett` from cobble() (hash, stone mask, point in the
// sett), `run` the ground map's run. Changes the albedo, relief and roughness; returns the debug colour of the fragment.
vec3 grit_street(vec2 xz, vec2 w, vec4 sett, float run, inout vec3 alb, inout float rel, inout float rough) {
	if (grit_on < 0.5) {
		return grit_class_colour(0);
	}
	vec4 g = grit_at(w);
	alb *= mix(0.8, 1.2, vnoise(xz * 0.45 + 5.0)) * mix(vec3(1.03, 1.0, 0.95), vec3(0.96, 0.99, 1.05), vnoise(xz * 0.3 + 17.0));   // G2: the 1-4 in tone drift
	float kp = keep(xz.x, SETT_W);
	float joint = mix(0.3, 1.0 - sett.y, kp);   // below ~3 px a joint is its share of the area
	vec3 mudc = grit_mud_colour();
	float foot = 0.55 * (1.0 - smoothstep(0.2, 1.0, g.r * GRIT_EDGE_CAP));   // dirt gathers at the wall foot and the street's edge too (style bible 15: grit is strongest in the 1 in there)
	float mud = grit_mud(max(g.g, foot), xz);
	float fill = smoothstep(0.15, 0.5, mud);
	alb = mix(alb, mudc, 0.9 * joint * fill);   // joints full of mud
	rel = mix(rel, max(rel, 0.45), joint * fill);
	float cover = min(GRIT_MUD_COVER, 0.75 * mud) * smoothstep(0.35, 0.65, vnoise(xz * 1.9 + 7.0));   // a broken film: the setts show through
	alb = mix(alb, mudc * 1.15, cover);
	rough = mix(rough, 0.55, 0.6 * mud);
	float lane = smoothstep(0.55, 1.1, g.r * GRIT_EDGE_CAP);   // the walked middle of a street (style bible 15: the calmest ground)
	int fate = grit_fate(sett.x, g.a, min(g.g, 0.7), lane);
	float f1 = kp * float(fate == 1);   // every fate fades out below ~3 px (keep): nothing crawls at the play camera
	alb = mix(alb, mudc * 1.25, f1 * sett.y);   // a missing sett: a hole of mud, paler than the joints round it
	rel = mix(rel, 0.1, f1);
	float f2 = kp * float(fate == 2);
	alb *= mix(1.0, 0.72, f2);   // a sunken sett: lower and darker
	rel = mix(rel, rel * 0.45, f2);
	float f3 = kp * float(fate == 3) * sett.y * (1.0 - smoothstep(0.03, 0.07, abs(sett.z * 0.8 - sett.w + (fract(sett.x * 5.3) - 0.5) * 0.3)));
	alb = mix(alb, vec3(0.035, 0.033, 0.03), 0.85 * f3);   // a crack across it
	float f4 = kp * float(fate == 4) * sett.y;
	alb = mix(alb, vec3(dot(alb, LUMA)) * vec3(1.6, 1.55, 1.42), 0.7 * f4);   // an odd pale stone, a repair
	float ken = grit_kennel(g, run);
	alb = mix(alb, mudc * 0.7, 0.7 * ken);   // the kennel: dark, wet, a channel
	rel = mix(rel, 0.25, ken);
	rough = mix(rough, 0.35, ken);
	int c = ken > 0.5 ? 3 : (mud > 0.35 ? 2 : 0);
	c = fate > 0 && c != 4 ? 6 + fate : c;   // the instrument counts the fate where it is, even where the look fades it out
	return grit_class_colour(c);
}

// The earth beside a street (plan G3): damp and darker within 1 in of the setts.
void grit_earth(vec2 w, inout vec3 alb, inout float rough) {
	if (grit_on < 0.5) {
		return;
	}
	float damp = smoothstep(0.1, 0.7, grit_at(w).g);
	alb *= mix(1.0, 0.68, damp);
	rough = mix(rough, 0.75, damp);
}

// The debug colour of an open-ground fragment for grit_debug = 2: the raw map.
vec3 grit_map_colour(vec2 w) {
	vec4 g = grit_at(w);
	return vec3(g.r, g.g, 0.0);
}

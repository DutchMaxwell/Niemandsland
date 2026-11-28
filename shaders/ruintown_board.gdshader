shader_type spatial;
// Look of a generated ruin-town board (BoardgenGreybox, theme RuinTown): ONE material for every box and gable of the board, all procedural
// (no texture file, nothing from a third party). The surface kind comes per instance (INSTANCE_CUSTOM.x, same contract as tiefwerk_board.gdshader),
// the base colours from the theme palette. Wall faces by height: 0-3 in coursed quarry stone with a door here and there, 3-6 in half-timber with
// plaster and small shuttered windows, 6 in up ashlar; an intact house is half-timber on a stone plinth under its tiled gable roof; the city wall
// and the stone pieces are coursed stone, a chimney is brick. The two halves of the board draw their stones, plaster and tiles with other seeds.
#include "res://shaders/tiefwerk_noise.gdshaderinc"
#include "res://shaders/ruintown_green.gdshaderinc"
#include "res://shaders/ruintown_soil.gdshaderinc"   // (LOOK5 S1) the ground as a material - inert until S4 calls soil_blend
uniform sampler2D green_map : filter_linear, repeat_disable;   // (LOOK5 S6) BoardgenTownGreen.map: R cover, G wear, B verge
uniform float soil_debug = 0.0;   // (LOOK5 S6) the grit debug exit for the soil: 1 the heaviest layer's class colour, 2 the blend-band share (grey)

uniform vec4 palette[19];   // display colours by kind index (BoardgenTheme.TOWN_KINDS)
uniform vec3 board_origin;   // world position of the board centre
uniform float cell_in = 3.0;
uniform sampler2D ground_map : filter_nearest;   // one texel per cell: R = surface kind, G = how a street runs (0 along x, 1 along z, 0.5 junction / square), BA = offset of the junction's centre (half cells, 128 = none)
uniform vec2 board_cells = vec2(16.0, 16.0);

// The authored T-R1 surface sets (plan R9; the CC0 sets staged by the assets lane), read when the library has them cached: coursed stone, plaster, timber, earth. `t_on` = 1 per complete set;
// 0 keeps the procedural surface. The albedo is used as a RATIO to the set's own mean, so the palette and per-lot tints survive and only the detail comes from the texture; the normal map
// replaces the procedural relief on the faces it covers. `t_tile` = inches per tile.
uniform sampler2D t_stone : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D t_plaster : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D t_timber : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D t_earth : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D n_stone : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D n_plaster : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D n_timber : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D n_earth : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 story = vec4(1.0, 0.0, 0.0, 1.0);   // the board's decay story (plan R5): xy = the way the fire came from (a unit vector), zw = the shade side (moss grows there)
uniform vec4 t_on = vec4(0.0);   // stone, plaster, timber, earth
uniform vec4 t_tile = vec4(1.3, 3.0, 3.0, 3.0);
uniform bool real_frames = false;   // (train 3) the kit draws the half-timber frames of the houses and the ruins' timber storey as geometry: the paint keeps only the infill
const vec3 MEAN_STONE = vec3(0.377, 0.244, 0.137);
const vec3 MEAN_PLASTER = vec3(0.4065, 0.3669, 0.3513);
const vec3 MEAN_TIMBER = vec3(0.1207, 0.0743, 0.0443);
const vec3 MEAN_EARTH = vec3(0.1747, 0.1326, 0.0824);

#include "res://shaders/ruintown_grit_tile.gdshaderinc"

vec3 ratio_of(sampler2D t, vec2 uv, vec3 mean) {
	return clamp(texture(t, uv).rgb / mean, vec3(0.3), vec3(2.6));
}

vec3 normal_of(sampler2D n, vec2 uv) {
	return texture(n, uv).xyz * 2.0 - 1.0;
}

// The coursed-stone set on a face point (uv in inches: image up = the direction of increasing uv.y): true when it is cached, with its detail ratio and normal.
bool use_stone(vec2 uv, inout vec3 ratio, inout vec3 tn) {
	if (t_on.x < 0.5) {
		return false;
	}
	if (grit_on > 0.5) {   // (plan PLAN_RUINTOWN_GRIT life train: with the grit map the house walls and the flag tops keep the procedural coursed stone - a stone per hash, no tile period)
		return false;
	}
	vec2 tuv = vec2(uv.x, -uv.y) / t_tile.x;
	ratio = clamp(grit_albedo(t_stone, tuv) / MEAN_STONE, vec3(0.3), vec3(2.6));   // (plan W0: without its 1.3 in period)
	tn = grit_normal(n_stone, tuv);
	return true;
}

// Plaster between the frame timbers and the timbers themselves (`wood` = 1 on a timber): each set that is cached; true when either is.
bool use_frame(vec2 uv, float wood, inout vec3 ratio, inout vec3 tn) {
	vec3 rp = vec3(1.0);
	vec3 np = vec3(0.0, 0.0, 1.0);
	vec3 rt = vec3(1.0);
	vec3 nt = vec3(0.0, 0.0, 1.0);
	if (t_on.y > 0.5) {
		vec2 pu = vec2(uv.x, -uv.y) / t_tile.y;
		rp = clamp(grit_albedo(t_plaster, pu) / MEAN_PLASTER, vec3(0.3), vec3(2.6));
		np = grit_normal(n_plaster, pu);
	}
	if (t_on.z > 0.5) {
		vec2 tu = vec2(uv.x, -uv.y) / t_tile.z;
		rt = ratio_of(t_timber, tu, MEAN_TIMBER);
		nt = normal_of(n_timber, tu);
	}
	ratio = mix(rp, rt, wood);
	tn = mix(np, nt, wood);
	return t_on.y > 0.5 || t_on.z > 0.5;
}

// The ground's floor (silhouette round 21.11., maintainer: "too dark"): the streets and the packed earth sit below the models' own values (readability gate) but no longer near black.
const float GROUND_COBBLE = 0.66;   // (townC4: 0.7 -> 0.66, the street ground sat on its luma bar) was 0.42 (train 2: the lamp pools shrank, the moon carries the street now), 0.27 before
const float GROUND_EARTH = 0.55;   // was 0.32
const float DECK_KEEP_HUE = 0.15;   // (townC4) how much of the boards' own warm hue survives the weather
const float DECK_LIFT = 1.12;
const float DECK_MOSS = 0.0;   // (townC4) the shade-side moss on a deck and on a stone top: on grey boards and flags it read as a green carpet from above (top camera green band 3-6 %)
const float TOP_LIFT = 1.15;   // (townC4) the cleaned flag tops a step paler, as C's grey stone
const float BAND_COVER = 0.06;
const float TOP_RIM_MOSS = 0.6;   // (texture plan step 7) in the outer 0.5 in of a stone top the moss gathers twice as thick
const float TOP_MOSS = 0.3;   // (lead 22.11.: C keeps moss in the seams and on the north side only - the green lives on the earth)
const float COVER_CUT = 0.58;   // the fbm level above which the earth is overgrown (~25 % of the earth; plan TARGET C, E2)
varying vec3 wpos;
varying vec3 wnrm;
varying flat float kind;
varying flat vec3 box_in;   // the size of the box in inches (INSTANCE_CUSTOM.gba): where its edges are
varying vec3 lpos;   // the point inside the box, in inches off the box's centre

const float IN = 0.0254;

// Tabletop scale (plan D-R2: true 1:56 x ~1.4, so the texture survives at arm's length): feature sizes in inches. A pawn base (~1 in) covers about seven setts and a wall course is a fifth of a pawn.
const float SETT_W = 0.14;
const float SETT_H = 0.11;
const float SETT_DEPTH_IN = 0.09;   // the setts' relief depth (look review R5: the relief read only under a lamp)
const float SETT_CAVITY = 0.45;   // light-independent: the joints a share darker, the crowns a little lighter (the mean stays), so the setts read under the moon too
const float SKY_AMBIENT = 1.0;   // (look review 2, R13) the ambient follows the bent normal on up-facing ground: a sett's crown sees more sky than its sides and joints
const float SKY_AMBIENT_FLOOR = 0.1;   // the share of the ambient a face tilted ~50 deg off the sky keeps
const float COURSE = 0.24;   // wall stone: courses 0.24 in high, stones 0.3 - 0.8 in long (len 0.5 x 0.7 .. 1.5)
const float TILE_W = 0.16;
const float TILE_H = 0.13;
const float BOARD_W = 0.18;   // floor boards 0.18 in wide, 1.5 - 3 in long

// How much of a pattern whose features are `size` inches survives at this pixel: 1 when a feature spans 3.5 pixels or more, 0 below 1.5 (it averages out instead of shimmering).
float keep(float coord, float size) {
	return smoothstep(1.5, 3.5, size / max(fwidth(coord), 0.00001));
}

#include "res://shaders/ruintown_grit.gdshaderinc"

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	kind = INSTANCE_CUSTOM.x;
	box_in = INSTANCE_CUSTOM.gba;
	lpos = VERTEX * INSTANCE_CUSTOM.gba;   // the unit cube's corners are +-0.5
}

// Coursed stone: courses `course` in high, stones about `len` in long, offset per course, dark mortar, a tone per stone.
// `fr` = (row id, inches up inside the row, the row's course height), from `flag_row` or a fixed course in stone(). `mortar` = the joint's colour.
vec3 stone_rows(vec2 uv, float seed, vec3 fr, float len, vec3 tint, vec3 mortar, out float rel) {
	float row = fr.x;
	float course = fr.z;
	float l = len * (0.7 + 0.8 * h21(vec2(row, seed + 7.0)));
	float x = uv.x + h21(vec2(row, seed)) * 4.0;
	float col = floor(x / l);
	vec2 f = vec2(fract(x / l) * l, fr.y);
	float edge = smoothstep(0.0, course * 0.11, min(min(f.x, l - f.x), min(f.y, course - f.y)));
	float tone = h21(vec2(col, row) + seed);
	vec3 laid = mix(mortar, tint * mix(0.72, 1.12, tone) * mix(0.9, 1.1, vnoise(uv * 4.0)), edge);
	rel = mix(0.5, edge * (0.8 + 0.2 * tone), keep(uv.y, course));   // the mortar is recessed, a stone stands a little proud
	return mix(tint * 0.8, laid, keep(uv.y, course));   // too fine for the pixel: the mean of stone and mortar
}

vec3 stone(vec2 uv, float seed, float course, float len, vec3 tint, out float rel) {
	return stone_rows(uv, seed, vec3(floor(uv.y / course), fract(uv.y / course) * course, course), len, tint, vec3(0.15, 0.14, 0.13), rel);
}

// (texture plan step 6) Irregular flag courses: bands of three rows 0.27 / 0.36 / 0.45 in (look review R1: was 0.45 / 0.6 / 0.75, too coarse), their order rotated by a hash of the band -> (row id, y inside the row, course).
vec3 flag_row(float y, float seed) {
	float band = floor(y / 1.08);
	float o = floor(h21(vec2(band, seed + 13.0)) * 2.999);
	float c0 = 0.27 + 0.09 * mod(o, 3.0);
	float c1 = 0.27 + 0.09 * mod(o + 1.0, 3.0);
	float y0 = y - band * 1.08;
	float i = y0 < c0 ? 0.0 : (y0 < c0 + c1 ? 1.0 : 2.0);
	float start = i < 0.5 ? 0.0 : (i < 1.5 ? c0 : c0 + c1);
	return vec3(band * 3.0 + i, y0 - start, i < 0.5 ? c0 : (i < 1.5 ? c1 : 1.08 - c0 - c1));
}

// Per-lot identity (plan R4b): four plasters (off-white, ochre, faded oxide red, grey-green) and three timbers (tarred, weathered grey, brown), picked by the lot's hash in the ground map.
vec3 plaster_of(float lot) {
	float k = floor(lot * 3.999);
	return grit_plaster(k < 0.5 ? vec3(0.86, 0.80, 0.68) : (k < 1.5 ? vec3(0.78, 0.62, 0.36) : (k < 2.5 ? vec3(0.62, 0.36, 0.28) : vec3(0.60, 0.65, 0.57))));   // (plan W2: faded with the grit map)
}

vec3 wood_of(float lot) {
	float k = floor(fract(lot * 7.0) * 2.999);
	return k < 0.5 ? vec3(0.07, 0.05, 0.04) : (k < 1.5 ? vec3(0.30, 0.28, 0.25) : vec3(0.20, 0.12, 0.07));
}

// The five roofs of the town (plan R4b; roofs lane 22.11., target C: weathered slate and grey-brown shingle, at most one roof in five a dull brick-brown clay, never orange),
// picked by the lot's hash, all in the wall stone's value range.
vec3 roof_of(float lot, vec3 clay) {
	float k = floor(fract(lot * 5.0) * 4.999);
	return k < 0.5 ? vec3(0.26, 0.27, 0.30) : (k < 1.5 ? vec3(0.23, 0.245, 0.27) : (k < 2.5 ? vec3(0.27, 0.25, 0.23) : (k < 3.5 ? mix(vec3(0.25, 0.24, 0.22), vec3(0.22, 0.27, 0.18), 0.35) : vec3(0.30, 0.22, 0.18))));
}

// Half-timber with a grammar (plan R4a), one 3 in cell wide and one 3 in storey high: a sill beam, a mid rail and a top plate; posts every 0.75 in; an opening (a window between two posts
// with a sill and a lintel) in most cells, braces only in the CORNER bays and never across it; the infill by bay: plaster, brick nogging, bare lath or - on a ruin (`holes` > 0) - a hole.
// The lot's hash picks the plaster and the timber; `rel` = the relief height (frame proud, opening recessed).
vec3 timber(vec2 uv, float seed, vec3 plaster, inout vec3 emis, out float rel, float lot, float holes_in, out float wood_mask, out float soot_mask) {
	float painted = step(-0.5, holes_in);   // holes_in < 0 (= holes - 1): the frame is real geometry, paint the infill only
	float holes = holes_in < -0.5 ? holes_in + 1.0 : holes_in;
	float y = mod(uv.y, 3.0);
	float cell = floor(uv.x / 3.0);
	float x = uv.x - cell * 3.0;
	float bay = floor(x / 0.75);
	float lx = fract(x / 0.75);
	float hc = h21(vec2(cell, seed + 3.0));
	vec3 pl = mix(plaster, plaster_of(lot), 0.7);
	vec3 wood = wood_of(lot) * mix(0.8, 1.2, vnoise(vec2(uv.x * 9.0, uv.y * 1.5)));
	float post = smoothstep(0.06, 0.04, min(lx, 1.0 - lx) * 0.75);
	post *= painted;
	float beam = painted * max(smoothstep(0.17, 0.12, y), max(smoothstep(0.17, 0.12, 3.0 - y), smoothstep(0.075, 0.05, abs(y - 1.5))));
	float has_open = painted * step(0.3, hc);
	vec2 wd = abs(vec2(x - 1.5, y - 1.55)) - vec2(0.6, 0.6);
	float d = max(wd.x, wd.y);
	float inside = has_open * step(d, 0.0);
	float frame = has_open * step(0.0, d) * step(d, 0.07);
	float corner = step(bay, 0.5) + step(2.5, bay);
	float t = bay < 1.5 ? 1.0 - lx : lx;
	float brace = painted * corner * step(0.4, h21(vec2(cell, seed + 1.0))) * smoothstep(0.07, 0.04, abs(y / 3.0 - t) * 1.6) * step(0.3, y) * step(y, 2.7);
	float hb = h21(vec2(cell * 4.0 + bay, seed + 6.0));
	vec3 infill = pl * mix(0.84, 1.1, fbm(uv * 1.7 + seed)) * mix(0.62, 1.0, smoothstep(0.0, 1.1, y));
	infill = grit_plaster_wear(infill, uv, x, y, seed, wood);   // (plan W2)
	infill = mix(infill, mix(infill, vec3(dot(infill, vec3(0.333))) * vec3(1.04, 1.0, 0.9), 0.45) * mix(0.55, 0.78, fbm(uv * 0.8 + seed + 3.0)) * mix(0.78, 1.0, smoothstep(0.0, 1.0, y)), 1.0 - painted);   // (train 3, lead review: between real timbers the infill is dirty cream-grey, blotchy, damp rising from the sill - not a zebra)
	// Brick nogging and bare lath (plan TEX 3): one dull tone with a thin dark joint, not two alternating tones (a light / dark zebra
	// that shimmered at the start camera). The fade is keyed on the joint, the narrowest feature: below ~3.5 px it mixes to the mean.
	float mortar = mix(0.2, step(fract(y / 0.12), 0.2), keep(uv.y, 0.024));   // 0.024 in joint every 0.12 in course
	float lath = mix(0.25, step(fract(uv.y / 0.09), 0.25), keep(uv.y, 0.0225));   // 0.0225 in gap every 0.09 in lath
	infill = hb > 0.6 && hb < 0.75 ? mix(vec3(0.28, 0.19, 0.15), vec3(0.22, 0.15, 0.12), mortar) : infill;   // brick nogging, dull weathered brick
	infill = hb >= 0.75 && hb < 0.9 ? mix(wood * 1.05, wood * 0.8, lath) : infill;   // bare lath
	float hole = step(0.9, hb) * step(0.0001, holes) * step(hb, 0.9 + holes);
	float members = max(post * (1.0 - inside), max(beam, max(brace, frame)));
	vec3 c = mix(infill, wood, members);
	c = mix(c, vec3(0.05, 0.04, 0.04), hole * (1.0 - members));
	rel = mix(0.35 + 0.25 * fbm(uv * 5.0 + seed), 0.95, members);   // plaster with a trowel's waviness, the frame timbers proud of it
	rel = mix(rel, 0.05, max(inside, hole * (1.0 - members)));   // an opening and a hole are recesses
	c = mix(c, vec3(0.06, 0.05, 0.05), inside);
	float lit = inside * step(d, -0.08);
	float glow = step(0.875, h21(vec2(cell, seed + 5.0)));   // one window in eight is lit (plan R7b): a dim warm glow and a flat warm patch of spill on the wall under its sill
	emis += vec3(1.0, 0.55, 0.22) * lit * glow * 0.6;
	emis += vec3(1.0, 0.55, 0.22) * has_open * glow * step(y, 0.95) * smoothstep(0.7, 0.15, abs(x - 1.5)) * smoothstep(0.0, 0.4, y) * 0.12;
	wood_mask = members;
	soot_mask = has_open * (step(2.15, y) * smoothstep(0.75, 0.0, abs(x - 1.5) - (y - 2.15) * 0.5) + 0.5 * step(y, 0.95) * smoothstep(0.45, 0.0, abs(x - 1.5) - 0.55) * vnoise(vec2(x * 8.0, y * 2.0)));   // soot fanning above an opening, a streak under its sill
	return c;
}

// Cobbles: staggered rounded setts about 0.6 x 0.4 in, a tone per sett, dark joints. They run along the street (`run` 0 = along x, 1 = along z) and fan round the
// middle of a junction or a square (`fan` = the offset of that middle from the sample, inches).
// `sett_out` (plan PLAN_RUINTOWN_GRIT): the sett's own hash, its mask (1 on the stone, 0 in the joint) and the point inside it (-0.5..0.5), for its tone and its fate.
vec3 cobble(vec2 xz, float seed, vec3 tint, float run, vec2 fan, out float rel, out vec4 sett_out) {
	float row;
	float x;
	vec2 f;
	if (run > 0.25 && run < 0.75) {
		float r = length(fan) + (vnoise(fan * 0.5 + seed) - 0.5) * 0.12;   // (train 2) the rings wobble
		row = floor(r / SETT_H);
		float n = max(floor(6.2832 * (row + 0.5) * SETT_H / SETT_W), 3.0);   // a whole number of setts in every ring: no seam
		x = (atan(fan.y, fan.x) / 6.2832 + 0.5) * n + 0.5 * mod(row, 2.0) + h21(vec2(row, seed)) * 0.3;
		f = vec2(fract(x), fract(r / SETT_H)) - 0.5;
	} else {
		vec2 q = run > 0.75 ? xz.yx : xz;
		q.y += (vnoise(vec2(q.x * 0.35, seed)) - 0.5) * 0.14;   // (train 2) the rows bend a little
		row = floor(q.y / SETT_H);
		x = q.x / (SETT_W * mix(0.85, 1.2, h21(vec2(row, seed + 5.0)))) + 0.5 * mod(row, 2.0) + h21(vec2(row, seed)) * 0.3;   // each row its own stone length
		f = vec2(fract(x), fract(q.y / SETT_H)) - 0.5;
	}
	float sh = h21(vec2(floor(x), row) + seed);
	// (train 2) every stone its own size and seat in its cell: uneven joints; one in twelve runs on over its end joint (a long stone)
	vec2 hs = vec2(fract(sh * 9.13) > 0.92 ? 0.49 : 0.25 + 0.1 * fract(sh * 3.71), 0.25 + 0.08 * fract(sh * 5.29));   // (lead, close street still: joints a third narrower)
	f -= (vec2(fract(sh * 2.17), fract(sh * 6.61)) - 0.5) * 0.08;
	float sett = smoothstep(0.17, 0.09, length(max(abs(f) - hs, 0.0)));
	vec3 laid = mix(vec3(0.11, 0.10, 0.085), grit_sett_tint(tint, sh) * mix(0.9, 1.1, vnoise(xz * 3.0)) * mix(0.86, 1.08, vnoise(xz * 11.0 + sh * 7.0)), sett);   // (train 2: dark dirty joints, a grain in every stone)
	sett_out = vec4(sh, sett, f);
	rel = mix(0.5, mix(0.34, 0.36 + 0.64 * clamp(1.0 - 3.2 * dot(f, f), 0.0, 1.0), sett), keep(xz.x, SETT_W));   // (lead: the dirt bed rises to the stone's shoulder - the stones sit in it, not on it)   // a rounded, worn sett in a recessed joint (train 2: pillowed, not a flat tile)
	return mix(tint * 0.78, laid, keep(xz.x, SETT_W));   // setts of 0.14 in are ~3 px at the play camera: below that they average out instead of crawling
}

// The ground map at a point (inches off the board centre), and the noise that bends the lookup: the earth / cobble border follows the bent point, not the 3 in grid.
vec4 ground_at(vec2 xz) {
	return texture(ground_map, clamp(xz / (cell_in * board_cells) + 0.5, vec2(0.001), vec2(0.999)));
}

vec2 wander(vec2 xz) {
	return (vec2(fbm(xz * 0.31 + vec2(3.0)), fbm(xz * 0.31 + vec2(11.0))) - 0.47) * 2.4;
}

// A door in the stone ground storey: 0.7 x 1.4 in in the middle of some 3 in cells.
float door(vec2 uv, float seed) {
	float cell = floor(uv.x / 3.0);
	vec2 d = abs(vec2(uv.x - cell * 3.0 - 1.5, uv.y - 0.7)) - vec2(0.35, 0.7);
	return step(0.62, h21(vec2(cell, seed + 21.0))) * step(max(d.x, d.y), 0.0);
}

void fragment() {
	int k = clamp(int(kind + 0.5), 0, 18);
	vec3 p = (wpos - board_origin) / IN;   // inches off the board centre, y up
	float half_seed = step(0.0, p.z);   // the south half draws with other seeds: a half turn does not look like the other half
	float seed = 17.0 * half_seed;
	vec3 tint = palette[k].rgb;
	vec3 alb = tint;
	vec3 emis = vec3(0.0);
	float rough = 0.92;
	float rel = 0.5;     // the height of the surface pattern, 0 = joint / gap, 1 = crown (0.5 = flat): the end of fragment() turns it into a bent normal, roughness and occlusion
	float wood_m = 0.0;   // 1 where a half-timber face shows its timbers, soot_m: the soot of its openings (plan R5)
	float soot_m = 0.0;
	float spec = 0.5;   // the specular level (the default of a dielectric); water takes 1.0 so the probe's reflection shows
	float depth_in = 0.0;   // how deep that relief is, in inches (0 = none)
	float ao = 1.0;
	float top_ring = 0.0;   // (texture plan step 7) 1 in the outer 0.5 in of a flag top, where rubble and moss gather
	vec3 tex_ratio = vec3(1.0);   // the authored set's detail on this face (1 = none) and its tangent-space normal
	vec3 tex_n = vec3(0.0, 0.0, 1.0);
	float tex_on = 0.0;
	vec2 gw = p.xz;   // GRIT (ruintown_grit.gdshaderinc): the bent ground lookup point and the debug colour of this fragment
	vec3 dbg = vec3(0.0);
	bool wall_face = abs(wnrm.y) < 0.5;
	vec3 tex_t = wall_face ? (abs(wnrm.x) > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0)) : vec3(1.0, 0.0, 0.0);   // image right and image up of the face in world space
	vec3 tex_b = wall_face ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0);
	if (abs(wnrm.y) < 0.2) {   // a wall face (or a gable end)
		float lot_h = ground_at(p.xz - wnrm.xz * 0.2).b;   // the lot's hash (ground map blue: house cells only): its plaster and timber
		vec2 uv = vec2(abs(wnrm.x) > 0.5 ? p.z : p.x, p.y);
		if (k == 15) {   // a gable end: plaster and a timber frame
			alb = timber(uv, seed, palette[13].rgb, emis, rel, lot_h, 0.0, wood_m, soot_m);
			depth_in = 0.03;
			rough = mix(0.95, 0.8, step(0.8, rel));
			ao = mix(0.6, 1.0, smoothstep(0.1, 0.5, rel));
			if (use_frame(uv, smoothstep(0.7, 0.9, rel), tex_ratio, tex_n)) {
				tex_on = 1.0;
				depth_in = 0.0;
			}
		} else if (k == 13) {   // an intact house: half-timber on a stone plinth
			float plinth = 0.3 + 0.75 * fract(kind);   // the house's own plinth height rides in the fraction of its kind
			if (uv.y < plinth) {
				alb = stone(uv, seed, 0.2, 0.45, vec3(0.5, 0.48, 0.44), rel);
				rough = 0.85;
				depth_in = 0.03;
				if (use_stone(uv, tex_ratio, tex_n)) {
					alb = vec3(0.5, 0.48, 0.44);
					tex_on = 1.0;
					depth_in = 0.0;
				}
			} else {
				alb = timber(vec2(uv.x, uv.y + 2.5), seed, tint * mix(0.95, 1.05, half_seed), emis, rel, lot_h, real_frames ? -1.0 : 0.0, wood_m, soot_m);
				depth_in = 0.03;
				rough = mix(0.95, 0.8, step(0.8, rel));
				ao = mix(0.6, 1.0, smoothstep(0.1, 0.5, rel));
				if (use_frame(uv, smoothstep(0.7, 0.9, rel), tex_ratio, tex_n)) {
					tex_on = 1.0;
					depth_in = 0.0;
				}
			}
		} else if (k == 12 || k == 9 || k == 10 || k == 16) {   // city wall, stone pieces, chimney: coursed stone (brick for the chimney)
			alb = k == 16 ? stone(uv, seed, 0.1, 0.22, tint, rel) : stone(uv, seed, COURSE, 0.5, tint, rel);
			depth_in = 0.025;
			rough = 0.85;
			ao = mix(0.6, 1.0, smoothstep(0.2, 0.7, rel));
			if (k != 16 && use_stone(uv, tex_ratio, tex_n)) {
				alb = tint * 0.95;   // the palette tone; the set brings the stones, the mortar and the wear
				tex_on = 1.0;
				depth_in = 0.0;
				ao = 1.0;
			}
		} else if (k == 18) {   // a wooden prop: planks with iron bands
			alb = tint * mix(0.7, 1.15, h21(vec2(floor(uv.x * 4.0), seed))) * mix(0.55, 1.0, smoothstep(0.0, 0.05, abs(fract(uv.y * 2.5) - 0.5) - 0.42)) * mix(0.8, 1.0, seam(uv.x, 0.25, 0.03));
		} else if (k == 3 || k == 4 || k == 6) {   // ruined house tiers and towers, by storey
			float part = k == 6 ? 0.5 : ground_at(p.xz - wnrm.xz * 0.2).g;   // the part of a ruined row this face belongs to (its tone and where its storey band falls)
			tint *= mix(0.86, 1.12, part);
			uv.y += (part - 0.5) * 0.7;
			float band = k == 6 ? 2.0 : floor(uv.y / 3.0);   // a tower is stone all the way up
			if (band < 0.5 || band > 1.5) {
				alb = band < 0.5 ? mix(stone(uv, seed, COURSE, 0.5, tint * 0.9, rel), vec3(0.09, 0.06, 0.04), door(uv, seed)) : stone(uv, seed, COURSE, 0.55, tint * 1.05, rel);
				rough = 0.85;
				depth_in = 0.03;
				ao = mix(0.6, 1.0, smoothstep(0.1, 0.6, rel));
				if (use_stone(uv, tex_ratio, tex_n)) {
					alb = band < 0.5 ? mix(tint * 0.95, vec3(0.09, 0.06, 0.04), door(uv, seed)) : tint * 1.05;
					tex_on = 1.0;
					depth_in = 0.0;
					ao = 1.0;
				}
			} else {
				alb = timber(uv, seed, tint * 1.02, emis, rel, lot_h, real_frames ? -0.9 : 0.1, wood_m, soot_m);
				rough = mix(0.95, 0.8, step(0.8, rel));
				depth_in = 0.03;
				ao = mix(0.6, 1.0, smoothstep(0.1, 0.6, rel));
				if (use_frame(uv, smoothstep(0.7, 0.9, rel), tex_ratio, tex_n)) {
					tex_on = 1.0;
					depth_in = 0.0;
				}
			}
		}
		grit_city_masonry(k, p, wnrm, seed, tint, box_in, lpos, alb, rel, depth_in, tex_on, tex_ratio, tex_n, ao);   // (plan W0: the city wall's own masonry, no banded set)
		float hband = k == 3 || k == 4 ? floor(uv.y / 3.0) : -1.0;   // (the storey of a ruined row: its branch has shifted uv by its part already)
		grit_house_wall(k, p, wnrm, seed, lot_h, hband, 0.3 + 0.75 * fract(kind), hband == 0.0 && !real_frames ? door(uv, seed) : 0.0, int(ground_at(p.xz + wnrm.xz * 0.4).r * 255.0 + 0.5), alb, rel, depth_in, tex_on, tex_ratio, tex_n, ao);   // (plastered rubble in a timber frame over a stone plinth; rubble onto a yard)
	} else if (wnrm.y < 0.95 && k == 15) {   // a sloped roof face: rows of tiles, a tone per tile, a shadow under each row
		tint = roof_of(ground_at(p.xz - wnrm.xz * 0.2).b, tint);   // each roof its own clay, slate or mossy clay
		float along = abs(wnrm.x) > abs(wnrm.z) ? p.z : p.x;
		float row = floor(p.y / TILE_H);
		float tile = floor(along / TILE_W + row * 0.5);
		vec3 base = tint * mix(0.8, 1.05, h21(vec2(tile, row + seed)));   // (roofs lane 22.11.: a narrower tone per tile, no bright stripes)
		vec3 laid = base * mix(0.7, 1.0, smoothstep(0.0, 0.7, fract(p.y / TILE_H))) * mix(1.0, 0.8, smoothstep(0.55, 0.7, fbm(vec2(along, p.y) * 1.3 + seed)));
		alb = mix(tint * 0.82, laid, keep(p.y, TILE_H));   // 0.16 x 0.13 in tiles: the mean below ~3 px
		rel = mix(0.5, fract(p.y / TILE_H) * (0.8 + 0.2 * h21(vec2(tile, row))), keep(p.y, TILE_H));   // every row of tiles is a step: a line of shadow under each
		alb = grit_roof(alb, tile, row, seed, ground_at(p.xz - wnrm.xz * 0.2).b, vec2(along, p.y), keep(p.y, TILE_H), rel);   // (plan W3)
		depth_in = 0.03;
		rough = 0.7;
		ao = mix(0.6, 1.0, smoothstep(0.0, 0.5, rel));
	} else if (wnrm.y > 0.5) {   // a top face, by kind
		vec2 xz = p.xz;
		float grid = 1.0;   // the faint 3 in cell line is gone from every top (plan R1: no grid to count on the table)
		float run = 0.5;
		vec2 fan = vec2(1.0, 0.0);
		float gutter = 0.0;
		if (k <= 1) {   // the open ground (earth, street): the border between the two wanders off the grid; RUINS, FOREST and DANGEROUS ground keep their exact cell edge
			vec2 w = xz + wander(xz);
			vec4 g = ground_at(w);
			if (int(g.r * 255.0 + 0.5) > 1 && int(ground_at(xz).r * 255.0 + 0.5) <= 1) {   // (look review 2, R14) the bent border wandered into a wall / ruin cell: keep this cell's own ground, or the setts lost their run and drew a plain strip
				w = xz;
				g = ground_at(w);
			}
			gw = w;
			if (int(g.r * 255.0 + 0.5) <= 1) {
				k = int(g.r * 255.0 + 0.5);
				tint = palette[k].rgb;
				alb = tint;
				run = g.g;
				vec2 centre = (floor(w / cell_in) + 0.5) * cell_in + (floor(g.ba * 255.0 + 0.5) - 128.0) * 0.5 * cell_in;   // one middle per junction / square (SETT-SEAM: half cells, exact)
				fan = xz - centre;   // the sett pattern itself is not bent: only the border is
			}
			for (int d = 0; d < 4; d++) {   // a gutter: wet dark stone where the street ends within 0.3 in of earth
				vec2 o = vec2(d < 2 ? (d == 0 ? 0.3 : -0.3) : 0.0, d >= 2 ? (d == 2 ? 0.3 : -0.3) : 0.0);
				gutter = max(gutter, float(int(ground_at(w + o).r * 255.0 + 0.5) == 0));
			}
		}
		if (k == 1) {   // streets: cobbles
			float crown;
			vec4 sett;
			alb = mix(cobble(xz, seed, grit_street_tint(tint * vec3(0.96, 1.0, 1.08) * GROUND_COBBLE), run, fan, crown, sett), vec3(0.06, 0.055, 0.05), 0.55 * gutter * (1.0 - grit_on));   // (the grit map draws the mud and the kennel instead)   // 0.27 (was 1.15): the streets sit well below the models' own values (readability gate, lead 21.11.)
			rel = crown;
			depth_in = SETT_DEPTH_IN;   // (train 2: was 0.045; look review R5: 0.06 -> 0.09)
			rough = mix(0.85, 0.65, smoothstep(0.3, 0.7, crown));   // (train 2) worn crowns catch the light, dirty joints stay matt
			ao = mix(0.4, 1.0, smoothstep(0.1, 0.5, crown));
			dbg = grit_debug == 2 ? grit_map_colour(gw) : grit_street(xz, gw, sett, run, alb, rel, rough);
			alb *= mix(1.0, mix(1.0 - SETT_CAVITY, 1.0 + 0.35 * SETT_CAVITY, smoothstep(0.1, 0.6, crown)), keep(xz.x, SETT_W));   // (look review R5) the cavity term
			float ne = 0.0;   // (train 2, C3) the setts thin out into the earth: within 0.8 in of an earth border some are gone (earth in the hole), weeds grow in the joints
			for (int d = 0; d < 8; d++) {
				vec2 o = vec2(cos(float(d) * 0.785), sin(float(d) * 0.785));
				ne = max(ne, max(float(int(ground_at(gw + o * 0.4).r * 255.0 + 0.5) == 0), 0.6 * float(int(ground_at(gw + o * 0.8).r * 255.0 + 0.5) == 0)));
			}
			ne *= mix(0.4, 1.2, vnoise(xz * 1.4 + 41.0));
			float gone = step(fract(sett.x * 31.7), 0.6 * ne) * keep(xz.x, SETT_W);
			alb = mix(alb, palette[0].rgb * GROUND_EARTH * 0.75, gone);
			rel = mix(rel, 0.15, gone);
			alb = mix(alb, vec3(0.07, 0.09, 0.045), 0.7 * ne * (1.0 - sett.y) * (1.0 - gone));
			float trod = smoothstep(0.25, 0.85, ne) * (1.0 - gone);   // (look review 2) where the street meets earth: a broken band of trodden mud, darker in the joints (no light needed)
			alb = mix(alb, grit_mud_colour() * mix(0.7, 0.95, vnoise(xz * 2.7 + seed)), 0.6 * trod * mix(1.0, 0.6, sett.y));
			emis += grit_fill(alb);
		} else if (k == 0) {   // earth: packed, with pebbles, weeds and broken stones
			alb = tint * GROUND_EARTH * mix(0.78, 1.15, fbm(xz * 1.6 + seed));   // 0.32 (was 1.0): the packed earth of the deployment bands sits below the models too (readability gate)
			vec3 soil_s = vec3(0.0);   // (LOOK5 S6) the soil colour (linear) and the base tone it is pinned to
			vec3 soil_base = vec3(1.0);
			vec3 soil_dbg = vec3(-1.0);
			if (soil_on < 0.5) {
				vec2 cp = xz * 3.0;   // 0.33 in cells, a pebble or a weed tuft in some of them: sparse, small, dark and irregular (rotated, stretched, off the cell centre)
				vec2 ci = floor(cp);
				float sp = h21(ci + seed);
				float ang = h21(ci + 3.0) * 6.2832;
				vec2 lf = (fract(cp) - 0.5 - (vec2(h21(ci + 7.0), h21(ci + 13.0)) - 0.5) * 0.4);
				lf = vec2(cos(ang) * lf.x - sin(ang) * lf.y, sin(ang) * lf.x + cos(ang) * lf.y) * vec2(1.0, 1.0 + 1.4 * h21(ci + 5.0));
				float pebble = step(0.955, sp) * smoothstep(0.2, 0.1, length(lf));
				float path = smoothstep(0.03, 0.0, abs(vnoise(xz * 0.21 + seed) - 0.5)) * step(0.5, vnoise(xz * 0.07 + 5.0)) * (1.0 - grit_on);   // (gone with the grit map: it led nowhere)   // a worn path: pale, meandering (a noise stand-in until the doors of R12c exist)
				// ground cover (plan TARGET C, E2): painted only, 0 in high - patches of rank growth, thicker within 1 in of a raised lot or a plot, thinner on the worn paths
				float near = 0.0;
				for (int d = 0; d < 4; d++) {
					vec2 o = vec2(d < 2 ? (d == 0 ? 1.0 : -1.0) : 0.0, d >= 2 ? (d == 2 ? 1.0 : -1.0) : 0.0);
					near = max(near, float(int(ground_at(gw + o).r * 255.0 + 0.5) >= 2));
				}
				float band = smoothstep(9.0, 13.0, abs(xz.y));   // (townC4, lead 22.11.: the green lives on the earth - the deployment strips overgrow most, like C's)
				float cover = smoothstep(COVER_CUT - 0.04, COVER_CUT + 0.04, fbm(xz * 0.35 + seed * 0.37) + 0.35 * near - 0.4 * path + BAND_COVER * band)
					* smoothstep(0.28, 0.48, vnoise(xz * 1.3 + seed * 1.7) + 0.3 * near + 0.25 * band);   // rough, not turf: bare earth between the clumps in the open
				float tuft = max(step(0.915, sp) * step(sp, 0.955), cover * step(sp, 0.6)) * smoothstep(0.26, 0.12, length(lf));   // in the cover 60 % of the 0.33 in cells carry a tuft (4 % outside)
				vec3 soil = alb;
				alb = mix(alb, GREEN_COVER * mix(0.55, 1.25, fbm(xz * 3.1 + seed)), cover);   // a dull dark yellow-grey green between the tufts, mottled
				alb = mix(alb, vec3(0.13, 0.14, 0.08) * mix(0.7, 1.2, h21(ci + 9.0)) * (1.0 + 0.9 * cover), 0.75 * tuft);   // a dull green-brown tuft, never a yellow coin
				alb *= mix(vec3(1.0), green_drift(xz, 0.0), cover);   // (look review R11) dry straw patches and greener ones over 3-8 in (ruintown_green: the one green, folded)
				float clump = green_break(xz, 0.0);   // the cover is clumped, not a carpet: dark hollows between the clumps
				alb *= 1.0 - 0.22 * cover * (1.0 - tuft) * smoothstep(0.55, 0.3, clump) * keep(xz.x, 0.18);
				alb *= min(1.0, (dot(soil, LUMA) + 0.03 * tuft) / max(dot(alb, LUMA), 0.001));   // the cover is never brighter than the soil, a tuft at most 0.03 (the ground stays under the models)
				alb = mix(alb, vec3(0.13, 0.12, 0.11) * mix(0.6, 1.3, h21(ci + 4.0)), pebble);   // a dark stone
				alb = mix(alb, tint * vec3(1.3, 1.3, 1.28), 0.75 * path);   // (was 1.4 1.34 1.2: an orange path; plan TARGET C, E1)
				if (t_on.w > 0.5) {
					vec3 r = ratio_of(t_earth, xz / t_tile.w, MEAN_EARTH);   // real rock and soil under the pebbles, the tufts and the paths
					tex_ratio = mix(vec3(dot(r, vec3(0.333))), r, 0.5);   // halfway to its own grey: the soil keeps its detail and loses its orange (plan TARGET C, E1)
				}
				rel = clamp(0.2 + 0.6 * fbm(xz * 3.0 + seed) - 0.15 * path + 0.35 * pebble + cover * (0.45 * clump - 0.15) + 0.3 * tuft, 0.0, 1.0);   // packed earth: lumps, the worn paths lower; (R11) the cover stands in clumps, a tuft on top
				depth_in = mix(0.05, 0.08, cover);
				ao = mix(1.0, mix(0.7, 1.0, smoothstep(0.2, 0.6, rel)), cover);
				rough = 0.95;
			} else {   // (LOOK5 S6) THE YARD IS A MATERIAL: the four photo soils at their own colour, exposure-pinned to this earth's tone (the readability budget)
				vec3 gm = texture(green_map, xz / (board_cells * cell_in) + 0.5).rgb;   // R cover = grass, G wear = mud, B verge = wet soil at the street's edge
				vec4 w = vec4(max(1.0 - gm.r - gm.g, 0.0) * (1.0 - gm.b), gm.g * (1.0 - gm.b), gm.r * (1.0 - gm.b), gm.b);
				SoilSample sm = soil_blend(w, xz);
				float macro = mix(0.88, 1.12, vnoise(green_fold(xz) * 0.4 + seed));   // lumpy ground over 2.5 in, folded (fairness), and it hides the tile
				soil_base = pow(alb, vec3(2.2));
				soil_s = sm.c * dot(soil_base, LUMA) * macro;
				tex_ratio = soil_s / max(soil_base, vec3(0.0001));
				tex_n = sm.n;
				tex_on = 1.0;
				rel = sm.h;
				ao = sm.ao;
				rough = sm.rough;
				depth_in = 0.06;
				if (soil_debug > 1.5) {   // how much of the pixel sits in the blend band (0 = one layer, 1 = an even mix)
					soil_dbg = vec3(4.0 * sm.k.x * sm.k.y);
				} else if (soil_debug > 0.5) {   // the HEAVIEST weight only, one pure colour per class (a summed colour let a bare + grass mix read as verge)
					soil_dbg = w.x >= max(max(w.y, w.z), w.w) ? vec3(1.0, 0.0, 0.0) : (w.y >= max(w.z, w.w) ? vec3(0.0, 0.0, 1.0) : (w.z >= w.w ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 1.0, 0.0)));   // bare red, mud blue, grass green, verge yellow
				}
			}
			grit_earth(gw, alb, rough);
			if (soil_on < 0.5) {
				emis += grit_fill(alb);
			} else {   // (S6) the Night fill carries the soil: mostly value and grain, a little cool-shifted colour (soil_fill_sat); the lit term keeps the full albedo
				vec3 f = mix(vec3(dot(soil_s, LUMA)) * vec3(0.92, 1.0, 1.10), soil_s, soil_fill_sat);
				emis += f * (dot(grit_fill(alb), LUMA) / max(dot(soil_base, LUMA), 0.0001)) * ao;
			}
			dbg = soil_dbg.x >= 0.0 ? soil_dbg : (grit_debug == 2 ? grit_map_colour(gw) : vec3(0.0));
		} else if (k == 3 || k == 4 || k == 8) {   // floor boards of a ruined house or yard, scorched in patches
			if (k != 8) {
				tint *= mix(0.9, 1.1, ground_at(xz).g);   // each part of a ruined row has its own tone
				float lot_h = fract(ground_at(xz).b * 7.13);   // and each ruined house its own weather (silhouette round 21.11.: one brown for every flat top read as one slab): grey sun-bleached, dark tarred, warm
				tint *= lot_h < 0.33 ? vec3(0.95, 0.97, 1.05) * 1.12 : (lot_h < 0.66 ? vec3(0.78, 0.74, 0.72) : vec3(1.1, 0.98, 0.84));
			}
			if (t_on.z > 0.5) {
				tex_ratio = ratio_of(t_timber, xz / t_tile.z, MEAN_TIMBER);   // the grain of the real planks on the boards
			}
			rel = mix(0.5, seam(xz.y, BOARD_W, 0.018), keep(xz.y, BOARD_W));   // a dark gap between boards
			depth_in = 0.02;
			rough = 0.82;
			alb = tint * mix(0.72, 1.05, h21(vec2(floor(xz.x / 2.2), floor(xz.y / BOARD_W) + seed))) * mix(0.8, 1.0, mix(1.0, seam(xz.y, BOARD_W, 0.018), keep(xz.y, BOARD_W))) * mix(0.84, 1.0, smoothstep(0.35, 0.6, fbm(xz * 0.9 + seed))) * grid;
			alb *= 0.5;   // the decks the models stand on (the deployment bands' yards, the tier floors) sit a step below the models' own values (readability gate)
			// (townC4, play camera: the brown decks were the board's largest warm area, 16 % warm vs C's 5 %) weathered silver-grey boards, a little paler, dirt in the gaps
			alb = mix(vec3(dot(alb, vec3(0.3, 0.55, 0.15))), alb, DECK_KEEP_HUE) * DECK_LIFT;
			alb = mix(alb, vec3(0.07, 0.068, 0.06), 0.5 * (1.0 - seam(xz.y, BOARD_W, 0.018)) * keep(xz.y, BOARD_W));   // dirt in the gaps
			if (k != 8 && box_in.x > 0.0) {   // A BROKEN FLOOR (plan R6): inside the 0.75 in edge strip of the tier, and only where the edge is the lot's outer edge, boards are missing and the joists show; the middle stays solid
				vec2 e2 = box_in.xz * 0.5 - abs(lpos.xz);
				bool nx = e2.x < e2.y;
				float ed = min(e2.x, e2.y);
				vec2 to_edge = nx ? vec2(sign(lpos.x), 0.0) : vec2(0.0, sign(lpos.z));
				float outer = step(0.004, abs(ground_at(xz).b - ground_at(xz + to_edge * (ed + 0.3)).b));   // across the edge is another lot or open ground (a lot is one hash)
				float strip = outer * (1.0 - smoothstep(0.1, 0.75, ed));
				float along = nx ? xz.y : xz.x;
				float lost = step(1.0 - 0.7 * strip, h21(vec2(floor(along / 0.5), floor(ed / 0.25) + seed + 11.0))) * step(0.0001, strip);
				alb = mix(alb, mix(vec3(0.012), vec3(0.09, 0.055, 0.035), step(0.75, fract(along / 0.8))), lost);   // a dark gap with a joist across it
				rel = mix(rel, 0.0, lost);
				depth_in = mix(depth_in, 0.06, lost);
				vec2 sc = xz / 0.55;   // a flat scatter of tile and stone bits, denser at the edge
				vec2 sci = floor(sc);
				float sh = h21(sci + seed + 31.0);
				float lump = step(0.95 - 0.1 * strip, sh) * smoothstep(0.2, 0.1, length(fract(sc) - 0.5 - (vec2(h21(sci + 3.0), h21(sci + 9.0)) - 0.5) * 0.3));
				alb = mix(alb, sh > 0.985 ? vec3(0.46, 0.24, 0.18) : vec3(0.22, 0.21, 0.19), 0.8 * lump * (1.0 - lost));
			}
		} else if (k == 6 || k == 12 || k == 9 || k == 10) {   // tower and wall tops, stone pieces: flagstones
			vec3 fr = flag_row(xz.y, seed);
			alb = stone_rows(xz, seed, fr, 0.43, tint, tint * 0.8, rel);   // (texture plan step 6, look review R1) flagstones 0.27 / 0.36 / 0.45 in courses, 0.3 - 0.65 in long; (6b) worn mortar in the flags' own value range
			depth_in = 0.015;   // (6b) a slightly recessed joint: at 0.03 in its shaded wall drew a dark grid
			rough = 0.85;
			if (use_stone(xz, tex_ratio, tex_n)) {
				alb = tint;
				tex_on = 1.0;
				depth_in = 0.0;
			}
			// weathered flags in the wall's stone family (lead 21.11.: the pale slabs with curly scribbles read as a tile puzzle and were the brightest thing on the board - and the tops are
			// standing room, so they sit a step below the models): darker and greyer, dirt and moss in the joints, a few flags broken by ONE short straight fracture from joint to joint
			float frow = fr.x;   // the flag this point lies on (as stone_rows() lays them)
			float fl_l = 0.43 * (0.7 + 0.8 * h21(vec2(frow, seed + 7.0)));
			float fx = xz.x + h21(vec2(frow, seed)) * 4.0;
			vec2 fc = vec2(floor(fx / fl_l), frow);
			vec2 fp = vec2(fract(fx / fl_l) * fl_l, fr.y);   // inches inside the flag
			vec3 tone = mix(vec3(1.0), grit_stone_tone(h21(fc + seed + 41.0)), 0.85);   // (step 6: 0.85 of the wall's spread - at 0.5 the tops read as one even car park)
			alb = mix(vec3(dot(alb, vec3(0.3, 0.55, 0.15))), alb, 0.35) * tone * vec3(0.53, 0.52, 0.51) * TOP_LIFT;   // (townC4: greyer - the warm tops were a third of the play camera's warm share; was 0.55 / (0.55, 0.52, 0.48))
			float joint = 1.0 - smoothstep(0.08, 0.45, rel);
			float mossy = step(0.8, vnoise(xz * 0.7 + seed * 3.0));
			alb = mix(alb, mossy > 0.5 ? alb * vec3(0.7, 0.85, 0.6) : alb * 0.8, 0.6 * joint * keep(xz.y, fr.z));   // (6b) worn mortar a little darker than its flag, moss a green tint of it - never a black line
			float fh = h21(fc + seed + 77.0);
			float fl = 0.0;
			if (fh > 0.82) {   // a fracture: one straight line through the flag at its own angle, fading out before the joints
				vec2 fo = vec2(fl_l * (0.3 + 0.4 * fract(fh * 7.0)), fr.z * (0.3 + 0.4 * fract(fh * 13.0)));
				float a = fract(fh * 29.0) * 3.14159;
				vec2 dir = vec2(cos(a), sin(a));
				vec2 rp = fp - fo;
				float inside = smoothstep(0.0, 0.05, min(min(fp.x, fl_l - fp.x), min(fp.y, fr.z - fp.y)));
				fl = smoothstep(0.012, 0.0, abs(dot(rp, vec2(-dir.y, dir.x)))) * inside * keep(xz.y, 0.12);
			}
			alb = mix(alb, vec3(0.03, 0.03, 0.03), 0.8 * fl);
			// (texture plan step 7) the top weathers as a whole: a 3 - 9 in value drift, one flag in ten gone or sunk (earth-dark, lower), rubble at the rim
			alb *= mix(0.85, 1.12, fbm(xz * 0.17 + seed));
			float gone = step(0.9, h21(fc + seed + 53.0)) * keep(xz.y, fr.z);
			alb = mix(alb, alb * vec3(0.66, 0.6, 0.5) * mix(0.85, 1.1, vnoise(xz * 3.0 + seed)), gone);   // dirt in the hole: a step darker and browner than its flag (the earth colour itself rendered as a black hole)
			rel = mix(rel, 0.15, gone);
			depth_in = mix(depth_in, 0.03, gone);
			if (box_in.x > 0.0) {   // the outer 0.5 in of the box top (as the deck strip): dirt, small rubble and the thicker moss
				vec2 e2 = box_in.xz * 0.5 - abs(lpos.xz);
				top_ring = 1.0 - smoothstep(0.1, 0.5, min(e2.x, e2.y));
				alb *= mix(1.0, 0.85, top_ring);
				vec2 sci = floor(xz / 0.2);
				float sh = h21(sci + seed + 61.0);
				float lump = step(1.0 - 0.45 * top_ring, sh) * smoothstep(0.3, 0.15, length(fract(xz / 0.2) - 0.5)) * keep(xz.x, 0.2);
				alb = mix(alb, alb * mix(0.55, 0.8, fract(sh * 13.0)), 0.85 * lump);   // a darker chip of stone (pale lumps with a lit crown read as white coins)
				rel = mix(rel, 0.65, lump);
			}
		} else if (k == 11) {   // garden plot: overgrown, weeds and bare patches
			alb = tint * 0.55 * mix(0.6, 1.25, fbm(xz * 2.4 + seed)) * mix(1.0, 0.7, step(0.9, h21(floor(xz * 9.0))));   // x0.55: the plots in the deployment bands sit below the models' own values (readability gate)
			vec2 pf = fract(xz / cell_in) * cell_in;
			alb = grit_plot(alb, xz, min(min(pf.x, cell_in - pf.x), min(pf.y, cell_in - pf.y)), palette[0].rgb * GROUND_EARTH * 0.85);   // (lead: no flat green square)
			float clump = green_break(xz, 0.0);   // (look review R11) a plot is rank growth in clumps, not a flat green: relief, dark hollows, dry patches
			alb *= mix(vec3(1.0), green_drift(xz, 0.0), 0.8);   // the earth's dry / green drift at 0.8 strength
			alb *= 1.0 - 0.22 * smoothstep(0.55, 0.3, clump) * keep(xz.x, 0.18);
			rel = clamp(0.15 + 0.7 * clump + 0.15 * vnoise(xz * 11.0 + seed), 0.0, 1.0);
			depth_in = 0.08;
			ao = mix(0.7, 1.0, smoothstep(0.2, 0.6, rel));
		} else if (k == 14) {   // rubble: broken stones
			alb = tint * mix(0.55, 1.2, h21(floor(xz * 4.0) + seed)) * mix(0.8, 1.0, vnoise(xz * 8.0));
		} else {
			alb = tint * grid;
		}
		if (k == 2) {   // dangerous ground: dark standing water - a teal depth, a faint sky sheen (no probe to reflect: a black mirror read as a hole in the table), small ripples
			float swirl = fbm(xz * 0.6 + seed);
			alb = vec3(0.018, 0.028, 0.03) * mix(0.7, 1.3, swirl);   // dark, peaty water (lead 21.11.: still a flat teal plane - the mirror took the teal; now a duller surface over a near-black body)
			emis += vec3(0.002, 0.004, 0.005) * (0.5 + fbm(xz * 1.3 + seed + 5.0));   // only a trace of sheen: no probe reflection would read as a black hole, the sheen must not win over it
			rough = 0.16;
			spec = 0.45;
			rel = fbm(xz * 2.6 + seed);
			depth_in = 0.05;   // ripples bend the reflection
			ao = 1.0;
		}
	}
	// DECAY WITH A STORY (plan R5): the board's seed picks the side the fire came from and the shade side. Folded by the half turn (like the board), so both halves tell the same story in their own frame.
	if (k == 15 || k == 13 || k == 3 || k == 4 || k == 6 || k == 9 || k == 10 || k == 12 || k == 16) {
		vec2 q = (p.z >= 0.0 ? -p.xz : p.xz) + vec2(0.0, 12.0);   // folded into one half, then centred on that half: the story is the same in both
		float lh = ground_at(p.xz - wnrm.xz * 0.2).b;
		float fire = clamp(0.5 + 0.65 * clamp(dot(q, story.xy) / (abs(story.x) * 24.0 + abs(story.y) * 12.0), -1.0, 1.0) + (lh - 0.5) * 0.4, 0.0, 1.0) * (k == 13 ? 0.35 : 1.0);   // the ruins on the fire side burn most, an intact house far less
		float shade = clamp(0.5 + 0.65 * clamp(dot(q, story.zw) / (abs(story.z) * 24.0 + abs(story.w) * 12.0), -1.0, 1.0) + (lh - 0.5) * 0.3, 0.0, 1.0);
		float moss = smoothstep(0.55, 0.95, shade);
		float patchy = wnrm.y > 0.5 ? fbm(p.xz * 1.3 + seed * 3.0) : fbm(vec2(p.x + p.z, p.y) * 1.3 + seed * 3.0);   // a top has no height to vary over: its patches follow the plan
		if (abs(wnrm.y) < 0.2) {   // a wall face
			grit_wall(p, wnrm, k, seed, box_in.x > 0.0 ? box_in.y * 0.5 - lpos.y : 99.0, float(int(ground_at(p.xz + wnrm.xz * 0.4).r * 255.0 + 0.5) == 1), alb, rel);   // (plan W0: a wall is not one wallpaper)
			float scorch = smoothstep(0.2, 0.6, fire) * (1.0 - smoothstep(0.0, mix(1.4, 6.5, fire), p.y)) * smoothstep(0.12, 0.45, patchy);   // rising from the foot, two storeys high on the fire side
			alb *= 1.0 - 0.4 * fire * fire;   // smoke over everything on that side
			alb = mix(alb, vec3(0.035, 0.03, 0.028), 0.9 * scorch);
			alb *= 1.0 - 0.55 * fire * soot_m;   // the fan of soot above an opening, the streak under its sill
			alb = mix(alb, vec3(0.022, 0.019, 0.017), 0.85 * wood_m * fire * smoothstep(0.35, 0.6, patchy));   // charred timber: black and cracked
			rough = mix(rough, 0.35, 0.6 * wood_m * fire);
			alb = mix(alb, grit_on > 0.5 ? vec3(0.11, 0.15, 0.08) : vec3(0.15, 0.25, 0.09), 0.7 * moss * (1.0 - smoothstep(0.0, 2.2, p.y)) * smoothstep(0.4, 0.7, patchy));   // moss and algae low on the shade side (green-black with the grit map, style bible 8)
		} else if (wnrm.y > 0.5 && k != 15) {   // a top
			vec2 pc = mod(p.xz, 3.0);
			float rim = 1.0 - smoothstep(0.1, 0.7, min(min(pc.x, 3.0 - pc.x), min(pc.y, 3.0 - pc.y)));   // (train 2, V2) moss gathers toward a top's edges too
			alb *= 0.85;   // (train 2, V2) the flat tops one value step down: they were the brightest thing on the board
			alb = mix(alb, vec3(0.12, 0.17, 0.08), clamp(0.65 * moss + 0.3 * rim, 0.0, 0.8) * smoothstep(0.45, 0.7, patchy) * (k == 3 || k == 4 || k == 8 ? DECK_MOSS : mix(TOP_MOSS, TOP_RIM_MOSS, top_ring)));   // moss on the tops of the shade side and at their edges
			alb = mix(alb, vec3(0.04, 0.035, 0.03), 0.6 * fire * smoothstep(0.55, 0.8, patchy) * float(k != 12));   // scorched patches on a ruin's top
		} else if (k == 15) {   // a roof face
			float lost = smoothstep(0.62, 0.7, fbm(vec2(p.x + p.z, p.y) * 0.9 + seed * 5.0)) * mix(0.25, 1.0, fire);
			alb = mix(alb, vec3(0.045, 0.04, 0.036), 0.7 * smoothstep(0.5, 0.85, fire) * smoothstep(0.3, 0.6, patchy));   // a burnt roof is black in patches   // tile slip and missing patches showing the battens
			alb = mix(alb, vec3(0.16, 0.11, 0.07) * (0.55 + 0.45 * step(0.5, fract(p.y / 0.35))), lost);
			alb = mix(alb, vec3(0.20, 0.30, 0.11), 0.5 * moss * smoothstep(0.4, 0.7, patchy));
		}
	}
	if (wnrm.y > 0.5 && k != 15 && k != 17 && k != 2) {
		alb *= mix(0.88, 1.12, clamp(p.y / 9.0, 0.0, 1.0));   // the value ladder (plan R4b): the 0 / 3 / 6 / 9 in tops read apart by value alone
	}
	// EDGES AND WEAR (plan R3): from the box size, within 0.06 in of an edge of its face a noise-broken chipped highlight (stone loses chips, plaster spalls to the stone beneath); a damp
	// moss band 0.3 in high at the foot of every wall face; soot under the eaves of an intact house; a ragged, course-stepped dark line at the top of a ruined tier. Box faces only (a
	// roof prism or a lantern has no box).
	vec3 fa = abs(wnrm);
	bool boxed = k != 15 && k != 17 && k != 5 && k != 18 && (fa.x > 0.85 || fa.y > 0.85 || fa.z > 0.85) && box_in.x > 0.0 && box_in.y > 0.5;   // a thin film (the ground skin, a pool) has no chipped edge: its 0.06 in rim read as a dashed pale line; nor has wood (ladder 5, wood 18): a 0.12 in rail is all edge, its pale chip read as a stripe
	if (boxed) {
		vec3 e = box_in * 0.5 - abs(lpos);
		float d_top = e.y - 0.0 + (lpos.y > 0.0 ? 0.0 : 1000.0);   // the distance below the box's top (1000 for a point in its lower half)
		float d_edge = min(min(e.x + 100.0 * fa.x, e.y + 100.0 * fa.y), e.z + 100.0 * fa.z);   // the distance to the nearest edge of THIS face
		float chip = (1.0 - smoothstep(0.0, 0.06, d_edge)) * smoothstep(0.35, 0.7, vnoise(p.xz * 17.0 + p.y * 13.0 + seed));
		bool stoney = k == 12 || k == 9 || k == 10 || k == 6 || k == 16 || k == 3 || k == 4;
		alb = mix(alb, stoney ? alb * 1.3 : vec3(0.55, 0.52, 0.48), chip * keep(d_edge, 0.06));   // fresh stone / the stone beneath the plaster
		if (abs(wnrm.y) < 0.2) {   // a wall face
			float foot = (1.0 - smoothstep(0.0, 0.3, p.y)) * smoothstep(0.3, 0.6, fbm(p.xz * 2.0 + p.y * 3.0 + seed));
			alb = mix(alb, grit_on > 0.5 ? vec3(0.075, 0.078, 0.068) : vec3(0.10, 0.14, 0.07), 0.55 * foot);   // damp and moss at the foot (with the grit map: a dark damp band, moss is the shade side's)
			rough = mix(rough, 0.6, foot);
			if (k == 13) {
				alb *= 1.0 - 0.45 * (1.0 - smoothstep(0.0, 0.6, d_top));   // soot under the eaves
			}
			if (k == 3 || k == 4 || k == 6) {
				float ragged = 0.3 * (0.35 + 0.65 * h21(floor(vec2((abs(wnrm.x) > 0.5 ? p.z : p.x) / 0.4, 0.0)) + seed));   // a broken top course, stepped per stone
				alb *= mix(0.5, 1.0, smoothstep(0.0, ragged, d_top));
			}
		}
	}
	if (k == 17) {   // a lit lantern
		emis = tint * 1.4;   // a lantern head, not a sun: the bloom must not wash the plaster
	}
	if (tex_on > 0.5) {   // the authored normal map replaces the procedural relief on this face
		vec3 wp = normalize(tex_n.x * tex_t + tex_n.y * tex_b + max(tex_n.z, 0.2) * normalize(wnrm));
		NORMAL = normalize((VIEW_MATRIX * vec4(wp, 0.0)).xyz);
	}
	if (depth_in > 0.0) {   // the relief: a bent normal from the screen-space gradient of the height (no tangents needed), and its occlusion
		float h = (rel - 0.5) * depth_in * IN;
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
		float tilt = length(grad) / max(abs(det), 0.0000001);   // never bend the normal by more than ~50 degrees: a mortar edge must not throw a pinprick of specular
		grad *= min(1.0, 1.2 / max(tilt, 0.0001));
		NORMAL = normalize(abs(det) * NORMAL - grad);
		AO = ao;
		float up = clamp((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, 0.0, 1.0);   // the bent normal's view of the sky (symmetric: no light direction)
		float sky = mix(1.0, mix(SKY_AMBIENT_FLOOR, 1.0, up * up), SKY_AMBIENT * step(0.5, wnrm.y));
		AO *= sky;
		emis *= sky;   // the grit's flat fill (an emission, the street's own ambient) follows the sky too: unshaded, it flattened the setts outside the lamps
		AO_LIGHT_AFFECT = 0.35;
	}
	ALBEDO = pow(alb, vec3(2.2)) * tex_ratio;
	EMISSION = emis;
	ROUGHNESS = rough;
	SPECULAR = spec;
	if (grit_debug > 0) {   // the grit instrument: only the class colours reach the image
		ALBEDO = vec3(0.0);
		EMISSION = dbg;
		SPECULAR = 0.0;
		ROUGHNESS = 1.0;
	}
}

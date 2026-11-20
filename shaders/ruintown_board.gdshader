shader_type spatial;
// Look of a generated ruin-town board (BoardgenGreybox, theme RuinTown): ONE material for every box and gable of the board, all procedural
// (no texture file, nothing from a third party). The surface kind comes per instance (INSTANCE_CUSTOM.x, same contract as tiefwerk_board.gdshader),
// the base colours from the theme palette. Wall faces by height: 0-3 in coursed quarry stone with a door here and there, 3-6 in half-timber with
// plaster and small shuttered windows, 6 in up ashlar; an intact house is half-timber on a stone plinth under its tiled gable roof; the city wall
// and the stone pieces are coursed stone, a chimney is brick. The two halves of the board draw their stones, plaster and tiles with other seeds.
#include "res://shaders/tiefwerk_noise.gdshaderinc"

uniform vec4 palette[19];   // display colours by kind index (BoardgenTheme.TOWN_KINDS)
uniform vec3 board_origin;   // world position of the board centre
uniform float cell_in = 3.0;
uniform sampler2D ground_map : filter_nearest;   // one texel per cell: R = surface kind, G = how a street runs (0 along x, 1 along z, 0.5 junction / square), BA = offset of the junction's centre (6 in = 0..1)
uniform vec2 board_cells = vec2(16.0, 16.0);

varying vec3 wpos;
varying vec3 wnrm;
varying flat float kind;

const float IN = 0.0254;

// Tabletop scale (plan D-R2: true 1:56 x ~1.4, so the texture survives at arm's length): feature sizes in inches. A pawn base (~1 in) covers about seven setts and a wall course is a fifth of a pawn.
const float SETT_W = 0.14;
const float SETT_H = 0.11;
const float COURSE = 0.24;   // wall stone: courses 0.24 in high, stones 0.3 - 0.8 in long (len 0.5 x 0.7 .. 1.5)
const float TILE_W = 0.16;
const float TILE_H = 0.13;
const float BOARD_W = 0.18;   // floor boards 0.18 in wide, 1.5 - 3 in long

// How much of a pattern whose features are `size` inches survives at this pixel: 1 when a feature spans 3.5 pixels or more, 0 below 1.5 (it averages out instead of shimmering).
float keep(float coord, float size) {
	return smoothstep(1.5, 3.5, size / max(fwidth(coord), 0.00001));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	kind = INSTANCE_CUSTOM.x;
}

// Coursed stone: courses `course` in high, stones about `len` in long, offset per course, dark mortar, a tone per stone.
vec3 stone(vec2 uv, float seed, float course, float len, vec3 tint, out float rel) {
	float row = floor(uv.y / course);
	float l = len * (0.7 + 0.8 * h21(vec2(row, seed + 7.0)));
	float x = uv.x + h21(vec2(row, seed)) * 4.0;
	float col = floor(x / l);
	vec2 f = vec2(fract(x / l) * l, fract(uv.y / course) * course);
	float edge = smoothstep(0.0, course * 0.11, min(min(f.x, l - f.x), min(f.y, course - f.y)));
	float tone = h21(vec2(col, row) + seed);
	vec3 laid = mix(vec3(0.15, 0.14, 0.13), tint * mix(0.72, 1.12, tone) * mix(0.9, 1.1, vnoise(uv * 4.0)), edge);
	rel = mix(0.5, edge * (0.8 + 0.2 * tone), keep(uv.y, course));   // the mortar is recessed, a stone stands a little proud
	return mix(tint * 0.8, laid, keep(uv.y, course));   // too fine for the pixel: the mean of stone and mortar
}

// Half-timber of one 3 in storey (uv.y = height in inches, a storey starts at a multiple of 3): dark posts every 1.5 in, rails at the storey
// edges, a brace in some panels, plaster between, a small shuttered window in some panels.
vec3 timber(vec2 uv, float seed, vec3 plaster, inout vec3 emis) {
	float y = mod(uv.y, 3.0);
	float px = uv.x / 1.5;
	float panel = floor(px);
	float lx = fract(px);
	float post = smoothstep(0.12, 0.08, min(lx, 1.0 - lx) * 1.5);
	float rail = smoothstep(0.2, 0.15, min(y, 3.0 - y));
	float flip = step(0.5, h21(vec2(panel, seed + 3.0)));
	float brace = step(0.55, h21(vec2(panel, seed))) * smoothstep(0.1, 0.06, abs(y / 3.0 - mix(1.0 - lx, lx, flip)) * 1.5) * step(0.3, y) * step(y, 2.7);
	vec3 wood = vec3(0.17, 0.10, 0.06) * mix(0.8, 1.2, vnoise(vec2(uv.x * 9.0, uv.y * 1.5)));
	vec3 fill = plaster * mix(0.84, 1.1, fbm(uv * 1.7 + seed)) * mix(0.62, 1.0, smoothstep(0.0, 1.1, y));
	vec2 w = abs(vec2((lx - 0.5) * 1.5, y - 1.7)) - vec2(0.22, 0.3);
	float d = max(w.x, w.y);
	float has_win = step(0.5, h21(vec2(panel, seed + 9.0)));
	vec3 c = mix(fill, wood, max(post, max(rail, brace)));
	c = mix(c, wood, has_win * step(d, 0.07));
	float lit = has_win * step(d, -0.06);
	emis += vec3(1.0, 0.55, 0.22) * lit * step(0.8, h21(vec2(panel, seed + 5.0))) * 0.9;   // a few windows glow
	return mix(c, vec3(0.06, 0.05, 0.05), lit);
}

// Cobbles: staggered rounded setts about 0.6 x 0.4 in, a tone per sett, dark joints. They run along the street (`run` 0 = along x, 1 = along z) and fan round the
// middle of a junction or a square (`fan` = the offset of that middle from the sample, inches).
vec3 cobble(vec2 xz, float seed, vec3 tint, float run, vec2 fan, out float rel) {
	float row;
	float x;
	vec2 f;
	if (run > 0.25 && run < 0.75) {
		float r = length(fan);
		row = floor(r / SETT_H);
		float n = max(floor(6.2832 * (row + 0.5) * SETT_H / SETT_W), 3.0);   // a whole number of setts in every ring: no seam
		x = (atan(fan.y, fan.x) / 6.2832 + 0.5) * n + 0.5 * mod(row, 2.0) + h21(vec2(row, seed)) * 0.3;
		f = vec2(fract(x), fract(r / SETT_H)) - 0.5;
	} else {
		vec2 q = run > 0.75 ? xz.yx : xz;
		row = floor(q.y / SETT_H);
		x = q.x / SETT_W + 0.5 * mod(row, 2.0) + h21(vec2(row, seed)) * 0.3;
		f = vec2(fract(x), fract(q.y / SETT_H)) - 0.5;
	}
	float sett = smoothstep(0.17, 0.10, length(max(abs(f) - vec2(0.3), 0.0)));
	vec3 laid = mix(vec3(0.10, 0.09, 0.09), tint * mix(0.7, 1.15, h21(vec2(floor(x), row) + seed)) * mix(0.9, 1.1, vnoise(xz * 3.0)), sett);
	rel = mix(0.5, sett * (0.6 + 0.4 * clamp(1.0 - 1.6 * length(f), 0.0, 1.0)), keep(xz.x, SETT_W));   // a domed sett in a recessed joint
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
	float depth_in = 0.0;   // how deep that relief is, in inches (0 = none)
	float ao = 1.0;
	if (abs(wnrm.y) < 0.2) {   // a wall face (or a gable end)
		vec2 uv = vec2(abs(wnrm.x) > 0.5 ? p.z : p.x, p.y);
		if (k == 15) {   // a gable end: plaster and a timber frame
			alb = timber(uv, seed, palette[13].rgb, emis);
		} else if (k == 13) {   // an intact house: half-timber on a stone plinth
			float plinth = 0.3 + 0.75 * fract(kind);   // the house's own plinth height rides in the fraction of its kind
			alb = uv.y < plinth ? stone(uv, seed, 0.2, 0.45, vec3(0.5, 0.48, 0.44), rel) : timber(vec2(uv.x, uv.y + 2.5), seed, tint * mix(0.95, 1.05, half_seed), emis);
		} else if (k == 12 || k == 9 || k == 10 || k == 16) {   // city wall, stone pieces, chimney: coursed stone (brick for the chimney)
			alb = k == 16 ? stone(uv, seed, 0.1, 0.22, tint, rel) : stone(uv, seed, COURSE, 0.5, tint, rel);
		} else if (k == 18) {   // a wooden prop: planks with iron bands
			alb = tint * mix(0.7, 1.15, h21(vec2(floor(uv.x * 4.0), seed))) * mix(0.55, 1.0, smoothstep(0.0, 0.05, abs(fract(uv.y * 2.5) - 0.5) - 0.42)) * mix(0.8, 1.0, seam(uv.x, 0.25, 0.03));
		} else if (k == 3 || k == 4 || k == 6) {   // ruined house tiers and towers, by storey
			float part = k == 6 ? 0.5 : ground_at(p.xz - wnrm.xz * 0.2).g;   // the part of a ruined row this face belongs to (its tone and where its storey band falls)
			tint *= mix(0.86, 1.12, part);
			uv.y += (part - 0.5) * 0.7;
			float band = k == 6 ? 2.0 : floor(uv.y / 3.0);   // a tower is stone all the way up
			if (band < 0.5) {
				alb = mix(stone(uv, seed, COURSE, 0.5, tint * 0.9, rel), vec3(0.09, 0.06, 0.04), door(uv, seed));
			} else if (band < 1.5) {
				alb = timber(uv, seed, tint * 1.02, emis);
			} else {
				alb = stone(uv, seed, COURSE, 0.55, tint * 1.05, rel);
			}
		}
	} else if (wnrm.y < 0.95 && k == 15) {   // a sloped roof face: rows of tiles, a tone per tile, a shadow under each row
		float along = abs(wnrm.x) > abs(wnrm.z) ? p.z : p.x;
		float row = floor(p.y / TILE_H);
		float tile = floor(along / TILE_W + row * 0.5);
		vec3 base = tint * mix(0.7, 1.15, h21(vec2(tile, row + seed)));
		vec3 laid = base * mix(0.62, 1.0, smoothstep(0.0, 0.7, fract(p.y / TILE_H))) * mix(1.0, 0.8, smoothstep(0.55, 0.7, fbm(vec2(along, p.y) * 1.3 + seed)));
		alb = mix(tint * 0.82, laid, keep(p.y, TILE_H));   // 0.16 x 0.13 in tiles: the mean below ~3 px
	} else if (wnrm.y > 0.5) {   // a top face, by kind
		vec2 xz = p.xz;
		float grid = 1.0;   // the faint 3 in cell line is gone from every top (plan R1: no grid to count on the table)
		float run = 0.5;
		vec2 fan = vec2(1.0, 0.0);
		float gutter = 0.0;
		if (k <= 1) {   // the open ground (earth, street): the border between the two wanders off the grid; RUINS, FOREST and DANGEROUS ground keep their exact cell edge
			vec2 w = xz + wander(xz);
			vec4 g = ground_at(w);
			if (int(g.r * 255.0 + 0.5) <= 1) {
				k = int(g.r * 255.0 + 0.5);
				tint = palette[k].rgb;
				alb = tint;
				run = g.g;
				vec2 centre = (floor(w / cell_in) + 0.5) * cell_in + (g.ba - 0.5) * 6.0;
				fan = xz - centre;   // the sett pattern itself is not bent: only the border is
			}
			for (int d = 0; d < 4; d++) {   // a gutter: wet dark stone where the street ends within 0.3 in of earth
				vec2 o = vec2(d < 2 ? (d == 0 ? 0.3 : -0.3) : 0.0, d >= 2 ? (d == 2 ? 0.3 : -0.3) : 0.0);
				gutter = max(gutter, float(int(ground_at(w + o).r * 255.0 + 0.5) == 0));
			}
		}
		if (k == 1) {   // streets: cobbles
			float crown;
			alb = mix(cobble(xz, seed, tint * 1.15, run, fan, crown), vec3(0.06, 0.055, 0.05), 0.55 * gutter);
			rel = crown;
			depth_in = 0.045;
			rough = mix(0.55, 0.8, smoothstep(0.3, 0.7, crown));   // damp joints, dry crowns
			ao = mix(0.55, 1.0, smoothstep(0.1, 0.5, crown));
		} else if (k == 0) {   // earth: packed, with pebbles, weeds and broken stones
			vec2 cellp = floor(xz * 5.0);
			float speck = h21(cellp + seed);
			alb = tint * mix(0.78, 1.15, fbm(xz * 1.6 + seed)) * mix(1.0, 1.3, step(0.94, h21(floor(xz * 7.0))));
			alb = mix(alb, vec3(0.30, 0.38, 0.17), step(0.84, speck) * step(length(fract(xz * 5.0) - 0.5), 0.34) * 0.7);   // a weed tuft
			alb = mix(alb, vec3(0.26, 0.25, 0.23) * mix(0.8, 1.25, h21(cellp + 3.0)), step(0.965, speck) * step(length(fract(xz * 5.0) - 0.5), 0.26));   // a broken stone
			float path = smoothstep(0.03, 0.0, abs(vnoise(xz * 0.21 + seed) - 0.5)) * step(0.5, vnoise(xz * 0.07 + 5.0));   // a worn path: pale, meandering (a noise stand-in until the doors of R12c exist)
			alb = mix(alb, tint * vec3(1.4, 1.34, 1.2), 0.75 * path);
			rel = 0.2 + 0.6 * fbm(xz * 3.0 + seed) - 0.15 * path;   // packed earth: lumps, and the worn paths lie lower
			depth_in = 0.05;
			rough = 0.95;
		} else if (k == 3 || k == 4 || k == 8) {   // floor boards of a ruined house or yard, scorched in patches
			if (k != 8) {
				tint *= mix(0.9, 1.1, ground_at(xz).g);   // each part of a ruined row has its own tone
			}
			rel = mix(0.5, seam(xz.y, BOARD_W, 0.018), keep(xz.y, BOARD_W));   // a dark gap between boards
			depth_in = 0.02;
			rough = 0.82;
			alb = tint * mix(0.72, 1.05, h21(vec2(floor(xz.x / 2.2), floor(xz.y / BOARD_W) + seed))) * mix(0.8, 1.0, mix(1.0, seam(xz.y, BOARD_W, 0.018), keep(xz.y, BOARD_W))) * mix(0.84, 1.0, smoothstep(0.35, 0.6, fbm(xz * 0.9 + seed))) * grid;
		} else if (k == 6 || k == 12 || k == 9 || k == 10) {   // tower and wall tops, stone pieces: flagstones
			alb = stone(xz, seed, 0.45, 0.6, tint, rel);   // flagstones 0.45 - 0.8 in
			depth_in = 0.03;
			rough = 0.85;
		} else if (k == 11) {   // garden plot: overgrown, weeds and bare patches
			alb = tint * mix(0.6, 1.25, fbm(xz * 2.4 + seed)) * mix(1.0, 0.7, step(0.9, h21(floor(xz * 9.0))));
		} else if (k == 14) {   // rubble: broken stones
			alb = tint * mix(0.55, 1.2, h21(floor(xz * 4.0) + seed)) * mix(0.8, 1.0, vnoise(xz * 8.0));
		} else {
			alb = tint * grid;
		}
		if (k == 2) {   // dangerous ground: dark standing water
			alb = tint * mix(0.7, 1.2, fbm(xz * 0.6 + seed));
			rough = 0.12;
		}
	}
	if (k == 17) {   // a lit lantern
		emis = tint * 3.0;
	}
	if (depth_in > 0.0) {   // the relief: a bent normal from the screen-space gradient of the height (no tangents needed), and its occlusion
		float h = (rel - 0.5) * depth_in * IN;
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
		NORMAL = normalize(abs(det) * NORMAL - grad);
		AO = ao;
		AO_LIGHT_AFFECT = 0.35;
	}
	ALBEDO = pow(alb, vec3(2.2));
	EMISSION = emis;
	ROUGHNESS = rough;
}

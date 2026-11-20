shader_type spatial;
// Look of a generated ruin-town board (BoardgenGreybox, theme RuinTown): ONE material for every box and gable of the board, all procedural
// (no texture file, nothing from a third party). The surface kind comes per instance (INSTANCE_CUSTOM.x, same contract as tiefwerk_board.gdshader),
// the base colours from the theme palette. Wall faces by height: 0-3 in coursed quarry stone with a door here and there, 3-6 in half-timber with
// plaster and small shuttered windows, 6 in up ashlar; an intact house is half-timber on a stone plinth under its tiled gable roof; the city wall
// and the stone pieces are coursed stone, a chimney is brick. The two halves of the board draw their stones, plaster and tiles with other seeds.
#include "res://shaders/tiefwerk_noise.gdshaderinc"

uniform vec4 palette[17];   // display colours by kind index (BoardgenTheme.TOWN_KINDS)
uniform vec3 board_origin;   // world position of the board centre
uniform float cell_in = 3.0;

varying vec3 wpos;
varying vec3 wnrm;
varying flat float kind;

const float IN = 0.0254;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	kind = INSTANCE_CUSTOM.x;
}

// Coursed stone: courses `course` in high, stones about `len` in long, offset per course, dark mortar, a tone per stone.
vec3 stone(vec2 uv, float seed, float course, float len, vec3 tint) {
	float row = floor(uv.y / course);
	float l = len * (0.7 + 0.8 * h21(vec2(row, seed + 7.0)));
	float x = uv.x + h21(vec2(row, seed)) * 4.0;
	float col = floor(x / l);
	vec2 f = vec2(fract(x / l) * l, fract(uv.y / course) * course);
	float edge = smoothstep(0.0, 0.05, min(min(f.x, l - f.x), min(f.y, course - f.y)));
	float tone = h21(vec2(col, row) + seed);
	return mix(vec3(0.15, 0.14, 0.13), tint * mix(0.72, 1.12, tone) * mix(0.9, 1.1, vnoise(uv * 4.0)), edge);
}

// Half-timber of one 3 in storey (uv.y = height in inches, a storey starts at a multiple of 3): dark posts every 1.5 in, rails at the storey
// edges, a brace in some panels, plaster between, a small shuttered window in some panels.
vec3 timber(vec2 uv, float seed, vec3 plaster) {
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
	return mix(c, vec3(0.06, 0.05, 0.05), has_win * step(d, -0.06));
}

// Cobbles: staggered rounded setts about 0.6 x 0.4 in, a tone per sett, dark joints.
vec3 cobble(vec2 xz, float seed, vec3 tint) {
	float row = floor(xz.y / 0.42);
	float x = xz.x / 0.62 + 0.5 * mod(row, 2.0) + h21(vec2(row, seed)) * 0.3;
	vec2 f = vec2(fract(x), fract(xz.y / 0.42)) - 0.5;
	float sett = smoothstep(0.17, 0.10, length(max(abs(f) - vec2(0.3), 0.0)));
	return mix(vec3(0.10, 0.09, 0.09), tint * mix(0.7, 1.15, h21(vec2(floor(x), row) + seed)) * mix(0.9, 1.1, vnoise(xz * 3.0)), sett);
}

// A door in the stone ground storey: 0.7 x 1.4 in in the middle of some 3 in cells.
float door(vec2 uv, float seed) {
	float cell = floor(uv.x / 3.0);
	vec2 d = abs(vec2(uv.x - cell * 3.0 - 1.5, uv.y - 0.7)) - vec2(0.35, 0.7);
	return step(0.62, h21(vec2(cell, seed + 21.0))) * step(max(d.x, d.y), 0.0);
}

void fragment() {
	int k = clamp(int(kind + 0.5), 0, 16);
	vec3 p = (wpos - board_origin) / IN;   // inches off the board centre, y up
	float half_seed = step(0.0, p.z);   // the south half draws with other seeds: a half turn does not look like the other half
	float seed = 17.0 * half_seed;
	vec3 tint = palette[k].rgb;
	vec3 alb = tint;
	float rough = 0.92;
	if (abs(wnrm.y) < 0.2) {   // a wall face (or a gable end)
		vec2 uv = vec2(abs(wnrm.x) > 0.5 ? p.z : p.x, p.y);
		if (k == 15) {   // a gable end: plaster and a timber frame
			alb = timber(uv, seed, palette[13].rgb);
		} else if (k == 13) {   // an intact house: half-timber on a stone plinth
			alb = uv.y < 0.45 ? stone(uv, seed, 0.45, 0.9, vec3(0.5, 0.48, 0.44)) : timber(vec2(uv.x, uv.y + 2.5), seed, tint * mix(0.95, 1.05, half_seed));
		} else if (k == 12 || k == 9 || k == 16) {   // city wall, stone pieces, chimney: coursed stone (brick for the chimney)
			alb = k == 16 ? stone(uv, seed, 0.25, 0.55, tint) : stone(uv, seed, 0.55, 1.0, tint);
		} else if (k == 3 || k == 4 || k == 6) {   // ruined house tiers and towers, by storey
			float band = floor(uv.y / 3.0);
			if (band < 0.5) {
				alb = mix(stone(uv, seed, 0.55, 1.0, tint * 0.9), vec3(0.09, 0.06, 0.04), door(uv, seed));
			} else if (band < 1.5) {
				alb = timber(uv, seed, tint * 1.02);
			} else {
				alb = stone(uv, seed, 0.5, 1.1, tint * 1.05);
			}
		}
	} else if (wnrm.y < 0.95 && k == 15) {   // a sloped roof face: rows of tiles, a tone per tile, a shadow under each row
		float along = abs(wnrm.x) > abs(wnrm.z) ? p.z : p.x;
		float row = floor(p.y * 4.0);
		float tile = floor(along / 0.45 + row * 0.5);
		vec3 base = tint * mix(0.7, 1.15, h21(vec2(tile, row + seed)));
		alb = base * mix(0.62, 1.0, smoothstep(0.0, 0.7, fract(p.y * 4.0))) * mix(1.0, 0.8, smoothstep(0.55, 0.7, fbm(vec2(along, p.y) * 1.3 + seed)));
	} else if (wnrm.y > 0.5) {   // a top face, by kind
		vec2 xz = p.xz;
		vec2 e = abs(fract(xz / cell_in) - 0.5);
		float grid = mix(1.0, 0.86, smoothstep(0.48, 0.495, max(e.x, e.y)));   // the 3 in cell, faint
		if (k == 1) {   // streets: cobbles
			alb = cobble(xz, seed, tint * 1.15) * grid;
		} else if (k == 0) {   // earth: packed, with pebbles
			alb = tint * mix(0.78, 1.15, fbm(xz * 1.6 + seed)) * mix(1.0, 1.3, step(0.94, h21(floor(xz * 7.0)))) * grid;
		} else if (k == 3 || k == 4 || k == 8) {   // floor boards of a ruined house or yard, scorched in patches
			alb = tint * mix(0.72, 1.05, h21(vec2(floor(xz.x / 2.1), floor(xz.y / 0.5) + seed))) * mix(0.8, 1.0, seam(xz.y, 0.5, 0.05)) * mix(0.84, 1.0, smoothstep(0.35, 0.6, fbm(xz * 0.9 + seed))) * grid;
		} else if (k == 6 || k == 12 || k == 9 || k == 10) {   // tower and wall tops, stone pieces: flagstones
			alb = stone(xz, seed, 1.0, 1.4, tint) * mix(0.95, 1.0, grid);
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
	ALBEDO = pow(alb, vec3(2.2));
	ROUGHNESS = rough;
}

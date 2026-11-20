shader_type spatial;
// Look of a generated undercity board (BoardgenGreybox): ONE material for every box of the board. The surface kind comes per
// instance (INSTANCE_CUSTOM.x); the neighbouring cell heights (tier lips, cliff stripes, contact shadow, sump rim) come from a
// one-texel-per-cell texture. Everything is procedural: no texture file, nothing from a third party.
// kinds: 0 ground, 1 street, 2 sump, 3 tier 1 (rusted plate deck), 4 tier 2 (rooftop slab), 5 ladder (every connector is a ladder),
// 6 tier 3 (a tower top: the rooftop slab, cooler and paler), 7 kerb (the low concrete rim round a sump).

uniform sampler2D cells : filter_nearest;   // red = height of the cell's top in inches, green = 255 for a sump cell
uniform vec2 board_cells = vec2(16.0);
uniform float cell_in = 3.0;
uniform vec3 board_origin;   // world position of the board centre
uniform float detail = 1.0;   // 1 = the finer look (edge wear, relief); 0 on Performance / Low and the Compatibility renderer

varying vec3 wpos;
varying vec3 wnrm;
varying flat float kind;
varying vec3 lpos;        // position in the box, inches off its centre
varying flat vec3 box_in;   // the box's size in inches (INSTANCE_CUSTOM.gba; 0 = not told)
varying flat vec3 lnrm;     // the face's normal in the box

const float IN = 0.0254;
const float PLATE = 1.5;   // the modular plate of floors and walls, in inches
const vec3 YELLOW = vec3(0.78, 0.55, 0.05);
const ivec2 DIRS[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	kind = INSTANCE_CUSTOM.x;
	box_in = INSTANCE_CUSTOM.gba;
	lpos = VERTEX * box_in;   // the mesh is the unit cube
	lnrm = NORMAL;
}

#include "res://shaders/tiefwerk_noise.gdshaderinc"

vec4 cell_at(ivec2 c) {   // x = height in inches, y = sump; outside the board = ground
	if (c.x < 0 || c.y < 0 || c.x >= int(board_cells.x) || c.y >= int(board_cells.y)) {
		return vec4(0.0);
	}
	return texelFetch(cells, c, 0) * 255.0;
}

// Distance in inches from the point g (cell units) to the nearest cell taller than h among the 3x3 around cell c; 9 = none. Euclidean,
// so it has no square corners and no cell-edge cut-offs (the grime and the puddles that collect along walls follow it).
float wall_dist(vec2 g, ivec2 c, float h) {
	float best = 9.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			ivec2 o = c + ivec2(i, j);
			if ((i != 0 || j != 0) && cell_at(o).x > h) {
				best = min(best, length(max(abs(g - (vec2(o) + 0.5)) - 0.5, 0.0)) * cell_in);
			}
		}
	}
	return best;
}

#include "res://shaders/tiefwerk_edges.gdshaderinc"
#include "res://shaders/tiefwerk_relief.gdshaderinc"

// Distance in inches from the point g to the nearest sump cell among the 3x3 around cell c (the toxic stain on the floor and the walls); 9 = none.
float sump_dist(vec2 g, ivec2 c) {
	float best = 9.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			ivec2 o = c + ivec2(i, j);
			if (cell_at(o).y > 0.5) {
				best = min(best, length(max(abs(g - (vec2(o) + 0.5)) - 0.5, 0.0)) * cell_in);
			}
		}
	}
	return best;
}

// The liquid's slow swell: two layers of noise drifting against each other (its gradient is the ripple normal).
float swell(vec2 q) {
	return 0.6 * vnoise(q * 1.5 + vec2(TIME * 0.05, TIME * 0.03)) + 0.4 * vnoise(q * 3.3 + vec2(-TIME * 0.04, TIME * 0.06));
}

// A few bubbles: a 1.25 in grid, a quarter of the cells hold one that swells, pops in a ring and flashes, then rests. x = skin and glint, y = pop ring.
vec2 bubbles(vec2 q) {
	vec2 g = q / 1.25, id = floor(g);
	float h = h21(id + 3.7);
	float ph = fract(TIME * (0.12 + 0.08 * h21(id + 9.1)) + h * 7.0);
	float d = length(g - (id + 0.3 + 0.4 * vec2(h21(id + 1.3), h21(id + 5.9)))) * 1.25;
	float r = 0.05 + 0.13 * smoothstep(0.0, 0.45, ph);
	float body = ph < 0.45 ? smoothstep(0.035, 0.0, abs(d - r)) + 0.5 * smoothstep(r, 0.0, d) : 0.0;
	float pop = ph > 0.45 && ph < 0.6 ? smoothstep(0.075, 0.0, abs(d - r - (ph - 0.45) * 1.2)) * (1.0 - (ph - 0.45) / 0.15) : 0.0;
	return step(0.75, h) * vec2(body, pop);
}

void fragment() {
	vec3 p = (wpos - board_origin) / IN;   // board inches, origin = board centre
	vec3 n = normalize(wnrm);
	vec3 nrel = n;   // the shading normal: the relief of walls and floors bends it
	int k = int(kind + 0.5);
	vec2 half_board = board_cells * cell_in * 0.5;
	bool top = n.y > 0.5;
	vec2 uv = top ? p.xz : vec2(abs(n.x) > 0.5 ? p.z : p.x, p.y);
	float px = max(length(fwidth(uv)), 0.0001);   // inches per pixel: the relief fades out below that
	float n1 = fbm(uv * 0.55), n2 = fbm(uv * 2.1 + 7.0), n3 = vnoise(uv * 11.0);
	vec3 alb = vec3(0.3);
	vec3 emis = vec3(0.0);
	float rough = 0.9, met = 0.0, ao = 1.0, spec = 0.5;
	vec3 nw = n;   // the shading normal: the sump's liquid ripples it
	bool liquid_on = false;

	if (k == 5) {   // ladder: weathered safety yellow
		alb = YELLOW * mix(0.5, 0.9, n2);
		rough = 0.5;
		met = 0.5;
	} else if (k == 7) {   // kerb: poured concrete, a chipped hazard stripe on top, green crust and a tide line on the inside
		float stripe = step(0.5, fract((p.x + p.z) * 0.8));
		alb = mix(vec3(0.24, 0.235, 0.23), vec3(0.36, 0.35, 0.33), n2) * mix(0.8, 1.0, n3);
		float crust = top ? 0.0 : 0.6 * smoothstep(0.12, 0.0, p.y - 0.06 - 0.08 * n3) + 0.3 * smoothstep(0.6, 0.9, n2);
		alb = top ? mix(vec3(0.05), YELLOW * 0.9, stripe) * mix(0.55, 1.0, smoothstep(0.35, 0.6, n2 + 0.3 * n3)) : mix(alb * 0.7, vec3(0.07, 0.11, 0.03), crust);
		emis = vec3(0.02, 0.06, 0.005) * crust * crust;
	} else if (!top) {   // cliff wall of a tier: formwork concrete, rust drips from the lip, hazard band under it
		vec2 nh = normalize(n.xz + 0.0001);
		vec2 g_in = (p.xz - nh * 0.02 + half_board) / cell_in;
		vec2 g_out = (p.xz + nh * 0.02 + half_board) / cell_in;
		float top_y = cell_at(ivec2(floor(g_in))).x;
		float low_y = cell_at(ivec2(floor(g_out))).x;
		float dtop = top_y - p.y;
		alb = mix(vec3(0.17, 0.165, 0.16), vec3(0.30, 0.285, 0.27), n1) * (k == 4 ? 1.25 : k == 6 ? 1.45 : 1.0);
		alb *= mix(0.55, 1.0, seam(uv.y, 1.5, 0.05)) * mix(0.7, 1.0, seam(uv.x, 1.5, 0.04));
		// Layered panels, 1.5 in: an inset frame, rivets, vents with soot above them, signage plates (abstract marks, no text), conduit runs.
		vec2 pid = floor(uv / PLATE);
		vec2 fp = (fract(uv / PLATE) - 0.5) * PLATE;
		vec2 ap = abs(fp);
		float ph = h21(pid + 9.1);
		float ed = PLATE * 0.5 - max(ap.x, ap.y);
		alb *= (1.0 - 0.45 * smoothstep(0.035, 0.0, abs(ed - 0.14))) * mix(0.92, 1.06, smoothstep(0.0, 0.1, ed - 0.14));
		float rv = min(length(ap - 0.6), min(length(ap - vec2(0.6, 0.0)), length(ap - vec2(0.0, 0.6))));
		if (detail < 0.5) {   // Low keeps the painted rivets; the finer look has them as relief
			alb = mix(alb, alb * 1.6 + 0.05, smoothstep(0.05, 0.03, rv) * step(0.1, ph));
		}
		if (ph < 0.1) {   // a vent
			alb = mix(alb, mix(vec3(0.015), vec3(0.2, 0.2, 0.21), step(0.5, fract(uv.y * 5.0))), step(ap.x, 0.5) * step(ap.y, 0.42));
			alb *= 1.0 - 0.55 * smoothstep(0.42, 0.75, fp.y) * step(ap.x, 0.6);
		} else if (ph < 0.2) {   // a signage plate: a coloured ground with three bars
			vec3 ground = ph < 0.13 ? YELLOW * 0.9 : ph < 0.17 ? vec3(0.62, 0.6, 0.55) : vec3(0.2, 0.32, 0.34);
			float row = floor((fp.y + 0.27) / 0.18);   // three bars of hashed length, like a label (abstract, no glyphs)
			float len = 0.12 + 0.4 * h21(vec2(row, pid.x * 7.0 + pid.y));
			float mark = step(abs(fract((fp.y + 0.27) / 0.18) - 0.5), 0.28) * step(fp.x + 0.5, len) * step(ap.x, 0.5) * step(ap.y, 0.27);
			alb = mix(alb, ground * mix(1.0, 0.15, mark) * mix(0.7, 1.0, n2), step(ap.x, 0.55) * step(ap.y, 0.32));
		} else if (h21(vec2(floor(uv.y / PLATE), floor(uv.x / 6.0)) + 21.0) > 0.82) {   // a conduit, clamped at the seams
			float t = (fp.y - 0.45) / 0.07;
			alb = abs(t) < 1.0 ? vec3(0.30, 0.28, 0.25) * (0.4 + 0.6 * sqrt(1.0 - t * t)) * (1.0 - 0.5 * step(0.72, ap.x)) : alb;
		}
		if (h21(pid - vec2(0.0, 1.0) + 9.1) < 0.1) {
			alb *= 1.0 - 0.5 * smoothstep(-0.2, -0.75, fp.y);   // the soot of the vent below
		}
		float drip = smoothstep(0.55, 0.8, fbm(vec2(uv.x * 1.7, uv.y * 0.18))) * smoothstep(3.0, 0.0, dtop);
		alb = mix(alb, vec3(0.33, 0.15, 0.06), drip);
		ao = mix(0.4, 1.0, smoothstep(0.0, 1.6, p.y - low_y));
		float tide = step(0.5, cell_at(ivec2(floor(g_out))).y) * smoothstep(1.8, 0.0, p.y + (n2 - 0.5) * 1.2);   // a toxic sump at the foot: tide marks
		alb = mix(alb, vec3(0.07, 0.12, 0.035) * mix(0.7, 1.4, n3), tide * 0.85);
		emis += vec3(0.03, 0.11, 0.01) * tide * smoothstep(0.7, 0.0, p.y);

		if (detail > 0.5) {
			float rh;
			nrel = wall_relief(uv, n, px, rh);   // frame, inset, rivets, louvres, plates and conduits as relief
			rough = clamp(0.8 - rh * 3.0, 0.45, 1.0);   // recesses stay dull, raised parts are worn smooth
			ao *= 1.0 + 4.0 * min(rh, 0.0);
		}
		if (top_y - low_y >= 2.0 && dtop > 0.25 && dtop < 0.85 && h21(vec2(floor(uv.x / cell_in) + top_y, low_y + 7.0)) > 0.45) {   // hazard band only on some edges, chipped and dirty
			vec3 paint = mix(vec3(0.04), YELLOW * 0.8, step(0.5, fract((uv.x + p.y) * 0.9)));
			alb = mix(paint, alb, smoothstep(0.45, 0.65, n2 + 0.2 * n3));
		}
	} else {   // top faces
		float wet = 0.0;   // water lies level: the relief flattens under it
		vec2 g = (p.xz + half_board) / cell_in;
		ivec2 c = ivec2(floor(g));
		vec2 f = fract(g) * cell_in;
		vec4 me = cell_at(c);
		float lip = 9.0, rim = 9.0;
		for (int i = 0; i < 4; i++) {
			vec2 d = vec2(DIRS[i]);
			float dist = d.x > 0.5 ? cell_in - f.x : d.x < -0.5 ? f.x : d.y > 0.5 ? cell_in - f.y : f.y;
			vec4 nb = cell_at(c + DIRS[i]);
			lip = nb.x < me.x ? min(lip, dist) : lip;
			rim = (nb.y > 0.5) != (me.y > 0.5) ? min(rim, dist) : rim;
		}
		if (k <= 2) {   // wet concrete: joints, grime at the walls, organic puddles, oil, contact shadow at the foot of a wall
			float wd = wall_dist(g, c, me.x);
			alb = mix(vec3(0.20, 0.20, 0.21), vec3(0.31, 0.305, 0.30), n1) * (k == 1 ? 1.15 : 1.0);
			alb *= mix(0.55, 1.0, seam(uv.x, 1.5, 0.04) * seam(uv.y, 1.5, 0.04));
			alb *= mix(0.8, 1.0, smoothstep(0.5, 0.75, fbm(uv * 0.3 + 3.0)));
			alb *= mix(0.65, 1.0, smoothstep(0.0, 1.4, wd + (n2 - 0.5) * 0.9));   // grime gradient: darker the closer to a wall
			vec2 fp = (fract(uv / PLATE) - 0.5) * PLATE;   // modular floor plates: tone, grime in the seams, worn edges, hatches, drain grates, worn paint
			float ph = h21(floor(uv / PLATE) + 3.7);
			float ed = PLATE * 0.5 - max(abs(fp.x), abs(fp.y));
			alb *= mix(0.88, 1.08, ph) * (1.0 - 0.45 * smoothstep(0.08, 0.0, ed) * (0.4 + n2));
			alb = mix(alb, vec3(0.45, 0.44, 0.42), smoothstep(0.1, 0.0, ed) * smoothstep(0.45, 0.7, n3) * 0.5);
			if (ph < 0.03) {
				vec4 h = hatch(fp, 0.5, n3);
				alb = mix(alb, h.rgb, h.a);
			} else if (ph < 0.06) {   // drain grate: dark slots between steel bars in a frame
				float frame = max(abs(fp.x), abs(fp.y));
				alb = mix(alb, mix(vec3(0.015), vec3(0.2, 0.2, 0.21), step(0.5, fract(fp.x * 6.0))), step(frame, 0.5));
				alb *= 1.0 - 0.6 * smoothstep(0.04, 0.0, abs(frame - 0.53));
			} else if (ph > 0.94 && k == 1) {   // a worn safety-yellow stripe on the street
				alb = mix(alb, YELLOW * 0.7, step(abs(fp.x), 0.09) * smoothstep(0.45, 0.65, n2 + 0.3 * n3));
			}
			// Water: a world-space noise field (domain-warped, so the outline is irregular), biased to collect along the walls. Nothing here
			// reads the cell grid, so no puddle is clipped at a cell edge; a damp ring and a soft rim surround the open water.
			vec2 warp = vec2(fbm(uv * 0.8 + 3.1), fbm(uv * 0.8 + 8.7)) - 0.5;
			float field = fbm(uv * 0.26 + warp * 1.4 + 11.0) + 0.2 * smoothstep(1.6, 0.0, wd);
			float damp = smoothstep(0.54, 0.64, field);
			float pud = smoothstep(0.65, 0.72, field);
			wet = pud;
			alb *= mix(1.0, 0.8, damp);
			alb = mix(alb, alb * vec3(0.72, 0.78, 0.85), pud);
			rough = mix(mix(0.8, 0.35, damp), 0.05, pud);
			float oil = smoothstep(0.67, 0.73, fbm(uv * 0.7 + 41.0)) * (1.0 - pud);   // oil stains: dark, glossy, a faint rainbow sheen
			alb = mix(alb, vec3(0.06, 0.05, 0.045), oil * 0.8);
			rough = mix(rough, 0.15, oil);
			emis += oil * 0.006 * (0.5 + 0.5 * cos(6.28 * (n1 * 2.0 + vec3(0.0, 0.33, 0.67))));
			ao = mix(0.6, 1.0, smoothstep(0.0, 1.0, wd));
			float sd = sump_dist(g, c);   // the sump's stain creeps over the floor round it: wet, green-black crust with ragged tongues
			float reach = 0.35 + 1.7 * fbm(uv * 1.1 + 5.0);   // ragged tongues: how far the stain goes from the pool at this spot
			float creep = smoothstep(reach, reach - 0.45, sd) * step(me.y, 0.5);
			alb = mix(alb, vec3(0.045, 0.07, 0.025) * mix(0.7, 1.3, n3), creep * 0.85);
			rough = mix(rough, 0.7, creep);
			emis += vec3(0.02, 0.08, 0.006) * smoothstep(0.4, 0.0, sd) * creep * n2;
			if (me.y > 0.5) {   // sump: a sunken basin; the liquid is dark where deep and bright at the shore, ripples slowly, with scum, glints and popping bubbles
				float depth = smoothstep(0.5, 1.9, rim);
				vec3 vd = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
				vec2 q = p.xz - vd.xz / max(vd.y, 0.2) * 0.3 * depth;   // the surface lies below the kerb: the pattern slides with the eye
				float h0 = swell(q);
				nw = normalize(vec3(-(swell(q + vec2(0.1, 0.0)) - h0) * 3.5, 1.0, -(swell(q + vec2(0.0, 0.1)) - h0) * 3.5));
				float liquid = smoothstep(0.42, 0.8, rim + (n2 - 0.5) * 0.6);
				float scum = smoothstep(0.5, 0.62, fbm(q * 0.9 + vec2(TIME * 0.02, TIME * 0.01) + 5.0)) * (0.5 + 0.5 * (1.0 - depth));
				float vein = pow(1.0 - abs(2.0 * fbm(q * 1.1 + TIME * 0.03) - 1.0), 4.0);
				vec2 bub = bubbles(q);
				vec3 bank = vec3(0.10, 0.09, 0.05) * mix(0.7, 1.3, n3);
				vec3 deep = mix(vec3(0.04, 0.11, 0.03), vec3(0.008, 0.03, 0.02), depth);
				alb = mix(bank, mix(deep, vec3(0.30, 0.34, 0.07) * mix(0.8, 1.2, n2), scum * 0.8), liquid);
				rough = mix(0.9, mix(0.04, 0.6, scum), liquid);
				spec = mix(0.5, 1.0, liquid * (1.0 - scum));
				float pulse = 0.65 + 0.35 * vnoise(q * 0.9 + TIME * 0.1);
				emis = (mix(vec3(0.10, 0.34, 0.015), vec3(0.0, 0.05, 0.03), depth) * pulse * (1.0 - scum * 0.7) + vec3(0.1, 0.5, 0.07) * vein * 0.3) * liquid;
				emis += (vec3(0.5, 1.0, 0.3) * bub.x * 0.5 + vec3(0.8, 1.0, 0.5) * bub.y * 0.7) * liquid;
				ao = mix(0.5, 1.0, smoothstep(0.28, 0.9, rim));
				liquid_on = true;
			}
		} else if (k == 3) {   // rusted plate deck: 1.5 in plates, rivets, seams
			float ph = h21(floor(uv / 1.5));
			alb = mix(vec3(0.50, 0.27, 0.13), vec3(0.62, 0.38, 0.20), n1) * mix(0.8, 1.15, ph);
			alb = mix(alb, vec3(0.34, 0.34, 0.37), step(0.78, ph) * 0.8);
			alb *= mix(0.45, 1.0, seam(uv.x, 1.5, 0.035) * seam(uv.y, 1.5, 0.035));
			alb *= mix(0.65, 1.0, smoothstep(0.45, 0.7, n2));
			float riv = smoothstep(0.075, 0.045, length(abs(fract(uv / 1.5) - 0.5) * 1.5 - vec2(0.6)));
			alb += riv * 0.12;
			vec4 hd = hatch((fract(uv / PLATE) - 0.5) * PLATE, 0.5, n3);
			alb = mix(alb, hd.rgb, hd.a * step(ph, 0.06));
			rough = 0.7;
			met = 0.35;
		} else {   // rooftop slab: 3 in slabs, tar joints, gravel
			vec2 sl = floor((uv + half_board) / cell_in);
			alb = mix(vec3(0.50, 0.495, 0.48), vec3(0.62, 0.60, 0.57), n1) * mix(0.9, 1.1, h21(sl));
			alb *= mix(0.2, 1.0, seam(uv.x + half_board.x, cell_in, 0.06) * seam(uv.y + half_board.y, cell_in, 0.06));
			alb *= mix(0.88, 1.08, n3) * mix(0.7, 1.0, smoothstep(0.5, 0.72, n2));
			rough = 0.85;
			vec4 hr = hatch((fract((uv + half_board) / cell_in) - 0.5) * cell_in, 1.0, n3);
			alb = mix(alb, hr.rgb, hr.a * step(h21(sl + 5.0), 0.1));
		}
		if (detail > 0.5) {
			float th;
			nrel = top_relief(uv, k, half_board, px, wet, th);   // plate seams, hatches, grates, deck rivets and tread, roof joints
			rough = clamp(rough - th * 4.0 * (1.0 - wet), 0.05, 1.0);
			ao *= 1.0 + 4.0 * min(th, 0.0);
		}
		if (k == 6) {
			alb *= vec3(0.82, 0.9, 1.08);
		}
		if (lip < 0.2) {   // the tier's trim: a pale lip with a dark groove behind it, no railing
			alb = lip < 0.08 ? alb * 1.5 + 0.08 : alb * 0.5;
		}
	}
	vec4 ew = box_in.x > 0.0 && detail > 0.5 ? edge_wear(lpos, box_in * 0.5, lnrm, p, k, half_board, smoothstep(0.48, 0.56, n3 * 0.6 + n2 * 0.5)) : vec4(0.0);   // every real box edge: a broken pale highlight, a bent normal
	alb = mix(alb, mix(alb * 1.5 + 0.08, vec3(0.62, 0.6, 0.57), 0.6), ew.x);
	rough = mix(rough, 0.45, ew.x);
	if (dot(ew.yzw, ew.yzw) > 0.0001 || dot(nrel - n, nrel - n) > 0.0) {
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nrel + ew.yzw * 0.9), 0.0)).xyz);
	}
	ALBEDO = pow(alb, vec3(2.2)) * (detail > 0.5 ? 1.0 : ao);   // the numbers above are display values; Low keeps the occlusion baked into the colour
	AO = detail > 0.5 ? ao : 1.0;   // the finer look: the cell occlusion shades the ambient light and part of the direct light
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = rough;
	METALLIC = met;
	EMISSION = emis;
	SPECULAR = spec;
	if (liquid_on) {
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}
}

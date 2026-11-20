shader_type spatial;
// Look of a generated undercity board (BoardgenGreybox): ONE material for every box of the board. The surface kind comes per
// instance (INSTANCE_CUSTOM.x); the neighbouring cell heights (tier lips, cliff stripes, contact shadow, sump rim) come from a
// one-texel-per-cell texture. Everything is procedural: no texture file, nothing from a third party.
// kinds: 0 ground, 1 street, 2 sump, 3 tier 1 (rusted plate deck), 4 tier 2 (rooftop slab), 5 stair, 6 ladder.

uniform sampler2D cells : filter_nearest;   // red = height of the cell's top in inches, green = 255 for a sump cell
uniform vec2 board_cells = vec2(16.0);
uniform float cell_in = 3.0;
uniform vec3 board_origin;   // world position of the board centre

varying vec3 wpos;
varying vec3 wnrm;
varying flat float kind;

const float IN = 0.0254;
const vec3 YELLOW = vec3(0.78, 0.55, 0.05);
const ivec2 DIRS[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	kind = INSTANCE_CUSTOM.x;
}

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + 17.1;
		a *= 0.5;
	}
	return s;
}

// A thin line every `step_in` inches (0 on the line, 1 off it).
float seam(float v, float step_in, float w) {
	return smoothstep(0.0, w, abs(fract(v / step_in + 0.5) - 0.5) * step_in);
}

vec4 cell_at(ivec2 c) {   // x = height in inches, y = sump; outside the board = ground
	if (c.x < 0 || c.y < 0 || c.x >= int(board_cells.x) || c.y >= int(board_cells.y)) {
		return vec4(0.0);
	}
	return texelFetch(cells, c, 0) * 255.0;
}

void fragment() {
	vec3 p = (wpos - board_origin) / IN;   // board inches, origin = board centre
	vec3 n = normalize(wnrm);
	int k = int(kind + 0.5);
	vec2 half_board = board_cells * cell_in * 0.5;
	bool top = n.y > 0.5;
	vec2 uv = top ? p.xz : vec2(abs(n.x) > 0.5 ? p.z : p.x, p.y);
	float n1 = fbm(uv * 0.55), n2 = fbm(uv * 2.1 + 7.0), n3 = vnoise(uv * 11.0);
	vec3 alb = vec3(0.3);
	vec3 emis = vec3(0.0);
	float rough = 0.9, met = 0.0, ao = 1.0;

	if (k == 6) {   // ladder: weathered safety yellow
		alb = YELLOW * mix(0.5, 0.9, n2);
		rough = 0.5;
		met = 0.5;
	} else if (k == 5) {   // stair: perforated steel treads
		float hole = top ? step(length(fract(uv * 4.0) - 0.5), 0.26) : 0.0;
		alb = vec3(0.34, 0.35, 0.38) * mix(1.0, 0.3, hole) * mix(0.8, 1.0, n2);
		rough = 0.45;
		met = 0.6;
	} else if (!top) {   // cliff wall of a tier: formwork concrete, rust drips from the lip, hazard band under it
		vec2 nh = normalize(n.xz + 0.0001);
		vec2 g_in = (p.xz - nh * 0.02 + half_board) / cell_in;
		vec2 g_out = (p.xz + nh * 0.02 + half_board) / cell_in;
		float top_y = cell_at(ivec2(floor(g_in))).x;
		float low_y = cell_at(ivec2(floor(g_out))).x;
		float dtop = top_y - p.y;
		alb = mix(vec3(0.17, 0.165, 0.16), vec3(0.30, 0.285, 0.27), n1) * (k == 4 ? 1.25 : 1.0);
		alb *= mix(0.55, 1.0, seam(uv.y, 1.5, 0.05)) * mix(0.7, 1.0, seam(uv.x, 1.5, 0.04));
		float drip = smoothstep(0.55, 0.8, fbm(vec2(uv.x * 1.7, uv.y * 0.18))) * smoothstep(3.0, 0.0, dtop);
		alb = mix(alb, vec3(0.33, 0.15, 0.06), drip);
		ao = mix(0.4, 1.0, smoothstep(0.0, 1.6, p.y - low_y));
		if (top_y - low_y >= 2.0 && dtop > 0.25 && dtop < 0.85) {   // hazard band, chipped and dirty
			vec3 paint = mix(vec3(0.04), YELLOW * 0.8, step(0.5, fract((uv.x + p.y) * 0.9)));
			alb = mix(paint, alb, smoothstep(0.45, 0.65, n2 + 0.2 * n3));
		}
	} else {   // top faces
		vec2 g = (p.xz + half_board) / cell_in;
		ivec2 c = ivec2(floor(g));
		vec2 f = fract(g) * cell_in;
		vec4 me = cell_at(c);
		float lip = 9.0, contact = 9.0, rim = 9.0;
		for (int i = 0; i < 4; i++) {
			vec2 d = vec2(DIRS[i]);
			float dist = d.x > 0.5 ? cell_in - f.x : d.x < -0.5 ? f.x : d.y > 0.5 ? cell_in - f.y : f.y;
			vec4 nb = cell_at(c + DIRS[i]);
			lip = nb.x < me.x ? min(lip, dist) : lip;
			contact = nb.x > me.x ? min(contact, dist) : contact;
			rim = (nb.y > 0.5) != (me.y > 0.5) ? min(rim, dist) : rim;
		}
		if (k <= 2) {   // wet concrete: joints, grime, puddles, contact shadow at the foot of a wall
			alb = mix(vec3(0.20, 0.20, 0.21), vec3(0.31, 0.305, 0.30), n1) * (k == 1 ? 1.15 : 1.0);
			alb *= mix(0.55, 1.0, seam(uv.x, 1.5, 0.04) * seam(uv.y, 1.5, 0.04));
			alb *= mix(0.8, 1.0, smoothstep(0.5, 0.75, fbm(uv * 0.3 + 3.0)));
			float pud = smoothstep(0.58, 0.64, fbm(uv * 0.22 + 11.0));
			alb *= mix(1.0, 0.9, pud);
			rough = mix(0.8, 0.15, pud);
			ao = mix(0.6, 1.0, smoothstep(0.0, 1.0, contact));
			if (me.y > 0.5) {   // sump: murky condensate
				alb = vec3(0.04, 0.075, 0.035) * mix(0.7, 1.3, n2);
				rough = 0.06;
				emis = vec3(0.07, 0.15, 0.01) * smoothstep(0.4, 0.9, fbm(uv * 0.8 + TIME * 0.04));
			}
			if (rim < 0.28) {   // painted rim of a sump
				alb = mix(vec3(0.05), YELLOW, step(0.5, fract((p.x + p.z) * 0.8))) * mix(0.6, 1.0, n2);
			}
		} else if (k == 3) {   // rusted plate deck: 1.5 in plates, rivets, seams
			float ph = h21(floor(uv / 1.5));
			alb = mix(vec3(0.50, 0.27, 0.13), vec3(0.62, 0.38, 0.20), n1) * mix(0.8, 1.15, ph);
			alb = mix(alb, vec3(0.34, 0.34, 0.37), step(0.78, ph) * 0.8);
			alb *= mix(0.45, 1.0, seam(uv.x, 1.5, 0.035) * seam(uv.y, 1.5, 0.035));
			alb *= mix(0.65, 1.0, smoothstep(0.45, 0.7, n2));
			float riv = smoothstep(0.075, 0.045, length(abs(fract(uv / 1.5) - 0.5) * 1.5 - vec2(0.6)));
			alb += riv * 0.12;
			rough = 0.7;
			met = 0.35;
		} else {   // rooftop slab: 3 in slabs, tar joints, gravel
			vec2 sl = floor((uv + half_board) / cell_in);
			alb = mix(vec3(0.50, 0.495, 0.48), vec3(0.62, 0.60, 0.57), n1) * mix(0.9, 1.1, h21(sl));
			alb *= mix(0.2, 1.0, seam(uv.x + half_board.x, cell_in, 0.06) * seam(uv.y + half_board.y, cell_in, 0.06));
			alb *= mix(0.88, 1.08, n3) * mix(0.7, 1.0, smoothstep(0.5, 0.72, n2));
			rough = 0.85;
		}
		if (lip < 0.2) {   // the tier's trim: a pale lip with a dark groove behind it, no railing
			alb = lip < 0.08 ? alb * 1.5 + 0.08 : alb * 0.5;
		}
	}
	ALBEDO = pow(alb, vec3(2.2)) * ao;   // the numbers above are display values
	ROUGHNESS = rough;
	METALLIC = met;
	EMISSION = emis;
}

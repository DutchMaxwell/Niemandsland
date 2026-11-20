// --- Edge wear (AAA step 1): a thin, broken highlight and a normal bent toward the neighbouring face on every REAL convex edge of a box.
// Boxes of one level are split per row, so a box edge is real only where the surface really ends: on a top face where the cell across
// it is lower, on a wall at its top and at a vertical corner where the cell along it is lower (concave corners and the foot stay clean).
// Ladders (kind 5) are free-standing, every edge of them is real. The box size comes per instance (INSTANCE_CUSTOM.gba, inches).

// One candidate edge on axis `ax` (0 x, 1 y, 2 z) of the face: m = 1 on the edge down to 0 at w inches, o = the outward direction.
float edge_one(int ax, vec3 lp, vec3 hs, vec3 ln, vec3 p, float w, int k, vec2 half_board, out vec3 o) {
	float l = ax == 0 ? lp.x : ax == 1 ? lp.y : lp.z;
	float h = ax == 0 ? hs.x : ax == 1 ? hs.y : hs.z;
	float a = ax == 0 ? ln.x : ax == 1 ? ln.y : ln.z;
	float s = l < 0.0 ? -1.0 : 1.0;
	float d = h - abs(l);
	o = vec3(ax == 0 ? s : 0.0, ax == 1 ? s : 0.0, ax == 2 ? s : 0.0);
	if (abs(a) > 0.5 || d > w) {
		return 0.0;   // the face's own axis, or too far from this edge
	}
	if (k != 5) {
		if (ax == 1) {
			if (s < 0.0) {
				return 0.0;   // a wall's foot is concave
			}
		} else {
			vec2 nb = p.xz + o.xz * (d + 0.1) - (ln.y > 0.5 ? vec2(0.0) : ln.xz * 0.02);
			if (cell_at(ivec2(floor((nb + half_board) / cell_in))).x > p.y - 0.5) {
				return 0.0;   // the surface goes on past this edge: a seam between two boxes, not an edge
			}
		}
	}
	return smoothstep(w, 0.0, d);
}

// x = highlight 0..1, yzw = the summed outward directions of the edges at this point (bend the shading normal by them).
vec4 edge_wear(vec3 lp, vec3 hs, vec3 ln, vec3 p, int k, vec2 half_board, float chip) {
	float w = min(0.05, min(hs.x, min(hs.y, hs.z)) * 0.35);
	vec3 o, bend = vec3(0.0);
	float hl = 0.0;
	for (int ax = 0; ax < 3; ax++) {
		float m = edge_one(ax, lp, hs, ln, p, w, k, half_board, o);
		bend += o * m;
		hl = max(hl, m);
	}
	return vec4(hl * mix(0.45, 1.0, chip), bend);
}

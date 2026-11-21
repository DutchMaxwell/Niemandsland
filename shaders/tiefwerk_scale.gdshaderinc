// --- Scale cues (AAA step 8) ---
// Human-scale features in the wall shader, so a wall is built for the 32 mm models standing against it: ground-level doors (0.7 x 1.4 in, frame,
// handle, hinges, kick plate), slit windows at 1.1 in with a dim glow (one per storey), a 0.3 in plinth, columns at the convex corners of a
// block and panels of 0.75 / 1.5 / 3 in by hash. Walls only; a wall's uv is (board inches along the wall, board height).
//
// ctx = (hy, door_ok, col): hy = the height above the floor OUTSIDE the wall (a tier wall stands on its own floor), door_ok = 1 when a door may
// stand here (the floor outside is no sump and no ladder foot), col = 0..1 how close the point is to a real convex corner of its block.

const float DOOR_W = 0.7;
const float DOOR_H = 1.4;
const float PLINTH_H = 0.3;
const float COLUMN_W = 0.3;
const float STOREY = 3.0;   // inches: the step between two levels, so a slit window repeats once per storey

// The plate size of a 3 x 3 in bay of wall: 0.75, 1.5 or 3 in (all three divide 3, so a plate never crosses a bay).
float wall_plate(vec2 uv) {
	float h = h21(floor(uv / 3.0) + 17.0);
	return h < 0.25 ? 0.75 : h < 0.78 ? 1.5 : 3.0;
}

// The door of the 3 in cell of wall holding u (inches along the wall): xy = inches from the door's bottom centre, z = its hash, w = 1 when a door stands here.
vec4 door_cell(float u, float hy, float ok) {
	float cell = floor(u / 3.0);
	float cx = (cell + 0.5) * 3.0 + (h21(vec2(cell, 31.0)) - 0.5) * 0.6;
	return vec4(u - cx, hy, h21(vec2(cell, 37.0)), ok * step(h21(vec2(cell, 29.0)), 0.2) * step(0.0, hy));
}

// The slit window of this storey in the 3 in cell holding u (none where the cell has a door at ground level): xy = inches from its centre, z = 1 when there is one.
vec3 slit_cell(float u, float hy, float door_w) {
	float cell = floor(u / 3.0);
	float s = floor((hy - 1.1) / STOREY + 0.5);
	float cx = (cell + 0.5) * 3.0 + (h21(vec2(cell, 43.0 + s)) - 0.5) * 0.8;
	float present = step(0.0, s) * step(0.74, h21(vec2(cell, 41.0 + s))) * (1.0 - door_w * step(s, 0.5));
	return vec3(u - cx, hy - (1.1 + STOREY * s), present);
}

// The height of the scale features, in inches, over the panel relief `h` (raised > 0).
float scale_height(float h, vec2 uv, vec3 ctx, float px) {
	float hy = ctx.x;
	vec4 d = door_cell(uv.x, hy, ctx.y);
	if (hy >= 0.0 && hy < PLINTH_H) {   // the plinth: a course a hair proud with a chamfered top, over whatever the panels have there
		h = 0.025 * (1.0 - smoothstep(PLINTH_H - 0.04, PLINTH_H, hy)) * feature(0.05, px);
	}
	if (d.w > 0.5) {
		float fo = max(abs(d.x) - DOOR_W * 0.5, d.y - DOOR_H);   // inches outside the leaf (negative inside it)
		if (fo < 0.07) {
			float frame = 0.025 * smoothstep(0.0, 0.012, fo) * smoothstep(0.07, 0.055, fo);
			float side = d.z < 0.5 ? 1.0 : -1.0;
			float handle = 0.03 * step(length(vec2(d.x - side * 0.24, (d.y - 0.72) * 0.45)), 0.04);
			float hinge = 0.012 * step(abs(d.x + side * 0.3), 0.04) * step(abs(abs(d.y - 0.7) - 0.4), 0.07);
			float kick = 0.006 * step(d.y, 0.22);
			h = mix(h, fo < 0.0 ? -0.012 + handle + hinge + kick : frame, feature(0.1, px));
		}
	}
	vec3 s = slit_cell(uv.x, hy, d.w);
	if (s.z > 0.5) {
		float fo = max(abs(s.x) - 0.3, abs(s.y) - 0.06);
		if (fo < 0.05) {
			h = mix(h, fo < 0.0 ? -0.05 : 0.015 * smoothstep(0.0, 0.01, fo), feature(0.09, px));
		}
	}
	h += 0.04 * smoothstep(0.02, 0.2, ctx.z) * feature(0.2, px);   // a column at a convex corner
	return h;
}

// The albedo of the scale features over the wall's own colour; glow = the slit windows' dim emission.
vec3 scale_albedo(vec3 base, vec2 uv, vec3 ctx, out vec3 glow) {
	float hy = ctx.x;
	vec3 c = base;
	glow = vec3(0.0);
	vec4 d = door_cell(uv.x, hy, ctx.y);
	if (hy >= 0.0 && hy < PLINTH_H + 0.01) {   // the plinth: darker, with a thin lit chamfer line along its top
		c = c * 0.72 + 0.1 * smoothstep(0.012, 0.0, abs(hy - (PLINTH_H - 0.015)));
	}
	if (d.w > 0.5) {
		float fo = max(abs(d.x) - DOOR_W * 0.5, d.y - DOOR_H);
		if (fo < 0.07) {
			float id = d.z;
			vec3 leaf = id < 0.4 ? vec3(0.10, 0.17, 0.18) : id < 0.75 ? vec3(0.34, 0.14, 0.08) : vec3(0.13, 0.14, 0.17);   // dark teal, oxide red, dark steel (the ochre stays the signage's)
			float side = id < 0.5 ? 1.0 : -1.0;
			vec3 paint = fo < 0.0 ? leaf * (1.0 - 0.35 * smoothstep(-0.03, 0.0, fo)) : vec3(0.30, 0.30, 0.31);
			if (fo < 0.0) {
				paint = d.y < 0.22 ? mix(paint, vec3(0.30, 0.29, 0.28), 0.8) * (1.0 - 0.4 * smoothstep(0.015, 0.0, abs(d.y - 0.22))) : paint;   // the kick plate
				paint = mix(paint, vec3(0.62, 0.6, 0.55), step(length(vec2(d.x - side * 0.24, (d.y - 0.72) * 0.45)), 0.04));   // the handle
				paint = mix(paint, vec3(0.05), step(abs(d.x + side * 0.3), 0.04) * step(abs(abs(d.y - 0.7) - 0.4), 0.07));   // two hinges
			}
			c = paint;
		}
	}
	vec3 s = slit_cell(uv.x, hy, d.w);
	if (s.z > 0.5) {
		float fo = max(abs(s.x) - 0.3, abs(s.y) - 0.06);
		if (fo < 0.05) {
			c = fo < 0.0 ? vec3(0.02, 0.018, 0.015) : vec3(0.1, 0.1, 0.11);   // a dark frame, a darker pane
			glow = fo < 0.0 ? vec3(0.9, 0.42, 0.12) * 0.08 : vec3(0.0);   // a dim warm glow behind the pane
		}
	}
	return c * (1.0 + 0.25 * smoothstep(0.02, 0.2, ctx.z));   // a column at a convex corner: a paler course
}

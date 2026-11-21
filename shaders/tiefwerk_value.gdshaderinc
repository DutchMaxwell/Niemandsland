// --- Value and colour structure (AAA step 6) ---
// The board reads from above by value first: the floor is the darkest and least saturated surface, every level is one value step lighter
// (0 / 3 / 6 / 9 in), the models stay the only saturated things. A roof has ONE look per lot (the lot id is in the cell texture, blue
// channel), never one per plate, and the accents are limited to oxide red, ochre, the sump's green and one cool teal.

const float FLOOR_GAIN = 0.7;    // the floor is the darkest surface
const float FLOOR_LUMA = 0.18;    // ... and its value range is pulled toward this (the local-contrast cap)
const float DECK_GAIN = 1.15;     // level 1 (a rusted plate deck)
const float ROOF_GAIN = 1.0;      // level 2 (a rooftop slab)
const float TOWER_GAIN = 1.25;    // level 3 (a tower top)

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 desaturate(vec3 c, float keep) {   // keep 1 = the colour as it is, 0 = its grey
	return mix(vec3(luma(c)), c, keep);
}

// The colour of a lot's roofs (luminance 1, so the plate structure keeps the value): oxide red, concrete, a cool teal grey, ochre grey.
vec3 lot_hue(float lot) {
	float h = h21(vec2(lot, 3.0));
	vec3 c = h < 0.34 ? vec3(0.56, 0.30, 0.17) : h < 0.62 ? vec3(0.50, 0.51, 0.52) : h < 0.84 ? vec3(0.34, 0.46, 0.48) : vec3(0.58, 0.50, 0.34);
	return c / luma(c);
}

// A top face: k 0 ground and 1 street (darker, less colour), 3 deck / 4 roof / 6 tower top (the lot's look at the level's value).
// Sumps (2) and ladders (5) keep their own colours.
vec3 value_top(vec3 alb, int k, float lot) {
	if (k <= 1) {
		float l = luma(alb);
		return desaturate(alb, 0.55) * FLOOR_GAIN * mix(FLOOR_LUMA, l, 0.8) / max(l, 0.001);
	}
	if (k == 3 || k == 4 || k == 6) {
		float gain = k == 3 ? DECK_GAIN : k == 4 ? ROOF_GAIN : TOWER_GAIN;
		return mix(alb, lot_hue(lot) * luma(alb), 0.85) * gain;
	}
	return alb;
}

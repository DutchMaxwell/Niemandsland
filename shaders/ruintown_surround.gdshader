shader_type spatial;
// The table round the ruin town (plan PLAN_RUINTOWN_TEXTURES step 8, decision D-TEX4 (a); BoardgenSurround): dark oiled planks 3 in wide along x, a soft contact shadow
// within 2 in of the table rim and, over the outer 12 in, a fade into the town sky's own colour (albedo to 0, the sky colour of the same view ray as emission), so the
// plane's end is never seen. A value below the street's: the board stays the brightest thing in the frame.
#include "res://shaders/tiefwerk_noise.gdshaderinc"
#include "res://shaders/ruintown_sky.gdshaderinc"

uniform vec3 wood : source_color = vec3(0.07, 0.052, 0.038);   // a dark oiled walnut: under the dusk it must stay below the street (first try 0.17, 0.12, 0.085 rendered luma ~95 vs cobbles ~71)
uniform vec2 table_half = vec2(0.625);   // metres: the table's half size out to its rim (scripts/table.gd)
uniform vec2 plane_half = vec2(1.524);   // metres: this plane's half size
const float IN = 0.0254;
const float PLANK_IN = 3.0;
const float JOINT_IN = 0.06;
const float SHADOW_IN = 2.0;
const float FADE_IN = 12.0;
varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;   // metres off the board centre (the plane is the board's child)
}

void fragment() {
	vec2 p = lp / IN;
	float plank = floor(p.y / PLANK_IN);
	float fw = fwidth(p.y);
	// the gap between two planks, box-filtered: it greys out to its mean instead of shimmering once a plank is only a few pixels deep
	float d = abs(fract(p.y / PLANK_IN + 0.5) - 0.5) * PLANK_IN;
	float gap = mix(1.0 - smoothstep(JOINT_IN * 0.5 - fw, JOINT_IN * 0.5 + fw, d), JOINT_IN / PLANK_IN, smoothstep(0.5, 2.0, fw / JOINT_IN));
	float seg = floor((p.x + h21(vec2(plank, 3.7)) * 40.0) / 40.0);   // butt joints every 40 in, staggered per plank
	float tone = mix(0.78, 1.18, h21(vec2(plank, seg)));
	float grain = mix(1.0, 0.82 + 0.36 * vnoise(vec2(p.x * 0.15, p.y * 3.0)), 1.0 - smoothstep(0.1, 0.4, fw));
	vec2 out_m = max(abs(lp) - table_half, 0.0);
	float shade = mix(0.45, 1.0, smoothstep(0.0, SHADOW_IN, length(out_m) / IN));
	vec2 edge = (plane_half - abs(lp)) / IN;
	float f = 1.0 - smoothstep(0.0, FADE_IN, min(edge.x, edge.y));
	ALBEDO = wood * tone * grain * (1.0 - 0.6 * gap) * shade * (1.0 - f);
	EMISSION = town_sky(normalize(mat3(INV_VIEW_MATRIX) * VERTEX)) * f;
	ROUGHNESS = 0.6;
	SPECULAR = 0.35 * (1.0 - f);
}

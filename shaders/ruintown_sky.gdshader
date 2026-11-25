shader_type sky;
// The ruin town's blue-hour sky (plan PLAN_RUINTOWN_TARGET_C, S1; lead call D-C2): the colour by elevation lives in ruintown_sky.gdshaderinc, shared with the table round the board.
// A pure backdrop: the town's ambient light is a colour and its reflections are off, so this sky lights nothing (BoardgenMood.town_sky).
// (look review 3) The key light's disc sits exactly where its light comes from (LIGHT0_DIRECTION): a pale moon for a cool key, a warm sun with a wider glow for a warm one.
#include "res://shaders/ruintown_sky.gdshaderinc"

uniform float disc_strength = 1.0;   // 0 = no disc
const float MOON_COS = 0.99962;   // the disc's edge: ~1.6 deg across, a little larger than the real moon so it reads at play distance
const float SUN_COS = 0.99945;

void sky() {
	vec3 col = town_sky(EYEDIR);
	if (disc_strength > 0.0 && LIGHT0_ENABLED) {
		float m = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
		vec3 tint = LIGHT0_COLOR / max(max(LIGHT0_COLOR.r, LIGHT0_COLOR.g), max(LIGHT0_COLOR.b, 0.001));
		float warm = smoothstep(0.0, 0.25, tint.r - tint.b);   // 0 = a cool moon, 1 = a warm sun
		float edge = mix(MOON_COS, SUN_COS, warm);
		float disc = smoothstep(edge - 0.00008, edge + 0.00008, m);
		float halo = pow(m, mix(400.0, 120.0, warm)) * mix(0.25, 0.6, warm) + pow(m, 24.0) * mix(0.03, 0.12, warm);
		col += tint * (disc * mix(1.6, 3.0, warm) + halo) * disc_strength;
	}
	COLOR = col;
}

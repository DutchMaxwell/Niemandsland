shader_type sky;
// The ruin town's blue-hour sky (plan PLAN_RUINTOWN_TARGET_C, S1; lead call D-C2): the colour by elevation lives in ruintown_sky.gdshaderinc, shared with the table round the board.
// A pure backdrop: the town's ambient light is a colour and its reflections are off, so this sky lights nothing (BoardgenMood.town_sky).
#include "res://shaders/ruintown_sky.gdshaderinc"

void sky() {
	COLOR = town_sky(EYEDIR);
}

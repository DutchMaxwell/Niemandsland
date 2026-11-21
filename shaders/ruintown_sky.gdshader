shader_type sky;
// The ruin town's blue-hour sky (plan PLAN_RUINTOWN_TARGET_C, S1; lead call D-C2): a dark blue zenith, a paler band in the lowest 12 degrees, dark slate below the horizon.
// A pure backdrop: the town's ambient light is a colour and its reflections are off, so this sky lights nothing (BoardgenMood.town_sky).
uniform vec3 zenith : source_color = vec3(0.216, 0.286, 0.345);   // sRGB (55, 73, 88)
uniform vec3 horizon : source_color = vec3(0.471, 0.588, 0.725);   // sRGB (120, 150, 185)
uniform vec3 below : source_color = vec3(0.110, 0.153, 0.176);   // sRGB (28, 39, 45)
uniform float gain = 0.5;   // the town's exposure and grade brighten the backdrop: this brings it back to the colours above

void sky() {
	float el = degrees(asin(clamp(EYEDIR.y, -1.0, 1.0)));
	COLOR = gain * (el < 0.0 ? mix(horizon, below, smoothstep(0.0, 2.0, -el)) : mix(horizon, zenith, smoothstep(0.0, 12.0, el)));
}

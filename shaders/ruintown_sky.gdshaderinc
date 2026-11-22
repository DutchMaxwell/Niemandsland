// The ruin town's sky colour by the view's elevation (plan PLAN_RUINTOWN_TARGET_C, S1; lead call D-C2): a dark blue zenith, a paler band in the lowest 12 degrees, dark slate
// below the horizon. Shared by the sky itself (ruintown_sky.gdshader) and the table round the board (ruintown_surround.gdshader), whose far edge fades into this very colour.
uniform vec3 zenith : source_color = vec3(0.216, 0.286, 0.345);   // sRGB (55, 73, 88)
uniform vec3 horizon : source_color = vec3(0.471, 0.588, 0.725);   // sRGB (120, 150, 185)
uniform vec3 below : source_color = vec3(0.110, 0.153, 0.176);   // sRGB (28, 39, 45)
uniform float gain = 0.5;   // the town's exposure and grade brighten the backdrop: this brings it back to the colours above

// `dir`: the world direction from the eye (a sky's EYEDIR).
vec3 town_sky(vec3 dir) {
	float el = degrees(asin(clamp(dir.y, -1.0, 1.0)));
	return gain * (el < 0.0 ? mix(horizon, below, smoothstep(0.0, 2.0, -el)) : mix(horizon, zenith, smoothstep(0.0, 12.0, el)));
}

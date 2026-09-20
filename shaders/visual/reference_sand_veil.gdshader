shader_type spatial;
// Ground-hugging wind-blown sand: a flat, translucent sheet whose fbm noise scrolls
// along the wind, stretched into streaks. Unlike a camera-facing billboard it never
// shows a round silhouette, so it reads as sand streaming low over the surface.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.86,0.74,0.52,1.0);
uniform float time = 0.0;
uniform float wind_speed = 0.06;
uniform float noise_scale = 4.0;
uniform float opacity = 0.22;
uniform float gust = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34,345.45));
	p += dot(p,p + 34.345);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i), b = hash21(i + vec2(1.0,0.0));
	float c = hash21(i + vec2(0.0,1.0)), d = hash21(i + vec2(1.0,1.0));
	return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void fragment() {
	// Stretch along X (the wind) so the haze reads as streaks, not blobs.
	vec2 p = vec2(UV.x * noise_scale * 2.2, UV.y * noise_scale);
	vec2 drift = vec2(time * wind_speed * 8.0, time * wind_speed * 0.6);
	float n = fbm(p - drift);
	float streak = fbm(vec2(p.x * 0.5,p.y * 3.0) - drift * 1.6);
	// Narrow band + strong streak term: distinct streaming wisps with gaps, not a film.
	float mask = smoothstep(0.40,0.66,n) * (0.30 + 0.70 * streak * streak);
	// Soft border so the sheet does not end on a hard edge over the board.
	float edge = smoothstep(0.0,0.12,UV.x) * smoothstep(1.0,0.88,UV.x)
		* smoothstep(0.0,0.12,UV.y) * smoothstep(1.0,0.88,UV.y);
	ALBEDO = tint.rgb;
	ALPHA = mask * edge * opacity * gust;
}

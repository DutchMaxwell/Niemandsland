shader_type canvas_item;
// Full-screen cinematic framing for the intro: vignette, edge-weighted chromatic
// aberration, and fine film grain, with a brief "boot" glitch/scanline burst. Lives on
// a ColorRect over the intro CanvasLayer. `fx_strength` is tweened 1 -> 0 at hand-off so
// gameplay stays untouched. Samples the already-rendered frame via SCREEN_TEXTURE.
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform float fx_strength : hint_range(0.0, 1.0) = 1.0;  // master fade for all effects
uniform float vignette_strength : hint_range(0.0, 2.0) = 1.1;
uniform float aberration : hint_range(0.0, 0.02) = 0.004;
uniform float grain_amount : hint_range(0.0, 0.3) = 0.06;
uniform float glitch_amount : hint_range(0.0, 1.0) = 0.0;  // pulsed during boot beats
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.08;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centre = uv - 0.5;
	float dist = length(centre);

	// Horizontal glitch tearing: shift whole scanlines sideways in short bursts.
	float line_id = floor(uv.y * 110.0);
	float glitch = step(0.96, hash(vec2(line_id, floor(TIME * 12.0)))) * glitch_amount;
	uv.x += (hash(vec2(line_id, floor(TIME * 20.0))) - 0.5) * 0.05 * glitch;

	// Chromatic aberration scaled by distance from centre.
	vec2 dir = centre * dist * aberration * fx_strength;
	float r = texture(screen_tex, uv + dir).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - dir).b;
	vec3 col = vec3(r, g, b);

	// Vignette.
	float vig = smoothstep(0.85, 0.25, dist);
	col *= mix(1.0, vig, vignette_strength * fx_strength);

	// Holographic scanlines.
	float scan = 0.5 + 0.5 * sin(uv.y * 800.0);
	col *= mix(1.0, scan, scanline_strength * fx_strength);

	// Film grain.
	float grain = (hash(uv + fract(TIME)) - 0.5) * grain_amount * fx_strength;
	col += grain;

	COLOR = vec4(col, 1.0);
}

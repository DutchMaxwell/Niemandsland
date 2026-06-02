shader_type canvas_item;
// Web-safe menu vignette: darkens the corners. Uses only UV (no screen texture),
// so it works identically on Forward+ and the Compatibility/web renderer.

uniform float radius : hint_range(0.0, 1.5) = 0.62;
uniform float strength : hint_range(0.0, 1.5) = 0.85;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	float dist = length(UV - vec2(0.5)) * 1.41421356;
	float edge = smoothstep(radius, 1.0, dist);
	COLOR = vec4(tint.rgb, clamp(edge * strength, 0.0, 1.0));
}

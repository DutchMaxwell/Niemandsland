shader_type canvas_item;
// Menu legibility scrim: darkens the left edge (under the menu column) fading out
// toward the diorama, plus a thin bottom gradient under the footer. Pure UV math —
// web-safe (no screen textures, no derivatives).

uniform float edge_alpha : hint_range(0.0, 1.0) = 0.7;
uniform float fade_end : hint_range(0.0, 1.0) = 0.62;
uniform float bottom_alpha : hint_range(0.0, 1.0) = 0.45;
uniform float bottom_start : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	float side = edge_alpha * (1.0 - smoothstep(0.0, fade_end, UV.x));
	float bottom = bottom_alpha * smoothstep(bottom_start, 1.0, UV.y);
	COLOR = vec4(0.0, 0.0, 0.0, max(side, bottom));
}

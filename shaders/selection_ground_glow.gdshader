shader_type spatial;
// Flat ground halo: additive, unshaded, never writes depth or casts/receives shadow,
// so it reads as projected light on the surface rather than a physical disc.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 glow_color : source_color = vec3(0.3, 0.6, 1.0);
// Peak HDR brightness — above the WorldEnvironment glow threshold so the ring blooms.
uniform float intensity : hint_range(0.0, 8.0) = 3.2;
uniform float pulse_speed = 2.4;
uniform float pulse_depth : hint_range(0.0, 1.0) = 0.35;
// Radial position (0 = centre, 1 = mesh edge) and softness of the bright ring.
uniform float ring_radius : hint_range(0.0, 1.0) = 0.78;
uniform float ring_width : hint_range(0.01, 0.5) = 0.13;
uniform float inner_fill : hint_range(0.0, 1.0) = 0.18;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;          // 0 centre .. 1 edge
	float ring = exp(-pow((d - ring_radius) / ring_width, 2.0));
	float inner = (1.0 - smoothstep(0.0, ring_radius, d)) * inner_fill;
	float edge_fade = 1.0 - smoothstep(0.94, 1.0, d); // kill the hard mesh border
	float pulse = 1.0 - pulse_depth * (0.5 + 0.5 * sin(TIME * pulse_speed));
	float a = clamp(ring + inner, 0.0, 1.0) * edge_fade * pulse;

	ALBEDO = glow_color * intensity;
	EMISSION = glow_color * intensity * a;
	ALPHA = a;
}

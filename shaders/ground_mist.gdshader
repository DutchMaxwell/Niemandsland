shader_type spatial;
// Thin, soft, slow-drifting white ground mist for a flat plane that hugs the table a
// few millimetres above the surface. Unshaded so it stays white, alpha-blended, never
// writes depth or casts shadow. Large soft patches with gaps (not full coverage), so it
// reads as vague drifting haze rather than a speckled sheet. Scrolls via TIME.
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, unshaded, fog_disabled;

uniform vec3 mist_color : source_color = vec3(0.93, 0.95, 0.98);
uniform sampler2D noise_tex : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform float density : hint_range(0.0, 1.5) = 0.45;
uniform float tiling = 1.25;
uniform vec2 scroll = vec2(0.0028, 0.0016);
uniform float edge_fade : hint_range(0.0, 0.5) = 0.2;
// Coverage threshold: higher = more bare ground (bigger gaps). softness widens the
// fade so patches dissolve vaguely instead of having defined edges.
uniform float coverage : hint_range(0.0, 1.0) = 0.52;
uniform float softness : hint_range(0.02, 0.6) = 0.34;

void fragment() {
	// Two large, slowly-drifting samples -> soft, vague, area-filling patches.
	vec2 uv1 = UV * tiling + scroll * TIME;
	vec2 uv2 = UV * tiling * 0.6 - scroll * TIME * 0.55 + vec2(0.37);
	float m = texture(noise_tex, uv1).r * 0.6 + texture(noise_tex, uv2).r * 0.4;

	// Only the denser regions show, with a soft transition -> gaps + vague edges.
	float cover = smoothstep(coverage, coverage + softness, m);

	// Fade out toward the plane edges (no hard rectangular boundary).
	vec2 e = smoothstep(vec2(0.0), vec2(edge_fade), UV)
		* smoothstep(vec2(0.0), vec2(edge_fade), 1.0 - UV);
	float a = clamp(cover * density, 0.0, 1.0) * e.x * e.y;

	ALBEDO = mist_color;
	ALPHA = a;
}

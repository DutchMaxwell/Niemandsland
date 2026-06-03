shader_type spatial;
// Thin, soft, drifting ground mist on a flat plane a few millimetres above the table.
// LIT (not unshaded) so scene lights tint it — the green selection spill, the star, etc.
// Alpha-blended, no depth write, no shadow. Large soft patches with gaps (vague, not a
// sheet). Pushed aside around miniatures via clear_points, and faded in via global_alpha.
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 mist_color : source_color = vec3(0.95, 0.96, 0.98);
uniform sampler2D noise_tex : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform float density : hint_range(0.0, 1.5) = 0.32;
uniform float tiling = 1.45;
uniform vec2 scroll = vec2(0.011, 0.006);
uniform float edge_fade : hint_range(0.0, 0.5) = 0.2;
// Coverage threshold: higher = more bare ground (bigger gaps). softness widens the fade.
uniform float coverage : hint_range(0.0, 1.0) = 0.6;
uniform float softness : hint_range(0.02, 0.6) = 0.32;
// Fade-in (0 = invisible). Driven by the script after the table is built.
uniform float global_alpha : hint_range(0.0, 1.0) = 0.0;

// Miniatures push the mist aside: local XZ offsets (metres) from the plane centre.
const int MAX_CLEAR = 32;
uniform int clear_count = 0;
uniform vec2 clear_points[MAX_CLEAR];
uniform float clear_radius = 0.05;
uniform float clear_softness = 0.045;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;  // PlaneMesh lies in XZ; v_local.xz is the offset from the centre
}

void fragment() {
	// Two large, drifting samples -> soft, vague, area-filling patches.
	vec2 uv1 = UV * tiling + scroll * TIME;
	vec2 uv2 = UV * tiling * 0.6 - scroll * TIME * 0.55 + vec2(0.37);
	float m = texture(noise_tex, uv1).r * 0.6 + texture(noise_tex, uv2).r * 0.4;
	float cover = smoothstep(coverage, coverage + softness, m);

	// Fade out toward the plane edges (no hard rectangular boundary).
	vec2 e = smoothstep(vec2(0.0), vec2(edge_fade), UV)
		* smoothstep(vec2(0.0), vec2(edge_fade), 1.0 - UV);
	float a = clamp(cover * density, 0.0, 1.0) * e.x * e.y;

	// Push the mist aside near miniatures (follows them as they move).
	float clear = 1.0;
	for (int i = 0; i < clear_count; i++) {
		float d = distance(v_local.xz, clear_points[i]);
		clear *= smoothstep(clear_radius, clear_radius + clear_softness, d);
	}

	ALBEDO = mist_color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	ALPHA = a * clear * global_alpha;
}

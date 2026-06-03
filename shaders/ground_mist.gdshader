shader_type spatial;
// Thin, soft, drifting ground mist on a flat plane a few millimetres above the table.
// LIT (not unshaded) so scene lights tint it. Alpha-blended, no depth write, no shadow.
// The mist is sampled in metres (noise_freq = tiles per metre) so its look is identical
// at any table size — the plane just grows to cover the whole field. Miniatures DISPLACE
// the mist like water: the sampled pattern is shoved outward around each model (it piles
// at the rim and a small core clears), and as a model moves the displacement follows it.
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 mist_color : source_color = vec3(0.95, 0.96, 0.98);
uniform sampler2D noise_tex : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform float density : hint_range(0.0, 1.5) = 0.32;
uniform float noise_freq = 1.3;            // tiles per metre (table-size independent)
uniform vec2 scroll = vec2(0.012, 0.007);
uniform float edge_fade : hint_range(0.0, 0.5) = 0.05;
uniform float coverage : hint_range(0.0, 1.0) = 0.55;
uniform float softness : hint_range(0.02, 0.6) = 0.32;
uniform float global_alpha : hint_range(0.0, 1.0) = 0.0;

// Miniatures part the mist like water: plane-local XZ offsets (metres) from the centre.
const int MAX_CLEAR = 32;
uniform int clear_count = 0;
uniform vec2 clear_points[MAX_CLEAR];
uniform float push_radius = 0.07;          // how far out the displacement reaches (m)
uniform float push_amount = 0.045;         // how hard the mist is shoved aside (m)
uniform float core_clear : hint_range(0.0, 1.0) = 0.7;  // clearing right under the model

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;  // PlaneMesh lies in XZ; v_local.xz is metres from the centre
}

void fragment() {
	vec2 local = v_local.xz;

	// Water-like displacement: shove the sampled position outward around each model,
	// and clear a small core directly beneath it.
	vec2 pushed = local;
	float thin = 1.0;
	for (int i = 0; i < clear_count; i++) {
		vec2 d = local - clear_points[i];
		float dist = length(d) + 1e-4;
		float infl = smoothstep(push_radius, 0.0, dist);     // 1 at centre .. 0 at rim
		pushed += (d / dist) * infl * push_amount;
		thin *= 1.0 - infl * core_clear;
	}

	// Two drifting samples in metres -> soft, vague, area-filling patches.
	vec2 uv1 = pushed * noise_freq + scroll * TIME;
	vec2 uv2 = pushed * noise_freq * 0.6 - scroll * TIME * 0.55 + vec2(0.37);
	float m = texture(noise_tex, uv1).r * 0.6 + texture(noise_tex, uv2).r * 0.4;
	float cover = smoothstep(coverage, coverage + softness, m);

	// Soft plane border (UV-based) so the mist meets the table edge without a hard line.
	vec2 e = smoothstep(vec2(0.0), vec2(edge_fade), UV)
		* smoothstep(vec2(0.0), vec2(edge_fade), 1.0 - UV);

	ALBEDO = mist_color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	ALPHA = clamp(cover * density, 0.0, 1.0) * e.x * e.y * thin * global_alpha;
}

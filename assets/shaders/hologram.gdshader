shader_type spatial;
// Holographic look for procedural terrain props (walls, trees, containers, dangerous
// hazards). Pale-blue, transparent, self-lit with a fresnel rim and faint scanlines.
//
// Texturable later: assign a texture to `albedo_tex` and raise `texture_mix` toward 1.0
// to blend from the hologram tint into a fully textured, opaque surface.
render_mode blend_mix, cull_back, depth_draw_opaque, specular_disabled, shadows_disabled, ambient_light_disabled;

uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 hologram_color : source_color = vec4(0.5, 0.75, 1.0, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.35;
uniform float texture_mix : hint_range(0.0, 1.0) = 0.0;
uniform float fresnel_power : hint_range(0.1, 8.0) = 2.5;
uniform float emission_strength : hint_range(0.0, 4.0) = 1.4;
uniform float scanline_density = 90.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.15;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 tex_rgb = texture(albedo_tex, UV).rgb;
	vec3 base_rgb = mix(hologram_color.rgb, tex_rgb, texture_mix);

	// Fresnel rim — edges glow brighter and more opaque (NORMAL/VIEW are view-space).
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);

	// Horizontal scanlines in world space for a stable holographic shimmer.
	float scan = mix(1.0, 0.5 + 0.5 * sin(v_world_pos.y * scanline_density), scanline_strength);

	ALBEDO = base_rgb * scan;
	EMISSION = base_rgb * emission_strength * (0.35 + fresnel);
	ALPHA = mix(clamp(base_alpha + fresnel * 0.5, 0.0, 1.0), 1.0, texture_mix);
}

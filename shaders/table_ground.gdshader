shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Macro battlefield mat (one stretched copy across the table — it is a one-off
// painted scene, not a tileable material, so UV1 stays 0..1).
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
// Seamless procedural micro-relief, tiled densely so the surface keeps crisp
// detail at any zoom instead of magnifying the soft mat texels.
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_height : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float detail_tiling = 28.0;
uniform float detail_normal_strength : hint_range(0.0, 1.0) = 0.35;
uniform float detail_albedo_strength : hint_range(0.0, 0.5) = 0.12;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;

	// Micro colour variation keeps the ground from reading as a flat blur up close.
	vec2 duv = UV * detail_tiling;
	float h = texture(detail_height, duv).r;
	float albedo_mod = 1.0 + (h - 0.5) * 2.0 * detail_albedo_strength;
	ALBEDO = base * albedo_mod;

	ROUGHNESS = roughness_value;
	METALLIC = 0.0;

	// Tangent-space detail normal for fine surface relief that catches the sun.
	vec3 n = texture(detail_normal, duv).xyz;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = detail_normal_strength;
}

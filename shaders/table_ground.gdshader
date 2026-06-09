shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// One biome battlemap mapped across the whole table at a fixed real-world extent (no
// tiling): uv_scale crops it for tables smaller than the 6x4 ft reference, keeping ground
// features at a constant real-world scale. Clamped (repeat_disable) so it never repeats.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// Seamless procedural micro-relief, tiled densely so the surface keeps crisp
// detail at any zoom instead of magnifying the soft mat texels.
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_height : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec2 uv_scale = vec2(1.0);
uniform float detail_tiling = 28.0;
uniform float detail_normal_strength : hint_range(0.0, 1.0) = 0.35;
uniform float detail_albedo_strength : hint_range(0.0, 0.5) = 0.12;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;

void fragment() {
	// Centre-crop the battlemap to the table: scale 1 shows the whole 6x4 image, <1 a
	// centred crop. Clamp keeps samples inside the image for any table size.
	vec2 macro_uv = clamp(0.5 + (UV - 0.5) * uv_scale, vec2(0.0), vec2(1.0));
	vec3 base = texture(albedo_tex, macro_uv).rgb;

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

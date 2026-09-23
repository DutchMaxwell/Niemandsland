shader_type spatial;
// One die body for every look (uidice2): a rounded cube whose six faces map into a 3 x 2 pip atlas
// (R = pip mask, soft edge) with a matching normal map for the engraving. The look is uniforms only
// (DiceLook); a die's colour tag is the per-instance body / pip colour. Visual only.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D pip_atlas : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D pip_normal : hint_normal, filter_linear_mipmap, repeat_disable;
uniform float roughness : hint_range(0.0, 1.0) = 0.45;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float clearcoat : hint_range(0.0, 1.0) = 0.0;
uniform float rim : hint_range(0.0, 1.0) = 0.0;
uniform float pip_depth : hint_range(0.0, 2.0) = 1.0;
uniform float pip_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float pip_roughness : hint_range(0.0, 1.0) = 0.7;
instance uniform vec4 body_color : source_color = vec4(0.93, 0.93, 0.90, 1.0);
instance uniform vec4 pip_color : source_color = vec4(0.12, 0.12, 0.14, 1.0);

void fragment() {
	float m = texture(pip_atlas, UV).r;
	ALBEDO = mix(body_color.rgb, pip_color.rgb, m);
	METALLIC = mix(metallic, pip_metallic, m);
	ROUGHNESS = mix(roughness, pip_roughness, m);
	NORMAL_MAP = texture(pip_normal, UV).rgb;
	NORMAL_MAP_DEPTH = pip_depth;
	CLEARCOAT = clearcoat * (1.0 - m);
	CLEARCOAT_ROUGHNESS = 0.15;
	RIM = rim;
	RIM_TINT = 0.6;
}

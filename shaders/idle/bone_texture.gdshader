shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/idle/bone_pose.gdshaderinc"
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool has_normal = false;
uniform float normal_scale = 1.0;
uniform float rim_amount = 0.0;

void vertex() {
	mat4 m = idle_skin(CUSTOM0, CUSTOM1, TIME);
	VERTEX = (m * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize(mat3(m) * NORMAL);
	TANGENT = normalize(mat3(m) * TANGENT);
	BINORMAL = normalize(mat3(m) * BINORMAL);
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * albedo_tint.rgb;
	ROUGHNESS = 0.7;
	METALLIC = 0.0;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	RIM = rim_amount;
	RIM_TINT = 0.65;
}

shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/idle/bone_pose.gdshaderinc"
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool has_normal = false;
uniform float normal_scale = 1.0;
uniform float rim_amount = 0.0;
instance uniform float hit_flash : instance_index(1) = 0.0;
instance uniform vec4 hit_flash_color : source_color, instance_index(2) = vec4(1.0, 0.30, 0.22, 1.0);

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
	float flash = clamp(hit_flash, 0.0, 1.5);
	if (flash > 0.001) {
		float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.2);
		EMISSION = hit_flash_color.rgb * (0.35 + 1.85 * fres) * flash;
		RIM = max(rim_amount, clamp(flash, 0.0, 1.0));
	} else {
		RIM = rim_amount;
	}
	RIM_TINT = 0.65;
}

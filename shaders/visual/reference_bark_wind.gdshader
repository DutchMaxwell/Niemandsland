shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Reconstructed oak branches. The trunk stays put; only the wood above `sway_bottom`
// bends, with the same phase as the leaf cards so crown and branches move together.
uniform sampler2D bark_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap;
uniform bool bark_normal_enabled = false;
uniform float wind_branch = 0.0;
uniform float sway_bottom = 0.0;
uniform float sway_top = 1.0;
void vertex() {
	vec3 p = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	float sway = smoothstep(sway_bottom, sway_top, VERTEX.y);
	if (wind_branch != 0.0) {
		VERTEX.x += sin(TIME*1.4+p.x*3.0+p.z*2.4)*wind_branch*sway;
		VERTEX.z += cos(TIME*1.1+p.x*2.6-p.z*3.1)*wind_branch*0.6*sway;
	}
}
void fragment() {
	ALBEDO = texture(bark_tex,UV).rgb;
	if (bark_normal_enabled) {
		NORMAL_MAP = texture(bark_normal,UV).rgb;
		NORMAL_MAP_DEPTH = 1.0;
	}
	ROUGHNESS = 0.94;
	SPECULAR = 0.15;
	METALLIC = 0.0;
}

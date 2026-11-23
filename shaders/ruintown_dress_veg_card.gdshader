// ruintown_dress_veg_card.gdshader - the card tufts of the ruin-town dressing (surface `ct_veg_card`, incl. dr_veg_plot_a):
// textured quads from the card atlas, cut by the engine's alpha scissor. Lit like the modelled plants
// (ruintown_dress_veg.gdshaderinc), two-sided with ONE normal, no emission, no shadow casting.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/ruintown_dress_veg.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;   // the card atlas, alpha in a
uniform sampler2D atlas_dry : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 card_tone = vec3(0.15);
uniform float alpha_scissor = 0.4;

void vertex() {
	thin = UV2.y;
}

void fragment() {
	vec4 card = texture(atlas, UV);
	vec3 dry = texture(atlas_dry, UV).rgb;
	ALBEDO = mix(card.rgb, dry, clamp(DEAD_SHARE * 1.2, 0.0, 1.0)) * COLOR.rgb * 2.0 * card_tone * mix(0.35, 1.0, COLOR.a);
	ALPHA = card.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	ROUGHNESS = mix(roughness, roughness - 0.2, thin);
	SPECULAR = 0.25;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.65;
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
}

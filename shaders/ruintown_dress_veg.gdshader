// ruintown_dress_veg.gdshader - the vegetation material ct_veg of the ruin-town dressing kit (vertex contract below and in docs/adr/0004-dressing-materials-and-kit-manifest.md).
// ONE shader, two variants chosen per MODULE: use_cards = 0 for modelled blades and moss (surface `ct_veg`), 1 for the card tufts incl. dr_veg_plot_a (surface `ct_veg_card`; BoardgenDressKit names it).
// LIT by the scene, no emission, no shadow casting (the MeshInstance has cast_shadow off). Two-sided with ONE normal: the engine flips the normal of back faces, that flip is undone, so both sides of a blade
// shade by the kit's bent normal (up + out of the clump) and a clump reads as one soft mass. light(): wrapped diffuse plus light passing THROUGH thin blades when the eye looks towards the light.
// Vertex data: COLOR rgb = linear albedo / albedo_scale x 0.5 (cards: 0.5 white), COLOR.a = ambient occlusion, UV = blade (u across, v along) or the card's atlas rectangle, UV2.x = a random number per blade,
// UV2.y = thinness (1 blade, 0.8 leaf, 0.4 stalk, 0 moss; cards 0.5 / 0).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float albedo_scale = 0.14;   // modelled plants: ALBEDO = COLOR.rgb x 2 x albedo_scale (the kit's dusk albedos are 0.007-0.066)
uniform float wrap = 0.4;
uniform float backlight = 0.7;
uniform float roughness = 0.9;
uniform float wind = 0.0;   // 0 in stills; sway = wind x height x thinness
uniform float dead_share : hint_range(0.0, 1.0) = 0.15;   // blades whose random number is below it take the dry tint, cards blend to atlas_dry
uniform float use_cards = 0.0;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;   // the card atlas, alpha in a
uniform sampler2D atlas_dry : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D atlas_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;   // reserved, unused in v1
uniform vec3 card_tone = vec3(0.15);
uniform float alpha_scissor = 0.4;
uniform vec3 dry_tint = vec3(1.3, 1.05, 0.62);

varying float thin;
varying float brand;

void vertex() {
	thin = UV2.y;
	brand = UV2.x;
	if (wind > 0.0) {
		float w = COLOR.a * COLOR.a * thin * wind;
		float ph = TIME * 1.7 + brand * 6.28;
		VERTEX.xz += vec2(sin(ph), cos(ph * 0.8)) * w * 0.0006;
	}
}

void fragment() {
	vec3 alb;
	if (use_cards > 0.5) {
		vec4 a = texture(atlas, UV);
		if (a.a < alpha_scissor) {
			discard;
		}
		alb = mix(a.rgb, texture(atlas_dry, UV).rgb, clamp(dead_share * 1.2, 0.0, 1.0)) * COLOR.rgb * 2.0 * card_tone * mix(0.35, 1.0, COLOR.a);
	} else {
		alb = COLOR.rgb * 2.0 * albedo_scale;
		float dead = step(brand, dead_share) * step(0.05, thin);
		float lum = dot(alb, vec3(0.3, 0.6, 0.1));
		alb = mix(alb, lum * dry_tint * 1.15, dead * 0.92);
	}
	ALBEDO = alb;
	ROUGHNESS = mix(roughness, roughness - 0.2, thin);
	SPECULAR = 0.25;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.65;
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
}

void light() {
	float wr = clamp((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0, 1.0);
	float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 2.0) * backlight * thin;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (wr + back) / PI;
}

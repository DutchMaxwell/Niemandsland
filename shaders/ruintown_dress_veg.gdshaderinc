// ruintown_dress_veg.gdshaderinc - what the two vegetation shaders of the ruin-town dressing share (material ct_veg,
// docs/adr/0004-dressing-materials.md): the light uniforms, the dry share, the thinness varying and light().
// Vertex data of the kit: COLOR rgb = linear albedo / albedo_scale x 0.5 (cards: 0.5 white), COLOR.a = ambient occlusion,
// UV = blade (u across, v along) or the card's atlas rectangle, UV2.x = a random number per blade,
// UV2.y = thinness (1 blade, 0.8 leaf, 0.4 stalk, 0 moss; cards 0.5 / 0).

uniform float wrap = 0.4;
uniform float backlight = 0.7;
uniform float roughness = 0.9;

// The board-wide share of dry plants: modelled blades whose random number is below it take the dry tint, cards blend
// this far towards the dry atlas. A constant, not a uniform: no material sets it.
const float DEAD_SHARE = 0.15;

varying float thin;

// Wrapped diffuse plus light passing THROUGH thin blades when the eye looks towards the light.
void light() {
	float wrapped = clamp((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0, 1.0);
	float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 2.0) * backlight * thin;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (wrapped + back) / PI;
}

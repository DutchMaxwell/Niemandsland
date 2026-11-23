// ruintown_dress_veg_solid.gdshader - the modelled vegetation of the ruin-town dressing (surface `ct_veg`: blades,
// leaves, moss). No texture and no discard, so the depth prepass stays valid and hidden blades cost no shading.
// LIT by the scene, no emission, no shadow casting (the MeshInstance has cast_shadow off). Two-sided with ONE normal: the
// engine flips the normal of back faces, that flip is undone, so both sides of a blade shade by the kit's bent normal
// (up + out of the clump) and a clump reads as one soft mass. Shared parts: ruintown_dress_veg.gdshaderinc.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/ruintown_dress_veg.gdshaderinc"

uniform float albedo_scale = 0.14;   // ALBEDO = COLOR.rgb x 2 x albedo_scale (the kit's dusk albedos are 0.007-0.066)

const vec3 DRY_TINT = vec3(1.3, 1.05, 0.62);

varying float brand;

void vertex() {
	thin = UV2.y;
	brand = UV2.x;
}

void fragment() {
	vec3 albedo = COLOR.rgb * 2.0 * albedo_scale;
	float dead = step(brand, DEAD_SHARE) * step(0.05, thin);
	float luminance = dot(albedo, vec3(0.3, 0.6, 0.1));
	ALBEDO = mix(albedo, luminance * DRY_TINT * 1.15, dead * 0.92);
	ROUGHNESS = mix(roughness, roughness - 0.2, thin);
	SPECULAR = 0.25;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.65;
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
}

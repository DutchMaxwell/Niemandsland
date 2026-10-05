// Shared maps only; no geometry, per-base resources or animation. Local metres keep grain
// attached to a moving base. Mipmapped anisotropic sampling limits distant shimmer.
uniform bool flock_enabled = false;
uniform sampler2D flock_height : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D flock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec2 flock_xz;
const float FLOCK_TILING = 36.0; // Local metres; millimetre grain with the shared 512 px maps.
vec3 flock_colour(vec3 ground, vec2 p) {
	float grain = smoothstep(0.25, 0.75, texture(flock_height, p * FLOCK_TILING).r);
	return ground * mix(0.58, 1.42, grain);
}

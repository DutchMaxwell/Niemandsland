shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Anti-tiling forest-floor material. The pad UVs come from world XZ / tile, so a large
// oval shows the same texture many times over and the eye latches onto distinctive
// features (big leaves, stones). This breaks the perceived repetition WITHOUT replacing
// the texture: a low-frequency hash noise (a) varies macro brightness and (b) selects
// between the base tap and a second rotated/rescaled tap per region. The second tap has
// an irrational scale so its period never aligns with the base — no visible grid.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float second_scale = 0.61;                          // irrational-ish: periods don't align
uniform float second_rotation = 0.9;                        // radians, rotates the second tap
uniform float variation_scale = 0.11;                       // macro-noise frequency over the pad
uniform float macro_strength : hint_range(0.0, 0.6) = 0.30; // brightness spread across regions
uniform float roughness_value : hint_range(0.0, 1.0) = 1.0;

// Cheap value noise (hash-based) so no extra texture asset is needed.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// Second tap: rotate + rescale + offset so its repeats never line up with the base.
	float c = cos(second_rotation);
	float s = sin(second_rotation);
	vec2 uv2 = mat2(vec2(c, -s), vec2(s, c)) * UV * second_scale + vec2(0.37, 0.61);

	vec3 tap_a = texture(albedo_tex, UV).rgb;
	vec3 tap_b = texture(albedo_tex, uv2).rgb;

	// Pick base vs. second tap per macro region; smoothstep keeps the seam soft, not blurred.
	float sel = smoothstep(0.42, 0.58, vnoise(UV * variation_scale));
	vec3 col = mix(tap_a, tap_b, sel);

	// Low-frequency brightness variation breaks the "same tile, same shade" grid feel.
	float macro = vnoise(UV * variation_scale * 1.7 + vec2(11.3, 7.9));
	col *= 1.0 - macro_strength * (0.5 - macro);

	ALBEDO = col;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
}

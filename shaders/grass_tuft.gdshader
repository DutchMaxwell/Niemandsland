shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2D blade_texture : source_color, filter_linear_mipmap, repeat_disable;

void fragment() {
	vec4 blade = texture(blade_texture, UV);
	ALBEDO = blade.rgb * COLOR.rgb;
	ALPHA = blade.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	// Both sides of a tiny foliage card receive the meadow's light. A flipped
	// backface normal otherwise turns half of each clump into black spikes.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

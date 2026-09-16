shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley;

uniform sampler2D litter_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 table_half_extent = vec2(1.0);
varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	// These cosmetic patches must never spill beyond the table edge.
	if (any(greaterThan(abs(world_xz), table_half_extent))) {
		discard;
	}
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float irregularity = sin(p.x * 9.0 + sin(p.y * 7.0)) * sin(p.y * 8.0) * 0.10;
	float feather = 1.0 - smoothstep(0.22, 0.97, radius + irregularity);
	vec3 litter = texture(litter_tex, world_xz / 0.06).rgb;
	ALBEDO = litter * 0.88;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = feather * 0.90;
}

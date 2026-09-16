// Shared by the board and miniature bases; material detail never moves geometry.
uniform bool use_grassland_surface = false;
uniform sampler2D grassland_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grassland_coverage : filter_linear_mipmap, repeat_disable;
uniform float coverage_extent_m = 4.0;

vec2 mirrored_tile(vec2 uv) {
	return 1.0 - abs(fract(uv * 0.5) * 2.0 - 1.0);
}

vec4 grassland_surface(vec2 map_uv, vec3 map_color) {
	// Fixed one-foot material scale, independent of board size. Mirror wrapping
	// keeps edge colours continuous; the rotated second tap breaks the tile grid.
	vec2 uv = map_uv * vec2(6.0, 4.0);
	vec3 a = texture(grassland_albedo, mirrored_tile(uv)).rgb;
	vec2 rotated = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv * 1.31 + vec2(0.37, 0.61);
	vec3 b = texture(grassland_albedo, mirrored_tile(rotated)).rgb;
	float patch = texture(detail_height, map_uv * vec2(0.3, 0.2) + vec2(0.17, 0.43)).r;
	vec3 surface = mix(a, b, smoothstep(0.32, 0.68, patch));
	// Preserve the battlemap's broad dry/worn regions, without its bright leaf
	// and straw speckles competing with miniature silhouettes.
	vec3 broad = textureLod(albedo_tex, map_uv, 5.0).rgb;
	float dry = smoothstep(0.08, 0.30, dot(broad, vec3(0.2126, 0.7152, 0.0722)));
	vec2 world_xz = (map_uv - 0.5) * vec2(1.8288, 1.2192);
	float coverage = texture(grassland_coverage, world_xz / coverage_extent_m + 0.5).r;
	float meadow = smoothstep(0.27, 0.72, coverage);
	vec3 earth = surface * vec3(1.06, 0.96, 0.84) * mix(1.0, 1.35, dry);
	vec3 grass = surface * vec3(0.74, 0.98, 0.66) * 1.4;
	vec3 color = mix(mix(earth, grass, meadow), map_color, 0.04);
	return vec4(color, mix(0.84, 0.97, meadow));
}

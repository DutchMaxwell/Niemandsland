shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec2 height_bounds = vec2(0.0, 1.0);
varying float crown_height;

void vertex() {
	crown_height = clamp((VERTEX.y - height_bounds.x) / max(height_bounds.y, 0.0001), 0.0, 1.0);
}

void fragment() {
	vec3 source = texture(albedo_tex, UV).rgb * base_color.rgb;
	// The baked atlas contains bark and leaves. Grade green foliage while retaining
	// the original trunk colour; no mesh or silhouette changes are needed.
	float leaves = smoothstep(0.0, 0.06, source.g - source.r * 0.65)
		* smoothstep(0.01, 0.08, source.g - source.b);
	float luminance = dot(source, vec3(0.2126, 0.7152, 0.0722));
	vec3 foliage = mix(source, luminance * vec3(0.78, 1.09, 0.76), 0.45);
	foliage *= mix(0.80, 1.08, smoothstep(0.2, 0.95, crown_height));
	ALBEDO = mix(source, foliage, leaves);
	ROUGHNESS = 0.96;
	SPECULAR = 0.18;
	METALLIC = 0.0;
	BACKLIGHT = ALBEDO * leaves * 0.18;
}

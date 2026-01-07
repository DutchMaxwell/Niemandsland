shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_disabled, unshaded;

// Cloud appearance
uniform vec4 cloud_color : source_color = vec4(0.85, 0.88, 0.95, 0.3);
uniform float cloud_density : hint_range(0.0, 1.0) = 0.4;
uniform float edge_softness : hint_range(0.1, 2.0) = 0.8;

// Animation
uniform float scroll_speed : hint_range(0.0, 0.5) = 0.02;
uniform vec2 scroll_direction = vec2(1.0, 0.3);

// Noise scales for layered clouds
uniform float noise_scale_1 : hint_range(0.5, 5.0) = 1.5;
uniform float noise_scale_2 : hint_range(0.5, 5.0) = 3.0;
uniform float noise_scale_3 : hint_range(0.5, 10.0) = 6.0;

// Fade based on camera distance (controlled by script)
uniform float visibility : hint_range(0.0, 1.0) = 1.0;

// Simple hash function for noise
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Value noise
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // Smoothstep

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal Brownian Motion for cloud-like noise
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;

	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p * frequency);
		amplitude *= 0.5;
		frequency *= 2.0;
	}

	return value;
}

void fragment() {
	// Scroll UV over time
	vec2 scroll = normalize(scroll_direction) * scroll_speed * TIME;
	vec2 uv = UV;

	// Layer multiple noise octaves for realistic clouds
	float cloud1 = fbm((uv + scroll) * noise_scale_1);
	float cloud2 = fbm((uv + scroll * 1.3) * noise_scale_2 + vec2(100.0, 50.0));
	float cloud3 = fbm((uv + scroll * 0.7) * noise_scale_3 + vec2(-50.0, 100.0));

	// Combine layers
	float cloud = (cloud1 * 0.5 + cloud2 * 0.3 + cloud3 * 0.2);

	// Apply density threshold with soft edges
	float threshold = 1.0 - cloud_density;
	cloud = smoothstep(threshold - edge_softness * 0.5, threshold + edge_softness * 0.5, cloud);

	// Edge fade (soft edges at quad boundaries)
	vec2 edge_uv = abs(uv - 0.5) * 2.0;
	float edge_fade = 1.0 - smoothstep(0.6, 1.0, max(edge_uv.x, edge_uv.y));

	// Final alpha
	float alpha = cloud * cloud_color.a * visibility * edge_fade;

	ALBEDO = cloud_color.rgb;
	ALPHA = alpha;
}

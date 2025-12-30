shader_type spatial;
render_mode unshaded, cull_disabled;

// Tron-style animated grid shader
uniform vec3 grid_color : source_color = vec3(0.0, 1.0, 1.0);  // Cyan
uniform vec3 accent_color : source_color = vec3(1.0, 0.0, 1.0);  // Magenta
uniform float grid_spacing = 0.5;
uniform float line_width = 0.02;
uniform float glow_intensity = 2.0;
uniform float animation_progress : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_speed = 2.0;
uniform float fade_distance = 20.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Calculate grid lines
	vec2 grid_uv = world_pos.xz / grid_spacing;
	vec2 grid_frac = abs(fract(grid_uv - 0.5) - 0.5);

	float line_x = smoothstep(line_width, line_width * 0.5, grid_frac.x);
	float line_z = smoothstep(line_width, line_width * 0.5, grid_frac.y);
	float grid_line = max(line_x, line_z);

	// Distance-based fade
	float dist = length(world_pos.xz);
	float distance_fade = 1.0 - smoothstep(fade_distance * 0.5, fade_distance, dist);

	// Animation: lines spread outward from center
	float animation_radius = animation_progress * fade_distance * 1.5;
	float animation_mask = smoothstep(animation_radius - 2.0, animation_radius, dist);
	animation_mask = 1.0 - animation_mask;

	// Pulse effect on grid lines
	float pulse = sin(TIME * pulse_speed - dist * 0.5) * 0.5 + 0.5;

	// Mix colors based on position
	float color_mix = sin(world_pos.x * 0.3 + world_pos.z * 0.3 + TIME) * 0.5 + 0.5;
	vec3 final_color = mix(grid_color, accent_color, color_mix * 0.3);

	// Apply glow and animation
	float intensity = grid_line * distance_fade * animation_mask * glow_intensity;
	intensity *= 0.8 + pulse * 0.4;

	ALBEDO = final_color * intensity;
	ALPHA = intensity * 0.9;
	EMISSION = final_color * intensity * 1.5;
}

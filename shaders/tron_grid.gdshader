shader_type spatial;
render_mode unshaded, cull_disabled;

// Tron-style grid with laser-drawing cursor effect
// Lines are drawn progressively by a moving laser point

uniform vec3 grid_color : source_color = vec3(0.0, 1.0, 1.0);  // Cyan
uniform vec3 cursor_color : source_color = vec3(1.0, 1.0, 1.0);  // White hot
uniform float grid_spacing = 0.5;
uniform float line_width = 0.008;  // Thinner, sharper lines
uniform float line_sharpness = 50.0;  // Higher = sharper edges
uniform float glow_intensity = 1.5;
uniform float cursor_progress : hint_range(0.0, 1.0) = 0.0;  // 0-1 animation progress
uniform float cursor_size = 0.15;
uniform float grid_size = 25.0;  // Total grid extent
uniform float cursor_pulse_speed = 15.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line_sdf(float coord, float spacing) {
	float grid_coord = mod(coord + spacing * 0.5, spacing) - spacing * 0.5;
	return abs(grid_coord);
}

void fragment() {
	// Calculate grid line distances
	float dist_x = line_sdf(world_pos.x, grid_spacing);
	float dist_z = line_sdf(world_pos.z, grid_spacing);

	// Sharp line rendering using smoothstep with high sharpness
	float line_x = 1.0 - smoothstep(0.0, line_width, dist_x);
	float line_z = 1.0 - smoothstep(0.0, line_width, dist_z);

	// Combine lines (max for intersections)
	float grid_line = max(line_x, line_z);

	// Calculate distance from origin for radial reveal
	float dist_from_center = length(world_pos.xz);

	// Cursor position moves outward as progress increases
	float cursor_radius = cursor_progress * grid_size;

	// Lines are only visible behind the cursor
	float reveal_mask = smoothstep(cursor_radius + 0.1, cursor_radius - 0.5, dist_from_center);

	// Cursor ring effect - bright ring at the drawing edge
	float cursor_ring = smoothstep(cursor_size, 0.0, abs(dist_from_center - cursor_radius));

	// Pulse the cursor
	float cursor_pulse = sin(TIME * cursor_pulse_speed) * 0.3 + 0.7;
	cursor_ring *= cursor_pulse;

	// Multiple cursor points along the ring for "drawing" effect
	float angle = atan(world_pos.z, world_pos.x);
	float num_cursors = 8.0;
	float cursor_angle = mod(angle + TIME * 2.0, TAU / num_cursors);
	float cursor_point = smoothstep(0.3, 0.0, cursor_angle) + smoothstep(TAU / num_cursors - 0.3, TAU / num_cursors, cursor_angle);

	// Combine cursor ring with cursor points for laser effect
	float laser_cursor = cursor_ring * (0.5 + cursor_point * 0.5);

	// Final line intensity
	float line_intensity = grid_line * reveal_mask * glow_intensity;

	// Add extra brightness at intersection points
	float intersection = line_x * line_z;
	line_intensity += intersection * reveal_mask * 0.5;

	// Combine line color with cursor
	vec3 final_color = grid_color * line_intensity;
	final_color += cursor_color * laser_cursor * 3.0;

	// Slight distance fade for depth
	float distance_fade = 1.0 - smoothstep(grid_size * 0.7, grid_size, dist_from_center);

	ALBEDO = final_color * distance_fade;
	ALPHA = max(line_intensity, laser_cursor * 2.0) * distance_fade;
	EMISSION = final_color * distance_fade * 2.0;
}

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

// Tron-style wireframe with laser-drawing effect for table edges
// Each edge is drawn by a traveling laser cursor

uniform vec3 wire_color : source_color = vec3(0.0, 1.0, 1.0);  // Cyan
uniform vec3 cursor_color : source_color = vec3(1.0, 1.0, 1.0);  // White hot
uniform float wire_width = 0.015;
uniform float glow_intensity = 2.0;
uniform float draw_progress : hint_range(0.0, 1.0) = 0.0;  // 0-1 animation progress
uniform float cursor_size = 0.05;
uniform float cursor_pulse_speed = 20.0;
uniform vec3 box_size = vec3(1.83, 0.05, 1.22);  // Table dimensions in meters

varying vec3 local_pos;
varying vec3 world_pos;

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Check if point is near an edge of the box
float edge_distance(vec3 pos, vec3 size) {
	vec3 half_size = size * 0.5;

	// Distance to each face
	vec3 d = abs(pos) - half_size;

	// Count how many axes are near the edge
	float edge_x = 1.0 - smoothstep(0.0, wire_width, abs(abs(pos.x) - half_size.x));
	float edge_y = 1.0 - smoothstep(0.0, wire_width, abs(abs(pos.y) - half_size.y));
	float edge_z = 1.0 - smoothstep(0.0, wire_width, abs(abs(pos.z) - half_size.z));

	// Edges are where two faces meet
	float edge_xy = edge_x * edge_y;
	float edge_xz = edge_x * edge_z;
	float edge_yz = edge_y * edge_z;

	return max(max(edge_xy, edge_xz), edge_yz);
}

void fragment() {
	// Calculate edge wireframe
	float wire = edge_distance(local_pos, box_size);

	// Calculate "drawing progress" based on position
	// Start from bottom-left corner and draw around the perimeter
	vec3 half_size = box_size * 0.5;

	// Normalize position to 0-1 range for progress calculation
	float perimeter_progress = 0.0;

	// Calculate progress around the box perimeter (bottom edges first, then top)
	// Bottom layer - start from -X, -Z corner
	float bottom_perimeter = (local_pos.x + half_size.x) / box_size.x;  // 0 to 1 for X
	bottom_perimeter += (local_pos.z + half_size.z) / box_size.z;  // Add Z progress

	// Top layer comes after bottom
	float is_top = step(half_size.y * 0.5, local_pos.y);
	float is_bottom = 1.0 - is_top;

	perimeter_progress = bottom_perimeter * 0.25 * is_bottom;
	perimeter_progress += (0.5 + bottom_perimeter * 0.25) * is_top;

	// Vertical edges
	float is_vertical = (1.0 - abs(local_pos.y) / half_size.y);

	// Draw progress reveals edges progressively
	float total_progress = draw_progress * 4.0;  // Speed up the drawing
	float reveal = smoothstep(perimeter_progress - 0.02, perimeter_progress + 0.02, total_progress);

	// Cursor at the drawing front
	float cursor_dist = abs(total_progress - perimeter_progress);
	float cursor = smoothstep(cursor_size, 0.0, cursor_dist);

	// Pulse the cursor
	float pulse = sin(TIME * cursor_pulse_speed) * 0.4 + 0.6;
	cursor *= pulse;

	// Final wire intensity
	float intensity = wire * reveal * glow_intensity;

	// Combine colors
	vec3 final_color = wire_color * intensity;
	final_color += cursor_color * cursor * wire * 5.0;  // Bright cursor on edges only

	ALBEDO = final_color;
	ALPHA = clamp(intensity + cursor * wire * 2.0, 0.0, 1.0);
	EMISSION = final_color * 2.5;
}

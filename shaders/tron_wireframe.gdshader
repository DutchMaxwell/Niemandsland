shader_type spatial;
render_mode unshaded, cull_disabled;

// Tron-style wireframe effect for objects building up
uniform vec3 wire_color : source_color = vec3(0.0, 1.0, 1.0);  // Cyan
uniform float wire_width = 0.02;
uniform float glow_intensity = 2.5;
uniform float build_progress : hint_range(0.0, 1.0) = 0.0;
uniform float scan_height = 0.0;  // Current scan line height
uniform float scan_width = 0.3;   // Width of the scan band
uniform float pulse_speed = 3.0;

varying vec3 local_pos;
varying vec3 world_pos;

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Edge detection using screen-space derivatives
	vec3 dx = dFdx(local_pos);
	vec3 dy = dFdy(local_pos);
	float edge = length(cross(dx, dy));

	// Wireframe effect based on barycentric-like coordinates
	float wire = 0.0;

	// Create wireframe from UV coordinates or position
	vec3 pos_frac = fract(local_pos * 10.0);
	float wx = smoothstep(wire_width, 0.0, pos_frac.x) + smoothstep(1.0 - wire_width, 1.0, pos_frac.x);
	float wy = smoothstep(wire_width, 0.0, pos_frac.y) + smoothstep(1.0 - wire_width, 1.0, pos_frac.y);
	float wz = smoothstep(wire_width, 0.0, pos_frac.z) + smoothstep(1.0 - wire_width, 1.0, pos_frac.z);
	wire = max(max(wx, wy), wz);

	// Scan line effect - reveals geometry from bottom to top
	float normalized_height = (world_pos.y + 1.0) / 2.0;  // Normalize height
	float scan_mask = smoothstep(scan_height - scan_width, scan_height, normalized_height);
	scan_mask *= smoothstep(scan_height + scan_width * 2.0, scan_height + scan_width, normalized_height);

	// Build progress - geometry appears as progress increases
	float build_mask = step(normalized_height, build_progress);

	// Pulse effect
	float pulse = sin(TIME * pulse_speed + world_pos.y * 5.0) * 0.3 + 0.7;

	// Combine effects
	float intensity = wire * glow_intensity * pulse;

	// Bright scan line
	float scan_glow = scan_mask * 3.0;
	intensity = max(intensity, scan_glow);

	// Apply build mask
	intensity *= build_mask;

	ALBEDO = wire_color;
	ALPHA = clamp(intensity, 0.0, 1.0);
	EMISSION = wire_color * intensity * 2.0;
}

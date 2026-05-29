shader_type spatial;
// Holographic build-up grid for the cinematic intro. A flat plane (lying in its local
// XZ) on which a cyan energy grid "prints" outward from the centre as `build_progress`
// rises 0 -> 1, led by a bright sweep ring at `sweep_pos`. Self-lit, additive, no
// shadows — driven entirely from GDScript via uniforms, so nothing rebuilds per frame.
render_mode blend_add, cull_disabled, depth_draw_never, unshaded, shadows_disabled, specular_disabled, ambient_light_disabled, fog_disabled;

// Reveal / sweep state (set by tron_intro.gd)
uniform float build_progress : hint_range(0.0, 1.0) = 0.0;  // radial reveal 0..1
uniform float sweep_pos : hint_range(0.0, 1.5) = 0.0;       // sweep ring radius, normalised
uniform float plane_radius = 1.0;                            // half-diagonal of the plane (m)

// Grid look
uniform float grid_spacing = 0.1524;        // metres between lines (~6")
uniform float line_width : hint_range(0.0, 0.02) = 0.004;  // half line thickness (m)
uniform vec3 line_color : source_color = vec3(0.0, 0.85, 1.0);
uniform vec3 core_color : source_color = vec3(0.7, 0.98, 1.0);
uniform float glow_strength : hint_range(0.0, 6.0) = 2.2;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;   // master fade (cross-fade to real table)

// Animation
uniform float flicker_speed = 9.0;
uniform float scanline_density = 60.0;

varying vec2 v_xz;     // local plane coords (metres, centred)
varying float v_radius;

float grid_mask(vec2 p) {
	// Anti-aliased lines: distance to nearest grid line on each axis, scaled by the
	// pixel-space derivative so the line stays ~constant thickness on screen.
	vec2 to_line = abs(fract(p / grid_spacing + 0.5) - 0.5) * grid_spacing;
	vec2 aa = fwidth(p) + 1e-6;
	vec2 line = 1.0 - smoothstep(vec2(0.0), vec2(line_width) + aa, to_line);
	return clamp(max(line.x, line.y), 0.0, 1.0);
}

void vertex() {
	v_xz = VERTEX.xz;
	v_radius = length(VERTEX.xz);
}

void fragment() {
	float norm_r = v_radius / max(plane_radius, 1e-4);

	// Radial reveal with a soft leading edge.
	float reveal = smoothstep(build_progress + 0.06, build_progress - 0.02, norm_r);

	// Bright sweep ring that leads the reveal as it expands.
	float ring = exp(-pow((norm_r - sweep_pos) / 0.05, 2.0));

	float grid = grid_mask(v_xz);

	// Subtle flicker + holographic scanlines for life.
	float flicker = 0.85 + 0.15 * sin(TIME * flicker_speed + v_radius * 12.0);
	float scan = 0.8 + 0.2 * sin(v_xz.y * scanline_density + TIME * 2.0);

	float grid_intensity = grid * reveal * flicker * scan;
	float total = grid_intensity + ring * 1.5;

	vec3 col = mix(line_color, core_color, clamp(ring + grid_intensity * 0.4, 0.0, 1.0));

	EMISSION = col * total * glow_strength;
	ALBEDO = col;
	ALPHA = clamp(total, 0.0, 1.0) * alpha;
}

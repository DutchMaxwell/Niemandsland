shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, skip_vertex_transform;

uniform vec4 tint : source_color = vec4(0.94, 0.36, 0.27, 1.0);
uniform int shape = 0;
uniform int count = 1;
uniform float fade = 1.0;
uniform float ring_radius = 0.020;
uniform float ring_y = 0.002;

void vertex() {
	vec2 q = UV * 2.0 - 1.0;
	vec3 world_pos = vec3(MODEL_MATRIX[3].x + q.x * ring_radius, ring_y, MODEL_MATRIX[3].z + q.y * ring_radius);
	VERTEX = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = mod(atan(p.y, p.x) + TAU, TAU);
	float rim_r = 0.78;
	float half_w = 0.085;
	float seg_mask = 0.0;
	float out_mask = 0.0;

	if (shape == 0) {
		// WOUND: segmented base-rim ticks (front-weighted for 1-4 ticks, full ring for 5+)
		int segs = clamp(count, 1, 10);
		float span = segs <= 4 ? PI * 1.15 : TAU;
		float start_a = segs <= 4 ? PI * 0.425 : 0.0;
		float rel = mod(ang - start_a + TAU, TAU);
		float in_span = step(rel, span);
		float step_a = span / float(segs);
		float local_a = mod(rel, step_a) / step_a;
		float gap = segs > 1 ? 0.14 : 0.04;
		float arc = smoothstep(gap, gap + 0.04, local_a) * (1.0 - smoothstep(1.0 - gap - 0.04, 1.0 - gap, local_a)) * in_span;
		float arc_out = smoothstep(max(0.0, gap - 0.05), gap + 0.01, local_a)
			* (1.0 - smoothstep(1.0 - gap - 0.01, min(1.0, 1.0 - gap + 0.05), local_a)) * in_span;
		float band = abs(r - rim_r);
		seg_mask = (1.0 - smoothstep(half_w - 0.025, half_w + 0.02, band)) * arc;
		out_mask = (1.0 - smoothstep(half_w + 0.02, half_w + 0.075, band)) * arc_out;
	} else if (shape == 1) {
		// KILL: bold 3-notched casualty base ring with outer organic splat lobes (zero torso occlusion)
		float lobe = 0.045 * sin(3.0 * ang + 1.1) + 0.025 * cos(7.0 * ang);
		float band = abs(r - (rim_r + lobe));
		float slot = mod(ang, TAU / 3.0) / (TAU / 3.0);
		float arc = smoothstep(0.07, 0.11, slot) * (1.0 - smoothstep(0.89, 0.93, slot));
		float arc_out = smoothstep(0.03, 0.08, slot) * (1.0 - smoothstep(0.92, 0.97, slot));
		half_w = 0.105;
		seg_mask = (1.0 - smoothstep(half_w - 0.03, half_w + 0.02, band)) * arc;
		out_mask = (1.0 - smoothstep(half_w + 0.02, half_w + 0.085, band)) * arc_out;
	} else if (shape == 2) {
		// HIT: crisp ivory dotted rim ring
		int segs = clamp(count, 1, 10);
		float step_a = TAU / float(segs);
		float local_a = mod(ang, step_a) / step_a;
		float dot_arc = smoothstep(0.24, 0.30, local_a) * (1.0 - smoothstep(0.70, 0.76, local_a));
		float dot_out = smoothstep(0.18, 0.26, local_a) * (1.0 - smoothstep(0.74, 0.82, local_a));
		float band = abs(r - rim_r);
		seg_mask = (1.0 - smoothstep(0.055, 0.085, band)) * dot_arc;
		out_mask = (1.0 - smoothstep(0.085, 0.14, band)) * dot_out;
	} else {
		// SAVE: sweeping cyan ward shield crescent along the defending rim
		float rel = mod(ang - PI * 0.60 + TAU, TAU);
		float span = PI * 0.80;
		float u = clamp(rel / span, 0.0, 1.0);
		float in_arc = step(rel, span) * smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.92, 1.0, u));
		float taper = 0.065 + 0.055 * sin(u * PI);
		float band = abs(r - (rim_r + 0.03));
		seg_mask = (1.0 - smoothstep(taper - 0.02, taper + 0.02, band)) * in_arc;
		out_mask = (1.0 - smoothstep(taper + 0.02, taper + 0.08, band)) * step(rel, span + 0.08);
	}

	float alpha = max(seg_mask, out_mask * 0.78) * clamp(fade, 0.0, 1.0);
	if (alpha <= 0.005) {
		discard;
	}
	vec3 dark_edge = vec3(0.03, 0.05, 0.06);
	ALBEDO = mix(dark_edge, tint.rgb * 1.35, seg_mask);
	ALPHA = alpha;
}

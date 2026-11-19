shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, skip_vertex_transform;

uniform vec4 tint : source_color = vec4(1.0, 0.76, 0.14, 1.0);
uniform int shape = 0;
uniform int count = 1;
uniform float fade = 1.0;
uniform float ring_radius = 0.026;
uniform float ring_y = 0.004;

void vertex() {
	vec2 q = UV * 2.0 - 1.0;
	vec3 world_pos = vec3(MODEL_MATRIX[3].x + q.x * ring_radius, ring_y, MODEL_MATRIX[3].z + q.y * ring_radius);
	VERTEX = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = mod(atan(p.y, p.x) + TAU, TAU);
	float rim_r = 0.76;
	float half_w = 0.115;
	float seg_mask = 0.0;
	float out_mask = 0.0;
	float inner_hi = 0.0;

	if (shape == 0) {
		// WOUND: bold segmented amber-gold base-rim ticks (front-weighted for 1-4 ticks, full ring for 5+)
		int segs = clamp(count, 1, 10);
		float span = segs <= 4 ? PI * 1.25 : TAU;
		float start_a = segs <= 4 ? PI * 0.375 : 0.0;
		float rel = mod(ang - start_a + TAU, TAU);
		float in_span = step(rel, span);
		float step_a = span / float(segs);
		float local_a = mod(rel, step_a) / step_a;
		float gap = segs > 1 ? 0.13 : 0.04;
		float arc = smoothstep(gap, gap + 0.04, local_a) * (1.0 - smoothstep(1.0 - gap - 0.04, 1.0 - gap, local_a)) * in_span;
		float arc_out = smoothstep(max(0.0, gap - 0.06), gap + 0.01, local_a)
			* (1.0 - smoothstep(1.0 - gap - 0.01, min(1.0, 1.0 - gap + 0.06), local_a)) * in_span;
		float band = abs(r - rim_r);
		seg_mask = (1.0 - smoothstep(half_w - 0.025, half_w + 0.02, band)) * arc;
		out_mask = (1.0 - smoothstep(half_w + 0.02, half_w + 0.09, band)) * arc_out;
	} else if (shape == 1) {
		// KILL: bold 3-notched casualty base ring with outer splat lobes + high-contrast bone inner rim
		float lobe = 0.055 * sin(3.0 * ang + 1.1) + 0.03 * cos(7.0 * ang);
		float target_r = rim_r + lobe;
		float band = abs(r - target_r);
		float slot = mod(ang, TAU / 3.0) / (TAU / 3.0);
		float arc = smoothstep(0.06, 0.10, slot) * (1.0 - smoothstep(0.90, 0.94, slot));
		float arc_out = smoothstep(0.02, 0.07, slot) * (1.0 - smoothstep(0.93, 0.98, slot));
		half_w = 0.13;
		seg_mask = (1.0 - smoothstep(half_w - 0.03, half_w + 0.02, band)) * arc;
		out_mask = (1.0 - smoothstep(half_w + 0.02, half_w + 0.10, band)) * arc_out;
		float in_edge = abs(r - (target_r - half_w + 0.022));
		inner_hi = (1.0 - smoothstep(0.012, 0.038, in_edge)) * arc;
	} else if (shape == 2) {
		// HIT: crisp ivory dotted rim ring
		int segs = clamp(count, 1, 10);
		float step_a = TAU / float(segs);
		float local_a = mod(ang, step_a) / step_a;
		float dot_arc = smoothstep(0.22, 0.28, local_a) * (1.0 - smoothstep(0.72, 0.78, local_a));
		float dot_out = smoothstep(0.16, 0.24, local_a) * (1.0 - smoothstep(0.76, 0.84, local_a));
		float band = abs(r - rim_r);
		seg_mask = (1.0 - smoothstep(0.065, 0.095, band)) * dot_arc;
		out_mask = (1.0 - smoothstep(0.095, 0.16, band)) * dot_out;
	} else {
		// SAVE: sweeping cyan ward shield crescent along the defending rim
		float rel = mod(ang - PI * 0.55 + TAU, TAU);
		float span = PI * 0.90;
		float u = clamp(rel / span, 0.0, 1.0);
		float in_arc = step(rel, span) * smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.92, 1.0, u));
		float taper = 0.085 + 0.065 * sin(u * PI);
		float band = abs(r - (rim_r + 0.02));
		seg_mask = (1.0 - smoothstep(taper - 0.02, taper + 0.02, band)) * in_arc;
		out_mask = (1.0 - smoothstep(taper + 0.02, taper + 0.095, band)) * step(rel, span + 0.08);
	}

	float alpha = max(max(seg_mask, inner_hi), out_mask * 0.92) * clamp(fade, 0.0, 1.0);
	if (alpha <= 0.005) {
		discard;
	}
	vec3 dark_edge = vec3(0.02, 0.03, 0.04);
	float gain = shape == 1 ? 2.15 : 1.65;
	vec3 col = mix(dark_edge, tint.rgb * gain, seg_mask);
	col = mix(col, vec3(1.55, 1.48, 1.32), inner_hi * 0.88);
	ALBEDO = col;
	ALPHA = alpha;
}

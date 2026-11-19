shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, skip_vertex_transform;

varying vec4 v_color;
varying float v_mode;
varying float v_alpha;
varying float v_len_m;

void vertex() {
	float head_t = INSTANCE_CUSTOM.x;
	float tail_t = INSTANCE_CUSTOM.y;
	float half_w = INSTANCE_CUSTOM.z;
	float signed_a = INSTANCE_CUSTOM.w;
	v_mode = signed_a < 0.0 ? 1.0 : 0.0;
	v_alpha = abs(signed_a);
	v_color = COLOR;
	if (half_w <= 0.00001 || v_alpha <= 0.001 || head_t <= tail_t + 0.0001) {
		VERTEX = vec3(0.0);
		v_len_m = 0.0;
	} else {
		vec3 mid = MODEL_MATRIX[3].xyz;
		vec3 seg = MODEL_MATRIX[1].xyz;
		v_len_m = max(length(seg), 0.001);
		vec3 p0 = mid - seg * 0.5;
		vec3 p1 = mid + seg * 0.5;
		float along = mix(tail_t, head_t, UV.y);
		vec3 wp = mix(p0, p1, along);
		vec3 dir = seg / v_len_m;
		vec3 to_cam = CAMERA_POSITION_WORLD - wp;
		vec3 side = cross(dir, to_cam);
		float sl = length(side);
		if (sl > 0.0001) {
			side /= sl;
		} else {
			vec3 ref_up = abs(dir.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
			side = normalize(cross(dir, ref_up));
		}
		float taper = v_mode > 0.5 ? 1.0 : mix(0.45, 1.0, UV.y);
		wp += side * (UV.x * 2.0 - 1.0) * half_w * taper;
		VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	}
}

void fragment() {
	if (v_alpha <= 0.001 || v_len_m <= 0.0) {
		discard;
	}
	float across = abs(UV.x * 2.0 - 1.0);
	vec3 dark_back = vec3(0.04, 0.03, 0.02);
	if (v_mode > 0.5) {
		// Reduced-motion static sight-line thread: steady dashed line with dark contrast edge
		float dash = step(0.32, fract(UV.y * max(4.0, v_len_m * 45.0)));
		float core = (1.0 - smoothstep(0.0, 0.45, across)) * dash;
		float edge = (1.0 - smoothstep(0.45, 0.98, across)) * dash * 0.48;
		float a = max(core * 0.82, edge) * v_alpha;
		if (a <= 0.005) {
			discard;
		}
		ALBEDO = mix(dark_back, v_color.rgb * 1.15, core);
		ALPHA = a;
	} else {
		// Animated HDR tapered tracer: dark sand-contrast edge + family glow + white-hot core
		float along_fade = smoothstep(0.0, 0.35, UV.y);
		float back = (1.0 - smoothstep(0.50, 1.0, across)) * 0.44 * along_fade;
		float glow = (1.0 - smoothstep(0.16, 0.86, across)) * along_fade;
		float core = (1.0 - smoothstep(0.0, 0.28, across)) * smoothstep(0.15, 0.95, UV.y);
		float a = clamp(max(max(back, glow * 0.82), core), 0.0, 1.0) * v_alpha;
		if (a <= 0.005) {
			discard;
		}
		float boost = max(v_color.a, 1.0);
		vec3 hdr = mix(dark_back, v_color.rgb * boost, smoothstep(0.08, 0.55, glow));
		hdr = mix(hdr, vec3(2.8, 2.75, 2.55), core);
		ALBEDO = hdr;
		ALPHA = a;
	}
}

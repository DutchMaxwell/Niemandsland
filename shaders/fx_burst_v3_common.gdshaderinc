uniform sampler2D atlas_tex : filter_linear_mipmap, repeat_disable;
uniform float progress = 0.0;
uniform vec4 c0 : source_color = vec4(1.0);
uniform vec4 c1 : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float s0 = 0.006;
uniform float s1 = 0.024;
uniform float life = 0.9;
uniform float gravity = 0.0;
uniform vec3 wind = vec3(0.0);
uniform float bounce = 0.0;
uniform float ground_y = 0.0;
uniform float stretch = 0.0;
uniform int channel_mode = 0;
uniform float contrast_rim = 0.0;
uniform float alpha_cap = 1.0;
uniform float static_mode = 0.0;
uniform float emit_gap = 0.0;   // streamed burst: seconds between two particles being born (0 = all born at once)
uniform float span = 1.0;       // streamed burst: its duration / a particle's life (progress runs over `life * span` seconds)

varying float t;
varying float v_seed;
varying float v_on;

void vertex() {
	float jit = fract(INSTANCE_CUSTOM.w);   // the integer part is the particle's birth step in a streamed burst
	float clock = progress * span - floor(INSTANCE_CUSTOM.w) * emit_gap / max(life, 0.001);
	float on = clock >= 0.0 ? 1.0 : 0.0;   // not born yet: the quad collapses to a point
	v_on = on;
	t = clamp(clock / mix(0.55, 1.0, jit), 0.0, 1.0);
	float tt = static_mode > 0.5 ? 0.0 : (t * life);
	vec3 p0 = MODEL_MATRIX[3].xyz;
	vec3 v0 = INSTANCE_CUSTOM.xyz;
	vec3 p = p0 + v0 * tt * (1.0 - 0.4 * t) + wind * tt - vec3(0.0, 0.5 * gravity * tt * tt, 0.0);
	vec3 vel = v0 * (1.0 - 0.8 * t) + wind - vec3(0.0, gravity * tt, 0.0);

	if (bounce > 0.001 && gravity > 0.01 && static_mode < 0.5) {
		float h0 = max(0.0, p0.y - ground_y);
		float disc = max(0.0, v0.y * v0.y + 2.0 * gravity * h0);
		float t_hit = (v0.y + sqrt(disc)) / gravity;
		if (tt > t_hit) {
			float dt = tt - t_hit;
			float vy_hit = max(0.04, sqrt(disc));
			float v_reb = vy_hit * bounce;
			float period = max(0.002, 2.0 * v_reb / gravity);
			float k_hop = floor(dt / period);
			float phase = mod(dt, period);
			float damp = pow(bounce, k_hop);
			float y_reb = abs(v_reb * phase - 0.5 * gravity * phase * phase) * damp;
			p.y = ground_y + y_reb;
			float t_hit_u = clamp(t_hit / max(life, 0.001), 0.0, 1.0);
			vec2 h_at_hit = p0.xz + v0.xz * t_hit * (1.0 - 0.4 * t_hit_u);
			p.xz = h_at_hit + (p.xz - h_at_hit) * 0.70;
			vel.y = (v_reb - gravity * phase) * damp;
			vel.xz *= 0.70;
		}
		p.y = max(ground_y, p.y);
	}

	float sz = mix(s0, s1, static_mode > 0.5 ? 0.35 : t);
	vec2 quad = VERTEX.xy;
	vec2 offset_v;
	if (stretch > 0.001 && static_mode < 0.5) {
		vec2 vv = (VIEW_MATRIX * vec4(vel, 0.0)).xy;
		float vlen = length(vv);
		if (vlen > 0.002) {
			vec2 dir2 = vv / vlen;
			vec2 perp2 = vec2(-dir2.y, dir2.x);
			float len_scale = sz * (1.0 + clamp(vlen * stretch, 0.0, 5.5));
			float wid_scale = sz * 0.65;
			offset_v = perp2 * (quad.x * wid_scale) + dir2 * (quad.y * len_scale);
		} else {
			offset_v = quad * sz;
		}
	} else {
		float spin = jit * TAU + (channel_mode == 3 && static_mode < 0.5 ? t * 4.5 : 0.0);
		float cs = cos(spin);
		float sn = sin(spin);
		vec2 rq = vec2(quad.x * cs - quad.y * sn, quad.x * sn + quad.y * cs);
		offset_v = rq * sz;
	}
	VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz + vec3(offset_v * on, 0.0);
	v_seed = jit;
}

void fragment() {
	if (v_on < 0.5) {
		discard;
	}
	vec4 atlas = texture(atlas_tex, UV);
	vec4 c = mix(c0, c1, static_mode > 0.5 ? t * 0.6 : t);
	float mask = 0.0;
	if (channel_mode == 0) {
		// Soft puff / flash / mote (R channel; negative stretch enables star-flare cross)
		mask = atlas.r;
		if (stretch < -0.5) {
			vec2 p = UV * 2.0 - 1.0;
			float core = exp(-dot(p, p) * 20.0);
			float star_h = exp(-abs(p.y) * 11.0) * max(0.0, 1.0 - abs(p.x));
			float star_v = exp(-abs(p.x) * 11.0) * max(0.0, 1.0 - abs(p.y));
			vec2 d = vec2(p.x + p.y, p.x - p.y) * 0.70710678;
			float diag = (exp(-abs(d.y) * 13.5) * max(0.0, 1.0 - abs(d.x) * 1.4)
				+ exp(-abs(d.x) * 13.5) * max(0.0, 1.0 - abs(d.y) * 1.4)) * 0.6;
			mask = clamp(max(core, (star_h + star_v + diag) * 0.88), 0.0, 1.0);
		}
	} else if (channel_mode == 1) {
		// FBM eroded smoke (G channel eroded by age into organic tendrils)
		float erode_lo = 0.10 + t * 0.52;
		float erode_hi = min(0.98, erode_lo + 0.34);
		mask = smoothstep(erode_lo, erode_hi, atlas.g);
	} else if (channel_mode == 2) {
		// Velocity-stretched spark / ember streak (B channel)
		mask = atlas.b;
	} else {
		// Angular clod / bone / debris silhouette (A channel)
		mask = smoothstep(0.32, 0.56, atlas.a);
	}
	float fade_in = channel_mode == 1 ? smoothstep(0.0, 0.14, t) : 1.0;
	float a = clamp(c.a, 0.0, alpha_cap) * mask * fade_in * step(t, 0.999);
	if (a <= 0.004) {
		discard;
	}
	vec3 rgb = c.rgb;
	if (contrast_rim > 0.001) {
		float inner = smoothstep(0.12, 0.62, mask);
		rgb = mix(rgb * (1.0 - 0.58 * contrast_rim), rgb, inner);
	}
	ALBEDO = rgb;
	ALPHA = a;
}

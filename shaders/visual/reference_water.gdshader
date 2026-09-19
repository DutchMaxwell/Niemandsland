shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform float ripple_strength = 0.10;
varying vec3 world_pos;
float w_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(p));
	uint h = (q.x * 16777619u) ^ (q.y * 1103515245u);
	h = ((h >> 16u) ^ h) * 16777619u;
	h = (h >> 13u) ^ h;
	return float(h & 65535u) / 65535.0;
}
float w_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(w_hash(i), w_hash(i + vec2(1,0)), f.x),
		mix(w_hash(i + vec2(0,1)), w_hash(i + vec2(1,1)), f.x), f.y);
}
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
	// A square plane reads as an irregular puddle through a noisy edge mask.
	float d = length(UV - vec2(0.5)) * 2.0;
	float mask = 1.0 - smoothstep(0.55,0.95,d + (w_noise(world_pos.xz*260.0)-0.5)*0.5);
	float nx = w_noise(world_pos.xz*180.0 + vec2(TIME*0.35,0.0)) - 0.5;
	float nz = w_noise(world_pos.xz*180.0 + vec2(0.0,TIME*0.30)) - 0.5;
	vec3 n = normalize(vec3(nx*ripple_strength,1.0,nz*ripple_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(n,0.0)).xyz);
	ALBEDO = mix(vec3(0.030,0.035,0.040), vec3(0.060,0.065,0.070), w_noise(world_pos.xz*90.0));
	ROUGHNESS = 0.02;
	SPECULAR = 0.95;
	METALLIC = 0.0;
	ALPHA = mask * 0.95;
}

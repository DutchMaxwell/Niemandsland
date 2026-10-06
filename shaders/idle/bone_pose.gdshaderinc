uniform sampler2D pose_tex : filter_nearest, repeat_disable;
uniform int frames = 216;
uniform float fps = 24.0;
global uniform float idle_freeze_time;
instance uniform float idle_phase : instance_index(0) = 0.0;

mat4 idle_bone(int b, int f) {
	vec4 r0 = texelFetch(pose_tex, ivec2(b * 3, f), 0);
	vec4 r1 = texelFetch(pose_tex, ivec2(b * 3 + 1, f), 0);
	vec4 r2 = texelFetch(pose_tex, ivec2(b * 3 + 2, f), 0);
	return mat4(vec4(r0.x, r1.x, r2.x, 0.0), vec4(r0.y, r1.y, r2.y, 0.0),
		vec4(r0.z, r1.z, r2.z, 0.0), vec4(r0.w, r1.w, r2.w, 1.0));
}

mat4 idle_skin(vec4 joints, vec4 weights, float clock) {
	float time = idle_freeze_time >= 0.0 ? idle_freeze_time : clock;
	int f = int(mod(time * fps + idle_phase * float(frames), float(frames)));
	ivec4 bi = ivec4(joints * 255.0 + 0.5);
	vec4 bw = weights / max(dot(weights, vec4(1.0)), 0.00001);
	return idle_bone(bi.x, f) * bw.x + idle_bone(bi.y, f) * bw.y
		+ idle_bone(bi.z, f) * bw.z + idle_bone(bi.w, f) * bw.w;
}

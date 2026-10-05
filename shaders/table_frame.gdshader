shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform bool along_z = false;
uniform int frame_strength = 1;
varying vec3 local_pos;
varying float top_face;
void vertex() {
	local_pos = VERTEX;
	top_face = max(NORMAL.y, 0.0);
}
void fragment() {
	// Real metres, so resizing the table never stretches the grain. Both long edges
	// run lengthwise; the existing 15 mm-wide boxes and their collision stay intact.
	float along = along_z ? local_pos.z : local_pos.x;
	float across = along_z ? local_pos.x : local_pos.z;
	float cross_section = mix(local_pos.y, across, top_face);
	float phase = cross_section * 3400.0 + sin(along * 11.0) * 2.0 + sin(along * 47.0) * 0.4;
	float grain = 0.5 + 0.5 * sin(phase) * exp(-fwidth(phase) * fwidth(phase));
	vec3 walnut = mix(vec3(0.055, 0.021, 0.009), vec3(0.24, 0.115, 0.042), grain);
	// Broad grain and whole-frame colors read from the deployment camera.
	float broad_grain = 0.5 + 0.5 * sin(cross_section * 340.0 + sin(along * 9.0));
	vec3 finish = frame_strength == 0 ? walnut : mix(vec3(0.20, 0.085, 0.022), vec3(0.55, 0.31, 0.10), broad_grain);
	if (frame_strength == 2) { finish = mix(vec3(0.62, 0.56, 0.43), vec3(0.84, 0.79, 0.65), grain); }
	float band = frame_strength == 0 ? 0.0062 : (frame_strength == 1 ? 0.0050 : 0.0040);
	float edge = top_face * smoothstep(band, band + 0.0009, abs(across));
	vec3 trim = frame_strength == 0 ? vec3(0.32, 0.23, 0.12) : vec3(0.72, 0.43, 0.12);
	ALBEDO = mix(finish, trim, edge * (frame_strength == 0 ? 0.65 : 1.0));
	ROUGHNESS = mix(0.48, 0.32, edge);
	SPECULAR = 0.35;
}

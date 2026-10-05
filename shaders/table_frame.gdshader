shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform bool along_z = false;
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
	float edge = top_face * smoothstep(0.0062, 0.0071, abs(across));
	ALBEDO = mix(walnut, vec3(0.32, 0.23, 0.12), edge * 0.65);
	ROUGHNESS = mix(0.48, 0.32, edge);
	SPECULAR = 0.35;
}

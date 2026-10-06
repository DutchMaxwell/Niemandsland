shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque;
#include "res://shaders/idle/bone_pose.gdshaderinc"
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float shell = 0.0;
void vertex() {
	mat4 m = idle_skin(CUSTOM0, CUSTOM1, TIME);
	VERTEX = (m * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize(mat3(m) * NORMAL);
	VERTEX += NORMAL * shell;
}
void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
	EMISSION = emission_color;
}

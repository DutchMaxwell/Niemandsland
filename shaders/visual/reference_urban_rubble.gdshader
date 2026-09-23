shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/visual/reference_ground.gdshaderinc"
uniform sampler2D clearance_mask : filter_nearest, repeat_disable;
uniform bool clearance_enabled = false;
uniform bool seat_on_ground = true;
varying vec3 world_vertex;

float urban_height(vec2 p) {
	return ((surface_noise(p*2.6)-0.5)*0.008+(surface_noise(p*7.5)-0.5)*0.003)*0.15;
}
void vertex() {
	world_vertex = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	if (seat_on_ground) {
		world_vertex.y += urban_height(MODEL_MATRIX[3].xz)-MODEL_MATRIX[3].y-0.0001;
		VERTEX = (inverse(MODEL_MATRIX)*vec4(world_vertex,1.0)).xyz;
	}
}
void fragment() {
	vec2 uv = world_vertex.xz/urban_board_size+vec2(0.5);
	if (any(lessThan(uv,vec2(0.005))) || any(greaterThan(uv,vec2(0.995)))) { discard; }
	if (clearance_enabled && texture(clearance_mask,uv).r>0.1) { discard; }
	vec3 grain = texture(earth_tex,world_vertex.xz*65.0).rgb;
	ALBEDO = COLOR.rgb*mix(vec3(0.65),vec3(1.15),grain);
	ROUGHNESS = 0.95;
	SPECULAR = 0.18;
}

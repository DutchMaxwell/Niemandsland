shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
#include "res://shaders/visual/reference_ground.gdshaderinc"
uniform sampler2D clearance_mask : filter_nearest, repeat_disable;
uniform bool clearance_enabled = false;
varying vec3 world_vertex;
void vertex() {
	VERTEX += NORMAL*0.00007;
	world_vertex = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	vec2 board_uv = world_vertex.xz/urban_board_size+vec2(0.5);
	if (any(lessThan(board_uv,vec2(0.005))) || any(greaterThan(board_uv,vec2(0.995)))) { discard; }
	if (clearance_enabled && texture(clearance_mask,board_uv).r>0.1) { discard; }
	float noise = surface_noise(UV*vec2(16.0,10.0))*0.6+surface_noise(UV*vec2(39.0,21.0))*0.4;
	float taper = (1.0-smoothstep(0.004,0.072,world_vertex.y))*smoothstep(0.0,0.10,UV.x)*smoothstep(0.0,0.10,1.0-UV.x);
	float streak = smoothstep(0.23,0.65,noise);
	ALBEDO = vec3(0.036,0.029,0.025);
	ALPHA = taper*streak*0.78;
	ROUGHNESS = 0.98;
}

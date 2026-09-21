shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_burley;
uniform float time = 0.0;
uniform vec2 board_size = vec2(1.8288,1.2192);
varying float fade;
void vertex() {
	float t = fract(time*0.14+INSTANCE_CUSTOM.r);
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 drift = vec2(t*0.09,t*0.025);
	origin.xz = mod(origin.xz+drift+board_size*0.5,board_size)-board_size*0.5;
	origin.y = 0.004+(1.0-t)*0.035;
	MODELVIEW_MATRIX = VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],vec4(origin,1.0));
	fade = sin(t*3.14159265);
}
void fragment() {
	float edge = 1.0-smoothstep(0.18,0.48,length(UV-vec2(0.5)));
	ALBEDO = vec3(0.34,0.32,0.29);
	ROUGHNESS = 1.0;
	ALPHA = edge*fade*0.48;
}

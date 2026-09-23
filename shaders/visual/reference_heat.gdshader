shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D scene_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float time = 0.0;
varying float phase;
void vertex() {
	phase = MODEL_MATRIX[3].x*23.0+MODEL_MATRIX[3].z*17.0;
	MODELVIEW_MATRIX = VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
float view_depth(vec2 uv,mat4 inverse_projection) {
	float depth = textureLod(scene_depth,uv,0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv,depth)*2.0-1.0;
#else
	vec3 ndc = vec3(uv*2.0-1.0,depth);
#endif
	vec4 point = inverse_projection*vec4(ndc,1.0);
	return -point.z/point.w;
}
void fragment() {
	float shape = pow(max(0.0,1.0-length((UV-vec2(0.5))*2.0)),1.5);
	float wave = sin(UV.y*21.0-time*2.7+phase+sin(UV.x*9.0+time));
	vec2 offset = vec2(wave,cos(UV.y*15.0-time*2.0+phase)*0.3)/VIEWPORT_SIZE*1.8;
	float depth = view_depth(SCREEN_UV,INV_PROJECTION_MATRIX);
	float warped_depth = view_depth(SCREEN_UV+offset,INV_PROJECTION_MATRIX);
	// Avoid pulling foreground silhouettes or the far background into the shimmer.
	float edge = 1.0-smoothstep(0.005,0.025,abs(depth-warped_depth));
	float contact = smoothstep(0.0005,0.006,depth+VERTEX.z);
	ALBEDO = textureLod(scene_tex,SCREEN_UV+offset,0.0).rgb;
	ALPHA = shape*edge*contact*0.55;
}

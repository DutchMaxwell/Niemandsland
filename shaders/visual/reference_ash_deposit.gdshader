shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley;
uniform sampler2D ash_tex : source_color, filter_linear_mipmap_anisotropic;
void fragment() {
	vec2 uv = 1.0-abs(mod(UV,2.0)-1.0);
	vec3 ash = texture(ash_tex,uv).rgb;
	float grain = dot(ash,vec3(0.3,0.5,0.2));
	ALBEDO = ash*vec3(1.03,1.04,1.04);
	ROUGHNESS = 1.0;
	SPECULAR = 0.10;
	float broken_edge = texture(ash_tex,UV*11.0+COLOR.g).r;
	float feather = 1.0-smoothstep(0.58,1.0,COLOR.r+(broken_edge-grain)*0.30);
	ALPHA = smoothstep(0.0,0.09,COLOR.r)*feather*COLOR.a;
}

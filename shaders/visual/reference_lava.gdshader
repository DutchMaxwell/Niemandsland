shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float time = 0.0;
void fragment() {
	vec3 source = texture(albedo_tex,UV).rgb;
	float up = clamp((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).y,0.0,1.0);
	float warm = source.r-max(source.b,source.g*0.55);
	float bright = smoothstep(0.60,0.94,min(source.r,min(source.g,source.b)))*up;
	float hot = max(smoothstep(0.10,0.48,warm),bright);
	float texture_detail = dot(source,vec3(0.30,0.50,0.20));
	vec3 crust = mix(source,vec3(texture_detail),0.65)*0.42;
	ALBEDO = mix(crust,vec3(0.28,0.055,0.009),hot);
	float pulse = 0.88+0.12*sin(time*0.9+UV.x*12.0+UV.y*7.0);
	EMISSION = vec3(1.0,0.19,0.016)*hot*(0.38+texture_detail*0.65)*pulse;
	ROUGHNESS = mix(0.96,0.68,hot);
	SPECULAR = 0.16;
}

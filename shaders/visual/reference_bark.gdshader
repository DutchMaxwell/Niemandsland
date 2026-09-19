shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D bark_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
void fragment() {
 vec3 bark = texture(bark_tex,UV).rgb;
 ALBEDO = bark*vec3(0.48,0.42,0.33);
 ROUGHNESS = 0.96;
 float h = dot(bark,vec3(0.3,0.5,0.2));
 NORMAL = normalize(NORMAL-dFdx(VERTEX)*dFdx(h)*12.0-dFdy(VERTEX)*dFdy(h)*12.0);
}

shader_type spatial;
render_mode cull_back;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 grass_tint = vec3(0.34,0.37,0.24);
uniform vec3 soil_tint = vec3(0.62,0.59,0.51);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec2 uv = wp.xz * 0.7;
 vec3 grass = texture(grass_tex,uv).rgb;
 vec3 soil = texture(earth_tex,uv*0.8).rgb;
 float slope = 1.0 - clamp(dot(NORMAL, (VIEW_MATRIX*vec4(0.0,1.0,0.0,0.0)).xyz),0.0,1.0);
 float patch = 0.5 + 0.5 * sin(wp.x*1.3+sin(wp.z*0.8))*sin(wp.z*1.1);
 ALBEDO = mix(grass*grass_tint,soil*soil_tint,clamp(slope*3.0+patch*0.28,0.0,1.0));
 ROUGHNESS = 0.94;
 SPECULAR = 0.22;
}

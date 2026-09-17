shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, alpha_to_coverage;
uniform sampler2D tuft_tex : source_color, filter_linear_mipmap_anisotropic;
void fragment(){
 vec3 tex=texture(tuft_tex,UV).rgb;
 float mask=max(tex.r,max(tex.g,tex.b));
 ALPHA=clamp(mask*40.0,0.0,1.0);
 ALPHA_SCISSOR_THRESHOLD=0.3;
 ALPHA_ANTIALIASING_EDGE=0.2;
 ALPHA_TEXTURE_COORDINATE=UV*vec2(textureSize(tuft_tex,0));
 ALBEDO=tex*COLOR.rgb*vec3(0.90,1.05,0.74);
 ROUGHNESS=0.83;
 SPECULAR=0.18;
 BACKLIGHT=ALBEDO*0.12;
 vec3 up=normalize((VIEW_MATRIX*vec4(0.0,1.0,0.0,0.0)).xyz);
 NORMAL=normalize(mix(FRONT_FACING ? NORMAL : -NORMAL,up,0.7));
}

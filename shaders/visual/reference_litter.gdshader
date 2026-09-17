shader_type spatial;
render_mode cull_disabled, diffuse_burley, alpha_to_coverage;
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic;
void fragment() {
 vec3 leaf = texture(leaf_tex,UV).rgb;
 ALPHA = clamp(max(leaf.r,max(leaf.g,leaf.b))*55.0,0.0,1.0);
 ALPHA_SCISSOR_THRESHOLD = 0.3;
 float edge = smoothstep(0.0,0.20,UV.x)*smoothstep(0.0,0.20,1.0-UV.x);
 float vein = 1.0-smoothstep(0.01,0.055,abs(UV.x-0.5));
 float fleck = fract(sin(dot(floor(UV*24.0),vec2(17.13,91.7)))*43758.5453);
 ALBEDO = COLOR.rgb*mix(0.65,1.15,edge)*(0.82+fleck*0.25)*(1.0-vein*0.20)*(0.55+leaf.g*1.8);
 ROUGHNESS = 0.92;
 NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
}

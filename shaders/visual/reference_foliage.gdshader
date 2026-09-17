shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, alpha_to_coverage;
uniform float wind_strength = 0.0;
uniform vec3 foliage_tint = vec3(1.0);
uniform bool textured_leaf = false;
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic;
void vertex() {
 vec3 p = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
 VERTEX.x += sin(TIME*1.5+p.x*32.0+p.z*19.0)*wind_strength*UV.y;
}
void fragment() {
 vec3 col = COLOR.rgb;
 if (textured_leaf) {
  vec3 tex = texture(leaf_tex,UV).rgb;
  ALPHA=clamp(max(tex.r,max(tex.g,tex.b))*55.0,0.0,1.0);
  ALPHA_SCISSOR_THRESHOLD=0.3;
  ALPHA_ANTIALIASING_EDGE=0.2;
  ALPHA_TEXTURE_COORDINATE=UV*vec2(textureSize(leaf_tex,0));
  col *= tex*1.9*foliage_tint;
 } else {
  ALPHA=1.0;
  col *= mix(0.45,1.12,smoothstep(0.0,0.7,UV.y));
 }
 ALBEDO = col;
 ROUGHNESS = 0.72;
 SPECULAR = 0.22;
 BACKLIGHT = col*0.24;
 NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
}

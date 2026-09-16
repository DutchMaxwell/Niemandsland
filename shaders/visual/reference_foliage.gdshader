shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform float wind_strength = 0.0;
void vertex() {
 vec3 p = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
 VERTEX.x += sin(TIME * 1.5 + p.x * 32.0 + p.z * 19.0) * wind_strength * UV.y;
}
void fragment() {
 float vein = 1.0 - smoothstep(0.015,0.08,abs(UV.x-0.5));
 ALBEDO = COLOR.rgb * (0.85 + 0.15 * UV.y) + vec3(0.008,0.012,0.002) * vein;
 ROUGHNESS = 0.87;
 BACKLIGHT = COLOR.rgb * 0.10;
 NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
}

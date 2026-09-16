shader_type spatial;
render_mode diffuse_burley;
void fragment() {
 float ridge = sin(UV.x * 94.0 + sin(UV.y * 24.0) * 1.8) * 0.5 + 0.5;
 float grain = sin(UV.y * 300.0 + UV.x * 60.0) * 0.5 + 0.5;
 ALBEDO = mix(vec3(0.037,0.027,0.018),vec3(0.12,0.093,0.060),ridge * 0.65 + grain * 0.12);
 ROUGHNESS = 0.97;
}

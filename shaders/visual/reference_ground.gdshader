shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/visual/reference_ground.gdshaderinc"
uniform bool clip_base = false;
uniform bool surface_relief = false;
float relief(vec2 p) {
 return (surface_noise(p*2.6)-0.5)*0.008+(surface_noise(p*7.5)-0.5)*0.003;
}
varying vec2 ground_xz;
void vertex() {
 ground_xz = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz;
 if(surface_relief) { VERTEX.y += relief(ground_xz); }
}
void fragment() {
 if (clip_base && length(UV) > 1.0) { discard; }
 ALBEDO = ground_sample(ground_xz);
 ROUGHNESS = 0.94;
 METALLIC = 0.0;
 float step_size=0.00014;
 vec2 uv=ground_xz*2.2;
 float h=dot(tiled_surface(earth_tex,uv),vec3(0.3,0.5,0.2));
 float hx=dot(tiled_surface(earth_tex,uv+vec2(step_size*2.2,0.0)),vec3(0.3,0.5,0.2));
 float hz=dot(tiled_surface(earth_tex,uv+vec2(0.0,step_size*2.2)),vec3(0.3,0.5,0.2));
 float slope_x=surface_relief ? (relief(ground_xz)-relief(ground_xz+vec2(step_size,0.0)))/step_size : 0.0;
 float slope_z=surface_relief ? (relief(ground_xz)-relief(ground_xz+vec2(0.0,step_size)))/step_size : 0.0;
 vec3 surface_normal=normalize(vec3((h-hx)*8.0+slope_x,1.0,(h-hz)*8.0+slope_z));
 NORMAL=normalize((VIEW_MATRIX*vec4(surface_normal,0.0)).xyz);
}

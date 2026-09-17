shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
varying vec3 world_pos;
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float noise(vec3 p){
 return (sin(p.x*1.7+sin(p.y*1.9))+sin(p.z*2.3+cos(p.x*0.8))+sin(p.y*2.1+p.z*1.2))*0.166667+0.5;
}
void fragment(){
 float grain=noise(world_pos*370.0);
 float patch=noise(world_pos*135.0);
 float foot=(1.0-smoothstep(0.0,0.026+0.012*patch,world_pos.y));
 float moss=smoothstep(0.45,0.72,patch)*foot;
 float lichen=smoothstep(0.76,0.9,noise(world_pos*280.0))*0.25;
 ALBEDO=mix(vec3(0.043,0.029,0.014),vec3(0.053,0.061,0.014),moss)*mix(0.7,1.2,grain);
 ROUGHNESS=0.99;
 ALPHA=clamp(0.18+foot*0.42+moss*0.42+lichen,0.0,0.82);
}

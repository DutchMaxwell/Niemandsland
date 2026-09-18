shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D stone_tex : filter_linear_mipmap, repeat_disable;
uniform bool joint_darken = false;
uniform vec2 panel_uv_scale = vec2(1.0,1.0);
uniform vec2 panel_uv_offset = vec2(0.0,0.0);
uniform float wall_top = 0.0635;
varying vec3 world_pos;
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float noise(vec3 p){
 return (sin(p.x*1.7+sin(p.y*1.9))+sin(p.z*2.3+cos(p.x*0.8))+sin(p.y*2.1+p.z*1.2))*0.166667+0.5;
}
void fragment(){
 float grain=noise(world_pos*370.0);
 float patch=noise(world_pos*135.0);
 float streak=noise(vec3(world_pos.x*90.0,world_pos.y*18.0,world_pos.z*90.0));
 float up=clamp((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).y,0.0,1.0);
 float h=clamp(world_pos.y/max(wall_top,0.001),0.0,1.0);
 float joint=0.0;
 float panel_alpha=1.0;
 if(joint_darken){
  vec4 stone_sample=texture(stone_tex,UV*panel_uv_scale+panel_uv_offset);
  float lum=dot(stone_sample.rgb,vec3(0.299,0.587,0.114));
  joint=1.0-smoothstep(0.07,0.15,lum);
  panel_alpha=step(0.5,stone_sample.a);
 }
 float foot=1.0-smoothstep(0.0,0.20+0.10*patch,h);
 float low=1.0-smoothstep(0.0,0.45,h);
 float cap=smoothstep(0.78,1.0,h);
 float moss=smoothstep(0.40,0.68,patch)*foot;
 moss=max(moss,joint*max(foot,low*0.55)*0.9);
 moss=max(moss,cap*smoothstep(0.28,0.62,patch)*0.75);
 float lichen=smoothstep(0.74,0.92,noise(world_pos*280.0))*0.30;
 float streak_fine=noise(vec3(world_pos.x*210.0,world_pos.y*4.0,world_pos.z*210.0));
 float damp=max(smoothstep(0.64,0.88,streak),smoothstep(0.70,0.90,streak_fine)*0.8)*0.5;
 float grime=smoothstep(0.30,0.72,patch)*0.35;
 vec3 base=mix(vec3(0.070,0.058,0.044),vec3(0.120,0.150,0.070),moss);
 base=mix(base,vec3(0.040,0.038,0.030),damp);
 base=mix(base,vec3(0.058,0.052,0.042),grime);
 base*=mix(1.0,0.70,low*0.6);
 ALBEDO=base*mix(0.72,1.15,grain)*(1.0-0.70*joint);
 ROUGHNESS=0.72;
 ALPHA=clamp(0.22+grime*0.30+foot*0.30+moss*0.40+lichen+damp*0.30+joint*0.35,0.0,0.88)*panel_alpha;
}

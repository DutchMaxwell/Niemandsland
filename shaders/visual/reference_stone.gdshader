shader_type spatial;
render_mode diffuse_burley;
varying vec3 local_pos;
void vertex(){local_pos=VERTEX;}
void fragment(){
 float grain=sin(local_pos.x*77.0+sin(local_pos.y*81.0)*2.0+local_pos.z*93.0)*0.06;
 float facets=sin(local_pos.x*9.0+local_pos.y*13.0+local_pos.z*11.0)*0.10;
 ALBEDO=COLOR.rgb*(0.86+grain+facets);
 ROUGHNESS=0.95;
 SPECULAR=0.18;
}

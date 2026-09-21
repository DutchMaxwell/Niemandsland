shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform float wind_time = -1.0;
void vertex() {
	vec3 world = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	float bend = smoothstep(0.001,0.017,VERTEX.y);
	float t = wind_time<0.0 ? TIME : wind_time;
	VERTEX.xz += vec2(sin(t*1.2+world.x*9.0+world.z*7.0),cos(t*0.95+world.z*8.0))*0.0008*bend;
}
void fragment() {
	float vein = 1.0-smoothstep(0.01,0.06,abs(UV.x-0.5));
	float ribs = pow(0.5+0.5*sin(UV.y*95.0+abs(UV.x-0.5)*12.0),9.0)*0.07;
	float grain = fract(sin(dot(floor(UV*180.0),vec2(17.13,91.7)))*43758.5453);
	ALBEDO = COLOR.rgb*mix(0.60,1.10,smoothstep(0.0,0.7,UV.y))*(0.94+grain*0.12+vein*0.15-ribs);
	ROUGHNESS = 0.56;
	SPECULAR = 0.32;
	BACKLIGHT = COLOR.rgb*0.42;
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
}

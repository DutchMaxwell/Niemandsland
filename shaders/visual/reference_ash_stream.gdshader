shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_burley;
uniform float time = 0.0;
float noise(vec2 p) {
	vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
	vec4 q=vec4(dot(i,vec2(127.1,311.7)),dot(i+vec2(1,0),vec2(127.1,311.7)),dot(i+vec2(0,1),vec2(127.1,311.7)),dot(i+vec2(1,1),vec2(127.1,311.7)));
	vec4 h=fract(sin(q)*43758.5453);
	return mix(mix(h.x,h.y,f.x),mix(h.z,h.w,f.x),f.y);
}
void fragment() {
	float phase=COLOR.r;
	float cycle=fract(time*(0.18+COLOR.g*0.04)+phase);
	float head=cycle*1.8-0.35;
	float gust=1.0-smoothstep(0.05,0.34,abs(UV.x-head));
	float ends=smoothstep(0.0,0.12,UV.x)*(1.0-smoothstep(0.82,1.0,UV.x));
	float side=pow(max(0.0,1.0-abs(UV.y*2.0-1.0)),1.6);
	vec2 flow=vec2(UV.x*11.0-time*2.7,UV.y*6.0+phase*23.0);
	float wisps=smoothstep(0.24,0.72,noise(flow));
	float grains=noise(flow*vec2(4.0,2.1));
	ALBEDO=vec3(0.25,0.245,0.23);
	ROUGHNESS=1.0;
	SPECULAR=0.05;
	ALPHA=gust*ends*side*(0.20+wisps*0.80)*(0.65+grains*0.35)*COLOR.a*0.72;
}

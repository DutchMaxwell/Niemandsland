// Slow unequal oscillations share a gentle gust envelope. Lower stems stay fixed.
vec3 jungle_displacement(vec3 p,float bottom,float height,float t,float phase,float strength) {
	float h = clamp((p.y-bottom)/max(height,0.001),0.0,1.0);
	float rooted = smoothstep(0.16,0.90,h);
	float gust = 0.72+0.28*sin(t*0.43+phase*0.37);
	vec2 sway = vec2(sin(t*0.93+phase),cos(t*0.71+phase*1.7));
	return vec3(sway.x,0.0,sway.y*0.65)*height*strength*rooted*gust;
}

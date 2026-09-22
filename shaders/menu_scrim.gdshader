shader_type canvas_item;
// Quiet navy backing for readable menu text, fading into the native night scene.
void fragment() {
	float side = mix(0.98,0.0,smoothstep(0.22,0.72,UV.x));
	float bottom = 0.88*smoothstep(0.76,1.0,UV.y);
	COLOR = vec4(0.035,0.055,0.078,max(side,bottom));
}

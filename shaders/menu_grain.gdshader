shader_type canvas_item;
// Web-safe film grain: faint animated noise overlay. Uses only UV + TIME (no
// screen texture), so it works on Forward+ and the Compatibility/web renderer.

uniform float amount : hint_range(0.0, 0.2) = 0.04;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float n = hash(UV * vec2(1280.0, 720.0) + fract(TIME) * 91.7);
	COLOR = vec4(vec3(n), amount);
}

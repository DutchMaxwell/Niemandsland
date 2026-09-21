shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float tree_bottom = 0.0;
uniform float tree_height = 1.0;
uniform float crown_width = 1.0;
uniform vec2 crown_lean = vec2(0.0);
uniform float wind_amount = 0.004;
uniform float snow_amount = 0.0;
uniform bool charred = false;
varying vec3 tree_position;

float patch(vec3 p) {
	return (sin(p.x * 11.7 + sin(p.y * 8.1)) + sin(p.z * 13.3 + p.y * 4.7)) * 0.25 + 0.5;
}

void vertex() {
	float h = clamp((VERTEX.y - tree_bottom) / max(tree_height,0.001),0.0,1.0);
	float crown = smoothstep(0.15,0.85,h);
	VERTEX.xz *= mix(1.0,crown_width,crown);
	VERTEX.xz += crown_lean * tree_height * h * h;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	float sway = sin(TIME * 1.15 + world.x * 3.0 + world.z * 2.4);
	VERTEX.xz += vec2(sway,cos(TIME * 0.91 + world.z * 2.0)) * tree_height * wind_amount * crown;
	tree_position = VERTEX / max(tree_height,0.001);
}

void fragment() {
	vec4 sample_color = texture(albedo_tex,UV) * albedo_tint;
	float up = clamp((INV_VIEW_MATRIX * vec4(NORMAL,0.0)).y,0.0,1.0);
	float broken_cover = smoothstep(0.28,0.74,patch(tree_position * 2.4));
	float snow = smoothstep(0.20,0.72,up) * broken_cover * snow_amount;
	ALBEDO = mix(sample_color.rgb,vec3(0.72,0.79,0.85),snow);
	if (charred) {
		float grey = dot(sample_color.rgb,vec3(0.3,0.5,0.2));
		ALBEDO = mix(vec3(grey)*vec3(0.49,0.51,0.55),vec3(0.16,0.15,0.14),smoothstep(0.30,0.85,up)*broken_cover*0.60);
	}
	ROUGHNESS = mix(0.89,0.97,snow);
	SPECULAR = 0.18;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex,UV).rgb;
		NORMAL_MAP_DEPTH = mix(1.0,0.35,snow);
	}
}

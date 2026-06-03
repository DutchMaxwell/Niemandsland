shader_type spatial;
// Thin, soft, drifting white ground mist for a flat plane that hugs the table a
// centimetre or two above the surface. Unshaded so it stays white regardless of the
// scene light, alpha-blended, never writes depth or casts shadow. Scrolls via TIME.
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, unshaded, fog_disabled;

uniform vec3 mist_color : source_color = vec3(0.92, 0.94, 0.97);
uniform sampler2D noise_tex : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform float density : hint_range(0.0, 2.0) = 0.6;
uniform float tiling = 2.4;
uniform vec2 scroll = vec2(0.012, 0.007);
uniform float edge_fade : hint_range(0.0, 0.5) = 0.18;
uniform float wisp : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	// Two scrolling samples multiplied -> wispy, ever-changing gaps.
	vec2 uv1 = UV * tiling + scroll * TIME;
	vec2 uv2 = UV * tiling * 1.7 - scroll * TIME * 0.6 + vec2(0.5);
	float n = texture(noise_tex, uv1).r * texture(noise_tex, uv2).r;
	n = smoothstep(wisp, 1.0, n);

	// Fade out toward the plane edges so there is no hard rectangular boundary.
	vec2 e = smoothstep(vec2(0.0), vec2(edge_fade), UV)
		* smoothstep(vec2(0.0), vec2(edge_fade), 1.0 - UV);
	float a = clamp(n * density, 0.0, 1.0) * e.x * e.y;

	ALBEDO = mist_color;
	ALPHA = a;
}

class_name SpellGlyphs
extends RefCounted
## The spell runes, as data and shaders only. No religious symbols (maintainer, 05.10.): every glyph is a set of arcs
## around its own centre (GLYPH_STROKES: [kind, radius, start, span] in half the glyph and turns), so no cross, star,
## crescent or wheel can be written; the rune column is rising, narrowing broken rings, never a stroke with a crossbar.
## test/vfx_glyphs_test.gd holds both to it.

const COLUMN := "shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color; uniform float fade = 1.0;
void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz; vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 f = normalize(vec3(cam.x - o.x, 0.0, cam.z - o.z) + vec3(0.0001, 0.0, 0.0));
	vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), f));
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(o + r * VERTEX.x + vec3(0.0, VERTEX.y, 0.0), 1.0);
}
void fragment() {
	float h = 1.0 - UV.y; float g = 0.0;
	for (int i = 0; i < 4; i++) {
		float t = fract(TIME * 0.45 + float(i) * 0.25); float a = mix(0.46, 0.16, t);
		vec2 q = vec2((UV.x - 0.5) / a, (h - 0.06 - t * 0.85) / (a * 0.19));
		float lit = step(0.25, fract(atan(q.y, q.x) / 6.28318 + TIME * 0.3 + float(i) * 0.37));
		g = max(g, lit * (1.0 - smoothstep(0.02, 0.05, abs(length(q) - 1.0) * a)) * (1.0 - t * 0.6));
	}
	float env = (1.0 - UV.y) * UV.y * 4.0 * (1.0 - abs(UV.x - 0.5) * 2.0);
	ALBEDO = tint.rgb * (g + 0.25); ALPHA = (env * 0.3 + g * smoothstep(0.0, 0.1, h)) * fade;
}"
const GLYPH := "shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color; uniform vec3 arcs[3]; uniform float fade = 1.0;
void vertex() { MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]); }
void fragment() {
	vec2 q = UV * 2.0 - 1.0; float r = length(q); float u = fract(atan(q.y, q.x) / 6.28318 + 1.0); float g = 0.0;
	for (int i = 0; i < 3; i++) {
		float on = step(fract(u - arcs[i].y), arcs[i].z) * step(0.001, arcs[i].x);
		g = max(g, on * (1.0 - smoothstep(0.06, 0.11, abs(r - arcs[i].x))));
	}
	ALBEDO = tint.rgb; ALPHA = g * fade;
}"
## The orbiting glyphs, as data: [kind, radius (in half the glyph), start and span (turns)] per stroke. Arcs around the
## glyph's own centre are the only stroke the shader draws, so no cross, star, crescent or wheel can be written here
## (maintainer 05.10.: no religious symbols; test/vfx_glyphs_test.gd holds the set to it).
const GLYPH_STROKES := [
	[["arc", 0.8, 0.0, 0.55], ["arc", 0.45, 0.5, 0.55]],
	[["arc", 0.8, 0.1, 0.4], ["arc", 0.55, 0.45, 0.45], ["arc", 0.3, 0.8, 0.5]],
	[["arc", 0.75, 0.25, 0.65], ["arc", 0.4, 0.75, 0.3]],
	[["arc", 0.8, 0.6, 0.35], ["arc", 0.6, 0.1, 0.35], ["arc", 0.35, 0.35, 0.6]],
	[["arc", 0.7, 0.0, 0.7], ["arc", 0.35, 0.5, 0.4]],
	[["arc", 0.85, 0.3, 0.3], ["arc", 0.5, 0.8, 0.6]],
]

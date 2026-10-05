class_name SpellHeroes
extends RefCounted
## Combat effects, the big moments of a cast that worked: a light pillar on each target and a soft screen glow pulse
## (a canvas overlay at low alpha — never the Environment, which RenderState owns). The two hero effects (chain
## lightning, a meteor) come in the next step.

const PILLAR := "shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color; uniform float fade = 1.0;
void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz; vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), normalize(vec3(cam.x - o.x, 0.0, cam.z - o.z) + vec3(0.0001, 0.0, 0.0))));
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(o + r * VERTEX.x + vec3(0.0, VERTEX.y, 0.0), 1.0);
}
void fragment() {
	float core = 1.0 - smoothstep(0.0, 0.5, abs(UV.x - 0.5));
	ALBEDO = tint.rgb * (0.6 + core); ALPHA = core * pow(UV.y, 1.5) * fade;
}"
const PULSE := "shader_type canvas_item;
render_mode blend_add;
uniform vec4 tint : source_color; uniform float strength = 0.0;
void fragment() { float r = length(UV * 2.0 - 1.0); COLOR = vec4(tint.rgb, (1.0 - smoothstep(0.2, 1.2, r)) * strength); }"
const PULSE_MAX := 0.18   # the pulse's peak alpha: a glow, never a flash
static var _shaders := {}


static func _material(code: String, tint: Color) -> ShaderMaterial:
	if not _shaders.has(code):
		_shaders[code] = Shader.new()
		(_shaders[code] as Shader).code = code
	var mat := ShaderMaterial.new()
	mat.shader = _shaders[code]
	mat.set_shader_parameter("tint", tint)
	return mat


## A pillar of light standing on `at` for 0.7 s.
static func pillar(host: Node3D, at: Vector3, tint: Color) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.3)
	quad.center_offset = Vector3(0, 0.15, 0)
	var m := MeshInstance3D.new()
	m.mesh = quad
	m.material_override = _material(PILLAR, tint)
	(m.material_override as ShaderMaterial).set_shader_parameter("fade", 1.0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(m)
	m.global_position = at - Vector3.UP * 0.03
	var tw := m.create_tween()
	tw.tween_property(m.material_override, "shader_parameter/fade", 0.0, 0.7).set_ease(Tween.EASE_IN)
	tw.tween_callback(m.queue_free)


## A soft glow over the whole picture, peaking at PULSE_MAX alpha for a quarter second.
static func pulse(host: Node, tint: Color) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _material(PULSE, tint)
	(rect.material as ShaderMaterial).set_shader_parameter("strength", 0.0)
	layer.add_child(rect)
	host.add_child(layer)
	var tw := layer.create_tween()
	tw.tween_property(rect.material, "shader_parameter/strength", PULSE_MAX, 0.08)
	tw.tween_property(rect.material, "shader_parameter/strength", 0.0, 0.22)
	tw.tween_callback(layer.queue_free)


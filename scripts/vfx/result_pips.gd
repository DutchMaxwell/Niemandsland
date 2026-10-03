class_name ResultPips
extends Node3D
## VFX #1: marks AT the models a resolved attack touched — a red tick per wound that landed on a survivor, a
## red cross on a casualty — read off the resolver's own allocation, never rolled or written back, no RNG.
## Over the model's sight-cylinder top (the LOS rule's eye). Still form on Performance/Low + Reduce Motion;
## capped pool. Off unless GraphicsSettings.show_combat_effects (default off until the look is approved).

enum Kind { WOUND, KILL, HIT, SAVE }
const COLORS := [Color(0.88, 0.2, 0.18), Color(0.88, 0.2, 0.18), Color(0.96, 0.93, 0.84), Color(0.4, 0.68, 0.95)]
const SIZE_M := 0.011
const LIFT_M := 0.01
const RISE_M := 0.012
const LIFE_S := 1.8
const MAX_LIVE := 32
const SHADER := "shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled;
uniform vec4 tint : source_color; uniform int shape; uniform int count = 1; uniform float fade = 1.0;
void vertex() { MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]); }
void fragment() {
	vec2 p = vec2(fract(UV.x * float(count)), UV.y) * 2.0 - 1.0; float d;
	if (shape == 0) { d = max(abs(p.x) - 0.22, abs(p.y) - 0.8); }
	else if (shape == 1) { d = max(min(abs(p.x - p.y), abs(p.x + p.y)) * 0.707 - 0.2, length(p) - 0.9); }
	else if (shape == 2) { d = length(p) - 0.5; } else { d = abs(length(p) - 0.58) - 0.16; }
	float a = 1.0 - smoothstep(-0.05, 0.05, d);
	ALBEDO = mix(vec3(0.04), tint.rgb, a); ALPHA = max(a, 1.0 - smoothstep(0.05, 0.2, d)) * fade;
}"

var enabled: bool = true
var force_for_tests: bool = false   # plain headless never spawns (FloatingRuleText's orphan lesson)
static var _shader: Shader


func _ready() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	enabled = gs != null and bool(gs.get("show_combat_effects"))


## Still form: no rise on Performance (0) / Low (1), nor with Reduce Motion — the mark appears and fades.
static func still_form(preset: int, reduce_motion: bool) -> bool:
	return reduce_motion or preset <= 1


## Mark `count` results of `kind` over a model (its node's spot, lifted to its sight-cylinder eye).
func mark_model(kind: Kind, mi: ModelInstance, count: int) -> MeshInstance3D:
	if mi == null or mi.node == null or not is_instance_valid(mi.node):
		return null
	var eye_m := VolumetricLos.height_in_for_base_mm(VolumetricLos.model_base_radius_m(mi) * 2000.0) \
		* VolumetricLos.INCHES_TO_METERS
	return mark(kind, mi.node.global_position + Vector3.UP * eye_m, count)


func mark(kind: Kind, eye: Vector3, count: int) -> MeshInstance3D:
	if not enabled or count <= 0 or (DisplayServer.get_name() == "headless" and not force_for_tests):
		return null
	while get_child_count() >= MAX_LIVE:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("tint", COLORS[kind])
	mat.set_shader_parameter("shape", int(kind))
	mat.set_shader_parameter("count", count)
	mat.set_shader_parameter("fade", 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(SIZE_M * count, SIZE_M)
	var pip := MeshInstance3D.new()
	pip.mesh = quad
	pip.material_override = mat
	pip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pip)
	pip.global_position = eye + Vector3.UP * LIFT_M
	var gs := get_node_or_null("/root/GraphicsSettings")
	var still := still_form(int(gs.current_preset) if gs != null else 2, UiMotion.reduced())
	var tw := pip.create_tween()   # bound to the pip: an evicted pip takes its tween with it
	if not still:
		tw.tween_property(pip, "position:y", pip.position.y + RISE_M, LIFE_S)
	tw.parallel().tween_property(mat, "shader_parameter/fade", 0.0, 0.4).set_delay(LIFE_S - 0.4)
	tw.tween_callback(pip.queue_free)
	return pip

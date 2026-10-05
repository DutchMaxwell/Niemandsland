class_name Splatters
extends Node3D
## VFX v3: flat splatters on the ground where a model bled or leaked — a lobed pool with droplets, drawn by one small
## shader from the cue's seed, fading out after a while and capped so a long game never piles them up. Only pictures:
## they are not the battlefield stains (those are the residue the game keeps) and never saved.

const SHADER := "shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color; uniform float fade = 1.0; uniform float seed = 0.0; uniform float splash = 1.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed) * 43758.5453); }
void fragment() {
	vec2 p = UV * 2.0 - 1.0; float r = length(p); float a = atan(p.y, p.x);
	float edge = 0.55 + (0.07 * sin(a * 3.0 + seed) + 0.04 * sin(a * 7.0 + seed * 2.3) + 0.02 * sin(a * 13.0 + seed * 3.1)) * (0.4 + splash);
	float pool = 1.0 - smoothstep(edge - 0.05, edge, r);
	vec2 c = floor(p * 7.0); float drop = step(0.8, h(c)) * splash * (1.0 - smoothstep(0.08, 0.16, length(fract(p * 7.0) - 0.5)));
	ALBEDO = tint.rgb * (0.8 + 0.2 * h(floor(UV * 37.0))); ALPHA = max(pool, drop * step(r, 0.97)) * tint.a * fade;
}"
const LIFT_M := 0.0015   # above the ground it lies on, below every base

var cap := 24
static var _shader: Shader


## A splatter of `size` metres at `ground` (the spot's own height), faded out after `life` seconds.
## `splash` 1 throws droplets around a ragged pool (blood); 0 is a smooth puddle (oil).
func add(ground: Vector3, size: float, tint: Color, rng_seed: int, life: float, splash := 1.0) -> MeshInstance3D:
	while get_child_count() >= cap:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("seed", float(rng_seed % 997))
	mat.set_shader_parameter("fade", 1.0)
	mat.set_shader_parameter("splash", splash)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * size
	var s := MeshInstance3D.new()
	s.mesh = plane
	s.material_override = mat
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s)
	s.global_position = ground + Vector3.UP * LIFT_M
	s.rotation.y = float(rng_seed % 628) / 100.0
	var tw := s.create_tween()
	tw.tween_interval(life)
	tw.tween_property(mat, "shader_parameter/fade", 0.0, 1.5)
	tw.tween_callback(s.queue_free)
	return s

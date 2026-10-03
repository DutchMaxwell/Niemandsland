class_name SpellSeal
extends Node3D
## VFX #3: the spell lifecycle seal — a flat glyph circle at the caster's base whose outer edge IS the spell
## range (the caller passes RangeRingController.ring_outer_radius_for_props: base edge + range, the purple
## preview ring's own convention and 4 mm band). It forms on the cast declaration, flares on success, cracks
## on a fail, dims/flickers when interfered with, fades on a cancel. Kind = colour AND rune count (damage /
## buff / debuff / utility). Still form (Performance/Low, Reduce Motion): no sweep, spin or flicker.
## No RNG; off unless GraphicsSettings.show_combat_effects (default off until the look GO).

enum Outcome { SUCCESS, FAIL, CANCEL }
const KINDS := {"damage": [Color(1.0, 0.46, 0.3), 6], "buff": [Color(0.45, 0.95, 0.55), 8],
	"debuff": [Color(0.86, 0.42, 0.95), 5], "utility": [Color(0.55, 0.76, 1.0), 4]}
const BAND_M := 0.004
const LIFT_M := 0.006
const FORM_S := 0.35
const SHADER := "shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color; uniform int runes = 6; uniform float band = 0.05;
uniform float progress = 1.0; uniform float flare = 0.0; uniform float crack = 0.0; uniform float fade = 1.0;
uniform float spin = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0; float r = length(p); float u = fract(atan(p.y, p.x) / 6.28318 + spin);
	float g = 1.0 - smoothstep(0.0, band * 0.25, abs(r - (1.0 - band * 0.5)) - band * 0.5);
	g = max(g, 1.0 - smoothstep(0.0, band * 0.2, abs(r - (1.0 - band * 4.0)) - band * 0.2));
	float du = abs(fract(u * float(runes) + 0.5) - 0.5) / float(runes) * 6.28318 * r;
	g = max(g, (1.0 - smoothstep(band * 0.3, band * 0.6, du)) * step(1.0 - band * 4.0, r) * step(r, 1.0 - band));
	g *= step(u, progress) * (1.0 - step(fract(u * 7.0 + 0.13), crack * 0.45));
	ALBEDO = mix(tint.rgb, vec3(1.0), flare * 0.6); ALPHA = g * fade * min(1.0, tint.a + flare);
}"

var enabled: bool = true
var force_for_tests: bool = false
static var _shader: Shader


func _ready() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	enabled = gs != null and gs.get("show_combat_effects") == true


func _still() -> bool:
	var gs := get_node_or_null("/root/GraphicsSettings")
	return UiMotion.reduced() or (int(gs.current_preset) if gs != null else 2) <= 1   # Performance / Low


## The cast is declared: the seal forms around `centre` (the caster's base) with the spell-range radius.
func begin(centre: Vector3, radius_m: float, kind: String) -> MeshInstance3D:
	if not enabled or radius_m <= BAND_M or (DisplayServer.get_name() == "headless" and not force_for_tests):
		return null
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var look: Array = KINDS.get(kind, KINDS["utility"])
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.render_priority = 8   # with the spell preview ring, above stains / zones / seize rings
	var params := {"tint": look[0], "runes": look[1], "band": BAND_M / radius_m, "progress": 1.0, "fade": 1.0,
		"flare": 0.0, "crack": 0.0, "spin": 0.0}
	for k: String in params:
		mat.set_shader_parameter(k, params[k])
	var seal := MeshInstance3D.new()
	seal.mesh = annulus(radius_m, maxf(0.0, radius_m - 5.0 * BAND_M))
	seal.material_override = mat
	seal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(seal)
	seal.global_position = centre + Vector3.UP * LIFT_M
	if not _still():
		mat.set_shader_parameter("progress", 0.0)
		var tw := seal.create_tween()
		tw.tween_property(mat, "shader_parameter/progress", 1.0, FORM_S)
		tw.parallel().tween_property(mat, "shader_parameter/spin", 0.25, 8.0)
	return seal


## Only the band the glyph lives in is geometry (like RangeRingController's flat ring): a full plane made every
## pixel inside an 18" circle run the shader for nothing (measured +0.6 ms GPU p95 on Medium). The polygon
## circumscribes the circle so its edge never clips the outer ring; UVs map the radius to 0.5 as a plane would.
static func annulus(radius_m: float, inner_m: float, segments: int = 64) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := radius_m / cos(PI / segments)
	for i in segments:
		var a := Vector2.from_angle(TAU * i / segments)
		var b := Vector2.from_angle(TAU * (i + 1) / segments)
		for v: Vector2 in [a * outer, a * inner_m, b * inner_m, a * outer, b * inner_m, b * outer]:
			st.set_uv(v / (radius_m * 2.0) + Vector2(0.5, 0.5))
			st.add_vertex(Vector3(v.x, 0.0, v.y))
	return st.commit()


## The cast resolved: flare (success), crack (fail) or a plain fade (cancel), then the seal is gone.
func finish(seal: MeshInstance3D, outcome: Outcome) -> void:
	if seal == null or not is_instance_valid(seal):
		return
	var mat := seal.material_override as ShaderMaterial
	var tw := seal.create_tween()
	if outcome == Outcome.SUCCESS:
		tw.tween_property(mat, "shader_parameter/flare", 1.0, 0.15)
	elif outcome == Outcome.FAIL:
		tw.tween_property(mat, "shader_parameter/crack", 1.0, 0.0 if _still() else 0.3)
	tw.tween_property(mat, "shader_parameter/fade", 0.0, 0.25 if outcome == Outcome.CANCEL else 0.5)
	tw.tween_callback(seal.queue_free)


## Interference (spell tokens spent against the cast): the seal dims twice, or once and steadily when still.
func interfere(seal: MeshInstance3D) -> void:
	if seal == null or not is_instance_valid(seal):
		return
	var mat := seal.material_override as ShaderMaterial
	var tw := seal.create_tween()
	for i in (1 if _still() else 2):
		tw.tween_property(mat, "shader_parameter/fade", 0.35, 0.1 if not _still() else 0.0)
		tw.tween_property(mat, "shader_parameter/fade", 1.0, 0.1 if not _still() else 0.3)

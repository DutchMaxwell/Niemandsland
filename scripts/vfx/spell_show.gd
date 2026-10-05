class_name SpellShow
extends Node3D
## Combat effects, the casting show around the rule-true seal (maintainer look verdicts 05.10.: all spells GO). A cast
## gathers in compact curved ribbons around the miniature with arc-only runes circling it (SpellGlyphs) and motes of
## its element (SpellLook); the caster stays visible and the seal stays independent. All variation comes from the
## peer-shared cue seed. Performance is silent; Low and Reduce Motion use two still arc runes, no particles, no spin.
## A declaration counts once, at most MAX_CASTS wait at a time, and an abandoned one expires after MAX_HOLD_S.
## (The moving sleeve, spin and motes, clearing a charge when a setting changes, and the resolution - release at the
## targets, collapse on a fail - come in the next step.)

const GLYPHS := 5
const MAX_HOLD_S := 30.0
const MAX_CASTS := 12

class Charge extends RefCounted:
	var focus: Node3D
	var at: Vector3
	var element: int
	var spin: Tween

var enabled := true
var force_for_tests := false
var _columns: Dictionary = {}
static var _shaders: Dictionary = {}


func _ready() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	enabled = gs != null and gs.get("show_combat_effects") == true


func _preset() -> int:
	var gs := get_node_or_null("/root/GraphicsSettings")
	return -1 if not enabled or (DisplayServer.get_name() == "headless" and not force_for_tests) \
		else (int(gs.current_preset) if gs != null else 2)


func _material(code: String, tint: Color) -> ShaderMaterial:
	if not _shaders.has(code):
		_shaders[code] = Shader.new()
		(_shaders[code] as Shader).code = code
	var mat := ShaderMaterial.new()
	mat.shader = _shaders[code]
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("fade", 1.0)
	return mat


## Only finite, bounded positions reach the mesh builders, including direct presenter callers.
static func valid_point(at: Vector3) -> bool:
	return at.is_finite() and at.length_squared() < 10000.0


## Declare once. An abandoned network cast expires, and concurrent pending casts have a hard cap.
func begin(key: String, at: Vector3, radius: float, el: int, rng_seed: int) -> void:
	var p := _preset()
	if p <= 0 or _columns.has(key) or _columns.size() >= MAX_CASTS or not valid_point(at) \
		or not is_finite(radius) or radius <= SpellSeal.BAND_M or el < 0 or el >= SpellLook.TINTS.size():
		return
	var still := p == 1 or UiMotion.reduced()
	var cast := Charge.new()
	cast.at = at
	cast.element = el
	cast.focus = Node3D.new()
	cast.focus.name = "SpellCharge"
	add_child(cast.focus)
	cast.focus.global_position = at
	var phase := fposmod(float(rng_seed), 628.0) * 0.01
	var ribbon := SpellForms.curl(cast.focus, 0.043, 0.0 if still else 0.065, 1.0 if still else 1.6,
		0.0025, SpellLook.TINTS[el], phase)
	ribbon.position.y = 0.012
	var count := 2 if still else GLYPHS
	for i in count:
		var q := QuadMesh.new()
		q.size = Vector2.ONE * 0.021
		var glyph := MeshInstance3D.new()
		glyph.name = "ArcGlyph"
		glyph.set_meta("spell_glyph", true)
		glyph.mesh = q
		glyph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glyph.material_override = _material(SpellGlyphs.GLYPH, SpellLook.TINTS[el])
		var arcs := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
		var strokes: Array = SpellGlyphs.GLYPH_STROKES[posmod(rng_seed + i, SpellGlyphs.GLYPH_STROKES.size())]
		for j in strokes.size():
			arcs[j] = Vector3(strokes[j][1], strokes[j][2], strokes[j][3])
		(glyph.material_override as ShaderMaterial).set_shader_parameter("arcs", arcs)
		cast.focus.add_child(glyph)
		var angle := phase + TAU * i / count
		glyph.position = Vector3(cos(angle) * 0.051, 0.025 + 0.011 * i, sin(angle) * 0.051)
	_columns[key] = cast
	var expiry := cast.focus.create_tween()
	expiry.tween_interval(MAX_HOLD_S)
	expiry.tween_callback(func() -> void:
		if _columns.get(key) == cast:
			_columns.erase(key)
		cast.focus.queue_free())

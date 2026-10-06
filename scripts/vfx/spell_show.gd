class_name SpellShow
extends Node3D
## Combat effects, the casting show around the rule-true seal (maintainer look verdicts 05.10.: all spells GO). A cast
## gathers in compact curved ribbons around the miniature with arc-only runes circling it (SpellGlyphs) and motes of
## its element (SpellLook); the caster stays visible and the seal stays independent. All variation comes from the
## peer-shared cue seed. Performance is silent; Low and Reduce Motion use two still arc runes, no particles, no spin.
## A declaration counts once, at most MAX_CASTS wait at a time, and an abandoned one expires after MAX_HOLD_S.
## When the cast resolves: on a success the charge flares and the element is released at the resolved targets
## (SpellImpacts for a damage spell, a strand and a ring otherwise); on a fail it collapses at the caster, its runes
## break away and fall, nothing travels; a cancel just fades. A setting change clears a waiting charge at once.

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
var _reduced := false
var _quality := 2
static var _shaders: Dictionary = {}


func _ready() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	enabled = gs != null and gs.get("show_combat_effects") == true
	_reduced = UiMotion.reduced()
	_quality = _preset()


func _preset() -> int:
	var gs := get_node_or_null("/root/GraphicsSettings")
	return -1 if not enabled or (DisplayServer.get_name() == "headless" and not force_for_tests) \
		else (int(gs.current_preset) if gs != null else 2)


func _process(_delta: float) -> void:
	# A setting changed during a roll: remove the old moving form immediately.
	var reduced := UiMotion.reduced()
	var quality := _preset()
	if quality <= 0 or reduced != _reduced or (quality == 1 and _quality > 1):
		_columns.clear()
		if get_child_count() > 0:
			for child in get_children():
				child.queue_free()
	_reduced = reduced
	_quality = quality


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
	if not still:
		# A faint sleeve of rising elliptical arcs; no central beam hiding the caster.
		var column := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.095, 0.09)
		quad.center_offset = Vector3(0, 0.052, 0)
		column.mesh = quad
		column.material_override = _material(SpellGlyphs.COLUMN, SpellLook.TINTS[el] * 0.22)
		column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cast.focus.add_child(column)
		cast.spin = cast.focus.create_tween().set_loops()
		cast.spin.tween_property(cast.focus, "rotation:y", TAU, 4.0).as_relative()
		FxBurst.spawn(self, SpellLook.PARTICLES[el][0], at + Vector3.UP * 0.035, Vector3.UP, 12, rng_seed, p, 0.65, SpellLook.PARTICLES[el][1])
	_columns[key] = cast
	var expiry := cast.focus.create_tween()
	expiry.tween_interval(MAX_HOLD_S)
	expiry.tween_callback(func() -> void:
		if _columns.get(key) == cast:
			_columns.erase(key)
		cast.focus.queue_free())


## Resolve once. Damage releases travel only on success; a failed cast collapses at its own origin.
func end(key: String, outcome: int, targets: Array, damage: bool, rng_seed: int) -> void:
	var cast: Charge = _columns.get(key)
	_columns.erase(key)
	if cast == null:
		return
	if cast.spin != null and cast.spin.is_valid():
		cast.spin.kill()
	var p := _preset()
	if p <= 0 or outcome < 0 or outcome > SpellSeal.Outcome.CANCEL:
		cast.focus.queue_free()
		return
	var still := p == 1 or UiMotion.reduced()
	if not still:
		var tw := cast.focus.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(cast.focus, "scale", Vector3.ONE * (1.35 if outcome == SpellSeal.Outcome.SUCCESS else 0.08), 0.3)
	SpellForms.retire(cast.focus, 0.0, 0.32)
	if outcome == SpellSeal.Outcome.CANCEL:
		return
	var release := Node3D.new()
	release.name = "SpellSuccess" if outcome == SpellSeal.Outcome.SUCCESS else "SpellFailure"
	add_child(release)
	var origin := cast.at + Vector3.UP * 0.009
	var tint: Color = SpellLook.TINTS[cast.element]
	if outcome == SpellSeal.Outcome.FAIL:
		SpellForms.ripple(release, origin, Color(1.0, 0.25, 0.14), 0.054, true, still)
		if not still:
			# The approved arc glyphs break away and fall; no new symbols are introduced by the shatter.
			for child in cast.focus.get_children():
				if child.get_meta("spell_glyph", false) != true:
					continue
				var glyph := child as Node3D
				glyph.reparent(release)
				var outward := (glyph.global_position - cast.at) * Vector3(0.55, 0.0, 0.55)
				var fall := glyph.create_tween()
				fall.tween_property(glyph, "global_position", glyph.global_position + outward - Vector3.UP * 0.055, 0.4)
				SpellForms.retire(glyph, 0.05, 0.35)
			FxBurst.spawn(release, FxBurst.Look.PUFF, origin, Vector3.ZERO, 14, rng_seed, p, 1.2,
				Color(0.28, 0.22, 0.3), true)
		SpellForms.retire(release, 1.1, 0.15)
		return
	SpellForms.ripple(release, origin, tint, 0.075, false, still)
	var clean: Array = []
	for target: Variant in targets.slice(0, 8):
		if target is Vector3 and valid_point(target):
			clean.append(target)
	if still:
		for target: Vector3 in clean:
			SpellForms.ripple(release, target, tint, 0.045, false, true)
	elif damage:
		SpellImpacts.release(release, cast.at + Vector3.UP * 0.045, clean, cast.element, rng_seed, p)
	else:
		for target: Vector3 in clean:
			SpellForms.stream(release, cast.at + Vector3.UP * 0.035, target, tint, rng_seed, 1)
			SpellForms.ripple(release, target, tint, 0.055)
	SpellForms.retire(release, 1.7, 0.15)

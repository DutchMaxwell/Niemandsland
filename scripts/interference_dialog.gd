class_name InterferenceDialog
extends CanvasLayer
## ONE modal tableau for spending spell tokens against an enemy cast (maintainer 2026-07-22: the
## old per-token Yes/No ConfirmationDialog loop). +/- selects the token count, a live line shows
## how the spend shifts the AI's cast roll BEFORE confirming; Confirm/No resolve the await.
## Code-built (no scene), awaitable via ask(); the preview line is a pure static for tests.

var _outcome: Array = []
var _count := 0
var _pool := 0
var _base_target := 4
var _boost := 0
var _count_label: Label = null
var _preview_label: Label = null
var _mode := "interfere"   # "interfere" (against an enemy cast) | "boost" (the player's own cast)


## PURE: the live preview line — target before/after the interference, with success odds.
static func format_preview(base_target: int, boost: int, interference: int) -> String:
	var before := AiSpell.cast_target(boost, 0, base_target)
	var after := AiSpell.cast_target(boost, interference, base_target)
	return "Cast roll: %d+ → %d+   (success %d%% → %d%%)" % [before, after,
		roundi(AiSpell.cast_success_chance(boost, 0, base_target) * 100.0),
		roundi(AiSpell.cast_success_chance(boost, interference, base_target) * 100.0)]


## PURE: the boost-side preview (spell wave F2) — the player's own cast improving with tokens.
static func format_preview_boost(base_target: int, interference: int, boost: int) -> String:
	var before := AiSpell.cast_target(0, interference, base_target)
	var after := AiSpell.cast_target(boost, interference, base_target)
	return "Cast roll: %d+ → %d+   (success %d%% → %d%%)" % [before, after,
		roundi(AiSpell.cast_success_chance(0, interference, base_target) * 100.0),
		roundi(AiSpell.cast_success_chance(boost, interference, base_target) * 100.0)]


## Modal ask: returns the number of tokens the player commits (0 = no interference).
func ask(caster_name: String, spell_name: String, target_label: String,
		base_target: int, boost: int, pool: int, mode: String = "interfere") -> int:
	_mode = mode
	_pool = maxi(0, pool)
	_base_target = base_target
	_boost = boost
	_count = 0
	_outcome = []
	layer = 90
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.text = "Enemy spell!" if _mode == "interfere" else "Boost your cast?"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	var info := Label.new()
	info.text = ("%s is casting %s at %s.\nSpell tokens in 18\" line of sight: %d — each spent token gives -1 to the cast roll." % [
		caster_name, spell_name, target_label, _pool]) if _mode == "interfere" else \
		("%s casts %s at %s.\nFriendly spell tokens in 18\" line of sight: %d — each spent token gives +1 to the cast roll." % [
		caster_name, spell_name, target_label, _pool])
	box.add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(44, 36)
	row.add_child(minus)
	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 17)
	row.add_child(_count_label)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(44, 36)
	row.add_child(plus)
	_preview_label = Label.new()
	_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_preview_label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	var ok := Button.new()
	ok.custom_minimum_size = Vector2(180, 36)
	buttons.add_child(ok)
	var no := Button.new()
	no.text = "No interference" if _mode == "interfere" else "No boost"
	no.custom_minimum_size = Vector2(140, 36)
	buttons.add_child(no)
	minus.pressed.connect(func() -> void: _set_count(_count - 1, ok))
	plus.pressed.connect(func() -> void: _set_count(_count + 1, ok))
	ok.pressed.connect(func() -> void: _outcome.append(_count))
	no.pressed.connect(func() -> void: _outcome.append(0))
	_set_count(mini(1, _pool), ok)   # sensible default: 1 token pre-selected when available
	while _outcome.is_empty() and is_inside_tree():
		await get_tree().process_frame
	var result: int = 0 if _outcome.is_empty() else int(_outcome[0])
	queue_free()
	return result


func _set_count(v: int, ok: Button) -> void:
	_count = clampi(v, 0, _pool)
	if _count_label != null:
		_count_label.text = "%d token%s" % [_count, "" if _count == 1 else "s"]
	if _preview_label != null:
		_preview_label.text = format_preview(_base_target, _boost, _count) if _mode == "interfere" \
			else format_preview_boost(_base_target, _boost, _count)
	if ok != null:
		if _mode == "interfere":
			ok.text = "Interfere (-%d)" % _count if _count > 0 else "Confirm (no tokens)"
		else:
			ok.text = "Boost (+%d)" % _count if _count > 0 else "Cast without boost"

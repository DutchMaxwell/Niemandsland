class_name StatePanel
extends VBoxContainer
## Reusable empty / loading / error state for data views (API fetch, downloads, connects)
## so a wait or a blank never reads as a freeze. Tactical styling from HudTokens; centred
## glyph + headline + mono detail + optional action button. Drop it into a content area
## and toggle it against the real content. Loading pulses (honours reduce_motion).

const T := preload("res://scripts/hud/hud_tokens.gd")

signal action_pressed

var _glyph: Label
var _headline: Label
var _detail: Label
var _action: Button
var _pulse: Tween


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", T.SPACE_8)

	_glyph = _centred_label(T.head_font(), 34, T.TEXT_MUTED)
	add_child(_glyph)
	_headline = _centred_label(T.head_font(), 16, T.TEXT)
	add_child(_headline)
	_detail = _centred_label(T.mono_font(), 12, T.TEXT_MUTED)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_detail)

	_action = Button.new()
	_action.theme_type_variation = "PrimaryButton"
	_action.visible = false
	_action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_action.pressed.connect(func() -> void: action_pressed.emit())
	add_child(_action)


func _centred_label(font: FontFile, size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Empty: nothing yet. Optional action button (e.g. "From clipboard").
func show_empty(headline: String, detail: String = "", action_text: String = "") -> void:
	_apply("○", headline, detail, T.TEXT_MUTED, action_text)


## Loading: a wait in progress; the glyph pulses so it never reads as frozen.
func show_loading(headline: String, detail: String = "") -> void:
	_apply("◇", headline, detail, T.CYAN, "")
	_start_pulse()


## Error: something failed; offers a retry action.
func show_error(headline: String, detail: String = "", action_text: String = "") -> void:
	_apply("!", headline, detail, T.DANGER, action_text)


func _apply(glyph: String, headline: String, detail: String, glyph_color: Color, action_text: String) -> void:
	_stop_pulse()
	_glyph.text = glyph
	_glyph.add_theme_color_override("font_color", glyph_color)
	_glyph.modulate.a = 1.0
	_headline.text = headline
	_detail.text = detail
	_detail.visible = detail != ""
	_action.text = action_text
	_action.visible = action_text != ""
	visible = true


func _start_pulse() -> void:
	_stop_pulse()
	if UiMotion.reduced() or not is_inside_tree():
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_glyph, "modulate:a", 0.35, 0.6).set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(_glyph, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)


func _stop_pulse() -> void:
	if _pulse and _pulse.is_valid():
		_pulse.kill()
	_pulse = null

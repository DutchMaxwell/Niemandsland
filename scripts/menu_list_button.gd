class_name MenuListButton
extends Button
## Frameless AAA "list" menu button: left-aligned Orbitron label behind a mono amber
## index ("01", "02", ...), with a vertical cyan accent bar at the left edge that
## scales in while hovered OR focused (keyboard navigation gets the same affordance
## as the mouse). Hover scale + tones come from the global UiFeedback autoload.

# === Constants ===

const ORBITRON_PATH := "res://assets/ui_glassmorphism/fonts/Orbitron.ttf"
const MONO_PATH := "res://assets/ui_glassmorphism/fonts/SourceCodePro.ttf"
const LABEL_SIZE := 17
const INDEX_SIZE := 11
const TEXT_LEFT_PAD := 26.0  # room for the accent bar + index column
const BAR_WIDTH := float(HudTokens.ACCENT_LINE)
const BAR_VPAD := 10.0       # accent bar insets from the button's top/bottom

# === Exports ===

## Mono index shown before the label ("01"). Empty hides the index column.
@export var index_text := "":
	set(value):
		index_text = value
		if _index_label != null:
			_index_label.text = value
## Accent color of the hover/focus bar (DANGER for Exit, AMBER for Continue).
@export var accent_color: Color = HudTokens.CYAN

# === Private variables ===

var _accent_bar: ColorRect = null
var _index_label: Label = null
var _bar_tween: Tween = null

# === Lifecycle ===

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size.y = maxf(custom_minimum_size.y, 52.0)
	flat = true
	# Frameless states; the left content margin indents the label past the accent
	# bar + index column.
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = TEXT_LEFT_PAD
	for state in ["normal", "hover", "pressed", "focus"]:
		add_theme_stylebox_override(state, empty)

	var orbitron := FontVariation.new()
	orbitron.base_font = load(ORBITRON_PATH)
	orbitron.variation_opentype = {"wght": 600}
	add_theme_font_override("font", orbitron)
	add_theme_font_size_override("font_size", LABEL_SIZE)
	add_theme_color_override("font_color", HudTokens.TEXT)
	add_theme_color_override("font_hover_color", Color.WHITE)
	add_theme_color_override("font_focus_color", Color.WHITE)
	add_theme_color_override("font_pressed_color", accent_color)
	_accent_bar = ColorRect.new()
	_accent_bar.color = accent_color
	_accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_accent_bar.scale.y = 0.0
	add_child(_accent_bar)

	_index_label = Label.new()
	var mono := FontVariation.new()
	mono.base_font = load(MONO_PATH)
	_index_label.add_theme_font_override("font", mono)
	_index_label.add_theme_font_size_override("font_size", INDEX_SIZE)
	_index_label.add_theme_color_override("font_color", HudTokens.AMBER)
	_index_label.text = index_text
	_index_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_index_label)

	mouse_entered.connect(_update_accent)
	mouse_exited.connect(_update_accent)
	focus_entered.connect(_update_accent)
	focus_exited.connect(_update_accent)
	resized.connect(_layout_children)
	_layout_children()

# === Private ===

func _layout_children() -> void:
	if _accent_bar == null:
		return
	_accent_bar.position = Vector2(0.0, BAR_VPAD)
	_accent_bar.size = Vector2(BAR_WIDTH, maxf(size.y - BAR_VPAD * 2.0, 0.0))
	_accent_bar.pivot_offset = Vector2(0.0, _accent_bar.size.y / 2.0)
	if _index_label != null:
		_index_label.position = Vector2(BAR_WIDTH + 6.0, (size.y - _index_label.size.y) / 2.0)


func _update_accent() -> void:
	var active := is_hovered() or has_focus()
	if _bar_tween != null and _bar_tween.is_valid():
		_bar_tween.kill()
	_bar_tween = create_tween()
	_bar_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_bar_tween.tween_property(_accent_bar, "scale:y", 1.0 if active else 0.0, HudTokens.DUR_HOVER)

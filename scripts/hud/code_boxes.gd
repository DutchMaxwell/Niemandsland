class_name CodeBoxes
extends Control
## An invitation code as six boxes with a short dash after the third. Underneath is ONE text field (so paste,
## selection and screen input keep working, and the control is one focus stop) whose own text and box are not
## drawn; the boxes, the characters and the box under the caret are drawn over it. `text` is the code without the
## hyphen.

signal changed(code: String)
signal submitted(code: String)

const BOX := Vector2(52, 62)
const GAP := 8
const DASH := 16
const LENGTH := 6

var field: LineEdit
var text: String:
	get:
		return field.text.replace("-", "")


func _init() -> void:
	custom_minimum_size = Vector2(LENGTH * BOX.x + (LENGTH - 1) * GAP + DASH, BOX.y)
	field = LineEdit.new()
	field.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	field.max_length = LENGTH + 1
	field.placeholder_text = "ABC-123"   # not drawn; names the field for screen readers and scripted drivers
	for colour: StringName in [&"font_color", &"caret_color", &"font_placeholder_color", &"selection_color"]:
		field.add_theme_color_override(colour, Color.TRANSPARENT)
	for box: StringName in [&"normal", &"focus", &"read_only"]:
		field.add_theme_stylebox_override(box, StyleBoxEmpty.new())
	field.text_changed.connect(_on_typed)
	field.text_submitted.connect(func(_typed: String) -> void: submitted.emit(text))
	field.focus_entered.connect(queue_redraw)
	field.focus_exited.connect(queue_redraw)
	add_child(field)


func _on_typed(raw: String) -> void:
	var typed := NetDialog.code_as_typed(raw)
	if typed != raw:
		field.text = typed
		field.caret_column = typed.length()
	queue_redraw()
	changed.emit(text)


## The six boxes; the one the next character goes into has the accent rim and a soft accent glow while focused.
func _draw() -> void:
	var font := HouseStyle.mono(500)
	var code := text
	for i in LENGTH:
		var x := i * (BOX.x + GAP) + (DASH + GAP if i >= 3 else 0)
		var rect := Rect2(Vector2(x, 0), BOX)
		var current := field.has_focus() and i == mini(code.length(), LENGTH - 1)
		if current:
			draw_rect(rect.grow(3), Color(HouseStyle.ACCENT, 0.14))
		draw_rect(rect, HouseStyle.WELL)
		draw_rect(rect, HouseStyle.ACCENT if current else HouseStyle.LINE, false, 1.0)
		if i < code.length():
			var at := Vector2(x + BOX.x / 2 - font.get_string_size(code[i], 0, -1, 30).x / 2, BOX.y / 2 + 11)
			draw_string(font, at, code[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, HouseStyle.INK)
	var dash_x := 3 * (BOX.x + GAP)
	draw_line(Vector2(dash_x + 2, BOX.y / 2), Vector2(dash_x + DASH - 2, BOX.y / 2), HouseStyle.MUTED, 2.0)

class_name ArrivalCard
extends PanelContainer
## The small card at the left edge of a new table: FIRST STEPS, "Your table is ready." and three numbered lines.
## The first line that is not done is the current one (ink text, gold ring and number); done lines have the ring
## filled in accent; lines after the current one are muted. Every line can be pressed at any time.
## It knows nothing about the game: TableArrival sets the lines and the progress and answers the two signals.

signal line_pressed(index: int)

const WIDTH := 230
const LINE_H := 34
const RING := 22

var _lines: Array[Button] = []
var _done := 0
var _body: VBoxContainer


func _init() -> void:
	theme = HouseStyle.menu_theme()
	theme_type_variation = HouseStyle.PANEL_VARIANT
	custom_minimum_size.x = WIDTH
	_body = VBoxContainer.new()
	_body.add_theme_constant_override(&"separation", 4)
	add_child(_body)
	_body.add_child(_text("FIRST STEPS", 12, HouseStyle.eyebrow_font(), HouseStyle.ACCENT))
	_body.add_child(_text("Your table is ready.", 18, HouseStyle.font(500), HouseStyle.INK))


func set_lines(texts: Array) -> void:
	for i in texts.size():
		var line := Button.new()
		line.name = "Line%d" % (i + 1)
		line.flat = true
		line.custom_minimum_size.y = LINE_H
		line.pressed.connect(func() -> void: line_pressed.emit(i))
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		row.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_theme_constant_override(&"separation", 10)
		var ring := Control.new()
		ring.custom_minimum_size = Vector2(RING, RING)
		ring.size_flags_vertical = SIZE_SHRINK_CENTER
		ring.draw.connect(_draw_ring.bind(ring, i))
		row.add_child(ring)
		row.add_child(_text(str(texts[i]), 15, HouseStyle.font(400), HouseStyle.MUTED))
		line.add_child(row)
		_body.add_child(line)
		_lines.append(line)
	set_done(_done)


## `count` lines are done; the next one is current.
func set_done(count: int) -> void:
	_done = count
	for i in _lines.size():
		var label := _lines[i].find_children("*", "Label", true, false)[0] as Label
		label.add_theme_color_override(&"font_color", HouseStyle.INK if state(i) == &"now" else HouseStyle.MUTED)
		_lines[i].queue_redraw()
		for ring: Control in _lines[i].find_children("*", "Control", true, false):
			ring.queue_redraw()


func state(index: int) -> StringName:
	return &"done" if index < _done else (&"now" if index == _done else &"next")


func _draw_ring(ring: Control, index: int) -> void:
	var centre := Vector2(RING, RING) / 2
	if state(index) == &"done":
		ring.draw_circle(centre, RING / 2.0, HouseStyle.ACCENT)
		return
	var colour := HouseStyle.GOLD if state(index) == &"now" else HouseStyle.LINE
	ring.draw_arc(centre, RING / 2.0 - 1, 0, TAU, 32, colour, 1.5, true)
	var digit := str(index + 1)
	var font := HouseStyle.mono()
	var at := centre + Vector2(-font.get_string_size(digit, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x / 2, 4)
	ring.draw_string(font, at, digit, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		HouseStyle.GOLD if state(index) == &"now" else HouseStyle.MUTED)


func _text(text: String, font_size: int, font: Font, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_font_override(&"font", font)
	label.add_theme_color_override(&"font_color", colour)
	return label

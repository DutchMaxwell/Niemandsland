class_name ArrivalCard
extends PanelContainer
## The small card at the left edge of a new table: FIRST STEPS, "Your table is ready." and three numbered lines.
## The first line that is not done is the current one (ink text, gold ring and number); done lines have the ring
## filled in accent with a dark tick; lines after the current one are muted. Every line can be pressed at any time.
## It knows nothing about the game: TableArrival sets the lines and the progress and answers the two signals.

signal line_pressed(index: int)
signal dismissed

const WIDTH := 230
const LINE_H := 34
const RING := 22
const TICK := [Vector2(6.5, 11.5), Vector2(9.5, 14.5), Vector2(15.5, 8.0)]

var _lines: Array[Button] = []
var _flags: Array = []   # per line: done
var _body: VBoxContainer


func _init() -> void:
	theme = HouseStyle.menu_theme()
	theme_type_variation = HouseStyle.PANEL_VARIANT
	custom_minimum_size.x = WIDTH
	_body = VBoxContainer.new()
	_body.add_theme_constant_override(&"separation", 4)
	add_child(_body)
	var head := HBoxContainer.new()
	var kicker := _text("FIRST STEPS", 12, HouseStyle.eyebrow_font(), HouseStyle.ACCENT)
	kicker.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(kicker)
	var close := HouseStyle.button(HouseStyle.GLYPH_CLOSE, HouseStyle.ICON, 24)
	close.name = "CloseButton"
	close.custom_minimum_size.x = 24
	close.size_flags_horizontal = SIZE_SHRINK_END
	close.tooltip_text = "Close"
	close.pressed.connect(func() -> void: dismissed.emit())
	head.add_child(close)
	_body.add_child(head)
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
	set_flags(_flags)


## The first `count` lines are done.
func set_done(count: int) -> void:
	set_flags(range(maxi(count, _lines.size())).map(func(i: int) -> bool: return i < count))


## Each line is done by its own flag (NACHTMAHR's army may stand before the player's); the first line not done is
## the current one, the rest are next.
func set_flags(done: Array) -> void:
	_flags = done
	for i in _lines.size():
		var label := _lines[i].find_children("*", "Label", true, false)[0] as Label
		label.add_theme_color_override(&"font_color", HouseStyle.INK if state(i) == &"now" else HouseStyle.MUTED)
		_lines[i].queue_redraw()
		for ring: Control in _lines[i].find_children("*", "Control", true, false):
			ring.queue_redraw()


func state(index: int) -> StringName:
	if _is_done(index):
		return &"done"
	for i in index:
		if not _is_done(i):
			return &"next"
	return &"now"


func _is_done(index: int) -> bool:
	return index < _flags.size() and bool(_flags[index])


func _draw_ring(ring: Control, index: int) -> void:
	var centre := Vector2(RING, RING) / 2
	match state(index):
		&"done":
			ring.draw_circle(centre, RING / 2.0, HouseStyle.ACCENT, true, -1.0, true)
			ring.draw_polyline(PackedVector2Array(TICK), HouseStyle.ON_GOLD, 2.0, true)
		_:
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

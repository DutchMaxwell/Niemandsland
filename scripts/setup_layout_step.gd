class_name SetupLayoutStep
extends Control
## Step 04 of the table setup, "Lay out the table" (the setup's second state): steps 01-03 folded into rows with
## their values and "Change", and the heading of step 04.

signal change_requested(step: int)

const STEPS := ["Game system", "Biome", "Table size"]
const TICK := "<path d='M5 12.5l4.5 4.5L19 7.5'/>"
const MenuView = preload("res://scripts/startup_menu_view.gd")

var left: VBoxContainer
var _layout: SetupLayout


func setup(layout: SetupLayout, values: Array) -> void:
	_layout = layout
	theme = HouseStyle.menu_theme()
	left = VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 8)
	left.position = Vector2(76, 232)   # under the setup's own title, as drawn at 1920 x 1080
	left.custom_minimum_size.x = 1040
	add_child(left)
	for i in STEPS.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 12)
		row.add_child(_text("%02d" % (i + 1), 16, HouseStyle.mono(), HouseStyle.OK))
		var tick := TextureRect.new()   # drawn, not a glyph: the mono font's coverage of U+2713 is not proven
		tick.texture = HouseStyle.svg_icon(MenuView.ICON_SVG % TICK)
		tick.custom_minimum_size = Vector2(14, 14)
		tick.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tick.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tick.modulate = HouseStyle.OK
		row.add_child(tick)
		var name_label := _text(STEPS[i], 18, HouseStyle.font(400), HouseStyle.MUTED)
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(_text(str(values[i]), 18, HouseStyle.font(400), HouseStyle.INK))
		var change := HouseStyle.button("Change", HouseStyle.BUTTON, 36)
		change.name = "Change%d" % (i + 1)
		change.flat = true
		change.focus_mode = FOCUS_ALL
		change.size_flags_horizontal = SIZE_SHRINK_END
		change.add_theme_color_override(&"font_color", HouseStyle.ACCENT)
		change.pressed.connect(func() -> void: change_requested.emit(i + 1))
		row.add_child(change)
		var folded := HouseStyle.card(row)
		folded.custom_minimum_size.y = 52
		left.add_child(folded)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 12)
	head.custom_minimum_size.y = 72   # air above the heading, as drawn
	head.add_child(_text("04", 16, HouseStyle.mono(), HouseStyle.GOLD))
	var heading := _text("Lay out the table", 22, HouseStyle.font(500), HouseStyle.INK)
	heading.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(heading)
	head.add_child(_text("Terrain can still be moved at the table.", 15, HouseStyle.font(400), HouseStyle.MUTED))
	left.add_child(head)


func _text(text: String, font_size: int, font: Font, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_font_override(&"font", font)
	label.add_theme_color_override(&"font_color", colour)
	return label

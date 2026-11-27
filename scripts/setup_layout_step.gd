class_name SetupLayoutStep
extends Control
## Step 04 of the table setup, "Lay out the table" (the setup's second state): steps 01-03 folded into rows with
## their values and "Change", the heading, and the four ways as cards bound to a SetupLayout.

signal change_requested(step: int)
signal create_requested

const WAYS := [
	["empty", "Empty table", "Place terrain yourself once you are at the table.", &"table"],
	["generated", "Auto-Generate Layout", "A balanced layout for this table size. Generate again until you like it.", &"table"],
	["theme", "Ruined Borderland", "", &"table"],
	["file", "Load a layout", "Open a layout file you saved in the layout editor.", &"folder"]]
const STEPS := ["Game system", "Biome", "Table size"]
const CROSS := "<path d='M7 7l10 10M17 7L7 17'/>"
const DEPLOYMENT := ["", " · Front Line (12\")", " · Custom Zones"]
const TICK := "<path d='M5 12.5l4.5 4.5L19 7.5'/>"
const MenuView = preload("res://scripts/startup_menu_view.gd")

var left: VBoxContainer
var _layout: SetupLayout
var _cards: Dictionary = {}
var _note: Label
var _file: FileDialog
var _legend: HBoxContainer
var _facts: Label
var _lines: VBoxContainer
var _layout_row: Label


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
	var ways := HBoxContainer.new()
	ways.add_theme_constant_override(&"separation", 12)
	left.add_child(ways)
	var theme_info := TableTheme.load_theme(SetupLayout.THEME_ID)
	for way: Array in WAYS:
		var caption: String = way[2] if way[0] != "theme" else "A ready-made table: %s, %d pieces." % [
			theme_info.mood.to_lower(), theme_info.pieces.size()]
		ways.add_child(_way_card(way[0], way[1], caption, way[3]))
	_note = _text("", 15, HouseStyle.font(400), HouseStyle.WARN)
	left.add_child(_note)
	_file = FileDialog.new()
	_file.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file.access = FileDialog.ACCESS_FILESYSTEM
	_file.filters = PackedStringArray(["*.json ; Layout files"])
	_file.title = "Load Terrain Layout"
	_file.file_selected.connect(func(path: String) -> void: _note.text = _layout.load_file(path))
	add_child(_file)
	_build_rail(values)
	_layout.changed.connect(_refresh)
	_refresh()


## The rail: the picture, the legend with counts, the facts line, the editor's first two guideline lines (ways
## generated and file only), what the table will be, and Create table.
func _build_rail(values: Array) -> void:
	var rail := PanelContainer.new()
	rail.name = "Rail"
	rail.theme_type_variation = HouseStyle.PANEL_VARIANT
	rail.position = Vector2(1160, 108)
	rail.custom_minimum_size.x = 684
	add_child(rail)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	rail.add_child(box)
	var picture := LayoutPreview.new()
	picture.custom_minimum_size.y = 456
	picture.show_layout(_layout)
	box.add_child(picture)
	_legend = HBoxContainer.new()
	_legend.add_theme_constant_override(&"separation", 18)
	box.add_child(_legend)
	_facts = _text("", 14, HouseStyle.mono(), HouseStyle.MUTED)
	box.add_child(_facts)
	_lines = VBoxContainer.new()
	box.add_child(_lines)
	for row: Array in [["SYSTEM", values[0]], ["BIOME · SIZE", "%s · %s" % [values[1], values[2]]], ["LAYOUT", ""]]:
		var line := HBoxContainer.new()
		var key := _text(row[0], 14, HouseStyle.eyebrow_font(), HouseStyle.MUTED)
		key.size_flags_horizontal = SIZE_EXPAND_FILL
		line.add_child(key)
		var value := _text(str(row[1]), 18, HouseStyle.font(400), HouseStyle.INK)
		line.add_child(value)
		box.add_child(line)
		_layout_row = value
	var create := HouseStyle.button("Create table", HouseStyle.PRIMARY, 56)
	create.name = "CreateTable"
	create.focus_mode = FOCUS_ALL
	create.alignment = HORIZONTAL_ALIGNMENT_LEFT
	create.pressed.connect(func() -> void: create_requested.emit())
	var cap := HouseStyle.key_cap_on_gold("Enter")
	cap.set_anchors_preset(PRESET_CENTER_RIGHT)
	cap.grow_horizontal = GROW_DIRECTION_BEGIN
	cap.offset_left = -16
	cap.offset_right = -16
	create.add_child(cap)
	box.add_child(create)


func _refresh_rail() -> void:
	var facts := _layout.facts()
	for child: Node in _legend.get_children() + _lines.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()
	for type: int in facts.pieces_by_type:
		var name_label := _text("%s %d" % [_layout.editor.TERRAIN_NAMES[type], facts.pieces_by_type[type]], 15,
			HouseStyle.font(400), HouseStyle.INK)
		var swatch := ColorRect.new()
		swatch.color = Color(_layout.editor.TERRAIN_COLORS[type], 1.0)
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = SIZE_SHRINK_CENTER
		_legend.add_child(swatch)
		_legend.add_child(name_label)
	_facts.text = "%d PIECES · COVERAGE %.1f %%" % [facts.pieces, facts.coverage_pct]
	if _layout.way in ["generated", "file"]:
		for line: Dictionary in (facts.lines as Array).slice(0, 2):
			var row := HBoxContainer.new()
			var mark := TextureRect.new()
			mark.texture = HouseStyle.svg_icon(MenuView.ICON_SVG % (TICK if line.ok else CROSS))
			mark.custom_minimum_size = Vector2(14, 14)
			mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			mark.modulate = HouseStyle.OK if line.ok else HouseStyle.WARN
			row.add_child(mark)
			row.add_child(_text(str(line.text), 15, HouseStyle.font(400), HouseStyle.OK if line.ok else HouseStyle.WARN))
			_lines.add_child(row)
	_layout_row.text = _layout.label() + DEPLOYMENT[_layout.editor.deployment_type]


func _way_card(way: String, title: String, caption: String, icon: StringName) -> Button:
	var card := Button.new()
	card.name = "Way_" + way
	card.custom_minimum_size = Vector2(0, 196)
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	card.focus_mode = FOCUS_ALL
	card.pressed.connect(func() -> void:
		if way == "file":
			_file.popup_centered_ratio(0.6)
		else:
			_layout.choose(way))
	var words := VBoxContainer.new()
	words.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_MINSIZE, 18)
	words.mouse_filter = MOUSE_FILTER_IGNORE
	var mark := TextureRect.new()
	mark.texture = MenuView._icon(icon)
	mark.custom_minimum_size = Vector2(28, 28)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	mark.modulate = HouseStyle.ACCENT
	words.add_child(mark)
	words.add_child(_text(title, 20, HouseStyle.font(500), HouseStyle.INK))
	var line := _text(caption, 15, HouseStyle.font(400), HouseStyle.MUTED)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD
	words.add_child(line)
	if way == "theme":
		words.add_child(_text("NEEDS 6 × 4 FT", 13, HouseStyle.mono(), HouseStyle.MUTED))
	card.add_child(words)
	_cards[way] = card
	return card


## The chosen way has the lighter fill and the 2 px gold rim; the ready-made table is off off 6 x 4 ft.
func _refresh() -> void:
	_refresh_rail()
	_note.text = _layout.note if not _layout.note.is_empty() else _note.text
	for way: String in _cards:
		var card: Button = _cards[way]
		var on := way == _layout.way
		card.set_meta("chosen", on)
		card.disabled = way == "theme" and not TableTheme.load_theme(SetupLayout.THEME_ID).fits(_layout.editor.table_size_feet)
		if on:
			var rim := HouseStyle.menu_theme().get_stylebox(&"normal", &"Button").duplicate() as StyleBoxFlat
			rim.bg_color = HouseStyle.ROW_HOVER
			rim.border_color = HouseStyle.GOLD
			rim.set_border_width_all(2)
			card.add_theme_stylebox_override(&"normal", rim)
		else:
			card.remove_theme_stylebox_override(&"normal")


func _text(text: String, font_size: int, font: Font, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_font_override(&"font", font)
	label.add_theme_color_override(&"font_color", colour)
	return label

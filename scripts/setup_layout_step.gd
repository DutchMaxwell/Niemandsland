class_name SetupLayoutStep
extends Control
## Step 05 of the table setup, "Lay out the table" (the setup's second state): steps 01-04 folded into rows with
## their values and "Change", the heading, and the four ways as cards bound to a SetupLayout.

signal change_requested(step: int)
signal create_requested

const WAYS := [
	["empty", "Empty table", "Place terrain yourself once you are at the table.", &"table"],
	["generated", "Auto-Generate Layout", "A balanced layout for this table size. Generate again until you like it.", &"table"],
	["theme", "Ruined Borderland", "", &"table"],
	["file", "Load a layout", "Open a layout file you saved in the layout editor.", &"folder"]]
const STEPS := ["Game system", "Biome", "Table size", "Opponent"]
const REFRESH := "<path d='M20 12a8 8 0 1 1-2.3-5.6M20 4v4.5h-4.5'/>"
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
var _again: Button
var _mirror: CheckButton
var _zones: Array[Button] = []
var _rail: PanelContainer
var _picture: LayoutPreview
var _keys: HBoxContainer
var _folded: Array[Control] = []
var _head: HBoxContainer
var _objectives: Label


func setup(layout: SetupLayout, values: Array) -> void:
	_layout = layout
	theme = HouseStyle.menu_theme()
	left = VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 8)
	add_child(left)
	for i in STEPS.size():
		var folded := folded_row(i + 1, STEPS[i], str(values[i]), change_requested.emit.bind(i + 1))
		left.add_child(folded)
		_folded.append(folded)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 12)
	_head = head
	head.add_child(_text("05", 16, HouseStyle.mono(), HouseStyle.GOLD))
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
	left.add_child(_tools())
	left.add_child(_zones_and_objectives())
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
	var keys := HBoxContainer.new()   # the key legend at the foot of the page
	_keys = keys
	keys.add_theme_constant_override(&"separation", 8)
	for pair: Array in [["Tab", "next step"], ["← →", "choose"], ["G", "generate again"], ["Enter", "create table"],
			["Esc", "back"]]:
		keys.add_child(HouseStyle.key_cap(pair[0]))
		keys.add_child(_text(pair[1], 15, HouseStyle.font(400), HouseStyle.MUTED))
	add_child(keys)
	resized.connect(_place)
	_place()
	_refresh()


## The page's measures: as drawn at 1920 x 1080; below 800 px of height the compact ones, so a 1280 x 720 window
## shows all of state two without scrolling (rows 38, way cards 112 without captions, the picture as high as the
## space leaves, at least 200).
func _place() -> void:
	var compact := size.y < 800
	var pad := 28.0 if compact else maxf(28.0, size.x * 0.04)
	var rail_w := 504.0 if compact else minf(684.0, size.x * 0.36)
	_rail.custom_minimum_size.x = rail_w
	_rail.position = Vector2(size.x - pad - rail_w, 100.0 if compact else 108.0)
	_picture.custom_minimum_size.y = maxf(200.0, size.y - 460.0) if compact else 456.0   # the rest of the rail ~340
	left.position = Vector2(pad, 120.0 if compact else 232.0)   # under the setup's own title
	left.custom_minimum_size.x = size.x - 2 * pad - rail_w - (24.0 if compact else 44.0)
	for row in _folded:   # four folded rows: below 800 px they lose their padding to stay 38 px (the Change button's 36)
		row.custom_minimum_size.y = 38 if compact else 52
		row.remove_theme_stylebox_override(&"panel")
		if compact:
			var tight := row.get_theme_stylebox(&"panel").duplicate() as StyleBox
			tight.content_margin_top = 1
			tight.content_margin_bottom = 1
			row.add_theme_stylebox_override(&"panel", tight)
	_head.custom_minimum_size.y = 40 if compact else 72
	for card: Button in _cards.values():
		card.custom_minimum_size.y = 128 if compact else 196
		(card.get_child(0).get_child(1) as Label).add_theme_font_size_override(&"font_size", 16 if compact else 20)
		(card.get_child(0).get_child(2) as Control).visible = not compact   # the caption
	_legend.add_theme_constant_override(&"separation", 8 if compact else 18)
	_keys.position = Vector2(pad, size.y - (44.0 if compact else 60.0))
	for box: Control in [left, _rail]:   # a container keeps its old height: shrink both to their new content
		box.reset_size.call_deferred()


## The tools card: Generate again and the mirror (the generated way only), and the layout editor.
func _tools() -> PanelContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	_again = HouseStyle.button("Generate again", HouseStyle.BUTTON, HouseStyle.MENU_H_ACTION)
	_again.name = "GenerateAgain"
	_again.icon = HouseStyle.svg_icon(MenuView.ICON_SVG % REFRESH)
	_again.add_theme_constant_override(&"icon_max_width", 16)
	_again.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_again.pressed.connect(_layout.generate)
	row.add_child(_again)
	_mirror = CheckButton.new()
	_mirror.name = "Mirror"
	_mirror.text = "Point Symmetry (Mirror)"
	_mirror.toggled.connect(_layout.set_mirror)
	row.add_child(_mirror)
	var air := Control.new()
	air.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(air)
	var edit := HouseStyle.button("Edit in the layout editor", HouseStyle.BUTTON, HouseStyle.MENU_H_ACTION)
	edit.name = "EditInEditor"
	edit.icon = MenuView._icon(&"go")
	edit.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	edit.add_theme_constant_override(&"icon_max_width", 14)
	edit.size_flags_horizontal = SIZE_SHRINK_END
	edit.pressed.connect(_layout.open_editor)
	row.add_child(edit)
	for b: BaseButton in [_again, _mirror, edit]:
		b.focus_mode = FOCUS_ALL
	return HouseStyle.card(row)


## DEPLOYMENT ZONES (the editor's own three types; Custom Zones opens its Deployment tab) and MISSION OBJECTIVES
## (the count, and Deploy Objectives, which opens the editor in its objectives mode).
func _zones_and_objectives() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var zones := VBoxContainer.new()
	zones.add_child(_text("DEPLOYMENT ZONES", 14, HouseStyle.eyebrow_font(), HouseStyle.MUTED))
	var segments := HouseStyle.button_row(["None", "Front Line (12\")", "Custom Zones"], HouseStyle.SEGMENT, 40)
	for i in 3:
		var segment := segments.get_child(i) as Button
		segment.name = ["ZoneNone", "ZoneFrontLine", "ZoneCustom"][i]
		segment.focus_mode = FOCUS_ALL
		segment.pressed.connect(func() -> void:
			_layout.set_deployment(i)
			if i == 2:
				_layout.open_editor("deployment"))
		_zones.append(segment)
	zones.add_child(segments)
	var aims := VBoxContainer.new()
	aims.add_child(_text("MISSION OBJECTIVES", 14, HouseStyle.eyebrow_font(), HouseStyle.MUTED))
	var line := HBoxContainer.new()
	_objectives = _text("", 15, HouseStyle.font(400), HouseStyle.MUTED)
	_objectives.size_flags_horizontal = SIZE_EXPAND_FILL
	line.add_child(_objectives)
	var deploy := HouseStyle.button("Deploy Objectives", HouseStyle.BUTTON, 40)
	deploy.name = "DeployObjectives"
	deploy.focus_mode = FOCUS_ALL
	deploy.size_flags_horizontal = SIZE_SHRINK_END
	deploy.pressed.connect(_layout.open_editor.bind("objectives"))
	line.add_child(deploy)
	aims.add_child(line)
	for part: VBoxContainer in [zones, aims]:
		var card := HouseStyle.card(part)
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(card)
	return row


## G generates again while the generated way is chosen and no text field has the focus.
func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_G and not _again.disabled \
			and not get_viewport().gui_get_focus_owner() is LineEdit:
		get_viewport().set_input_as_handled()
		_layout.generate()


## The rail: the picture, the legend with counts, the facts line, the editor's first two guideline lines (ways
## generated and file only), what the table will be, and Create table.
func _build_rail(values: Array) -> void:
	var rail := PanelContainer.new()
	_rail = rail
	rail.name = "Rail"
	rail.theme_type_variation = HouseStyle.PANEL_VARIANT
	add_child(rail)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	rail.add_child(box)
	var picture := LayoutPreview.new()
	_picture = picture
	picture.show_layout(_layout)
	box.add_child(picture)
	_legend = HBoxContainer.new()
	_legend.add_theme_constant_override(&"separation", 18)
	box.add_child(_legend)
	_facts = _text("", 14, HouseStyle.mono(), HouseStyle.MUTED)
	box.add_child(_facts)
	_lines = VBoxContainer.new()
	box.add_child(_lines)
	for row: Array in [["SYSTEM", values[0]], ["BIOME · SIZE", "%s · %s" % [values[1], values[2]]],
			["OPPONENT", values[3]], ["LAYOUT", ""]]:
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
	var name_label := _text(title, 20, HouseStyle.font(500), HouseStyle.INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	words.add_child(name_label)
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
	_again.disabled = _layout.way != "generated"
	_mirror.visible = _layout.way == "generated"
	for i in _zones.size():
		HouseStyle.set_selected(_zones[i], i == _layout.editor.deployment_type)
	var count: int = _layout.editor.mission_objectives.size()
	_objectives.text = "No objectives placed" if count == 0 else "%d objective%s placed" % [count, "" if count == 1 else "s"]
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


## A folded step row of the setup: "01 ✓" in mono, the step's name muted, its value, "Change" (`Change<index>`)
## in accent calling `on_change`. Shared by the layout page and the opponent page.
static func folded_row(index: int, step_name: String, value: String, on_change: Callable) -> PanelContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	row.add_child(_text("%02d" % index, 16, HouseStyle.mono(), HouseStyle.OK))
	var tick := TextureRect.new()   # drawn, not a glyph: the mono font's coverage of U+2713 is not proven
	tick.texture = HouseStyle.svg_icon(MenuView.ICON_SVG % TICK)
	tick.custom_minimum_size = Vector2(14, 14)
	tick.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tick.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tick.modulate = HouseStyle.OK
	row.add_child(tick)
	var name_label := _text(step_name, 18, HouseStyle.font(400), HouseStyle.MUTED)
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(_text(value, 18, HouseStyle.font(400), HouseStyle.INK))
	var change := HouseStyle.button("Change", HouseStyle.BUTTON, 36)
	change.name = "Change%d" % index
	change.flat = true
	change.focus_mode = FOCUS_ALL
	change.size_flags_horizontal = SIZE_SHRINK_END
	change.add_theme_color_override(&"font_color", HouseStyle.ACCENT)
	change.pressed.connect(func() -> void: on_change.call())
	row.add_child(change)
	return HouseStyle.card(row)


static func _text(text: String, font_size: int, font: Font, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_font_override(&"font", font)
	label.add_theme_color_override(&"font_color", colour)
	return label

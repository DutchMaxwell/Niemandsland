class_name SetupOpponentStep
extends Control
## Step 04 of the table setup, "Who is at the table?" (sheet 03b): steps 01-03 folded into rows, the heading and
## three cards - Solo against NACHTMAHR, two players on one screen, an online room - bound to a SetupOpponent.

signal change_requested(step: int)
signal layout_requested
signal create_requested

const WHO := [
	["solo", "Solo against NACHTMAHR", "The computer opponent builds its own list and plays by the rules.",
		"<path d='M12 3l7 3v5.5c0 4.4-3 7.7-7 9.5-4-1.8-7-5.1-7-9.5V6z'/><path d='M9 11.5l2 2 4-4.5'/>"],
	["local", "Two players, one screen", "Share this computer and take turns like at a real table.",
		"<circle cx='9' cy='8.5' r='3.2'/><path d='M3 19c.6-3.2 3-5 6-5s5.4 1.8 6 5M16 5.6a3.2 3.2 0 0 1 0 5.8M18 14.4c1.7.7 2.7 2.3 3 4.6'/>"],
	["online", "Online room", "Create a room for your group and share the invitation code.",
		"<circle cx='12' cy='12' r='9'/><path d='M3 12h18M12 3c3 3.2 3 14.8 0 18M12 3c-3 3.2-3 14.8 0 18'/>"]]
const MenuView = preload("res://scripts/startup_menu_view.gd")
## At the table (table_mode) the rail's button says what it does for the chosen card.
const TABLE_ACTIONS := {"solo": "Bring NACHTMAHR", "local": "Bring the second army", "online": "Host an online room"}

var left: VBoxContainer
var _opponent: SetupOpponent
var _cards: Dictionary = {}
var _head: HBoxContainer
var _solo: PanelContainer
var _off: Label
var _faction: OptionButton
var _points: OptionButton
var _seat: OptionButton
var _rail: PanelContainer
var _opponent_row: Label
var _layout_row: Button
var _keys: HBoxContainer
var _enter_key: Label   # the legend's word for Enter: "create table", at the table the rail button's action
var _create: Button
var _next: Label
var table_mode := false   # set before setup: the page opened at the table (rows read-only, no step 05)
var human_seats: Array = []   # set before setup: seats a connected human holds (#196: never NACHTMAHR's)


func setup(opponent: SetupOpponent, values: Array) -> void:
	_opponent = opponent
	theme = HouseStyle.menu_theme()
	left = VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 8)
	add_child(left)
	for i in 3:   # steps 01-03 (the layout page also folds this step, 04)
		left.add_child(SetupLayoutStep.folded_row(i + 1, SetupLayoutStep.STEPS[i], str(values[i]),
			change_requested.emit.bind(i + 1)))
	var head := HBoxContainer.new()
	_head = head
	head.add_theme_constant_override(&"separation", 12)
	head.add_child(SetupLayoutStep._text("04", 16, HouseStyle.mono(), HouseStyle.GOLD))
	head.add_child(SetupLayoutStep._text("Who is at the table?", 22, HouseStyle.font(500), HouseStyle.INK))
	left.add_child(head)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override(&"separation", 12)
	left.add_child(cards)
	for entry: Array in WHO:
		cards.add_child(_who_card(entry[0], entry[1], entry[2], entry[3]))
	_solo = _solo_card()
	var air := Control.new()   # 12 px between the cards and the Solo fields (sheet 03b), on top of the column's 8
	air.custom_minimum_size.y = 4
	air.visible = false
	_solo.visibility_changed.connect(func() -> void: air.visible = _solo.visible)
	left.add_child(air)
	left.add_child(_solo)
	_off = SetupLayoutStep._text("", 15, HouseStyle.font(400), HouseStyle.MUTED)
	left.add_child(_off)
	left.add_child(_layout_link(str(values[3]) if values.size() > 3 else ""))
	_build_rail(values)
	if table_mode:
		_layout_row.visible = false
		_next.visible = false
		for change: Node in left.find_children("Change*", "Button", true, false):
			(change as Control).visible = false
		if human_seats.has(_opponent.seat):
			_opponent.choose_seat(3 - _opponent.seat)
	_keys = HBoxContainer.new()   # the key legend at the foot of the page, as state one
	_keys.add_theme_constant_override(&"separation", 8)
	for pair: Array in [["Tab", "next step"], ["← →", "choose"], ["Enter", "create table"],
			["Esc", "back to the table" if table_mode else "back"]]:
		_keys.add_child(HouseStyle.key_cap(pair[0]))
		_keys.add_child(SetupLayoutStep._text(pair[1], 15, HouseStyle.font(400), HouseStyle.MUTED))
	_enter_key = _keys.get_child(5) as Label
	add_child(_keys)
	_opponent.changed.connect(_refresh)
	resized.connect(_place)
	_place()
	_refresh()


## The layout page's measures: as drawn at 1920 x 1080; below 800 px of height rows of 38 and cards of 96 without
## captions, so a 1280 x 720 window shows the page without scrolling.
func _place() -> void:
	var compact := size.y < 800
	var pad := maxf(28.0, size.x * 0.04)   # the setup's own margin, so the rows stand under its title (720p too)
	var rail_w := 504.0 if compact else minf(684.0, size.x * 0.36)
	_rail.custom_minimum_size.x = rail_w
	_rail.position = Vector2(size.x - pad - rail_w, 100.0 if compact else 232.0)   # level with row 01 (sheet 03b)
	left.position = Vector2(pad, 120.0 if compact else 232.0)
	left.custom_minimum_size.x = size.x - 2 * pad - rail_w - (24.0 if compact else 44.0)
	for row: Control in left.get_children().slice(0, 3) + [_layout_row]:
		row.custom_minimum_size.y = 38 if compact else 52
		if row is PanelContainer:   # as the layout page: the folded rows lose their padding to stay 38 px
			row.remove_theme_stylebox_override(&"panel")
			if compact:
				var tight := row.get_theme_stylebox(&"panel").duplicate() as StyleBox
				tight.content_margin_top = 1
				tight.content_margin_bottom = 1
				row.add_theme_stylebox_override(&"panel", tight)
	_head.custom_minimum_size.y = 40 if compact else 72
	for card: Button in _cards.values():
		card.custom_minimum_size.y = 96 if compact else 132
		(card.get_child(0).get_child(1) as Label).add_theme_font_size_override(&"font_size", 16 if compact else 20)
		(card.get_child(0).get_child(2) as Control).visible = not compact   # the caption
	SetupLayoutStep.fit_rail_lines(_rail, compact)
	_keys.position = Vector2(pad, size.y - (44.0 if compact else 60.0))
	for box: Control in [left, _rail]:
		box.reset_size.call_deferred()


## Step 05 under the cards, in the look of a folded row: "05", its name, the chosen way, Change.
func _layout_link(way: String) -> Button:
	_layout_row = Button.new()
	_layout_row.name = "LayoutRow"
	_layout_row.focus_mode = FOCUS_ALL
	_layout_row.pressed.connect(func() -> void: layout_requested.emit())
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	line.offset_left = 14
	line.offset_right = -14
	line.add_theme_constant_override(&"separation", 12)
	line.mouse_filter = MOUSE_FILTER_IGNORE
	line.add_child(SetupLayoutStep._text("05", 16, HouseStyle.mono(), HouseStyle.GOLD))
	var name_label := SetupLayoutStep._text("Lay out the table", 18, HouseStyle.font(400), HouseStyle.MUTED)
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	line.add_child(name_label)
	line.add_child(SetupLayoutStep._text(way, 18, HouseStyle.font(400), HouseStyle.INK))
	line.add_child(SetupLayoutStep._text("Change", 16, HouseStyle.font(400), HouseStyle.ACCENT))
	for label: Label in line.get_children():
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_layout_row.add_child(line)
	return _layout_row


## The rail YOUR TABLE: SYSTEM, BIOME, SIZE, OPPONENT (it follows the model), Create table, what comes next.
func _build_rail(values: Array) -> void:
	_rail = PanelContainer.new()
	_rail.name = "Rail"
	_rail.theme_type_variation = HouseStyle.PANEL_VARIANT
	add_child(_rail)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	_rail.add_child(box)
	box.add_child(SetupLayoutStep._text("YOUR TABLE", 14, HouseStyle.eyebrow_font(), HouseStyle.MUTED))
	for row: Array in [["SYSTEM", values[0]], ["BIOME", values[1]], ["SIZE", values[2]], ["OPPONENT", ""]]:
		_opponent_row = SetupLayoutStep._text(str(row[1]), 18, HouseStyle.font(400), HouseStyle.INK)
		box.add_child(SetupLayoutStep.rail_line(row[0], _opponent_row))
	var create := HouseStyle.button("Create table", HouseStyle.PRIMARY, 56)
	_create = create
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
	var next := SetupLayoutStep._text("Next at the table: bring your own army, then deploy.", 15, HouseStyle.font(400),
		HouseStyle.MUTED)
	next.autowrap_mode = TextServer.AUTOWRAP_WORD
	_next = next
	box.add_child(next)


func _who_card(id: String, title: String, caption: String, icon: String) -> Button:
	var card := Button.new()
	card.name = "Who_" + id
	card.custom_minimum_size = Vector2(0, 132)
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	card.focus_mode = FOCUS_ALL
	card.pressed.connect(func() -> void: _opponent.choose_who(id))
	var words := VBoxContainer.new()
	words.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_MINSIZE, 18)
	words.mouse_filter = MOUSE_FILTER_IGNORE
	var mark := TextureRect.new()
	mark.texture = HouseStyle.svg_icon(MenuView.ICON_SVG % icon)
	mark.custom_minimum_size = Vector2(28, 28)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	mark.modulate = HouseStyle.ACCENT
	words.add_child(mark)
	var name_label := SetupLayoutStep._text(title, 20, HouseStyle.font(500), HouseStyle.INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	words.add_child(name_label)
	var line := SetupLayoutStep._text(caption, 15, HouseStyle.font(400), HouseStyle.MUTED)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD
	words.add_child(line)
	card.add_child(words)
	_cards[id] = card
	return card


## NACHTMAHR's list: three equal columns, FACTION / POINTS / AI PLAYS AS, each an eyebrow over a dropdown.
func _solo_card() -> PanelContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	_faction = _field(row, "FACTION", "Faction")
	_faction.item_selected.connect(func(i: int) -> void: _opponent.choose_faction(_faction.get_item_metadata(i)))
	_points = _field(row, "POINTS", "Points")
	_points.item_selected.connect(_opponent.choose_bracket)
	_seat = _field(row, "AI PLAYS AS", "Seat")
	_seat.add_item("Player 2 (Red)", 2)
	_seat.add_item("Player 1 (Blue)", 1)
	for i in _seat.item_count:   # #196: a seat a connected human holds is not on offer
		if human_seats.has(_seat.get_item_id(i)):
			_seat.set_item_disabled(i, true)
			_seat.set_item_text(i, _seat.get_item_text(i) + " — human player")
	_seat.item_selected.connect(func(i: int) -> void: _opponent.choose_seat(_seat.get_item_id(i)))
	return HouseStyle.card(row)


func _field(row: HBoxContainer, eyebrow: String, field_name: String) -> OptionButton:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 8)
	column.add_child(SetupLayoutStep._text(eyebrow, 14, HouseStyle.eyebrow_font(), HouseStyle.MUTED))
	var pick := OptionButton.new()
	pick.name = field_name
	pick.theme_type_variation = HouseStyle.BUTTON
	pick.custom_minimum_size.y = 44
	column.add_child(pick)
	row.add_child(column)
	return pick


## The dropdowns follow the model: the system's factions, the chosen faction's brackets, the seat.
func _refresh_solo() -> void:
	_solo.visible = _opponent.who == "solo"
	_off.text = _opponent.off_line()
	_off.visible = not _off.text.is_empty()
	_faction.clear()
	for f: Array in _opponent.factions():
		_faction.add_item(f[1])
		_faction.set_item_metadata(_faction.item_count - 1, f[0])
		if f[0] == _opponent.faction:
			_faction.select(_faction.item_count - 1)
	_points.clear()
	for p: int in _opponent.brackets():
		_points.add_item("%d points" % p)
	if _points.item_count > 0:
		_points.select(_opponent.bracket)
	_seat.select(_seat.get_item_index(_opponent.seat))


## The chosen card has the sheet's lighter fill and the 2 px gold rim; Solo is off while
## NACHTMAHR has no list for the picked system.
func _refresh() -> void:
	for id: String in _cards:
		var card: Button = _cards[id]
		card.disabled = id == "solo" and not _opponent.solo_available()
		if id == _opponent.who:
			var rim := HouseStyle.menu_theme().get_stylebox(&"normal", &"Button").duplicate() as StyleBoxFlat
			rim.bg_color = HouseStyle.CARD_CHOSEN
			rim.draw_center = true   # the theme's button box may draw its rim only
			rim.border_color = HouseStyle.GOLD
			rim.set_border_width_all(2)
			card.add_theme_stylebox_override(&"normal", rim)
		else:
			card.remove_theme_stylebox_override(&"normal")
		card.set_meta("chosen", id == _opponent.who)
	_refresh_solo()
	_opponent_row.text = _opponent.label()
	if table_mode:
		_create.text = TABLE_ACTIONS[_opponent.who]
		_enter_key.text = _create.text.left(1).to_lower() + _create.text.substr(1)

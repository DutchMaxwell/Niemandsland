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

var left: VBoxContainer
var _opponent: SetupOpponent
var _cards: Dictionary = {}
var _head: HBoxContainer


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
	_opponent.changed.connect(_refresh)
	resized.connect(_place)
	_place()
	_refresh()


## The layout page's left column: same padding, width and top (under the setup's own title).
func _place() -> void:
	var compact := size.y < 800
	var pad := 28.0 if compact else maxf(28.0, size.x * 0.04)
	var rail_w := 504.0 if compact else minf(684.0, size.x * 0.36)
	left.position = Vector2(pad, 120.0 if compact else 232.0)
	left.custom_minimum_size.x = size.x - 2 * pad - rail_w - (24.0 if compact else 44.0)
	for row: Control in left.get_children().slice(0, 3):
		row.custom_minimum_size.y = 38 if compact else 52
	_head.custom_minimum_size.y = 40 if compact else 72
	left.reset_size.call_deferred()


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


## The chosen card has the lighter fill and the 2 px gold rim (as the layout step's way cards); Solo is off while
## NACHTMAHR has no list for the picked system.
func _refresh() -> void:
	for id: String in _cards:
		var card: Button = _cards[id]
		card.disabled = id == "solo" and not _opponent.solo_available()
		if id == _opponent.who:
			var rim := HouseStyle.menu_theme().get_stylebox(&"normal", &"Button").duplicate() as StyleBoxFlat
			rim.bg_color = HouseStyle.ROW_HOVER
			rim.border_color = HouseStyle.GOLD
			rim.set_border_width_all(2)
			card.add_theme_stylebox_override(&"normal", rim)
		else:
			card.remove_theme_stylebox_override(&"normal")
		card.set_meta("chosen", id == _opponent.who)

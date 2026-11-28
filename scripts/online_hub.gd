class_name OnlineHub
extends MenuPage
## "Play online": one page in place of the menu's list. The player's name once, the block "Create a room" and one
## folded relay line for every function of the page. "Prepare table" hands the table setup the settings of an
## online table; hosting begins at the table, nothing touches the network here.

signal host_requested(settings: Dictionary)
signal join_requested(code: String, url: String, player_name: String, button: Button)

const JOIN_W := 124   # the Join-with-a-code button: its word, then its Enter cap (sheet 02)
const LOCK := "<rect x='5' y='11' width='14' height='9' rx='1.5'/><path d='M8 11V8a4 4 0 0 1 8 0v3'/>"
const JOIN_CODE_LEN := 6
const TIMEOUT_S := 8.0
const REFRESH := "<path d='M20 12a8 8 0 1 1-2.3-5.6M20 4v4.5h-4.5'/>"

var name_field: LineEdit
var public_check: CheckBox
var prepare_button: Button
var code_boxes: CodeBoxes
var join_button: Button
var join_error: Label
var relay_line: Button
var relay_field: LineEdit
var lists_on_open := true   # false: no request until refresh() (tests)
var count_label: Label
var status_label: Label
var _rows: VBoxContainer
var _lobby: InternetLobby
var _gen := 0


func _init() -> void:
	super()
	column_width = 520
	eyebrow.text = "PLAY ONLINE"
	title.text = "Meet around the table."
	var caption := _text("YOUR NAME", HouseStyle.MENU_FONT_EYEBROW, HouseStyle.eyebrow_font())
	caption.add_theme_color_override(&"font_color", HouseStyle.MUTED)
	left.add_child(caption)
	name_field = NetDialog.line_edit(PlayerIdentity.load_saved_name(), "Player name")
	name_field.max_length = PlayerIdentity.MAX_NAME_LEN
	name_field.text_submitted.connect(func(_typed: String) -> void: _on_prepare())
	left.add_child(name_field)
	var create := _block(MenuView._icon(&"table"), "Create a room", "Prepare a table for your group")
	create.draw.connect(_draw_corners.bind(create))
	public_check = CheckBox.new()
	public_check.text = "List room publicly"
	public_check.focus_mode = FOCUS_ALL
	create.get_child(0).add_child(public_check)
	prepare_button = HouseStyle.button("Prepare table", HouseStyle.PRIMARY, 56)
	prepare_button.focus_mode = FOCUS_ALL
	prepare_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	prepare_button.icon = MenuView._icon(&"go")
	prepare_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prepare_button.add_theme_constant_override(&"icon_max_width", 18)
	prepare_button.pressed.connect(_on_prepare)
	create.get_child(0).add_child(prepare_button)
	var note := _text("Your invitation code appears once you connect at the table.", HouseStyle.MENU_FONT_CAPTION,
		HouseStyle.font(400))
	note.add_theme_color_override(&"font_color", HouseStyle.MUTED)
	create.get_child(0).add_child(note)
	_build_join()
	relay_line = Button.new()
	relay_line.flat = true
	relay_line.alignment = HORIZONTAL_ALIGNMENT_LEFT
	relay_line.icon = MenuView._icon(&"go")
	relay_line.add_theme_constant_override(&"icon_max_width", 14)
	relay_line.text = "Relay server · " + InternetLobby.DEFAULT_RELAY_URL
	relay_line.add_theme_color_override(&"font_color", HouseStyle.MUTED)
	relay_line.pressed.connect(func() -> void: relay_field.visible = not relay_field.visible)
	left.add_child(relay_line)
	relay_field = NetDialog.line_edit(InternetLobby.DEFAULT_RELAY_URL, InternetLobby.DEFAULT_RELAY_URL)
	relay_field.visible = false
	left.add_child(relay_field)


## The right panel "Public tables": the count and a refresh button in its head, one row per room.
func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	right.add_child(box)
	var head := HBoxContainer.new()
	var names := VBoxContainer.new()
	names.size_flags_horizontal = SIZE_EXPAND_FILL
	var kicker := _text("PUBLIC TABLES", HouseStyle.MENU_FONT_EYEBROW, HouseStyle.eyebrow_font())
	kicker.add_theme_color_override(&"font_color", HouseStyle.ACCENT)
	names.add_child(kicker)
	names.add_child(_text("Find an open game", 22, HouseStyle.font(500)))
	head.add_child(names)
	count_label = _text("", HouseStyle.MENU_FONT_CAPTION, HouseStyle.font(400))
	count_label.add_theme_color_override(&"font_color", HouseStyle.MUTED)
	head.add_child(count_label)
	var again := HouseStyle.button("", HouseStyle.ICON, HouseStyle.MENU_H_ACTION)   # a 44 px framed button (sheet 02)
	again.custom_minimum_size.x = HouseStyle.MENU_H_ACTION
	again.focus_mode = FOCUS_ALL
	again.icon = HouseStyle.svg_icon(MenuView.ICON_SVG % REFRESH)
	again.add_theme_constant_override(&"icon_max_width", 18)
	again.size_flags_horizontal = SIZE_SHRINK_END
	again.size_flags_vertical = SIZE_SHRINK_CENTER
	again.tooltip_text = "Refresh list"
	again.name = "Refresh"
	again.pressed.connect(refresh)
	head.add_child(again)
	box.add_child(head)
	box.add_child(HSeparator.new())
	_rows = VBoxContainer.new()
	_rows.name = "RoomRows"
	box.add_child(_rows)
	status_label = _text("", HouseStyle.MENU_FONT_CAPTION, HouseStyle.font(400))
	_rows.add_child(status_label)
	var info := _text("The list shows what the relay reports today: a code and its player count.",
		HouseStyle.MENU_FONT_CAPTION, HouseStyle.font(400))
	info.add_theme_color_override(&"font_color", HouseStyle.MUTED)
	box.add_child(info)
	relay_field.text_submitted.connect(func(_url: String) -> void: refresh())
	_chain()
	if lists_on_open:
		refresh()


## Exactly one kind of request, list_rooms, from a fresh listing lobby; a reply or the timeout of an older request
## (an older generation) changes nothing.
func refresh() -> void:
	_drop_lobby()
	_gen += 1
	var gen := _gen
	_show_status("Loading rooms…")
	_lobby = InternetLobby.new()
	add_child(_lobby)
	_lobby.rooms_list_received.connect(_on_rooms.bind(gen))
	_lobby.rooms_list_failed.connect(_on_failed.bind(gen))
	_lobby.list_rooms(_relay())
	get_tree().create_timer(TIMEOUT_S).timeout.connect(_on_timeout.bind(gen))


func _on_timeout(gen: int) -> void:
	if gen == _gen and status_label.text == "Loading rooms…":
		_show_status("Could not reach the relay (timed out).")


func _on_rooms(rooms: Array, gen: int) -> void:
	if gen != _gen:
		return
	_show_status("0 games online right now." if rooms.is_empty() else "")
	count_label.text = "%d game%s online" % [rooms.size(), "" if rooms.size() == 1 else "s"]
	for room: Dictionary in rooms:
		_rows.add_child(_room_row(str(room.get("code", "")), int(room.get("players", 0))))
	if not rooms.is_empty():
		_choose_room(_rows.get_child(1) as PanelContainer)   # child 0 is the status line
	_chain()


func _on_failed(reason: String, gen: int) -> void:
	if gen == _gen:
		_show_status(reason)


func _show_status(text: String) -> void:
	for row: Node in _rows.get_children():
		if row != status_label:
			_rows.remove_child(row)
			row.queue_free()
	status_label.text = text
	status_label.visible = not text.is_empty()


## A room: its code in mono, eight pips (as many filled as players are in), "<n> / 8 players" and Join.
func _room_row(code: String, players: int) -> PanelContainer:
	var card := PanelContainer.new()   # the chosen room is filled, its Join gold (sheet 02 .room.on)
	card.name = "Room" + code
	var row := HBoxContainer.new()
	card.add_child(row)
	row.custom_minimum_size.y = 64
	row.add_theme_constant_override(&"separation", 18)
	row.add_child(_text(NetDialog.code_as_typed(code), 24, HouseStyle.mono()))
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override(&"separation", 4)
	for i in InternetLobby.MAX_ROOM_PLAYERS:
		var pip := Panel.new()
		pip.name = "Pip%d" % i
		pip.set_meta("filled", i < players)
		pip.custom_minimum_size = Vector2(10, 10)
		pip.size_flags_vertical = SIZE_SHRINK_CENTER
		var dot := StyleBoxFlat.new()
		dot.set_corner_radius_all(5)
		dot.bg_color = HouseStyle.ACCENT if i < players else Color.TRANSPARENT
		dot.border_color = HouseStyle.ACCENT if i < players else HouseStyle.LINE
		dot.set_border_width_all(1)
		pip.add_theme_stylebox_override(&"panel", dot)
		pips.add_child(pip)
	row.add_child(pips)
	var count := _text("%d / %d players" % [players, InternetLobby.MAX_ROOM_PLAYERS], 18, HouseStyle.font(400))
	count.add_theme_color_override(&"font_color", HouseStyle.MUTED)
	count.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(count)
	var join := HouseStyle.button("Join", HouseStyle.BUTTON, HouseStyle.MENU_H_ACTION)
	join.custom_minimum_size.x = 110
	join.size_flags_horizontal = SIZE_SHRINK_END
	join.size_flags_vertical = SIZE_SHRINK_CENTER
	join.focus_mode = FOCUS_ALL
	join.name = "Join"
	join.pressed.connect(func() -> void:
		_drop_lobby()
		join_requested.emit(code, _relay(), PlayerIdentity.sanitize(name_field.text), join))
	join.focus_entered.connect(_choose_room.bind(card))
	row.add_child(join)
	return card


## The chosen room (the first, then the one whose Join has the focus): the 10 % accent fill, the soft rim, a gold Join.
func _choose_room(chosen: PanelContainer) -> void:
	for card: Node in _rows.get_children():
		if not card is PanelContainer:
			continue
		var box := StyleBoxFlat.new()
		box.bg_color = HouseStyle.ROW_HOVER if card == chosen else Color.TRANSPARENT
		box.border_color = HouseStyle.LINE_SOFT if card == chosen else Color.TRANSPARENT
		box.set_border_width_all(1)
		box.set_corner_radius_all(HouseStyle.RADIUS_CARD)
		box.content_margin_left = 16
		box.content_margin_right = 16
		(card as PanelContainer).add_theme_stylebox_override(&"panel", box)
		(card.find_child("Join", true, false) as Button).theme_type_variation = \
			HouseStyle.PRIMARY if card == chosen else HouseStyle.BUTTON


func _relay() -> String:
	var url := relay_field.text.strip_edges()
	return url if not url.is_empty() else InternetLobby.DEFAULT_RELAY_URL


## The listing socket closes and its node goes when the page closes, a join commits or a table is prepared.
func _drop_lobby() -> void:
	if is_instance_valid(_lobby):
		_lobby.disconnect_internet_game()
		_lobby.queue_free()
	_lobby = null


func _exit_tree() -> void:
	_drop_lobby()


## The list panel stands right of the column as drawn: from x = 720, y = 196, 760 px wide.
func _layout() -> void:
	super()
	right.position = Vector2(720, 196)
	right.size.x = 760


## A block of the left column (panel box, 18 px padding): a drawn icon, its title and a line under it.
func _block(icon: Texture2D, heading: String, line: String) -> PanelContainer:
	var block := PanelContainer.new()
	block.theme_type_variation = HouseStyle.PANEL_VARIANT
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 12)
	block.add_child(body)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 14)
	var mark := TextureRect.new()
	mark.texture = icon
	mark.custom_minimum_size = Vector2(28, 28)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.modulate = HouseStyle.ACCENT
	head.add_child(mark)
	var words := VBoxContainer.new()
	words.add_child(_text(heading, 22, HouseStyle.font(500)))
	var sub := _text(line, HouseStyle.MENU_FONT_CAPTION, HouseStyle.font(400))
	sub.add_theme_color_override(&"font_color", HouseStyle.MUTED)
	words.add_child(sub)
	head.add_child(words)
	body.add_child(head)
	left.add_child(block)
	return block


## "Join with a code": the six boxes and Join (off below six characters, gold from then on, with an Enter cap); the
## two error lines of today's join window under the boxes, only when needed, until the next keystroke.
func _build_join() -> void:
	var block := _block(HouseStyle.svg_icon(MenuView.ICON_SVG % LOCK), "Join with a code",
		"Enter a six-character invitation code")
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	code_boxes = CodeBoxes.new()
	code_boxes.changed.connect(_on_code_changed)
	code_boxes.submitted.connect(func(_code: String) -> void: _on_join())
	row.add_child(code_boxes)
	join_button = HouseStyle.button("Join", HouseStyle.BUTTON, 62)
	join_button.name = "JoinWithCode"
	join_button.focus_mode = FOCUS_ALL
	join_button.disabled = true
	join_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	join_button.custom_minimum_size.x = JOIN_W   # "Join" and its Enter cap side by side at the menu's button scale
	join_button.pressed.connect(_on_join)
	var cap := HouseStyle.key_cap("Enter")
	cap.mouse_filter = MOUSE_FILTER_IGNORE
	cap.set_anchors_preset(PRESET_CENTER_RIGHT)
	cap.grow_horizontal = GROW_DIRECTION_BEGIN
	cap.offset_left = -10
	cap.offset_right = -10
	join_button.add_child(cap)
	row.add_child(join_button)
	block.get_child(0).add_child(row)
	join_error = _text("", HouseStyle.MENU_FONT_CAPTION, HouseStyle.font(400))
	join_error.add_theme_color_override(&"font_color", HouseStyle.tone_ink(HouseStyle.TONE_DANGER))
	join_error.visible = false
	block.get_child(0).add_child(join_error)


func _on_code_changed(code: String) -> void:
	join_error.visible = false
	join_button.disabled = code.length() != JOIN_CODE_LEN
	join_button.theme_type_variation = HouseStyle.BUTTON if join_button.disabled else HouseStyle.PRIMARY


func _on_join() -> void:
	var code := code_boxes.text
	if code.length() != JOIN_CODE_LEN:
		join_error.text = "Enter your game’s invitation code." if code.is_empty() else \
			"An invitation code has %d characters, for example ABC-123." % JOIN_CODE_LEN
		join_error.visible = true
		return
	var url := relay_field.text.strip_edges()
	join_requested.emit(code, url if not url.is_empty() else InternetLobby.DEFAULT_RELAY_URL,
		PlayerIdentity.sanitize(name_field.text), join_button)


## Today's settings of an online table (the menu's create window had the same five).
func _on_prepare() -> void:
	var url := relay_field.text.strip_edges()
	var player_name := PlayerIdentity.sanitize(name_field.text)
	PlayerIdentity.save_name(player_name)
	_drop_lobby()
	host_requested.emit(host_settings(player_name, url if not url.is_empty() else InternetLobby.DEFAULT_RELAY_URL,
		public_check.button_pressed))


## The settings that make the next table an online room hosted by this player.
static func host_settings(player_name: String, relay_url: String, public: bool) -> Dictionary:
	return {
		"niemandsland/pending_internet_lobby": true,
		"niemandsland/internet_is_host": true,
		"niemandsland/internet_relay_url": relay_url,
		"niemandsland/player_name": player_name,
		"niemandsland/internet_public": public}


## The create block's two gold corner brackets (top left, bottom right), as on the menu's Continue card.
func _draw_corners(block: Control) -> void:
	for corner: Array in [[Vector2.ONE, Vector2.ONE], [block.size - Vector2.ONE, -Vector2.ONE]]:
		block.draw_line(corner[0], corner[0] + Vector2(14 * corner[1].x, 0), HouseStyle.GOLD, 1.5, true)
		block.draw_line(corner[0], corner[0] + Vector2(0, 14 * corner[1].y), HouseStyle.GOLD, 1.5, true)


## Tab in reading order: the way back, the name, the check, Prepare table, the code, Join, the relay line, refresh,
## the rows' Join buttons, and round again.
func _chain() -> void:
	var stops: Array[Control] = [back, name_field, public_check, prepare_button, code_boxes.field, join_button,
		relay_line, find_child("Refresh", true, false)]
	for row: Node in _rows.get_children():
		if row.name.begins_with("Room"):
			stops.append(row.find_children("*", "Button", true, false)[0])
	for i in stops.size():
		stops[i].focus_next = stops[i].get_path_to(stops[(i + 1) % stops.size()])
		stops[i].focus_previous = stops[i].get_path_to(stops[i - 1])

class_name InviteCard
extends Control
## The host's invite card at the table: over the dimmed table, the room's invitation code large enough to read
## out, "Copy code", and "Keep setting up". Esc and a click on the dimmed table close it as well. A local view: it
## sends nothing.

signal closed

const WIDTH := 600
const COPIED_S := 1.5
const COPY := "<rect x='9' y='9' width='11' height='11' rx='2'/><path d='M5 15V5a1 1 0 0 1 1-1h9'/>"
const MenuView = preload("res://scripts/startup_menu_view.gd")

var _code := ""
var _code_label: Label
var _caption: Label
var _copy: Button
var _count: Label
var _players: VBoxContainer
var _waiting: PanelContainer
var _ready: Button
var _main: Node


func _init() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	theme = HouseStyle.menu_theme()
	var scrim := ColorRect.new()
	scrim.color = Color(HouseStyle.SCRIM, 0.58)
	scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scrim.gui_input.connect(func(e: InputEvent) -> void: if e is InputEventMouseButton and e.pressed: close())
	add_child(scrim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	centre.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(centre)
	var card := PanelContainer.new()
	card.theme_type_variation = HouseStyle.PANEL_VARIANT
	card.custom_minimum_size.x = WIDTH
	card.draw.connect(_draw_corners.bind(card))
	centre.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 16)
	card.add_child(body)
	body.add_child(_text("YOUR ROOM", HouseStyle.MENU_FONT_EYEBROW, HouseStyle.eyebrow_font(), HouseStyle.ACCENT))
	body.add_child(_text("Invite your group.", HouseStyle.FONT_PAGE_TITLE, HouseStyle.font(500), HouseStyle.INK))
	var code_row := HBoxContainer.new()
	var code_box := VBoxContainer.new()
	code_box.size_flags_horizontal = SIZE_EXPAND_FILL
	code_box.add_child(_text("INVITATION CODE", HouseStyle.MENU_FONT_EYEBROW, HouseStyle.eyebrow_font(), HouseStyle.MUTED))
	_code_label = _text("", 54, HouseStyle.mono(500), HouseStyle.GOLD)
	code_box.add_child(_code_label)
	code_row.add_child(code_box)
	_copy = HouseStyle.button("Copy code", HouseStyle.BUTTON, HouseStyle.MENU_H_ACTION)
	_copy.name = "CopyCode"
	_copy.focus_mode = FOCUS_ALL
	_copy.icon = HouseStyle.svg_icon(MenuView.ICON_SVG % COPY)
	_copy.add_theme_constant_override(&"icon_max_width", 16)
	_copy.size_flags_horizontal = SIZE_SHRINK_END
	_copy.size_flags_vertical = SIZE_SHRINK_CENTER
	_copy.pressed.connect(_on_copy)
	code_row.add_child(_copy)
	body.add_child(HouseStyle.card(code_row))
	_count = _text("", HouseStyle.MENU_FONT_EYEBROW, HouseStyle.eyebrow_font(), HouseStyle.MUTED)
	_players = VBoxContainer.new()
	_waiting = PanelContainer.new()   # an empty seat: a dashed frame and a dashed ring (sheet 02b .p.empty)
	_waiting.name = "WaitingSeat"
	var seat_box := StyleBoxEmpty.new()
	seat_box.content_margin_left = 40
	seat_box.content_margin_top = 14
	seat_box.content_margin_bottom = 14
	_waiting.add_theme_stylebox_override(&"panel", seat_box)
	_waiting.add_child(_text("Waiting for a player …", HouseStyle.MENU_FONT_BODY, HouseStyle.font(400), HouseStyle.MUTED))
	_waiting.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, _waiting.size).grow(-0.5)
		for edge: Array in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end],
				[r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
			_waiting.draw_dashed_line(edge[0], edge[1], HouseStyle.LINE, 1.0, 5.0)
		var ring := Vector2(20, _waiting.size.y * 0.5)
		for i in 8:   # the empty seat's swatch: a dashed 14 px ring
			_waiting.draw_arc(ring, 7.0, TAU * i / 8.0, TAU * (i + 0.5) / 8.0, 4, HouseStyle.LINE, 1.0))
	for part: Control in [_count, _players, _waiting]:
		part.visible = false   # setup(main) shows the seats
		body.add_child(part)
	var buttons := HBoxContainer.new()
	var keep := HouseStyle.button("Keep setting up", HouseStyle.BUTTON, HouseStyle.MENU_H_ACTION)
	keep.name = "KeepSettingUp"
	keep.pressed.connect(close)
	_ready = HouseStyle.button("Ready", HouseStyle.PRIMARY, HouseStyle.MENU_H_ACTION)
	_ready.name = "ReadyButton"
	_ready.visible = false
	for b: Button in [keep, _ready]:
		b.focus_mode = FOCUS_ALL
		buttons.add_child(b)
	body.add_child(buttons)
	_caption = _text("", HouseStyle.MENU_FONT_CAPTION, HouseStyle.font(400), HouseStyle.MUTED)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_child(_caption)
	visible = false


## The seats from the game's own sources (`main`: network_manager, _peer_display_name, _get_player_color,
## _on_start_game_pressed), refreshed on the five roster signals. Ready is the game menu's own Ready action.
func setup(main: Node) -> void:
	_main = main
	var nm: Node = main.network_manager
	for signal_name: StringName in [&"player_connected", &"player_disconnected", &"remote_player_name_updated",
			&"slot_table_synced", &"ready_state_changed"]:
		nm.connect(signal_name, func(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void: _refresh())
	_ready.pressed.connect(func() -> void:
		_main._on_start_game_pressed()
		_refresh())
	for part: Control in [_count, _players, _ready]:
		part.visible = true
	_refresh()


## One 52 px row per player (swatch, name, "(you, host)" / "(you)" / "(host)", the ready tag where this client
## knows it: the host for every seat, a guest for its own), then the dashed row while seats are free.
func _refresh() -> void:
	var nm: Node = _main.network_manager
	var me: int = nm.get_my_peer_id()
	var ids: Array[int] = [me]
	for id: int in nm.connected_peers:
		if not ids.has(id):
			ids.append(id)
	ids.sort()
	for row: Node in _players.get_children():
		_players.remove_child(row)
		row.queue_free()
	for id in ids:
		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 12)
		var swatch := ColorRect.new()
		swatch.color = _main._get_player_color(id)
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = SIZE_SHRINK_CENTER
		line.add_child(swatch)
		line.add_child(_text(_main._peer_display_name(id), HouseStyle.MENU_FONT_BODY, HouseStyle.font(500), HouseStyle.INK))
		var suffix := ("(you, host)" if nm.is_host else "(you)") if id == me else ("(host)" if id == 1 else "")
		var who := _text(suffix, HouseStyle.MENU_FONT_BODY, HouseStyle.font(400), HouseStyle.MUTED)
		who.size_flags_horizontal = SIZE_EXPAND_FILL
		line.add_child(who)
		if nm.is_host or id == me:
			var ready: bool = nm.is_slot_ready(1 if id == me else nm.slot_for_peer(id)) if nm.is_host else nm.is_local_ready()
			var tag := _text("Ready" if ready else "Not ready", 12, HouseStyle.mono(), HouseStyle.GOLD if ready else HouseStyle.MUTED)
			tag.uppercase = true
			var chip := PanelContainer.new()   # a bordered chip (sheet 02b)
			var rim := StyleBoxFlat.new()
			rim.bg_color = Color.TRANSPARENT
			rim.border_color = Color(HouseStyle.GOLD, 0.6) if ready else HouseStyle.LINE
			rim.set_border_width_all(1)
			rim.set_corner_radius_all(3)
			rim.content_margin_left = 8
			rim.content_margin_right = 8
			chip.add_theme_stylebox_override(&"panel", rim)
			chip.size_flags_vertical = SIZE_SHRINK_CENTER
			chip.add_child(tag)
			line.add_child(chip)
		var row := HouseStyle.card(line)
		row.name = "Player%d" % id
		row.custom_minimum_size.y = 52
		_players.add_child(row)
	_count.text = "AT THE TABLE · %d / %d" % [ids.size(), InternetLobby.MAX_ROOM_PLAYERS]
	_waiting.visible = ids.size() < InternetLobby.MAX_ROOM_PLAYERS
	_ready.text = "Cancel Ready" if nm.is_local_ready() else "Ready"


## Shows the card for `code` ("ABC123" reads "ABC-123"); `caption` is the session's own line.
func open(code: String, caption := "") -> void:
	_code = code
	_code_label.text = NetDialog.code_as_typed(code)
	_caption.text = caption
	_caption.visible = not caption.is_empty()
	show()
	_copy.grab_focus.call_deferred()


func close() -> void:
	if visible:
		hide()
		closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _on_copy() -> void:
	DisplayServer.clipboard_set(_code)
	_copy.text = "Copied"
	get_tree().create_timer(COPIED_S).timeout.connect(_copy.set.bind(&"text", "Copy code"))


func _text(text: String, font_size: int, font: Font, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_font_override(&"font", font)
	label.add_theme_color_override(&"font_color", colour)
	return label


func _draw_corners(card: Control) -> void:
	for corner: Array in [[Vector2.ONE, Vector2.ONE], [card.size - Vector2.ONE, -Vector2.ONE]]:
		card.draw_line(corner[0], corner[0] + Vector2(14 * corner[1].x, 0), HouseStyle.GOLD, 1.5, true)
		card.draw_line(corner[0], corner[0] + Vector2(0, 14 * corner[1].y), HouseStyle.GOLD, 1.5, true)

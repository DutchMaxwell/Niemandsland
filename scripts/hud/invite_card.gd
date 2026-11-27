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
	var keep := HouseStyle.button("Keep setting up", HouseStyle.BUTTON, HouseStyle.MENU_H_ACTION)
	keep.name = "KeepSettingUp"
	keep.focus_mode = FOCUS_ALL
	keep.pressed.connect(close)
	body.add_child(keep)
	_caption = _text("", HouseStyle.MENU_FONT_CAPTION, HouseStyle.font(400), HouseStyle.MUTED)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_child(_caption)
	visible = false


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

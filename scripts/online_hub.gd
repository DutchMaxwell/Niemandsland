class_name OnlineHub
extends MenuPage
## "Play online": one page in place of the menu's list. The player's name once, the block "Create a room" and one
## folded relay line for every function of the page. "Prepare table" hands the table setup the settings of an
## online table; hosting begins at the table, nothing touches the network here.

signal host_requested(settings: Dictionary)
signal join_requested(code: String, url: String, player_name: String, button: Button)

const LOCK := "<rect x='5' y='11' width='14' height='9' rx='1.5'/><path d='M8 11V8a4 4 0 0 1 8 0v3'/>"
const JOIN_CODE_LEN := 6

var name_field: LineEdit
var public_check: CheckBox
var prepare_button: Button
var code_boxes: CodeBoxes
var join_button: Button
var join_error: Label
var relay_line: Button
var relay_field: LineEdit


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
	name_field.text_submitted.connect(func(_text: String) -> void: _on_prepare())
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
	join_button.focus_mode = FOCUS_ALL
	join_button.disabled = true
	join_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
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
	host_requested.emit({
		"niemandsland/pending_internet_lobby": true,
		"niemandsland/internet_is_host": true,
		"niemandsland/internet_relay_url": url if not url.is_empty() else InternetLobby.DEFAULT_RELAY_URL,
		"niemandsland/player_name": player_name,
		"niemandsland/internet_public": public_check.button_pressed})


## The create block's two gold corner brackets (top left, bottom right), as on the menu's Continue card.
func _draw_corners(block: Control) -> void:
	for corner: Array in [[Vector2.ONE, Vector2.ONE], [block.size - Vector2.ONE, -Vector2.ONE]]:
		block.draw_line(corner[0], corner[0] + Vector2(14 * corner[1].x, 0), HouseStyle.GOLD, 1.5, true)
		block.draw_line(corner[0], corner[0] + Vector2(0, 14 * corner[1].y), HouseStyle.GOLD, 1.5, true)

class_name OnlineHub
extends MenuPage
## "Play online": one page in place of the menu's list. The player's name once and the block "Create a room":
## "Prepare table" hands the table setup the settings of an online table; hosting begins at the table, nothing
## touches the network here.

signal host_requested(settings: Dictionary)

var name_field: LineEdit
var public_check: CheckBox
var prepare_button: Button


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
	var create := _block("table", "Create a room", "Prepare a table for your group")
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


## A block of the left column (panel box, 18 px padding): a drawn icon, its title and a line under it.
func _block(icon: StringName, heading: String, line: String) -> PanelContainer:
	var block := PanelContainer.new()
	block.theme_type_variation = HouseStyle.PANEL_VARIANT
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 12)
	block.add_child(body)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 14)
	var mark := TextureRect.new()
	mark.texture = MenuView._icon(icon)
	mark.custom_minimum_size = Vector2(28, 28)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
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


## Today's settings of an online table (the menu's create window had the same five).
func _on_prepare() -> void:
	var player_name := PlayerIdentity.sanitize(name_field.text)
	PlayerIdentity.save_name(player_name)
	host_requested.emit({
		"niemandsland/pending_internet_lobby": true,
		"niemandsland/internet_is_host": true,
		"niemandsland/internet_relay_url": InternetLobby.DEFAULT_RELAY_URL,
		"niemandsland/player_name": player_name,
		"niemandsland/internet_public": public_check.button_pressed})

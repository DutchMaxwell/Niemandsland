extends Window
class_name OPRImportDialog
## Dialog for importing OPR Army Forge armies via Share-Link

signal army_imported(army: OPRApiClient.OPRArmy, player_id: int)

## UI Elements
var player_option: OptionButton
var army_preview: RichTextLabel
var import_btn: Button
var cancel_btn: Button
var share_link_input: LineEdit
var link_status_label: Label

## Parsed army (preview)
var _preview_army: OPRApiClient.OPRArmy = null

## API Client for parsing
var api_client: OPRApiClient


func _ready() -> void:
	title = "Import OPR Army"
	size = Vector2i(550, 450)
	close_requested.connect(_on_cancel)

	_setup_ui()


func _setup_ui() -> void:
	# Main container
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Title
	var title_label = Label.new()
	title_label.text = "Import Army from OPR Army Forge"
	title_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title_label)

	# === SHARE LINK SECTION ===
	var link_section = VBoxContainer.new()
	link_section.add_theme_constant_override("separation", 8)
	vbox.add_child(link_section)

	var link_info = Label.new()
	link_info.text = "Enter an Army Forge share link or list ID:"
	link_info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	link_section.add_child(link_info)

	var link_example = Label.new()
	link_example.text = "e.g. https://army-forge.onepagerules.com/share?id=XXX"
	link_example.add_theme_font_size_override("font_size", 11)
	link_example.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	link_section.add_child(link_example)

	# Link input
	share_link_input = LineEdit.new()
	share_link_input.placeholder_text = "Paste a share link or list ID here..."
	share_link_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	link_section.add_child(share_link_input)

	# Link buttons row
	var link_btn_row = HBoxContainer.new()
	link_btn_row.add_theme_constant_override("separation", 8)
	link_section.add_child(link_btn_row)

	var paste_link_btn = Button.new()
	paste_link_btn.text = "From clipboard"
	paste_link_btn.pressed.connect(_on_paste_link)
	link_btn_row.add_child(paste_link_btn)

	var fetch_btn = Button.new()
	fetch_btn.text = "Load army"
	fetch_btn.pressed.connect(_on_fetch_from_link)
	link_btn_row.add_child(fetch_btn)

	link_status_label = Label.new()
	link_status_label.text = ""
	link_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	link_btn_row.add_child(link_status_label)

	# === COMMON ELEMENTS ===

	# Player selection
	var player_row = HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 8)
	vbox.add_child(player_row)

	var player_label = Label.new()
	player_label.text = "Assign player:"
	player_row.add_child(player_label)

	player_option = OptionButton.new()
	player_option.add_item("Player 1 (Blue)", 1)
	player_option.add_item("Player 2 (Red)", 2)
	player_option.add_item("Player 3 (Green)", 3)
	player_option.add_item("Player 4 (Gold)", 4)
	player_option.select(0)
	player_row.add_child(player_option)

	# Army preview
	var preview_label = Label.new()
	preview_label.text = "Preview:"
	vbox.add_child(preview_label)

	army_preview = RichTextLabel.new()
	army_preview.bbcode_enabled = true
	army_preview.custom_minimum_size = Vector2(0, 150)
	army_preview.scroll_following = true
	army_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var preview_panel = PanelContainer.new()
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.9)
	style.border_color = Color(0.3, 0.3, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	preview_panel.add_theme_stylebox_override("panel", style)
	vbox.add_child(preview_panel)
	preview_panel.add_child(army_preview)

	# Button row
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)

	cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)

	import_btn = Button.new()
	import_btn.text = "Import army"
	import_btn.disabled = true
	import_btn.pressed.connect(_on_import)
	btn_row.add_child(import_btn)

	# API Client
	api_client = OPRApiClient.new()
	add_child(api_client)


func _on_paste_link() -> void:
	var clipboard = DisplayServer.clipboard_get()
	if not clipboard.is_empty():
		share_link_input.text = clipboard


func _on_fetch_from_link() -> void:
	var link = share_link_input.text.strip_edges()
	if link.is_empty():
		link_status_label.text = "No link entered"
		link_status_label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5))
		return

	link_status_label.text = "Loading..."
	link_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))
	army_preview.text = "[color=#aaaaaa]Loading army from the Army Forge API...[/color]"
	import_btn.disabled = true

	# Fetch from API
	_preview_army = await api_client.import_from_share_link(link)
	if _preview_army and _preview_army.units.size() > 0:
		link_status_label.text = "Loaded!"
		link_status_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
		_update_preview()
		import_btn.disabled = false
	elif _preview_army and _preview_army.units.size() == 0:
		link_status_label.text = "Empty"
		link_status_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3))
		army_preview.text = "[color=yellow]The army list is empty.[/color]\n\nThis list contains no units. Add some units in Army Forge first."
		import_btn.disabled = true
	else:
		link_status_label.text = "Error"
		link_status_label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5))
		army_preview.text = "[color=red]Could not load the army.[/color]\n\nCheck the link and your internet connection."
		import_btn.disabled = true


func _update_preview() -> void:
	if not _preview_army:
		army_preview.text = ""
		return

	var text = "[b]%s[/b]\n" % _preview_army.name
	text += "[color=#aaaaaa]%s[/color]\n\n" % _preview_army.game_system

	text += "[b]Points:[/b] %d | " % _preview_army.points
	text += "[b]Units:[/b] %d | " % _preview_army.units.size()
	if _preview_army.model_count > 0:
		text += "[b]Models:[/b] %d" % _preview_army.model_count
	text += "\n\n"

	for unit in _preview_army.units:
		var unit_line = "• %s" % unit.get_display_name()
		if unit.cost > 0:
			unit_line += " [color=#ffcc44](%d pts)[/color]" % unit.cost
		unit_line += " [color=#88ff88]Q%d+[/color] [color=#8888ff]D%d+[/color]" % [unit.quality, unit.defense]
		text += unit_line + "\n"

		# Show weapons
		if unit.weapons.size() > 0:
			var weapon_strs: Array[String] = []
			for w in unit.weapons:
				var ws = w.name
				if w.count > 1:
					ws = "%dx %s" % [w.count, w.name]
				weapon_strs.append(ws)
			text += "  [color=#888888]%s[/color]\n" % ", ".join(weapon_strs)

	army_preview.text = text


func _on_import() -> void:
	if not _preview_army:
		return

	var player_id = player_option.get_selected_id()
	_preview_army.player_id = player_id

	army_imported.emit(_preview_army, player_id)
	hide()

	# Reset state
	_reset_dialog()


func _on_cancel() -> void:
	hide()
	_reset_dialog()


func _reset_dialog() -> void:
	_preview_army = null
	share_link_input.text = ""
	link_status_label.text = ""
	army_preview.text = ""
	import_btn.disabled = true


## Sets the pre-selected player for import.
func set_player(player_id: int) -> void:
	# Find index for the given player ID
	for i in range(player_option.item_count):
		if player_option.get_item_id(i) == player_id:
			player_option.select(i)
			return

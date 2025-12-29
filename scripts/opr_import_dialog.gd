extends Window
class_name OPRImportDialog
## Dialog for importing OPR Army Forge armies
## Allows selecting a JSON file and assigning to a player

signal army_imported(army: OPRApiClient.OPRArmy, player_id: int)

## UI Elements
var file_dialog: FileDialog
var player_option: OptionButton
var army_preview: RichTextLabel
var import_btn: Button
var cancel_btn: Button
var status_label: Label

## Selected file path
var _selected_file: String = ""

## Parsed army (preview)
var _preview_army: OPRApiClient.OPRArmy = null

## API Client for parsing
var api_client: OPRApiClient


func _ready() -> void:
	title = "Import OPR Army"
	size = Vector2i(500, 450)
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
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title
	var title_label = Label.new()
	title_label.text = "Import Army from OPR Army Forge"
	title_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title_label)

	# Info label
	var info_label = Label.new()
	info_label.text = "Export your army from Army Forge as JSON and select the file below."
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(info_label)

	# File selection row
	var file_row = HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 8)
	vbox.add_child(file_row)

	var select_btn = Button.new()
	select_btn.text = "Select JSON File..."
	select_btn.pressed.connect(_on_select_file)
	file_row.add_child(select_btn)

	status_label = Label.new()
	status_label.text = "No file selected"
	status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_row.add_child(status_label)

	# Player selection
	var player_row = HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 8)
	vbox.add_child(player_row)

	var player_label = Label.new()
	player_label.text = "Assign to Player:"
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
	preview_label.text = "Army Preview:"
	vbox.add_child(preview_label)

	army_preview = RichTextLabel.new()
	army_preview.bbcode_enabled = true
	army_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	army_preview.custom_minimum_size = Vector2(0, 180)
	army_preview.scroll_following = true

	var preview_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.9)
	style.border_color = Color(0.3, 0.3, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	preview_panel.add_theme_stylebox_override("panel", style)
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	import_btn.text = "Import Army"
	import_btn.disabled = true
	import_btn.pressed.connect(_on_import)
	btn_row.add_child(import_btn)

	# File dialog
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.json ; OPR Army Forge JSON"])
	file_dialog.title = "Select OPR Army Forge Export"
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)

	# API Client for parsing
	api_client = OPRApiClient.new()
	add_child(api_client)


func _on_select_file() -> void:
	file_dialog.popup_centered(Vector2i(700, 500))


func _on_file_selected(path: String) -> void:
	_selected_file = path
	status_label.text = path.get_file()
	status_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))

	# Parse and preview
	_preview_army = api_client.import_from_file(path)
	if _preview_army:
		_update_preview()
		import_btn.disabled = false
	else:
		army_preview.text = "[color=red]Failed to parse army file.[/color]\n\nMake sure this is a valid OPR Army Forge export."
		import_btn.disabled = true


func _update_preview() -> void:
	if not _preview_army:
		army_preview.text = ""
		return

	var text = "[b]%s[/b]\n" % _preview_army.name
	text += "[color=#aaaaaa]%s[/color]\n\n" % _preview_army.game_system

	text += "[b]Total Points:[/b] %d\n" % _preview_army.points
	text += "[b]Units:[/b] %d\n\n" % _preview_army.units.size()

	for unit in _preview_army.units:
		var unit_line = "• %s" % unit.get_display_name()
		if unit.cost > 0:
			unit_line += " [color=#ffcc44](%d pts)[/color]" % unit.cost
		text += unit_line + "\n"

		# Show weapons briefly
		if unit.weapons.size() > 0:
			var weapon_names: Array[String] = []
			for w in unit.weapons:
				weapon_names.append(w.name)
			text += "  [color=#888888]%s[/color]\n" % ", ".join(weapon_names)

	army_preview.text = text


func _on_import() -> void:
	if not _preview_army:
		return

	var player_id = player_option.get_selected_id()
	_preview_army.player_id = player_id

	army_imported.emit(_preview_army, player_id)
	hide()

	# Reset state
	_selected_file = ""
	_preview_army = null
	status_label.text = "No file selected"
	army_preview.text = ""
	import_btn.disabled = true


func _on_cancel() -> void:
	hide()
	_selected_file = ""
	_preview_army = null

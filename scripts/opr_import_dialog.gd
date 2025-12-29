extends Window
class_name OPRImportDialog
## Dialog for importing OPR Army Forge armies
## Supports both direct text paste and file import

signal army_imported(army: OPRApiClient.OPRArmy, player_id: int)

## UI Elements
var tab_container: TabContainer
var text_input: TextEdit
var file_dialog: FileDialog
var player_option: OptionButton
var army_preview: RichTextLabel
var import_btn: Button
var cancel_btn: Button
var status_label: Label
var paste_btn: Button
var clear_btn: Button

## Selected file path (for file mode)
var _selected_file: String = ""

## Parsed army (preview)
var _preview_army: OPRApiClient.OPRArmy = null

## API Client for parsing
var api_client: OPRApiClient

## Current import mode
var _import_mode: String = "text"  # "text" or "file"


func _ready() -> void:
	title = "Import OPR Army"
	size = Vector2i(550, 550)
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

	# Tab container for import modes
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.tab_changed.connect(_on_tab_changed)
	vbox.add_child(tab_container)

	# === TEXT PASTE TAB ===
	var text_tab = VBoxContainer.new()
	text_tab.name = "Text einfügen"
	text_tab.add_theme_constant_override("separation", 8)
	tab_container.add_child(text_tab)

	var text_info = Label.new()
	text_info.text = "Army Forge → Share → 'Share as Text' → Text hier einfügen:"
	text_info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	text_tab.add_child(text_info)

	# Text input area
	text_input = TextEdit.new()
	text_input.placeholder_text = "++ Army Name - Faction [GF 2000pts] ++\n\nUnit Name [5] Q3+ D4+ | 100pts | Special Rules\nWeapon (24\", A2, AP(1)), CCW (A1)\n..."
	text_input.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_input.custom_minimum_size = Vector2(0, 150)
	text_input.text_changed.connect(_on_text_changed)
	text_tab.add_child(text_input)

	# Text buttons row
	var text_btn_row = HBoxContainer.new()
	text_btn_row.add_theme_constant_override("separation", 8)
	text_tab.add_child(text_btn_row)

	paste_btn = Button.new()
	paste_btn.text = "Aus Zwischenablage einfügen"
	paste_btn.pressed.connect(_on_paste_from_clipboard)
	text_btn_row.add_child(paste_btn)

	clear_btn = Button.new()
	clear_btn.text = "Leeren"
	clear_btn.pressed.connect(_on_clear_text)
	text_btn_row.add_child(clear_btn)

	var parse_btn = Button.new()
	parse_btn.text = "Text parsen"
	parse_btn.pressed.connect(_on_parse_text)
	text_btn_row.add_child(parse_btn)

	# === FILE IMPORT TAB ===
	var file_tab = VBoxContainer.new()
	file_tab.name = "Datei importieren"
	file_tab.add_theme_constant_override("separation", 8)
	tab_container.add_child(file_tab)

	var file_info = Label.new()
	file_info.text = "JSON oder Text-Datei von Army Forge auswählen:"
	file_info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	file_tab.add_child(file_info)

	# File selection row
	var file_row = HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 8)
	file_tab.add_child(file_row)

	var select_btn = Button.new()
	select_btn.text = "Datei auswählen..."
	select_btn.pressed.connect(_on_select_file)
	file_row.add_child(select_btn)

	status_label = Label.new()
	status_label.text = "Keine Datei ausgewählt"
	status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_row.add_child(status_label)

	# Spacer in file tab
	var file_spacer = Control.new()
	file_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	file_tab.add_child(file_spacer)

	# === COMMON ELEMENTS (below tabs) ===

	# Player selection
	var player_row = HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 8)
	vbox.add_child(player_row)

	var player_label = Label.new()
	player_label.text = "Spieler zuweisen:"
	player_row.add_child(player_label)

	player_option = OptionButton.new()
	player_option.add_item("Spieler 1 (Blau)", 1)
	player_option.add_item("Spieler 2 (Rot)", 2)
	player_option.add_item("Spieler 3 (Grün)", 3)
	player_option.add_item("Spieler 4 (Gold)", 4)
	player_option.select(0)
	player_row.add_child(player_option)

	# Army preview
	var preview_label = Label.new()
	preview_label.text = "Vorschau:"
	vbox.add_child(preview_label)

	army_preview = RichTextLabel.new()
	army_preview.bbcode_enabled = true
	army_preview.custom_minimum_size = Vector2(0, 120)
	army_preview.scroll_following = true

	var preview_panel = PanelContainer.new()
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
	cancel_btn.text = "Abbrechen"
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)

	import_btn = Button.new()
	import_btn.text = "Armee importieren"
	import_btn.disabled = true
	import_btn.pressed.connect(_on_import)
	btn_row.add_child(import_btn)

	# File dialog (hidden, used when file tab is active)
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.txt ; OPR Text Export", "*.json ; OPR Army Forge JSON"])
	file_dialog.title = "OPR Army Forge Export auswählen"
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)

	# API Client for parsing
	api_client = OPRApiClient.new()
	add_child(api_client)


func _on_tab_changed(tab: int) -> void:
	_import_mode = "text" if tab == 0 else "file"
	# Reset preview when switching tabs
	_preview_army = null
	army_preview.text = ""
	import_btn.disabled = true


func _on_paste_from_clipboard() -> void:
	var clipboard = DisplayServer.clipboard_get()
	if not clipboard.is_empty():
		text_input.text = clipboard
		_on_parse_text()


func _on_clear_text() -> void:
	text_input.text = ""
	_preview_army = null
	army_preview.text = ""
	import_btn.disabled = true


func _on_text_changed() -> void:
	# Auto-parse when text looks complete (starts with ++)
	pass  # Don't auto-parse, let user click button


func _on_parse_text() -> void:
	var text = text_input.text.strip_edges()
	if text.is_empty():
		army_preview.text = "[color=red]Kein Text eingegeben.[/color]"
		import_btn.disabled = true
		return

	if not text.begins_with("++"):
		army_preview.text = "[color=red]Ungültiges Format.[/color]\n\nText muss mit '++' beginnen (Army Forge Text Export)."
		import_btn.disabled = true
		return

	# Parse the text directly
	_preview_army = api_client._parse_text_export(text, "clipboard")
	if _preview_army and _preview_army.units.size() > 0:
		_update_preview()
		import_btn.disabled = false
	else:
		army_preview.text = "[color=red]Parsing fehlgeschlagen.[/color]\n\nStelle sicher, dass der Text ein gültiger Army Forge Export ist."
		import_btn.disabled = true


func _on_select_file() -> void:
	file_dialog.popup_centered(Vector2i(700, 500))


func _on_file_selected(path: String) -> void:
	_selected_file = path
	status_label.text = path.get_file()
	status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))

	# Show loading state
	army_preview.text = "[color=#aaaaaa]Lade Armee-Daten...[/color]"
	import_btn.disabled = true

	# Parse file (async for JSON)
	_preview_army = await api_client.import_from_file(path)
	if _preview_army:
		status_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
		_update_preview()
		import_btn.disabled = false
	else:
		status_label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5))
		army_preview.text = "[color=red]Datei konnte nicht gelesen werden.[/color]"
		import_btn.disabled = true


func _update_preview() -> void:
	if not _preview_army:
		army_preview.text = ""
		return

	var text = "[b]%s[/b]\n" % _preview_army.name
	text += "[color=#aaaaaa]%s[/color]\n\n" % _preview_army.game_system

	text += "[b]Punkte:[/b] %d | " % _preview_army.points
	text += "[b]Units:[/b] %d | " % _preview_army.units.size()
	if _preview_army.model_count > 0:
		text += "[b]Modelle:[/b] %d" % _preview_army.model_count
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
	_selected_file = ""
	_preview_army = null
	text_input.text = ""
	status_label.text = "Keine Datei ausgewählt"
	status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	army_preview.text = ""
	import_btn.disabled = true

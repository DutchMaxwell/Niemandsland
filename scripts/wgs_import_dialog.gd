extends Window
class_name WGSImportDialog
## Dialog for importing WGS (Wargaming Simulator) game states
## Allows selecting a text file or fetching from server

signal game_imported(game: WGSClient.WGSGame)

## UI Elements
var file_dialog: FileDialog
var game_preview: RichTextLabel
var import_btn: Button
var cancel_btn: Button
var status_label: Label
var game_id_input: LineEdit
var fetch_btn: Button
var tab_container: TabContainer

## Selected file path
var _selected_file: String = ""

## Parsed game (preview)
var _preview_game: WGSClient.WGSGame = null

## WGS Client for parsing
var wgs_client: WGSClient


func _ready() -> void:
	title = "Import WGS Game"
	size = Vector2i(550, 500)
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
	title_label.text = "Import from Wargaming Simulator"
	title_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title_label)

	# Info label
	var info_label = Label.new()
	info_label.text = "Import a game state from Udo's Wargaming Simulator (udos3dworld.com)"
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(info_label)

	# Tab container for File vs Server import
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(tab_container)

	# File import tab
	var file_tab = VBoxContainer.new()
	file_tab.name = "From File"
	file_tab.add_theme_constant_override("separation", 12)
	tab_container.add_child(file_tab)

	_setup_file_tab(file_tab)

	# Server import tab
	var server_tab = VBoxContainer.new()
	server_tab.name = "From Server"
	server_tab.add_theme_constant_override("separation", 12)
	tab_container.add_child(server_tab)

	_setup_server_tab(server_tab)

	# Game preview (shared)
	var preview_label = Label.new()
	preview_label.text = "Game Preview:"
	vbox.add_child(preview_label)

	game_preview = RichTextLabel.new()
	game_preview.bbcode_enabled = true
	game_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_preview.custom_minimum_size = Vector2(0, 150)
	game_preview.scroll_following = true

	var preview_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.9)
	style.border_color = Color(0.3, 0.3, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	preview_panel.add_theme_stylebox_override("panel", style)
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(preview_panel)
	preview_panel.add_child(game_preview)

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
	import_btn.text = "Import Game"
	import_btn.disabled = true
	import_btn.pressed.connect(_on_import)
	btn_row.add_child(import_btn)

	# File dialog
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.txt ; WGS Game State"])
	file_dialog.title = "Select WGS Game State File"
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)

	# WGS Client for parsing
	wgs_client = WGSClient.new()
	add_child(wgs_client)


func _setup_file_tab(container: VBoxContainer) -> void:
	var file_info = Label.new()
	file_info.text = "Select a WGS game state file (.txt) exported from the Wargaming Simulator."
	file_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	file_info.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	container.add_child(file_info)

	var file_row = HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 8)
	container.add_child(file_row)

	var select_btn = Button.new()
	select_btn.text = "Select File..."
	select_btn.pressed.connect(_on_select_file)
	file_row.add_child(select_btn)

	status_label = Label.new()
	status_label.text = "No file selected"
	status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_row.add_child(status_label)


func _setup_server_tab(container: VBoxContainer) -> void:
	var server_info = Label.new()
	server_info.text = "Enter the Game ID to fetch the current state from the WGS server."
	server_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	server_info.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	container.add_child(server_info)

	var id_row = HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 8)
	container.add_child(id_row)

	var id_label = Label.new()
	id_label.text = "Game ID:"
	id_row.add_child(id_label)

	game_id_input = LineEdit.new()
	game_id_input.placeholder_text = "e.g., MyGame123"
	game_id_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_row.add_child(game_id_input)

	fetch_btn = Button.new()
	fetch_btn.text = "Fetch"
	fetch_btn.pressed.connect(_on_fetch)
	id_row.add_child(fetch_btn)

	var url_info = Label.new()
	url_info.text = "The game state will be fetched from:\nhttps://udos3dworld.com/WargamingSimulator/{game_id}.txt"
	url_info.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	url_info.add_theme_font_size_override("font_size", 11)
	container.add_child(url_info)


func _on_select_file() -> void:
	file_dialog.popup_centered(Vector2i(700, 500))


func _on_file_selected(path: String) -> void:
	_selected_file = path
	status_label.text = path.get_file()
	status_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))

	# Parse and preview
	_preview_game = wgs_client.import_from_file(path)
	if _preview_game:
		_update_preview()
		import_btn.disabled = false
	else:
		game_preview.text = "[color=red]Failed to parse game state file.[/color]\n\nMake sure this is a valid WGS game state file."
		import_btn.disabled = true


func _on_fetch() -> void:
	var game_id = game_id_input.text.strip_edges()
	if game_id.is_empty():
		game_preview.text = "[color=yellow]Please enter a Game ID.[/color]"
		return

	game_preview.text = "[color=#aaaaaa]Fetching game state...[/color]"
	fetch_btn.disabled = true

	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_fetch_completed.bind(http, game_id))

	var url = "https://udos3dworld.com/WargamingSimulator/%s.txt" % game_id
	var error = http.request(url)

	if error != OK:
		game_preview.text = "[color=red]Failed to start HTTP request.[/color]"
		fetch_btn.disabled = false
		http.queue_free()


func _on_fetch_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, game_id: String) -> void:
	http.queue_free()
	fetch_btn.disabled = false

	if result != HTTPRequest.RESULT_SUCCESS:
		game_preview.text = "[color=red]HTTP request failed.[/color]\n\nPlease check your internet connection."
		return

	if response_code == 404:
		game_preview.text = "[color=red]Game not found.[/color]\n\nThe game ID '%s' does not exist on the server." % game_id
		return

	if response_code != 200:
		game_preview.text = "[color=red]Server error: %d[/color]" % response_code
		return

	var content = body.get_string_from_utf8()
	if content.is_empty():
		game_preview.text = "[color=yellow]Game state is empty.[/color]"
		return

	_preview_game = wgs_client.import_from_text(content, game_id)
	if _preview_game:
		_update_preview()
		import_btn.disabled = false
	else:
		game_preview.text = "[color=red]Failed to parse game state.[/color]"
		import_btn.disabled = true


func _update_preview() -> void:
	if not _preview_game:
		game_preview.text = ""
		return

	var text = "[b]Game: %s[/b]\n\n" % _preview_game.game_id

	text += "[b]Units:[/b] %d\n" % _preview_game.get_unit_count()
	text += "[b]Total Models:[/b] %d\n\n" % _preview_game.get_model_count()

	# List units
	var colors_seen: Dictionary = {}
	for unit in _preview_game.units:
		var color_hex = unit.color.to_html(false)
		if not colors_seen.has(unit.color_name):
			colors_seen[unit.color_name] = 0
		colors_seen[unit.color_name] += 1

		var unit_line = "• [color=#%s]%s[/color]" % [color_hex, unit.get_display_name()]
		if unit.model_count > 1:
			unit_line += " [color=#888888](x%d)[/color]" % unit.model_count
		if unit.points > 0:
			unit_line += " [color=#ffcc44]%d pts[/color]" % unit.points
		text += unit_line + "\n"

	# Summary by color/player
	if not colors_seen.is_empty():
		text += "\n[b]By Color:[/b]\n"
		for color_name in colors_seen:
			text += "  %s: %d units\n" % [color_name.capitalize(), colors_seen[color_name]]

	game_preview.text = text


func _on_import() -> void:
	if not _preview_game:
		return

	game_imported.emit(_preview_game)
	hide()

	# Reset state
	_selected_file = ""
	_preview_game = null
	status_label.text = "No file selected"
	game_preview.text = ""
	import_btn.disabled = true
	game_id_input.text = ""


func _on_cancel() -> void:
	hide()
	_selected_file = ""
	_preview_game = null

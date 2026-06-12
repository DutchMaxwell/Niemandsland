extends Window
class_name OPRImportDialog
## Dialog for importing OPR Army Forge armies via Share-Link

signal army_imported(army: OPRApiClient.OPRArmy, player_id: int)

## UI Elements
var player_option: OptionButton
var army_preview: RichTextLabel
var state_panel: StatePanel
var import_btn: Button
var cancel_btn: Button
var fetch_btn: Button
var share_link_input: LineEdit
var link_status_label: Label

## Parsed army (preview)
var _preview_army: OPRApiClient.OPRArmy = null

## API Client for parsing
var api_client: OPRApiClient


func _ready() -> void:
	title = "Import OPR Army"
	# Tall enough that the preview + the Cancel/Import button row always fit (the army
	# list scrolls inside the preview well; the buttons stay pinned). Clamped on open.
	UiPolish.keep_window_reachable(self, Vector2i(560, 560))
	theme = ThemeManager.get_current_theme()
	borderless = true  # we draw our own tactical chrome (no gray Godot title bar)
	close_requested.connect(_on_cancel)
	visibility_changed.connect(func() -> void:
		if visible:
			UiPolish.grab_first_focus.call_deferred(self))

	_setup_ui()


func _setup_ui() -> void:
	# Tactical background panel (deep-navy glass + hairline + shadow), then content.
	var bg_panel = PanelContainer.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_panel.add_theme_stylebox_override("panel", HudTokens.panel_style())
	add_child(bg_panel)

	var margin = MarginContainer.new()
	UiPolish.set_dialog_margins(margin)
	bg_panel.add_child(margin)

	# Corner-bracket chrome on top (instrumentation look)
	bg_panel.add_child(HudFrame.new())

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UiPolish.SECTION_SEP)
	margin.add_child(vbox)

	# Tactical header (Orbitron title + amber index + accent line)
	vbox.add_child(HudTokens.header("ARMY IMPORT", "/// NODE-01"))

	# === SHARE LINK SECTION ===
	var link_section = VBoxContainer.new()
	link_section.add_theme_constant_override("separation", 8)
	vbox.add_child(link_section)

	var link_info = Label.new()
	link_info.text = "ENTER ARMY FORGE SHARE LINK / LIST ID"
	link_info.add_theme_font_override("font", HudTokens.mono_font())
	link_info.add_theme_font_size_override("font_size", 12)
	link_info.add_theme_color_override("font_color", UiPolish.TEXT_MUTED)
	link_section.add_child(link_info)

	var link_example = Label.new()
	link_example.text = "e.g. https://army-forge.onepagerules.com/share?id=XXX"
	link_example.add_theme_font_size_override("font_size", 11)
	link_example.add_theme_color_override("font_color", UiPolish.TEXT_MUTED)
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
	paste_link_btn.text = "FROM CLIPBOARD"
	UiPolish.primary_button(paste_link_btn)
	paste_link_btn.pressed.connect(_on_paste_link)
	link_btn_row.add_child(paste_link_btn)

	fetch_btn = Button.new()
	fetch_btn.text = "LOAD ARMY"
	fetch_btn.theme_type_variation = "PrimaryButton"
	UiPolish.primary_button(fetch_btn)
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
	player_label.text = "ASSIGN PLAYER"
	player_label.add_theme_font_override("font", HudTokens.mono_font())
	player_label.add_theme_font_size_override("font_size", 12)
	player_label.add_theme_color_override("font_color", UiPolish.TEXT_MUTED)
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
	preview_label.text = "PREVIEW"
	preview_label.add_theme_font_override("font", HudTokens.mono_font())
	preview_label.add_theme_font_size_override("font_size", 12)
	preview_label.add_theme_color_override("font_color", UiPolish.TEXT_MUTED)
	vbox.add_child(preview_label)

	army_preview = RichTextLabel.new()
	army_preview.bbcode_enabled = true
	# Small minimum so a long army list never forces the dialog past its height and pushes
	# the buttons off — the label EXPANDs to fill the well and SCROLLS its content.
	army_preview.custom_minimum_size = Vector2(0, 80)
	army_preview.scroll_active = true
	army_preview.scroll_following = true
	army_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var preview_panel = PanelContainer.new()
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.add_theme_stylebox_override("panel", UiPolish.sunken_panel_style())
	vbox.add_child(preview_panel)
	preview_panel.add_child(army_preview)

	# Empty / loading / error state over the same well, so a wait never reads as blank.
	state_panel = StatePanel.new()
	state_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	state_panel.action_pressed.connect(_on_fetch_from_link)
	preview_panel.add_child(state_panel)
	_show_empty_state()

	# Button row
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)

	cancel_btn = Button.new()
	cancel_btn.text = "CANCEL"
	UiPolish.primary_button(cancel_btn)
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)

	import_btn = Button.new()
	import_btn.text = "IMPORT ARMY"
	import_btn.disabled = true
	import_btn.theme_type_variation = "PrimaryButton"
	UiPolish.primary_button(import_btn)
	import_btn.pressed.connect(_on_import)
	btn_row.add_child(import_btn)

	# API Client
	api_client = OPRApiClient.new()
	add_child(api_client)


## Borderless windows get no WM close/ESC; provide keyboard escape ourselves.
func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_on_cancel()
		get_viewport().set_input_as_handled()


func _on_paste_link() -> void:
	var clipboard = DisplayServer.clipboard_get()
	if not clipboard.is_empty():
		share_link_input.text = clipboard


func _on_fetch_from_link() -> void:
	var link = share_link_input.text.strip_edges()
	if link.is_empty():
		_set_status("No link entered", UiPolish.WARNING)
		return

	_set_status("Loading…", UiPolish.ACCENT)
	army_preview.visible = false
	state_panel.show_loading("LOADING ARMY", "Fetching from the Army Forge API…")
	import_btn.disabled = true
	fetch_btn.disabled = true

	# Fetch from API
	_preview_army = await api_client.import_from_share_link(link)
	fetch_btn.disabled = false
	if _preview_army and _preview_army.units.size() > 0:
		_set_status("Loaded!", UiPolish.SUCCESS)
		_show_loaded()
		_update_preview()
		import_btn.disabled = false
	elif _preview_army and _preview_army.units.size() == 0:
		_set_status("Empty", UiPolish.WARNING)
		state_panel.show_empty("EMPTY LIST", "This list contains no units. Add some in Army Forge first.")
		import_btn.disabled = true
	else:
		_set_status("Error", UiPolish.DESTRUCTIVE)
		state_panel.show_error("LOAD FAILED", "Check the link and your internet connection.", "RETRY")
		import_btn.disabled = true


## Toggle the preview well between the live army list and the state panel.
func _show_empty_state() -> void:
	army_preview.visible = false
	state_panel.show_empty("NO ARMY LOADED", "Paste an Army Forge share link or list ID above, then Load Army.")


func _show_loaded() -> void:
	state_panel.visible = false
	army_preview.visible = true


## Sets the inline link status text + colour (use a UiPolish token).
func _set_status(text: String, color: Color) -> void:
	link_status_label.text = text
	link_status_label.add_theme_color_override("font_color", color)


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
	var army := _preview_army  # _reset_dialog() nulls _preview_army; keep a reference

	# Hide + reset BEFORE emitting: the handler spawns the army synchronously (it blocks
	# the main thread), so anything after the emit would only run once loading is done —
	# the dialog would otherwise stay on screen over the loading overlay the whole time.
	hide()
	_reset_dialog()
	army_imported.emit(army, player_id)


func _on_cancel() -> void:
	hide()
	_reset_dialog()


func _reset_dialog() -> void:
	_preview_army = null
	share_link_input.text = ""
	link_status_label.text = ""
	army_preview.text = ""
	import_btn.disabled = true
	if state_panel:
		_show_empty_state()


## Sets the pre-selected player for import.
func set_player(player_id: int) -> void:
	# Find index for the given player ID
	for i in range(player_option.item_count):
		if player_option.get_item_id(i) == player_id:
			player_option.select(i)
			return

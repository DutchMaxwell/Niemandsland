extends CanvasLayer
class_name OPRImportDialog
## Import OPR Army Forge armies via share link — an in-viewport house-style sheet (D98 a).

signal army_imported(army: OPRApiClient.OPRArmy, player_id: int, ai_controlled: bool)

const LAYER := 108
const SHEET_W := 620

## UI Elements
var player_option: OptionButton
var ai_check: CheckBox   # "AI-controlled (Solo)" — goal 001 / bus 038
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
	layer = LAYER
	visibility_changed.connect(func() -> void:
		if visible:
			UiPolish.grab_first_focus.call_deferred(self))
	_setup_ui()


func _setup_ui() -> void:
	var parts := HouseStyle.overlay_sheet("Army import", SHEET_W)
	(parts["close"] as Button).pressed.connect(_on_cancel)
	add_child(parts["root"] as Control)
	var vbox: VBoxContainer = parts["body"]
	vbox.add_child(HouseStyle.label("/// NODE-01", HouseStyle.CAPTION))

	var link_section := VBoxContainer.new()
	link_section.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
	vbox.add_child(link_section)
	link_section.add_child(HouseStyle.label("ENTER ARMY FORGE SHARE LINK / LIST ID", HouseStyle.CAPTION))
	link_section.add_child(HouseStyle.label("e.g. https://army-forge.onepagerules.com/share?id=XXX", HouseStyle.CAPTION))
	share_link_input = LineEdit.new()
	share_link_input.placeholder_text = "Paste a share link or list ID here..."
	share_link_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	link_section.add_child(share_link_input)

	var link_btn_row := HBoxContainer.new()
	link_btn_row.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
	link_section.add_child(link_btn_row)
	var paste_link_btn := HouseStyle.button("FROM CLIPBOARD", HouseStyle.BUTTON, HouseStyle.H_ACTION)
	paste_link_btn.pressed.connect(_on_paste_link)
	link_btn_row.add_child(paste_link_btn)
	fetch_btn = HouseStyle.button("LOAD ARMY", HouseStyle.PRIMARY)
	fetch_btn.pressed.connect(_on_fetch_from_link)
	link_btn_row.add_child(fetch_btn)
	link_status_label = HouseStyle.label("", HouseStyle.CAPTION)
	link_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	link_btn_row.add_child(link_status_label)

	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
	vbox.add_child(player_row)
	player_row.add_child(HouseStyle.label("ASSIGN PLAYER", HouseStyle.CAPTION))
	player_option = OptionButton.new()
	player_option.theme_type_variation = HouseStyle.BUTTON
	player_option.add_item("Player 1 (Blue)", 1)
	player_option.add_item("Player 2 (Red)", 2)
	player_option.add_item("Player 3 (Green)", 3)
	player_option.add_item("Player 4 (Gold)", 4)
	player_option.select(0)
	player_row.add_child(player_option)
	# Solo mode: mark this army as AI-controlled at import (changeable later in the left-panel Solo section).
	ai_check = CheckBox.new()
	ai_check.text = "AI-controlled (Solo)"
	ai_check.tooltip_text = "The Solo AI plays this army (F11 runs its activations)."
	ai_check.focus_mode = Control.FOCUS_NONE
	player_row.add_child(ai_check)

	vbox.add_child(HouseStyle.label("PREVIEW", HouseStyle.CAPTION))
	army_preview = RichTextLabel.new()
	army_preview.bbcode_enabled = true
	army_preview.add_theme_color_override("default_color", HouseStyle.INK)
	# Small minimum so a long army list never pushes the buttons off: the label fills the well and scrolls.
	army_preview.custom_minimum_size = Vector2(0, 180)
	army_preview.scroll_active = true
	army_preview.scroll_following = true
	army_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var preview_panel := HouseStyle.card(army_preview)
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(preview_panel)
	# Empty / loading / error state over the same well, so a wait never reads as blank.
	state_panel = StatePanel.new()
	state_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	state_panel.action_pressed.connect(_on_fetch_from_link)
	preview_panel.add_child(state_panel)
	_show_empty_state()

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)
	cancel_btn = HouseStyle.button("CANCEL", HouseStyle.BUTTON, HouseStyle.H_ACTION)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)
	import_btn = HouseStyle.button("IMPORT ARMY", HouseStyle.PRIMARY)
	import_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	import_btn.disabled = true
	import_btn.pressed.connect(_on_import)
	btn_row.add_child(import_btn)

	api_client = OPRApiClient.new()
	add_child(api_client)


## No native window to close: give the keyboard escape ourselves.
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
		_set_status("No link entered", HouseStyle.TONE_WARN)
		return

	_set_status("Loading…", HouseStyle.TONE_ACCENT)
	army_preview.visible = false
	state_panel.show_loading("LOADING ARMY", "Fetching from the Army Forge API…")
	import_btn.disabled = true
	fetch_btn.disabled = true

	# Fetch from API
	_preview_army = await api_client.import_from_share_link(link)
	fetch_btn.disabled = false
	if _preview_army and _preview_army.units.size() > 0:
		_set_status("Loaded!", HouseStyle.TONE_OK)
		_show_loaded()
		_update_preview()
		import_btn.disabled = false
	elif _preview_army and _preview_army.units.size() == 0:
		_set_status("Empty", HouseStyle.TONE_WARN)
		state_panel.show_empty("EMPTY LIST", "This list contains no units. Add some in Army Forge first.")
		import_btn.disabled = true
	else:
		_set_status("Error", HouseStyle.TONE_DANGER)
		state_panel.show_error("LOAD FAILED", "Check the link and your internet connection.", "RETRY")
		import_btn.disabled = true


## Toggle the preview well between the live army list and the state panel.
func _show_empty_state() -> void:
	army_preview.visible = false
	state_panel.show_empty("NO ARMY LOADED", "Paste an Army Forge share link or list ID above, then Load Army.")


func _show_loaded() -> void:
	state_panel.visible = false
	army_preview.visible = true


## Sets the inline link status text + its tone (a HouseStyle TONE_*).
func _set_status(text: String, tone: StringName) -> void:
	link_status_label.text = text
	link_status_label.add_theme_color_override("font_color", HouseStyle.tone_ink(tone))


func _update_preview() -> void:
	if not _preview_army:
		army_preview.text = ""
		return

	var text = "[b]%s[/b]\n" % _preview_army.name
	text += "%s\n\n" % _tint(_preview_army.game_system, HouseStyle.MUTED)

	text += "[b]Points:[/b] %d | " % _preview_army.points
	text += "[b]Units:[/b] %d | " % _preview_army.units.size()
	if _preview_army.model_count > 0:
		text += "[b]Models:[/b] %d" % _preview_army.model_count
	text += "\n\n"

	for unit in _preview_army.units:
		var unit_line = "• %s" % unit.get_display_name()
		if unit.cost > 0:
			unit_line += " " + _tint("(%d pts)" % unit.cost, HouseStyle.GOLD)
		unit_line += " %s %s" % [_tint("Q%d+" % unit.quality, HouseStyle.OK), _tint("D%d+" % unit.defense, HouseStyle.ACCENT)]
		text += unit_line + "\n"

		# Show weapons
		if unit.weapons.size() > 0:
			var weapon_strs: Array[String] = []
			for w in unit.weapons:
				var ws = w.name
				if w.count > 1:
					ws = "%dx %s" % [w.count, w.name]
				weapon_strs.append(ws)
			text += "  %s\n" % _tint(", ".join(weapon_strs), HouseStyle.MUTED)

	army_preview.text = text


func _tint(text: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), text]


func _on_import() -> void:
	if not _preview_army:
		return

	var player_id = player_option.get_selected_id()
	_preview_army.player_id = player_id
	var army := _preview_army  # _reset_dialog() nulls _preview_army; keep a reference

	# Hide + reset BEFORE emitting: the handler spawns the army synchronously (it blocks
	# the main thread), so anything after the emit would only run once loading is done —
	# the dialog would otherwise stay on screen over the loading overlay the whole time.
	var ai_controlled: bool = ai_check != null and ai_check.button_pressed
	hide()
	_reset_dialog()
	army_imported.emit(army, player_id, ai_controlled)


func _on_cancel() -> void:
	hide()
	_reset_dialog()


func _reset_dialog() -> void:
	_preview_army = null
	share_link_input.text = ""
	link_status_label.text = ""
	army_preview.text = ""
	import_btn.disabled = true
	if ai_check:
		ai_check.button_pressed = false
	if state_panel:
		_show_empty_state()


## Sets the pre-selected player for import.
func set_player(player_id: int) -> void:
	# Find index for the given player ID
	for i in range(player_option.item_count):
		if player_option.get_item_id(i) == player_id:
			player_option.select(i)
			return

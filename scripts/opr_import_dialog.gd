extends CanvasLayer
class_name OPRImportDialog
## Import OPR Army Forge armies via share link — an in-viewport house-style sheet (D98 a).

signal army_imported(army: OPRApiClient.OPRArmy, player_id: int, ai_controlled: bool)

const LAYER := 108
const SHEET_W := 620

## UI Elements
var player_option: OptionButton
var ai_check: CheckBox   # "AI-controlled (Solo)" — goal 001 / bus 038
var army_preview: ScrollContainer   # the loaded list: a header, then one row per unit (sheet 04)
var _preview_rows: VBoxContainer
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
## The table's armies by seat (main sets it): an import into a held seat asks first. Null = no question.
var army_manager: OPRArmyManager = null


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

	var link_section := VBoxContainer.new()
	link_section.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
	vbox.add_child(link_section)
	link_section.add_child(HouseStyle.label("Army Forge share link or list ID", HouseStyle.CAPTION))
	link_section.add_child(HouseStyle.label("e.g. https://army-forge.onepagerules.com/share?id=XXX", HouseStyle.CAPTION))
	share_link_input = LineEdit.new()
	share_link_input.placeholder_text = "Paste a share link or list ID here..."
	share_link_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	link_section.add_child(share_link_input)

	var link_btn_row := HBoxContainer.new()
	link_btn_row.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
	link_section.add_child(link_btn_row)
	var paste_link_btn := HouseStyle.button("From clipboard", HouseStyle.BUTTON, HouseStyle.H_ACTION)
	paste_link_btn.pressed.connect(_on_paste_link)
	link_btn_row.add_child(paste_link_btn)
	fetch_btn = HouseStyle.button("Load army", HouseStyle.PRIMARY)
	fetch_btn.pressed.connect(_on_fetch_from_link)
	link_btn_row.add_child(fetch_btn)
	link_status_label = HouseStyle.label("", HouseStyle.CAPTION)
	link_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	link_btn_row.add_child(link_status_label)

	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
	vbox.add_child(player_row)
	player_row.add_child(HouseStyle.label("Assign player", HouseStyle.CAPTION))
	player_option = OptionButton.new()
	player_option.theme_type_variation = HouseStyle.BUTTON
	player_option.add_item("Player 1 (Blue)", 1)
	player_option.add_item("Player 2 (Red)", 2)
	player_option.add_item("Player 3 (Green)", 3)
	player_option.add_item("Player 4 (Gold)", 4)
	player_option.select(0)
	player_option.visible = false   # the hidden twin of the segment pair: holds the value the import reads
	player_row.add_child(player_option)
	# Two players as drawn (maintainer 27.11.); a room seats a third or fourth guest at 3 or 4, so set_player
	# shows that seat's own segment as well - the menu control changes, no seat loses its import.
	var segments := HouseStyle.button_row(["Player 1 (Blue)", "Player 2 (Red)", "Player 3 (Green)", "Player 4 (Gold)"],
		HouseStyle.SEGMENT, HouseStyle.H_SEGMENT)
	segments.name = "PlayerSegments"
	segments.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for i in segments.get_child_count():
		var segment := segments.get_child(i) as Button
		segment.custom_minimum_size.x = 150
		segment.visible = i < 2
		segment.pressed.connect(func() -> void: _select_player(i))
	player_row.add_child(segments)
	_select_player(0)
	# Solo mode: mark this army as AI-controlled at import (changeable later in the left-panel Solo section).
	ai_check = CheckBox.new()
	ai_check.text = "AI-controlled (Solo)"
	ai_check.tooltip_text = "The Solo AI plays this army (F11 runs its activations)."
	ai_check.focus_mode = Control.FOCUS_NONE
	player_row.add_child(ai_check)

	vbox.add_child(HouseStyle.label("Preview", HouseStyle.CAPTION))
	army_preview = ScrollContainer.new()
	army_preview.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Small minimum so a long army list never pushes the buttons off: the rows fill the well and scroll.
	army_preview.custom_minimum_size = Vector2(0, 180)
	army_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_rows = VBoxContainer.new()
	_preview_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_rows.add_theme_constant_override("separation", 0)
	army_preview.add_child(_preview_rows)
	var preview_panel := HouseStyle.card(army_preview)
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(preview_panel)
	# Empty / loading / error state over the same well, so a wait never reads as blank.
	state_panel = StatePanel.new()
	state_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	state_panel.action_pressed.connect(_on_fetch_from_link)
	state_panel.use_house_style()
	preview_panel.add_child(state_panel)
	_show_empty_state()

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)
	cancel_btn = HouseStyle.button("Cancel", HouseStyle.BUTTON, HouseStyle.H_ACTION)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)
	import_btn = HouseStyle.button("Import army", HouseStyle.PRIMARY)
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
	state_panel.show_loading("Loading army", "Fetching from the Army Forge API…")
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
		state_panel.show_empty("Empty list", "This list contains no units. Add some in Army Forge first.")
		import_btn.disabled = true
	else:
		_set_status("Error", HouseStyle.TONE_DANGER)
		state_panel.show_error("Load failed", "Check the link and your internet connection.", "RETRY")
		import_btn.disabled = true


## Toggle the preview well between the live army list and the state panel.
func _show_empty_state() -> void:
	army_preview.visible = false
	state_panel.show_empty("No army loaded", "Paste an Army Forge share link or list ID above, then Load army.")


func _show_loaded() -> void:
	state_panel.visible = false
	army_preview.visible = true


## Sets the inline link status text + its tone (a HouseStyle TONE_*).
func _set_status(text: String, tone: StringName) -> void:
	link_status_label.text = text
	link_status_label.add_theme_color_override("font_color", HouseStyle.tone_ink(tone))


## The loaded list as on sheet 04: its name and game system, "2000 PTS · 8 UNITS · 37 MODELS" in mono, then one row
## per unit - the name with quality, defense and weapons under it, the model count and the points (mono, gold).
func _update_preview() -> void:
	for child: Node in _preview_rows.get_children():
		_preview_rows.remove_child(child)
		child.queue_free()
	if not _preview_army:
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", HouseStyle.GAP_SECTION)
	var army_name := HouseStyle.label(_preview_army.name, HouseStyle.BODY)
	army_name.add_theme_font_override("font", HouseStyle.font(500))
	army_name.add_theme_font_size_override("font_size", HouseStyle.FONT_VALUE)
	head.add_child(army_name)
	var system := _preview_army.game_system
	head.add_child(HouseStyle.label(GameSystem.label(system) if GameSystem.is_known(system) else system, HouseStyle.NOTE))
	_preview_rows.add_child(head)
	var facts := "%d PTS · %d UNITS" % [_preview_army.points, _preview_army.units.size()]
	if _preview_army.model_count > 0:
		facts += " · %d MODELS" % _preview_army.model_count
	_preview_rows.add_child(_mono(facts, HouseStyle.MUTED))
	for unit in _preview_army.units:
		var weapon_strs: Array[String] = []
		for w in unit.weapons:
			weapon_strs.append("%dx %s" % [w.count, w.name] if w.count > 1 else w.name)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_constant_override("separation", 0)
		words.add_child(HouseStyle.label(unit.custom_name if not unit.custom_name.is_empty() else unit.name, HouseStyle.BODY))
		words.add_child(HouseStyle.label("  ".join(["Q%d+ D%d+" % [unit.quality, unit.defense]] + ([", ".join(weapon_strs)] if not weapon_strs.is_empty() else [])), HouseStyle.CAPTION))
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 42
		row.add_child(words)
		var count := HouseStyle.label("× %d" % unit.size, HouseStyle.CAPTION)
		count.custom_minimum_size.x = 70
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(count)
		var cost := _mono(str(unit.cost) if unit.cost > 0 else "", HouseStyle.GOLD)
		cost.custom_minimum_size.x = 90
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(cost)
		_preview_rows.add_child(row)
		var rule := ColorRect.new()
		rule.color = Color(HouseStyle.LINE, 0.6)
		rule.custom_minimum_size.y = 1
		_preview_rows.add_child(rule)


func _mono(text: String, colour: Color) -> Label:
	var l := HouseStyle.label(text, HouseStyle.CAPTION)
	l.add_theme_font_override("font", HouseStyle.mono())
	l.add_theme_color_override("font_color", colour)
	return l


func _on_import() -> void:
	if not _preview_army:
		return

	var player_id = player_option.get_selected_id()
	if army_manager != null and ArmyReplaceConfirm.occupied(army_manager.armies, player_id) \
			and not await ArmyReplaceConfirm.ask(army_manager.armies, player_id):
		return   # Keep: the window stays open with its list, another seat can be picked
	if _preview_army == null:
		return
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
	_update_preview()
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
			_select_player(i)
			return


## The segment pair and its hidden dropdown twin show the same player; a third or fourth seat shows its segment.
func _select_player(index: int) -> void:
	player_option.select(index)
	var segments := player_option.get_parent().get_node("PlayerSegments")
	for i in segments.get_child_count():
		var segment := segments.get_child(i) as Button
		HouseStyle.set_selected(segment, i == index)
		if i >= 2:
			segment.visible = i == index

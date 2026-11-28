extends CanvasLayer
class_name OPRImportDialog
## Import OPR Army Forge armies via share link — an in-viewport house-style sheet (D98 a).

signal army_imported(army: OPRApiClient.OPRArmy, player_id: int, ai_controlled: bool)

const LAYER := 108
const SHEET_W := 620
const ARMY_FORGE_URL := "https://army-forge.onepagerules.com"
const SHEET_W_MAX := 1320   # sheet 04: up to 1320 px wide, inputs left and the preview right
const TWO_COLUMNS_MIN_W := 1100.0   # a narrower window stacks the two columns as before

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
var _sheet: Control
var _columns: BoxContainer
var _preview_panel: Control
var _recent: VBoxContainer   # "RECENT LISTS" and up to five rows (sheet 04); hidden without a stored list
var _opponent_line: HBoxContainer   # "Need an opponent? … AI Opponent ›" (offline tables only)

## Parsed army (preview)
var _preview_army: OPRApiClient.OPRArmy = null

## API Client for parsing
var api_client: OPRApiClient
## The table's armies by seat (main sets it): an import into a held seat asks first. Null = no question.
var army_manager: OPRArmyManager = null
## Where the recent lists are kept (tests hand in a temporary file).
var recent_path := RecentArmyLists.DEFAULT


func _ready() -> void:
	layer = LAYER
	visibility_changed.connect(func() -> void:
		if visible:
			_fill_recent()
			_opponent_line.visible = _table() != null and not _table().network_manager.is_multiplayer_active()
			UiPolish.grab_first_focus.call_deferred(self))
	_setup_ui()


func _setup_ui() -> void:
	var parts := HouseStyle.overlay_sheet("Army import", SHEET_W)
	(parts["close"] as Button).pressed.connect(_on_cancel)
	add_child(parts["root"] as Control)
	(parts["root"] as Control).theme = HouseStyle.menu_theme()   # sheet 04 stands at the menu's scale, as the arrival card
	_sheet = parts["sheet"]
	var body: VBoxContainer = parts["body"]
	var title := HouseStyle.label("Bring your army.", HouseStyle.BODY)
	title.add_theme_font_override("font", HouseStyle.font(500))
	title.add_theme_font_size_override("font_size", HouseStyle.FONT_PAGE_TITLE)
	body.add_child(title)
	_columns = BoxContainer.new()
	_columns.add_theme_constant_override("separation", 30)
	body.add_child(_columns)
	var vbox := VBoxContainer.new()   # left: the link, its buttons and the player
	vbox.add_theme_constant_override("separation", HouseStyle.GAP_SECTION)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.add_child(vbox)
	var right := VBoxContainer.new()   # right: the preview with Cancel and Import army under it
	right.add_theme_constant_override("separation", HouseStyle.GAP_SECTION)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.15
	_columns.add_child(right)

	var link_section := VBoxContainer.new()
	link_section.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
	vbox.add_child(link_section)
	link_section.add_child(_eyebrow("Army Forge share link or list ID"))
	var example := HBoxContainer.new()
	example.add_child(HouseStyle.label("e.g. https://army-forge.onepagerules.com/share?id=XXX", HouseStyle.CAPTION))
	example.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var forge := _link_button("Open Army Forge", HouseStyle.ACCENT)
	forge.pressed.connect(func() -> void: OS.shell_open(ARMY_FORGE_URL))
	example.add_child(forge)
	link_section.add_child(example)
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
	player_row.add_child(_eyebrow("Assign player"))
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
	_recent = VBoxContainer.new()
	_recent.name = "RecentLists"
	_recent.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
	vbox.add_child(_recent)

	right.add_child(_eyebrow("Preview"))
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
	_preview_panel = preview_panel
	right.add_child(preview_panel)
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
	right.add_child(btn_row)
	cancel_btn = HouseStyle.button("Cancel", HouseStyle.BUTTON, HouseStyle.H_ACTION)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)
	import_btn = HouseStyle.button("Import army", HouseStyle.PRIMARY, HouseStyle.MENU_H_ACTION)
	import_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	import_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	import_btn.custom_minimum_size.x = 210   # room for its Enter cap at the right (sheet 04)
	var cap := HouseStyle.key_cap_on_gold("Enter")
	cap.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	cap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cap.offset_left = -14
	cap.offset_right = -14
	import_btn.add_child(cap)
	cancel_btn.custom_minimum_size.y = HouseStyle.MENU_H_ACTION
	import_btn.disabled = true
	import_btn.pressed.connect(_on_import)
	btn_row.add_child(import_btn)

	_opponent_line = HBoxContainer.new()
	_opponent_line.add_child(HouseStyle.label("Need an opponent? NACHTMAHR builds its own list.", HouseStyle.CAPTION))
	var ai := _link_button("AI Opponent ›", HouseStyle.GOLD)
	ai.pressed.connect(func() -> void:
		_on_cancel()
		TableOpponentLayer.open(_table()))   # the table's one opponent page (lead 27.11., Q1)
	_opponent_line.add_child(ai)
	_opponent_line.visible = false
	(parts["body"] as VBoxContainer).add_child(_opponent_line)

	api_client = OPRApiClient.new()
	add_child(api_client)
	get_viewport().size_changed.connect(_fit)
	_fit()


## The table this window imports into (the main scene), or null in a test or a tool.
func _table() -> Node:
	var scene := get_tree().current_scene if is_inside_tree() else null
	return scene if scene != null and scene.has_method("_table_system") and scene.get("network_manager") != null else null


## A field's name as sheet 04 draws it: a muted eyebrow in capitals (the text keeps its case for the code).
func _eyebrow(text: String) -> Label:
	var l := HouseStyle.label(text, HouseStyle.EYEBROW)
	l.uppercase = true
	l.add_theme_color_override("font_color", HouseStyle.MUTED)
	return l


func _link_button(text: String, colour: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.add_theme_color_override("font_color", colour)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


## RECENT LISTS (sheet 04): the stored lists as rows - name, the system's short tag (gold on the table's system), the
## points in mono and Load, which puts the stored link into the field and loads it fresh. No list, no section.
func _fill_recent() -> void:
	for child: Node in _recent.get_children():
		_recent.remove_child(child)
		child.queue_free()
	var lists := RecentArmyLists.load_all(recent_path)
	_recent.visible = not lists.is_empty()
	if lists.is_empty():
		return
	_recent.add_child(HouseStyle.label("RECENT LISTS", HouseStyle.EYEBROW))
	var table_system := str(_table().call("_table_system")) if _table() != null else ""
	for entry: Dictionary in lists:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 54
		row.add_theme_constant_override("separation", 14)
		var list_name := HouseStyle.label(str(entry.name), HouseStyle.BODY)
		list_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(list_name)
		var system := str(entry.system)
		var tag := _mono(GameSystem.short(system).to_upper() if GameSystem.is_known(system) else system.to_upper(),
			HouseStyle.GOLD if system == table_system else HouseStyle.MUTED)
		row.add_child(tag)
		row.add_child(_mono("%d PTS" % int(entry.points), HouseStyle.MUTED))
		var load_button := HouseStyle.button("Load", HouseStyle.BUTTON, 36)
		load_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		load_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		load_button.pressed.connect(func() -> void:
			share_link_input.text = str(entry.link)
			_on_fetch_from_link())
		row.add_child(load_button)
		var framed := PanelContainer.new()   # a framed row (sheet 04 .r)
		var box := StyleBoxFlat.new()
		box.bg_color = HouseStyle.FILL
		box.border_color = HouseStyle.LINE
		box.set_border_width_all(1)
		box.set_corner_radius_all(HouseStyle.RADIUS_CARD)
		box.content_margin_left = 14
		box.content_margin_right = 8
		framed.add_theme_stylebox_override("panel", box)
		row.custom_minimum_size.y = 52
		framed.add_child(row)
		_recent.add_child(framed)


## Sheet 04's measures: up to 1320 px wide with the two columns side by side and a tall preview; below 1100 px of window
## width the columns stack in today's 620 px sheet.
func _fit() -> void:
	_fit_to(get_viewport().get_visible_rect().size)


func _fit_to(window: Vector2) -> void:
	var wide := window.x >= TWO_COLUMNS_MIN_W
	_sheet.custom_minimum_size.x = minf(SHEET_W_MAX, window.x - 160.0) if wide else float(SHEET_W)
	_columns.vertical = not wide
	_preview_panel.custom_minimum_size.y = minf(520.0, window.y - 400.0) if wide else 0.0


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
	RecentArmyLists.remember({"link": share_link_input.text, "name": army.name, "system": army.game_system_abbrev,
		"points": army.points if army.points > 0 else army.get_total_points()}, recent_path)
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

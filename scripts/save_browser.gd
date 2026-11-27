class_name SaveBrowser
extends Control
## "Load game": one sheet over the dimmed menu that lists the saves of the save folder, newest first, each with
## its name, its date and a Load button. The fact lines (system, round, biome, size) are read one file per frame
## after the sheet is open, so fifty saves do not freeze the opening.

signal load_requested(path: String, button: Button)
signal closed

const ROW_H := 98
const ROW_H_SMALL := 78   # below 800 px of window height (three rows show at 720)
const PICTURE := Vector2(150, 78)
const PICTURE_SMALL := Vector2(120, 62)
const LOAD_W := 130
const FONT_NAME := 22
const MenuView = preload("res://scripts/startup_menu_view.gd")

var rows: VBoxContainer
var browse_button: Button
var file_dialog: FileDialog
var empty_note: VBoxContainer
var _facts: Array[Label] = []
var _saves: Array[Dictionary] = []
var _next := 0
var _small := false
var _pictures: Array[TextureRect] = []
var _loads: Array[Button] = []


## Builds the sheet over `host` for the saves of `dir` (default: the save folder).
func open(host: Node, dir := "") -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var parts := HouseStyle.overlay_sheet("Load game", 0)
	var root := parts["root"] as Control
	root.theme = HouseStyle.menu_theme()
	add_child(root)
	var view := host.get_viewport().get_visible_rect().size if host.is_inside_tree() else Vector2(1920, 1080)
	_small = view.y < 800
	(parts["sheet"] as Control).custom_minimum_size = Vector2(minf(1200, view.x - 128), minf(780, view.y - 120))
	(parts["close"] as Button).pressed.connect(close)
	HouseStyle.sheet_close_box(parts["close"] as Button)
	var body := parts["body"] as VBoxContainer
	body.add_child(_text("Open a saved game", HouseStyle.BODY, HouseStyle.FONT_PAGE_TITLE, HouseStyle.font(500)))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.follow_focus = true
	body.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	rows.add_theme_constant_override(&"separation", HouseStyle.GAP_SECTION)
	scroll.add_child(rows)
	var saves := SaveManager.list_saves(dir)
	for info: Dictionary in saves:
		rows.add_child(_row(info))
	empty_note = VBoxContainer.new()
	empty_note.size_flags_vertical = SIZE_EXPAND_FILL
	empty_note.alignment = BoxContainer.ALIGNMENT_CENTER
	empty_note.visible = saves.is_empty()
	scroll.visible = not saves.is_empty()   # the empty list takes no half of the sheet: the note stands in its middle
	for line: Array in [["No saved games yet.", HouseStyle.BODY],
			["Games you save at the table appear here.", HouseStyle.CAPTION]]:
		var label := HouseStyle.label(line[0], line[1])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_note.add_child(label)
	body.add_child(empty_note)
	body.add_child(_footer(saves.size()))
	_saves = saves
	host.add_child(self)
	_chain()
	if not _loads.is_empty():
		_loads[0].grab_focus.call_deferred()


## "<n> SAVES IN YOUR SAVES FOLDER", then "Open saves folder" and "Browse files…" (any folder, any .nml).
func _footer(count: int) -> HBoxContainer:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", HouseStyle.GAP_ROW)
	var line := "%d SAVE%s IN YOUR SAVES FOLDER" % [count, "" if count == 1 else "S"]
	var count_label := _text(line, HouseStyle.CAPTION, HouseStyle.MENU_FONT_EYEBROW, HouseStyle.mono())
	count_label.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(count_label)
	var folder := HouseStyle.button("Open saves folder", HouseStyle.BUTTON, HouseStyle.MENU_H_ACTION)
	folder.name = "OpenFolder"
	folder.pressed.connect(func() -> void: OS.shell_show_in_file_manager(SaveManager.get_default_save_dir()))
	browse_button = HouseStyle.button("Browse files…", HouseStyle.BUTTON, HouseStyle.MENU_H_ACTION)
	browse_button.pressed.connect(_open_file_dialog)
	for b: Button in [folder, browse_button]:
		b.focus_mode = FOCUS_ALL
		b.size_flags_horizontal = SIZE_SHRINK_END
		footer.add_child(b)
	return footer


func _open_file_dialog() -> void:
	if file_dialog == null:
		file_dialog = FileDialog.new()
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.filters = PackedStringArray(["*.nml ; Niemandsland Save Files"])
		file_dialog.title = "Load game"
		# FileDialog derives its OK label from file_mode and takes both button labels from
		# Godot's own translations, i.e. from the SYSTEM language — on a German Windows the
		# English-only UI would otherwise show localized Open/Cancel labels. Pin them
		# explicitly, AFTER file_mode (set_file_mode rewrites ok_button_text).
		file_dialog.ok_button_text = "Open"
		file_dialog.cancel_button_text = "Cancel"
		file_dialog.file_selected.connect(func(path: String) -> void: load_requested.emit(path, null))
		file_dialog.theme = HouseStyle.theme()   # native FileDialog: the theme only
		add_child(file_dialog)
		# A hard 800x600 is nearly full-screen on a 1366x768 laptop; clamp to the host
		# window instead (and re-clamp when it is resized).
		UiPolish.keep_window_reachable(file_dialog, Vector2i(800, 600))
	file_dialog.current_dir = SaveManager.get_default_save_dir()
	file_dialog.popup_centered()


func close() -> void:
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _row(info: Dictionary) -> PanelContainer:
	var row := HouseStyle.card()
	row.custom_minimum_size.y = ROW_H_SMALL if _small else ROW_H
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", HouseStyle.MENU_PAD_PANEL)
	row.add_child(line)
	var picture := TextureRect.new()   # the save's biome picture, shown once its facts are read
	picture.custom_minimum_size = PICTURE_SMALL if _small else PICTURE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.size_flags_vertical = SIZE_SHRINK_CENTER
	picture.visible = false
	line.add_child(picture)
	_pictures.append(picture)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_child(words)
	var title := _text(str(info.name), HouseStyle.BODY, 19 if _small else FONT_NAME, HouseStyle.font(500))
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	words.add_child(title)
	var facts := _text("", HouseStyle.CAPTION, HouseStyle.MENU_FONT_EYEBROW, HouseStyle.mono())
	facts.name = "Facts"
	words.add_child(facts)
	_facts.append(facts)
	line.add_child(_text(_date(int(info.modified_unix)), HouseStyle.CAPTION, 16))
	var button := HouseStyle.button("Load", HouseStyle.BUTTON, HouseStyle.MENU_H_ACTION)
	button.focus_mode = FOCUS_ALL
	button.custom_minimum_size.x = LOAD_W
	button.size_flags_horizontal = SIZE_SHRINK_END
	button.size_flags_vertical = SIZE_SHRINK_CENTER
	button.pressed.connect(func() -> void: load_requested.emit(str(info.path), button))
	var cap := HouseStyle.key_cap_on_gold("Enter")
	cap.name = "EnterCap"
	cap.mouse_filter = MOUSE_FILTER_IGNORE
	cap.set_anchors_preset(PRESET_CENTER_RIGHT)
	cap.grow_horizontal = GROW_DIRECTION_BEGIN
	cap.grow_vertical = GROW_DIRECTION_BOTH
	cap.offset_left = -10
	cap.offset_right = -10
	cap.visible = false
	button.add_child(cap)
	line.add_child(button)
	_loads.append(button)
	button.focus_entered.connect(_select.bind(row))
	row.mouse_entered.connect(button.grab_focus)
	return row


## The selected row (the one with focus): accent fill at 10 %, a 1 px gold rim, its Load gold with an Enter cap.
func _select(selected: PanelContainer) -> void:
	for i in rows.get_child_count():
		var row := rows.get_child(i) as PanelContainer
		var on := row == selected
		var box := StyleBoxFlat.new()
		box.bg_color = HouseStyle.ROW_HOVER
		box.border_color = HouseStyle.GOLD
		box.set_border_width_all(HouseStyle.BORDER)
		box.set_corner_radius_all(HouseStyle.RADIUS_CARD)
		box.set_content_margin_all(HouseStyle.PAD_CARD_X)
		if on:
			row.add_theme_stylebox_override(&"panel", box)
		else:
			row.remove_theme_stylebox_override(&"panel")
		_loads[i].theme_type_variation = HouseStyle.PRIMARY if on else HouseStyle.BUTTON
		_loads[i].alignment = HORIZONTAL_ALIGNMENT_LEFT if on else HORIZONTAL_ALIGNMENT_CENTER
		(_loads[i].get_node("EnterCap") as Control).visible = on


## Up / Down walk the rows' Load buttons; Tab goes on to the footer, the close box and back to the first row.
func _chain() -> void:
	var stops: Array[Control] = []
	stops.append_array(_loads)
	stops.append_array([find_child("OpenFolder", true, false), browse_button, find_child("CloseButton", true, false)])
	for i in stops.size():
		stops[i].focus_mode = FOCUS_ALL
		stops[i].focus_next = stops[i].get_path_to(stops[(i + 1) % stops.size()])
		stops[i].focus_previous = stops[i].get_path_to(stops[i - 1])
	for i in _loads.size():
		_loads[i].focus_neighbor_top = _loads[i].get_path_to(_loads[maxi(i - 1, 0)])
		_loads[i].focus_neighbor_bottom = _loads[i].get_path_to(_loads[mini(i + 1, _loads.size() - 1)])


## One save per frame: its facts as one upper-case mono line ("GRIMDARK FUTURE · ROUND 1 · GRASSLAND · 6 x 4 FT").
func _process(_delta: float) -> void:
	if _next >= _saves.size():
		set_process(false)
		return
	var facts := SaveManager.save_facts(str(_saves[_next].path))
	_facts[_next].text = " · ".join(MenuView.facts_lines(facts))
	var picture := TableSizeDialog.preview_path(str(facts.get("biome", "")))
	if not picture.is_empty() and ResourceLoader.exists(picture):
		_pictures[_next].texture = load(picture)
		_pictures[_next].visible = true
	_next += 1


## "26 Nov 2026 · 07:31" in local time (the unix time is UTC).
static func _date(unix: int) -> String:
	var stamp := Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().bias) * 60)
	return "%d %s %d · %02d:%02d" % [stamp.day, MenuView.MONTHS[stamp.month - 1], stamp.year, stamp.hour, stamp.minute]


func _text(text: String, variant: StringName, font_size: int, font: Font = null) -> Label:
	var label := HouseStyle.label(text, variant)
	label.add_theme_font_size_override(&"font_size", font_size)
	if font != null:
		label.add_theme_font_override(&"font", font)
	return label

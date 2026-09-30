class_name BattleLogPanel
extends PanelContainer
## In-game Battle Log panel — a collapsible HUD window in the house style (HouseStyle, maintainer D98 = a)
## that shows the BattleLog's entries as compact one-liners with a round prefix, newest pinned to view.
## One filter dropdown (All / Combat / Movement / AI). Placed by main.gd; fed by a BattleLog via bind().
## AI lines are the gold key lines, so they stand out; a line with reasoning folds out under a mark.

const MAX_VISIBLE := 200

## The player pressed Export — main.gd writes the log to a user:// file (adding the AI decision records when
## the dev "AI reasoning" toggle is on) and reports the path. A signal so the panel stays free of
## SoloController / dev-mode knowledge.
signal export_requested()
signal copy_requested()
## The panel opened or closed (the top bar's Battle Log button follows it).
signal open_changed(open: bool)

var _log: BattleLog = null
var _open := false   # starts collapsed to a top-centre tab; click the header to expand downward
var _filter := BattleLog.Filter.ALL

var _header: Button = null
var _body: VBoxContainer = null
var _filter_opt: OptionButton = null
var _scroll: ScrollContainer = null
var _list: VBoxContainer = null


func _ready() -> void:
	HouseStyle.apply(self)
	custom_minimum_size = Vector2(340, 0)   # width only — the panel shrinks to the header when collapsed
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", HouseStyle.GAP_CONTROL)
	add_child(col)

	# Collapsed by default (▼ = click to expand downward).
	_header = HouseStyle.button("▼  Battle Log", HouseStyle.BUTTON)
	_header.pressed.connect(_toggle)
	col.add_child(_header)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", HouseStyle.GAP_CONTROL)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", HouseStyle.GAP_CONTROL)
	_body.add_child(controls)

	_filter_opt = OptionButton.new()
	_filter_opt.theme_type_variation = HouseStyle.BUTTON
	_filter_opt.focus_mode = Control.FOCUS_NONE
	_filter_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_opt.add_item("All", BattleLog.Filter.ALL)
	_filter_opt.add_item("Combat", BattleLog.Filter.COMBAT)
	_filter_opt.add_item("Movement", BattleLog.Filter.MOVEMENT)
	_filter_opt.add_item("AI", BattleLog.Filter.AI)
	_filter_opt.item_selected.connect(_on_filter_changed)
	controls.add_child(_filter_opt)

	# Export the full log to a shareable file (the maintainer's field-test artefact). main.gd does the write.
	var export_btn := HouseStyle.button("Export", HouseStyle.BUTTON)
	export_btn.size_flags_horizontal = Control.SIZE_FILL   # as wide as its word; the filter takes the rest
	export_btn.pressed.connect(func() -> void: export_requested.emit())
	controls.add_child(export_btn)

	# Maintainer request (live-test loop): one click puts the whole log on the clipboard,
	# ready to paste into a chat/issue — the file export stays for archiving.
	var copy_btn := HouseStyle.button("Copy", HouseStyle.BUTTON)
	copy_btn.size_flags_horizontal = Control.SIZE_FILL
	copy_btn.pressed.connect(func() -> void: copy_requested.emit())
	controls.add_child(copy_btn)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 220)   # log height when expanded
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	_body.visible = _open   # start collapsed (just the header tab)


## Attach a BattleLog: render its current entries and follow new ones.
func bind(log_node: BattleLog) -> void:
	if _log != null and _log.entry_added.is_connected(_on_entry_added):
		_log.entry_added.disconnect(_on_entry_added)
		_log.cleared.disconnect(_rebuild)
	_log = log_node
	if _log != null:
		_log.entry_added.connect(_on_entry_added)
		_log.cleared.connect(_rebuild)
	_rebuild()


func _on_filter_changed(idx: int) -> void:
	_filter = _filter_opt.get_item_id(idx)
	_rebuild()


func _on_entry_added(entry: Dictionary) -> void:
	if not _passes(entry):
		return
	_list.add_child(_entry_label(entry))
	while _list.get_child_count() > MAX_VISIBLE:
		var old := _list.get_child(0)
		_list.remove_child(old)
		old.queue_free()
	_pin_to_newest()


func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if _log == null:
		return
	for entry in _log.entries(_filter):
		_list.add_child(_entry_label(entry))
	_pin_to_newest()


## Auto-scroll to the newest entry AFTER the list re-lays out (the dice-log live-scroll technique:
## recompute against the scrollbar's max once layout is final, else the new row isn't measured yet).
func _pin_to_newest() -> void:
	if not is_inside_tree() or _scroll == null:
		return
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _passes(entry: Dictionary) -> bool:
	match _filter:
		BattleLog.Filter.COMBAT:
			return int(entry["category"]) == BattleLog.Category.COMBAT
		BattleLog.Filter.MOVEMENT:
			return int(entry["category"]) == BattleLog.Category.MOVEMENT
		BattleLog.Filter.AI:
			return bool(entry["ai"])
		_:
			return true


func _entry_label(entry: Dictionary) -> Control:
	var l := HouseStyle.label(BattleLog.format_entry(entry), HouseStyle.NOTE if bool(entry["ai"]) else HouseStyle.SMALL)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var detail := str(entry.get("detail", ""))
	if detail.is_empty():
		return l
	# Stage 3 (transparency, grilled 2026-07-30): a line with REASONING expands on click and
	# carries it as the hover tooltip — "why did the AI do that" lives one click away.
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text = HouseStyle.GLYPH_GO + " " + l.text   # folded; the UI font has no ▸ ▾
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.tooltip_text = detail
	var d := HouseStyle.label("    " + detail, HouseStyle.CAPTION)
	d.visible = false
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			d.visible = not d.visible
			l.text = (HouseStyle.GLYPH_COLLAPSE if d.visible else HouseStyle.GLYPH_GO) + " " + l.text.substr(2))
	box.add_child(l)
	box.add_child(d)
	return box


func _toggle() -> void:
	set_open(not _open)


func is_open() -> bool:
	return _open


## Expands the panel downward or folds it back to its header.
func set_open(open: bool) -> void:
	if open == _open:
		return
	_open = open
	_body.visible = _open
	# Top-edge panel: ▲ collapses up (open), ▼ expands down (collapsed).
	_header.text = ("▲  Battle Log" if _open else "▼  Battle Log")
	reset_size()
	open_changed.emit(_open)


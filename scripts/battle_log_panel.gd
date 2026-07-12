class_name BattleLogPanel
extends PanelContainer
## In-game Battle Log panel — a collapsible HUD panel (Tactical-HUD language: dark navy / cyan / amber)
## that shows the BattleLog's entries as compact one-liners with a round prefix, newest pinned to view.
## One filter dropdown (All / Combat / Movement / AI). Placed by main.gd; fed by a BattleLog via bind().

const NAVY := Color(0.10, 0.13, 0.19, 0.96)
const NAVY_HI := Color(0.16, 0.20, 0.28)
const CYAN := Color(0.36, 0.80, 0.92)
const AMBER := Color(0.96, 0.62, 0.18)
const TEXT := Color(0.86, 0.90, 0.95)
const TEXT_DIM := Color(0.58, 0.64, 0.72)
const AI_TINT := Color(0.96, 0.62, 0.18)      # AI lines get an amber tint so they stand out
const ENTRY_FONT := 12
const MAX_VISIBLE := 200

## The player pressed Export — main.gd writes the log to a user:// file (adding the AI decision records when
## the dev "AI reasoning" toggle is on) and reports the path. A signal so the panel stays free of
## SoloController / dev-mode knowledge.
signal export_requested()

var _log: BattleLog = null
var _open := false   # starts collapsed to a top-centre tab; click the header to expand downward
var _filter := BattleLog.Filter.ALL

var _header: Button = null
var _body: VBoxContainer = null
var _filter_opt: OptionButton = null
var _scroll: ScrollContainer = null
var _list: VBoxContainer = null


func _ready() -> void:
	add_theme_stylebox_override("panel", _panel_style())
	custom_minimum_size = Vector2(340, 0)   # width only — the panel shrinks to the header when collapsed
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)

	_header = Button.new()
	_header.text = "▼  Battle Log"   # collapsed by default (▼ = click to expand downward)
	_header.focus_mode = Control.FOCUS_NONE
	_header.add_theme_font_size_override("font_size", 13)
	_header.add_theme_color_override("font_color", CYAN)
	_header.add_theme_stylebox_override("normal", _flat(NAVY_HI))
	_header.add_theme_stylebox_override("hover", _flat(NAVY_HI))
	_header.add_theme_stylebox_override("pressed", _flat(NAVY_HI))
	_header.pressed.connect(_toggle)
	col.add_child(_header)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	_body.add_child(controls)

	_filter_opt = OptionButton.new()
	_filter_opt.focus_mode = Control.FOCUS_NONE
	_filter_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_opt.add_item("All", BattleLog.Filter.ALL)
	_filter_opt.add_item("Combat", BattleLog.Filter.COMBAT)
	_filter_opt.add_item("Movement", BattleLog.Filter.MOVEMENT)
	_filter_opt.add_item("AI", BattleLog.Filter.AI)
	_filter_opt.item_selected.connect(_on_filter_changed)
	controls.add_child(_filter_opt)

	# Export the full log to a shareable file (the maintainer's field-test artefact). main.gd does the write.
	var export_btn := Button.new()
	export_btn.text = "Export"
	export_btn.focus_mode = Control.FOCUS_NONE
	export_btn.add_theme_font_size_override("font_size", 12)
	export_btn.add_theme_color_override("font_color", AMBER)
	export_btn.add_theme_stylebox_override("normal", _flat(NAVY_HI))
	export_btn.add_theme_stylebox_override("hover", _flat(NAVY_HI))
	export_btn.add_theme_stylebox_override("pressed", _flat(NAVY_HI))
	export_btn.pressed.connect(func() -> void: export_requested.emit())
	controls.add_child(export_btn)

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


func _entry_label(entry: Dictionary) -> Label:
	var l := Label.new()
	l.text = BattleLog.format_entry(entry)
	l.add_theme_font_size_override("font_size", ENTRY_FONT)
	l.add_theme_color_override("font_color", AI_TINT if bool(entry["ai"]) else TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _toggle() -> void:
	_open = not _open
	_body.visible = _open
	# Top-edge panel: ▲ collapses up (open), ▼ expands down (collapsed).
	_header.text = ("▲  Battle Log" if _open else "▼  Battle Log")
	reset_size()


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = NAVY
	s.set_corner_radius_all(6)
	s.set_border_width_all(1)
	s.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.35)
	s.set_content_margin_all(8)
	return s


func _flat(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(4)
	s.set_content_margin_all(4)
	return s

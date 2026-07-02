class_name UnitDock
extends Control
## Army unit-card UI. Two parts:
##  • a compact centre-bottom TAB button that slides up a horizontally-scrollable STRIP of compact
##    cards, one per the local player's units (player-colour tinted, activation-dimmed, coherency-flagged);
##  • a single PRESENTED card that flies in — with a slight curved, card-like "deal" motion — and
##    settles at the bottom centre whenever a unit is selected (and the strip is not open). It carries
##    the unit's live stats/status plus action buttons (activate, fatigued, shaken, casts, wounds,
##    details, revive), replacing the old detail UnitCard as the on-selection readout.
## Cards select their whole unit on click, locate it on hover, and centre the camera on double-click.

const TAB_W := 168
const TAB_H := 28
const STRIP_H := 100
const CARD_W := 152
const PCARD_W := 320
const PCARD_H := 188
const GAP_ABOVE_TAB := 12
const REFRESH_INTERVAL := 0.4

# Injected by main.gd.
var army_manager: OPRArmyManager = null
var object_manager = null
var network_manager = null
var camera_controller = null
var radial_menu_controller = null
var unit_card_detail = null            # the old full UnitCard, reused for the "Details" expansion

var _dock_open := false
var _tab: Button = null
var _strip_panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _strip: HBoxContainer = null
var _cards: Dictionary = {}            # unit_id -> {card, name, stats, status}
var _presented: PanelContainer = null
var _p_name: Label = null
var _p_stats: Label = null
var _p_status: Label = null
var _p_coherency: Label = null
var _p_actions: HBoxContainer = null
var _btn_cast: Button = null
var _btn_revive: Button = null
var _presented_unit: GameUnit = null
var _refresh_timer: Timer = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_tab()
	_build_strip()
	_build_presented()
	resized.connect(_layout)
	_layout()
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = REFRESH_INTERVAL
	_refresh_timer.timeout.connect(_refresh_status)
	add_child(_refresh_timer)
	_refresh_timer.start()


func setup(p_army_manager: OPRArmyManager, p_object_manager, p_network_manager, p_camera, p_unit_card) -> void:
	army_manager = p_army_manager
	object_manager = p_object_manager
	network_manager = p_network_manager
	camera_controller = p_camera
	unit_card_detail = p_unit_card
	if object_manager != null and object_manager.has_signal("selection_changed"):
		object_manager.selection_changed.connect(_on_table_selection_changed)
	rebuild()


func set_radial_controller(rmc) -> void:
	radial_menu_controller = rmc


# === Build ===

func _build_tab() -> void:
	_tab = Button.new()
	_tab.custom_minimum_size = Vector2(TAB_W, TAB_H)
	_tab.size = Vector2(TAB_W, TAB_H)
	_tab.text = "▲  Units"
	_tab.focus_mode = Control.FOCUS_NONE
	_tab.mouse_filter = Control.MOUSE_FILTER_STOP
	_tab.pressed.connect(_toggle_dock)
	add_child(_tab)


func _build_strip() -> void:
	_strip_panel = PanelContainer.new()
	_strip_panel.add_theme_stylebox_override("panel", _panel_style())
	_strip_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, STRIP_H)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_strip_panel.add_child(_scroll)
	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override("separation", 6)
	_scroll.add_child(_strip)
	add_child(_strip_panel)


func _build_presented() -> void:
	_presented = PanelContainer.new()
	_presented.custom_minimum_size = Vector2(PCARD_W, PCARD_H)
	_presented.size = Vector2(PCARD_W, PCARD_H)
	_presented.pivot_offset = Vector2(PCARD_W / 2.0, PCARD_H / 2.0)
	_presented.add_theme_stylebox_override("panel", _card_face_style(Color(0.55, 0.78, 0.95)))
	_presented.mouse_filter = Control.MOUSE_FILTER_STOP
	_presented.visible = false
	var mc := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 12)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	_p_name = Label.new()
	_p_name.add_theme_font_size_override("font_size", 21)
	_p_name.clip_text = true
	_p_stats = Label.new()
	_p_stats.add_theme_font_size_override("font_size", 16)
	_p_status = Label.new()
	_p_status.add_theme_font_size_override("font_size", 14)
	_p_coherency = Label.new()
	_p_coherency.add_theme_font_size_override("font_size", 13)
	_p_coherency.add_theme_color_override("font_color", Color(1.0, 0.5, 0.35))
	box.add_child(_p_name)
	box.add_child(_p_stats)
	box.add_child(_p_status)
	box.add_child(_p_coherency)
	box.add_child(_build_actions())
	mc.add_child(box)
	_presented.add_child(mc)
	add_child(_presented)
	_presented.gui_input.connect(_on_presented_input)


func _build_actions() -> HBoxContainer:
	_p_actions = HBoxContainer.new()
	_p_actions.add_theme_constant_override("separation", 4)
	_p_actions.mouse_filter = Control.MOUSE_FILTER_STOP
	_add_action("Act", func(): _card_action("activation"))
	_add_action("Fat", func(): _card_action("fatigued"))
	_add_action("Shk", func(): _card_action("shaken"))
	_btn_cast = _add_action("Cast", func(): _card_action("casts"))
	_add_action("Wnd", func(): _card_action("wounds"))
	_add_action("Info", func(): _card_action("details"))
	_btn_revive = _add_action("Revive", func(): _card_action("revive"))
	return _p_actions


func _add_action(label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.pressed.connect(cb)
	_p_actions.add_child(b)
	return b


# === Layout ===

func _layout() -> void:
	var vp := get_viewport_rect().size
	if _tab != null:
		_tab.position = Vector2(vp.x / 2.0 - TAB_W / 2.0, vp.y - TAB_H)
	if _strip_panel != null:
		_strip_panel.size = Vector2(vp.x, STRIP_H)
		_strip_panel.position = Vector2(0, _strip_target_y(_dock_open))
	if _presented != null and _presented.visible:
		_presented.position = _presented_rest_pos()


func _strip_target_y(open: bool) -> float:
	var vp := get_viewport_rect().size
	return (vp.y - STRIP_H - TAB_H) if open else vp.y


func _presented_rest_pos() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x / 2.0 - PCARD_W / 2.0, vp.y - PCARD_H - TAB_H - GAP_ABOVE_TAB)


# === Strip show/hide ===

func _toggle_dock() -> void:
	_dock_open = not _dock_open
	_tab.text = ("▼  Units" if _dock_open else "▲  Units")
	var tw := create_tween()
	tw.tween_property(_strip_panel, "position:y", _strip_target_y(_dock_open), 0.2).set_trans(Tween.TRANS_CUBIC)
	if _dock_open:
		_presented.visible = false
	elif _presented_unit != null:
		_animate_card_in()


# === Compact strip cards ===

func rebuild() -> void:
	if _strip == null:
		return
	for child in _strip.get_children():
		child.queue_free()
	_cards.clear()
	# Sort: living units before wiped ones, then by name (⑨ grouping) — applied only on rebuild so
	# live status changes don't reshuffle the row under the player's cursor.
	var units := _local_units()
	units.sort_custom(_sort_units)
	for unit in units:
		_add_card(unit)
	_refresh_status()


func _sort_units(a, b) -> bool:
	var au := a as GameUnit
	var bu := b as GameUnit
	if au == null or bu == null:
		return false
	var a_dead: bool = au.get_alive_count() == 0
	var b_dead: bool = bu.get_alive_count() == 0
	if a_dead != b_dead:
		return b_dead   # living first
	return au.get_name() < bu.get_name()


func _local_units() -> Array:
	if army_manager == null:
		return []
	var slot := 0
	if network_manager != null and network_manager.has_method("get_my_player_slot"):
		slot = int(network_manager.get_my_player_slot())
	if slot > 0:
		return army_manager.get_game_units_for_player(slot)
	# Single-player / slot not yet assigned in MP: show every unit.
	return army_manager.get_all_game_units()


func _add_card(unit: GameUnit) -> void:
	if unit == null:
		return
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel", _card_style(false, _unit_color(unit)))
	var mc := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 6)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var name_lbl := Label.new()
	name_lbl.text = unit.get_name()
	name_lbl.clip_text = true
	name_lbl.add_theme_font_size_override("font_size", 13)
	var stats_lbl := Label.new()
	stats_lbl.add_theme_font_size_override("font_size", 12)
	var status_lbl := Label.new()
	status_lbl.add_theme_font_size_override("font_size", 12)
	box.add_child(name_lbl)
	box.add_child(stats_lbl)
	box.add_child(status_lbl)
	mc.add_child(box)
	card.add_child(mc)
	card.gui_input.connect(_on_card_input.bind(unit))
	card.mouse_entered.connect(_on_card_hover.bind(unit, true))
	card.mouse_exited.connect(_on_card_hover.bind(unit, false))
	_strip.add_child(card)
	_cards[unit.unit_id] = {"card": card, "name": name_lbl, "stats": stats_lbl, "status": status_lbl, "accent": _unit_color(unit)}


# === Live status ===

func _refresh_status() -> void:
	for unit: GameUnit in _local_units():
		var entry = _cards.get(unit.unit_id)
		if entry == null:
			continue
		(entry["stats"] as Label).text = _stat_line(unit)
		(entry["status"] as Label).text = _status_line(unit)
		var card := entry["card"] as PanelContainer
		var dim: bool = unit.is_activated or unit.get_alive_count() == 0
		card.modulate = Color(1, 1, 1, 0.45) if dim else Color(1, 1, 1, 1)
	if _presented_unit != null and _presented.visible:
		_fill_presented(_presented_unit)


func _stat_line(unit: GameUnit) -> String:
	return "Q%d+  D%d+   %d/%d" % [unit.get_quality(), unit.get_defense(), unit.get_alive_count(), unit.models.size()]


func _status_line(unit: GameUnit) -> String:
	var parts: Array[String] = []
	if unit.is_activated:
		parts.append("✓ Act")
	if unit.is_fatigued:
		parts.append("Fatigued")
	if unit.is_shaken:
		parts.append("Shaken")
	if unit.is_caster():
		parts.append("Cast %d" % unit.casts_current)
	if unit.get_alive_count() == 0:
		parts.append("† dead")
	elif not _is_coherent(unit):
		parts.append("⚠ Coherency")
	return "   ".join(parts) if not parts.is_empty() else "ready"


func _is_coherent(unit: GameUnit) -> bool:
	if unit.get_alive_count() <= 1:
		return true
	var res = CoherencyChecker.check_unit_coherency(unit, CoherencyChecker.is_skirmish_system(unit))
	return res.valid if res != null else true


# === Presented card ===

func present_unit(unit: GameUnit) -> void:
	if unit == null:
		_presented_unit = null
		_animate_card_out()
		return
	var same: bool = unit == _presented_unit
	_presented_unit = unit
	_fill_presented(unit)
	if _dock_open:
		_presented.visible = false
		return
	if same and _presented.visible:
		return
	_animate_card_in()


func _fill_presented(unit: GameUnit) -> void:
	_p_name.text = unit.get_name()
	_p_stats.text = _stat_line(unit)
	_p_status.text = _status_line(unit)
	var dead: bool = unit.get_alive_count() == 0
	_p_coherency.visible = (not dead) and (not _is_coherent(unit))
	_p_coherency.text = "⚠ Unit out of coherency"
	_btn_cast.visible = unit.is_caster()
	_btn_revive.visible = dead
	_presented.add_theme_stylebox_override("panel", _card_face_style(_unit_color(unit)))


func _animate_card_in() -> void:
	var rest := _presented_rest_pos()
	_presented.visible = true
	_presented.position = rest + Vector2(46, 250)
	_presented.rotation = deg_to_rad(7.0)
	_presented.scale = Vector2(0.82, 0.82)
	_presented.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_presented, "position", rest, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_presented, "rotation", 0.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_presented, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_presented, "modulate:a", 1.0, 0.18)


func _animate_card_out() -> void:
	if _presented == null or not _presented.visible:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_presented, "position:y", _presented.position.y + 210, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_presented, "modulate:a", 0.0, 0.18)
	tw.set_parallel(false)
	tw.tween_callback(func() -> void: _presented.visible = false)


# === Card actions (⑤⑥⑦⑧) ===

func _card_action(kind: String) -> void:
	var unit := _presented_unit
	# D6: log every dispatch so live QA can SEE that a button press arrives here and where it routes
	# (a silent log on click = the press never reached the button → an input/overlay issue, not routing).
	print("[UnitDock] card action '%s' → unit=%s, controller=%s" % [
		kind, (unit.get_name() if unit != null else "<none>"), str(radial_menu_controller != null)])
	if unit == null:
		return
	# Defensive (D6): if the controller ref was never set or was dropped, resolve it from the scene so
	# the action still dispatches instead of silently no-op'ing.
	if radial_menu_controller == null:
		radial_menu_controller = get_tree().root.get_node_or_null("Main/RadialMenuController")
		if radial_menu_controller == null:
			push_warning("[UnitDock] no radial controller — card action '%s' dropped" % kind)
	match kind:
		"details":
			if unit_card_detail != null and unit_card_detail.has_method("show_unit"):
				unit_card_detail.show_unit(unit, 0)
			return
		"revive":
			if radial_menu_controller != null:
				radial_menu_controller.card_revive(unit)
		"activation":
			if radial_menu_controller != null:
				radial_menu_controller.card_toggle_activation(unit)
		"fatigued":
			if radial_menu_controller != null:
				radial_menu_controller.card_toggle_fatigued(unit)
		"shaken":
			if radial_menu_controller != null:
				radial_menu_controller.card_toggle_shaken(unit)
		"casts":
			if radial_menu_controller != null:
				radial_menu_controller.card_open_casts(unit)
		"wounds":
			if radial_menu_controller != null:
				radial_menu_controller.card_open_wounds(unit)
	_fill_presented(unit)


# === Interaction ===

func _on_card_input(event: InputEvent, unit: GameUnit) -> void:
	_handle_card_click(event, unit)


func _on_presented_input(event: InputEvent) -> void:
	if _presented_unit != null:
		_handle_card_click(event, _presented_unit)


func _handle_card_click(event: InputEvent, unit: GameUnit) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.double_click:
		_focus_camera_on(unit)
	else:
		_select_unit(unit)


func _on_card_hover(unit: GameUnit, entered: bool) -> void:
	if object_manager == null or not object_manager.has_method("set_hover_target"):
		return
	object_manager.set_hover_target(_unit_anchor_node(unit) if entered else null)


func _select_unit(unit: GameUnit) -> void:
	if object_manager == null or unit.models.is_empty():
		return
	var anchor: Node3D = _unit_anchor_node(unit)
	if anchor != null and anchor.has_meta(RegimentTray.MEMBER_META):
		var tray = anchor.get_meta(RegimentTray.MEMBER_META)
		if is_instance_valid(tray):
			object_manager.select_objects([tray])
			return
	var models: Array = UnitUtils.get_combined_unit_models(anchor) if anchor != null else []
	if models.is_empty():
		for m in unit.models:
			if m.node != null and is_instance_valid(m.node):
				models.append(m.node)
	object_manager.select_objects(models)


func _focus_camera_on(unit: GameUnit) -> void:
	if camera_controller == null or not camera_controller.has_method("focus_on"):
		return
	camera_controller.focus_on(_unit_centre(unit))


func _unit_anchor_node(unit: GameUnit) -> Node3D:
	for m in unit.models:
		if m.node != null and is_instance_valid(m.node):
			return m.node
	return null


func _unit_centre(unit: GameUnit) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for m in unit.models:
		if m.node != null and is_instance_valid(m.node) and m.is_alive:
			sum += (m.node as Node3D).global_position
			n += 1
	if n == 0:
		var anchor := _unit_anchor_node(unit)
		return anchor.global_position if anchor != null else Vector3.ZERO
	return sum / float(n)


func _unit_color(unit: GameUnit) -> Color:
	var pid: int = int(unit.unit_properties.get("player_id", 1))
	return OPRArmyManager.PLAYER_COLORS.get(pid, Color(0.5, 0.55, 0.6))


# === Table → card sync ===

func _on_table_selection_changed(selected_objects: Array) -> void:
	var selected_ids := {}
	for u in UnitUtils.get_unique_units(selected_objects):
		if u != null:
			selected_ids[(u as GameUnit).unit_id] = true
	for uid in _cards:
		var card := (_cards[uid]["card"]) as PanelContainer
		var accent: Color = _cards[uid].get("accent", Color(0.4, 0.44, 0.5))
		card.add_theme_stylebox_override("panel", _card_style(selected_ids.has(uid), accent))


# === Styles ===

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.14, 0.92)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.3, 0.55, 0.7, 0.7)
	return sb


func _card_style(selected: bool, accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.18, 0.22, 0.95)
	sb.set_corner_radius_all(5)
	sb.border_width_left = 6   # player-colour accent stripe
	sb.border_width_top = 2 if selected else 1
	sb.border_width_right = 2 if selected else 1
	sb.border_width_bottom = 2 if selected else 1
	# One border colour per box: the player accent normally, cyan when selected.
	sb.border_color = Color(0.35, 0.85, 1.0, 1.0) if selected else accent
	return sb


func _card_face_style(accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.16, 0.20, 0.98)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_width_left = 6
	sb.border_color = accent
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 6)
	return sb

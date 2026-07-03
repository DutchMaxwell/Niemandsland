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
const STRIP_CARD_H := 84
const PCARD_W := 320
const PCARD_H := 188
const PCARD_MAX_H := 348          # presented card auto-grows to fit weapons, capped here
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
var _presented: CardVisual = null      # the presented card is a CardVisual (feel) holding CardFace content
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
	_presented = CardVisual.new()
	_presented.size = Vector2(PCARD_W, PCARD_H)
	_presented.visible = false
	# Clicks on the card BODY (not an action chip) still select/locate the unit; chips are on top and
	# route through CardFace → _card_action first.
	_presented.gui_input.connect(_on_presented_input)
	add_child(_presented)


# === Layout ===

func _layout() -> void:
	var vp := get_viewport_rect().size
	if _tab != null:
		_tab.position = Vector2(vp.x / 2.0 - TAB_W / 2.0, vp.y - TAB_H)
	if _strip_panel != null:
		_strip_panel.size = Vector2(vp.x, STRIP_H)
		_strip_panel.position = Vector2(0, _strip_target_y(_dock_open))
	if _presented != null and _presented.visible:
		_presented.snap_to(_presented_rest_pos(), 0.0, 1.0)


func _strip_target_y(open: bool) -> float:
	var vp := get_viewport_rect().size
	return (vp.y - STRIP_H - TAB_H) if open else vp.y


func _presented_rest_pos() -> Vector2:
	var vp := get_viewport_rect().size
	var h: float = _presented.size.y if _presented != null else float(PCARD_H)
	return Vector2(vp.x / 2.0 - PCARD_W / 2.0, vp.y - h - TAB_H - GAP_ABOVE_TAB)


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
	# The HBox positions this inert SLOT; the CardVisual sits at local 0 inside it, so its own
	# self-positioning never fights the container while still giving the approved CardFace design —
	# dark-navy rounded face, bevel, drop shadow, hover lift/tilt — with NO legacy blue panel frame.
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(CARD_W, STRIP_CARD_H)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cv := CardVisual.new()
	cv.size = Vector2(CARD_W, STRIP_CARD_H)
	cv.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cv.gui_input.connect(_on_card_input.bind(unit))
	cv.mouse_entered.connect(_on_card_hover.bind(unit, true))
	cv.mouse_exited.connect(_on_card_hover.bind(unit, false))
	slot.add_child(cv)
	_strip.add_child(slot)
	# Content only after the card is in the tree, so CardVisual._ready has built its content holder.
	cv.set_content_node(CardFace.build_strip(_card_data(unit)))
	cv.snap_to(Vector2.ZERO, 0.0, 1.0)
	_cards[unit.unit_id] = {"card": cv}


# === Live status ===

func _refresh_status() -> void:
	for unit: GameUnit in _local_units():
		var entry = _cards.get(unit.unit_id)
		if entry == null:
			continue
		var card := entry["card"] as CardVisual
		# Rebuild the compact CardFace content so live stats/status/wounds show.
		card.set_content_node(CardFace.build_strip(_card_data(unit)))
		var dim: bool = unit.is_activated or unit.get_alive_count() == 0
		card.modulate = Color(1, 1, 1, 0.45) if dim else Color(1, 1, 1, 1)
	if _presented_unit != null and _presented.visible:
		_fill_presented(_presented_unit)


func _is_coherent(unit: GameUnit) -> bool:
	if unit.get_alive_count() <= 1:
		return true
	var res = CoherencyChecker.check_unit_coherency(unit, CoherencyChecker.is_skirmish_system(unit))
	return res.valid if res != null else true


## Builds the plain data Dictionary CardFace renders (D8 bridge). Reuses the dock's existing accessors
## and the unit's OWN OPR source data for weapons/rules — the same aggregation the old UnitCard reads,
## NOT re-derived. Pure: no UI side effects.
func _card_data(unit: GameUnit) -> Dictionary:
	var alive: int = unit.get_alive_count()
	var data: Dictionary = {
		"name": unit.get_name(),
		"points": unit.get_cost(),
		"quality": unit.get_quality(),
		"defense": unit.get_defense(),
		"alive": alive,
		"total": unit.models.size(),
		"activated": unit.is_activated,
		"fatigued": unit.is_fatigued,
		"shaken": unit.is_shaken,
		"caster": unit.is_caster(),
		"coherent": _is_coherent(unit),
		"dead": alive == 0,
		"weapons": [],
		"rules": "",
	}
	var opr: OPRApiClient.OPRUnit = null
	if unit.source_type == "opr" and unit.source_data:
		opr = unit.source_data as OPRApiClient.OPRUnit
	if opr != null:
		for w: OPRApiClient.OPRWeapon in opr.weapons:
			data["weapons"].append(_weapon_entry(w))
	var rules: Array = unit.get_special_rules()
	if not rules.is_empty():
		data["rules"] = " · ".join(rules)
	return data


## One distinct weapon → CardFace's {name, meta, rules} shape, in the APPROVED format (bus 027):
## the stat column is range (OMITTED for melee) + attacks + AP INLINE ("30\" A1 AP1", "A2"); AP is a
## stat, not a named rule. The cyan sub-line (rules) carries ONLY named special rules (Counter, Rending,
## Deadly(2), …).
func _weapon_entry(w: OPRApiClient.OPRWeapon) -> Dictionary:
	var count_str: String = "%dx " % w.count if w.count > 1 else ""
	var parts: Array[String] = []
	if w.range_value > 0:
		parts.append("%d\"" % w.range_value)   # no "Melee" token for melee weapons
	parts.append("A%d" % w.attacks)
	var named: Array[String] = []
	for r: String in w.special_rules:
		var ap := _ap_value(r)
		if ap != "":
			parts.append("AP%s" % ap)           # AP inline in the stat column, no parentheses
		else:
			named.append(r)
	return {
		"name": count_str + w.name,
		"meta": " ".join(parts),
		"rules": ", ".join(named),
	}


## The numeric value of an OPR armour-piercing rule "AP(X)" → "X", or "" if the rule is not AP.
func _ap_value(rule: String) -> String:
	var r := rule.strip_edges()
	if not r.begins_with("AP("):
		return ""
	var num := ""
	for i in range(3, r.length()):
		if r[i] >= "0" and r[i] <= "9":
			num += r[i]
	return num


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
	# Rebuild the CardFace content each time so live status/wounds are reflected; the action chips route
	# back through _card_action (the dispatch proven by card_action_dispatch_test).
	var content := CardFace.build_presented(_card_data(unit), _card_action)
	_presented.set_content_node(content)
	var h: float = clampf(content.get_combined_minimum_size().y, float(PCARD_H), float(PCARD_MAX_H))
	_presented.size = Vector2(PCARD_W, h)


func _animate_card_in() -> void:
	# CardVisual carries the deal-in feel: snap below with a slight tilt, then spring up to rest.
	var rest := _presented_rest_pos()
	_presented.modulate.a = 1.0
	_presented.visible = true
	_presented.snap_to(rest + Vector2(40, 240), 7.0, 0.82)
	_presented.spring_to(rest, 0.0, 1.0)
	UiFeedback.play_card_deal()   # D5: soft deal-in cue (chips already sound via the global button hook)


func _animate_card_out() -> void:
	if _presented == null or not _presented.visible:
		return
	_presented.spring_to(_presented_rest_pos() + Vector2(0, 230), 5.0, 0.85)
	var t := get_tree().create_timer(0.22)
	t.timeout.connect(func() -> void:
		if _presented != null and _presented_unit == null:
			_presented.visible = false)


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


# === Table → card sync ===

func _on_table_selection_changed(selected_objects: Array) -> void:
	var selected_ids := {}
	for u in UnitUtils.get_unique_units(selected_objects):
		if u != null:
			selected_ids[(u as GameUnit).unit_id] = true
	for uid in _cards:
		var card := (_cards[uid]["card"]) as CardVisual
		if card != null:
			card.set_selected(selected_ids.has(uid))


# === Styles ===

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.14, 0.92)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.3, 0.55, 0.7, 0.7)
	return sb



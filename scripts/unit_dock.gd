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
const STRIP_H := 256           # MINIMUM strip band height; grows with the tallest card (see _strip_h)
const CARD_W := 196            # wider so the full face is legible in the strip
const STRIP_CARD_H := 200      # min full-face card height in the strip (cards auto-grow to content)
# Strip hand-fan tunables (bus 028): per-card rotation, edge cap, and horizontal overlap. Overlap
# tightens automatically when the fan would exceed the panel width (many units).
const STRIP_FAN_DEG_PER_CARD := 1.5   # gentle fan (full faces need to stay readable, not a tight hand)
const STRIP_FAN_MAX_DEG := 8.0
const STRIP_OVERLAP_PX := 6           # near-touching so each full face stays fully legible (no right clip)
const STRIP_FAN_ARC_PX := 6.0         # shallow vertical arc
const STRIP_SIDE_MARGIN := 14         # the strip background hugs the fan + this margin (grows w/ card count)
const PCARD_W := 320
const PCARD_H := 188
const PCARD_MAX_H := 640          # presented card auto-grows to fit weapons + a full caster spell list
const GAP_ABOVE_TAB := 12
const REFRESH_INTERVAL := 0.4

# Injected by main.gd.
var army_manager: OPRArmyManager = null
var object_manager = null
var network_manager = null
var camera_controller = null
var radial_menu_controller = null
var unit_card_detail = null            # deprecated old detail card (retired; kept as an unused ctor arg)
var range_ring_controller: Node = null # injected by main.gd — spell-range ring on spell hover (bus 033)
var _presented_sig: int = 0            # hash of the presented card's last-built data; skip rebuild if unchanged
var _pending_click_unit: GameUnit = null   # strip-card single-click waiting out the double-click window
var _click_defer_timer: Timer = null       # so a double-click never fires the single-click collapse first
var _null_present_queued := false          # transient empty-selection debounce (see present_unit)

var _dock_open := false
var _tab: Button = null
var _strip_panel: PanelContainer = null
var _strip: Control = null             # fan holder — cards are placed manually (CardVisual self-positions)
var _cards: Dictionary = {}            # unit_id -> {card}
var _refit_gen: int = 0                # invalidates in-flight deferred height refits on rebuild
var _strip_h: float = float(STRIP_H)   # current strip band height — hugs the tallest card vertically
var _presented: CardVisual = null      # the presented card is a CardVisual (feel) holding CardFace content
var _presented_unit: GameUnit = null
var _refresh_timer: Timer = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_tab()
	_build_strip()
	_build_presented()
	_click_defer_timer = Timer.new()
	_click_defer_timer.one_shot = true
	# Must be LONGER than the OS double-click interval (~0.4 s): with a shorter window the single-click
	# collapse fired BETWEEN the two clicks of a slow double-click — the second click then hit the table,
	# deselected the unit and the card "jumped away" (maintainer). Selection itself is instant; only the
	# collapse+present waits this window out.
	_click_defer_timer.wait_time = 0.45
	_click_defer_timer.timeout.connect(_on_click_defer_timeout)
	add_child(_click_defer_timer)
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
	_tab.z_index = 20   # always above the strip cards so it stays clickable to collapse the dock
	# Dark-grey panel like the other HUD boxes (was the transparent default theme — maintainer).
	for state in ["normal", "hover", "pressed", "focus"]:
		_tab.add_theme_stylebox_override(state, _panel_style())
	_tab.pressed.connect(_toggle_dock)
	add_child(_tab)


func _build_strip() -> void:
	_strip_panel = PanelContainer.new()
	_strip_panel.add_theme_stylebox_override("panel", _panel_style())
	_strip_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Plain holder: cards are laid out in a playing-card FAN (rotation + overlap) by _layout_fan, each
	# CardVisual springing to its slot; no container forces a flat row.
	_strip = Control.new()
	_strip.custom_minimum_size = Vector2(0, STRIP_H)
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip_panel.add_child(_strip)
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
		_tab.position = Vector2(vp.x / 2.0 - TAB_W / 2.0, _tab_target_y(_dock_open))
	if _strip_panel != null:
		_strip_panel.size.y = _strip_h
		_strip_panel.position.y = _strip_target_y(_dock_open)
		_layout_fan()   # sizes the panel WIDTH to hug the fan + centres it horizontally
	if _presented != null and _presented.visible:
		_presented.snap_to(_presented_rest_pos(), 0.0, 1.0)


func _strip_target_y(open: bool) -> float:
	var vp := get_viewport_rect().size
	return (vp.y - _strip_h - TAB_H) if open else vp.y


## True if a screen point is over one of the dock's interactive surfaces (tab, open strip, presented
## card). object_manager consults this to reject a world click by ACTUAL position — the cached
## gui_get_hovered_control() goes stale the instant a card click collapses the strip, which otherwise let
## the click fall through to the table and open a box-select rubber-band (maintainer bug).
func occludes_point(gpos: Vector2) -> bool:
	if _tab != null and _tab.visible and _tab.get_global_rect().has_point(gpos):
		return true
	# Actual rect, NOT gated on _dock_open: while the strip tweens closed it is still on screen and must
	# keep blocking table clicks — the second click of a double-click otherwise landed on the table and
	# deselected the unit (the "card vanishes" gamble). Closed = fully offscreen = never contains a point.
	if _strip_panel != null and _strip_panel.get_global_rect().has_point(gpos):
		return true
	if _presented != null and _presented.visible and _presented.get_global_rect().has_point(gpos):
		return true
	return false


## Read-only state/geometry accessors (tutorial coach-mark targeting; no behaviour).
func is_dock_open() -> bool:
	return _dock_open


func get_presented_unit() -> GameUnit:
	return _presented_unit if (_presented != null and _presented.visible) else null


func tab_rect() -> Rect2:
	return _tab.get_global_rect() if _tab != null else Rect2()


func strip_rect() -> Rect2:
	return _strip_panel.get_global_rect() if _strip_panel != null else Rect2()


func presented_rect() -> Rect2:
	return _presented.get_global_rect() if (_presented != null and _presented.visible) else Rect2()


## Where the ▲/▼ Units tab sits: at the screen bottom when closed, but ABOVE the open strip so the full-
## face cards can never cover the collapse button (maintainer feedback).
func _tab_target_y(open: bool) -> float:
	var vp := get_viewport_rect().size
	return (_strip_target_y(true) - TAB_H) if open else (vp.y - TAB_H)


func _presented_rest_pos() -> Vector2:
	var vp := get_viewport_rect().size
	var h: float = _presented.size.y if _presented != null else float(PCARD_H)
	return Vector2(vp.x / 2.0 - PCARD_W / 2.0, vp.y - h - TAB_H - GAP_ABOVE_TAB)


# === Strip show/hide ===

func _toggle_dock() -> void:
	_dock_open = not _dock_open
	_tab.text = ("▼  Units" if _dock_open else "▲  Units")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_strip_panel, "position:y", _strip_target_y(_dock_open), 0.2).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_tab, "position:y", _tab_target_y(_dock_open), 0.2).set_trans(Tween.TRANS_CUBIC)
	if _dock_open:
		_presented.visible = false
	elif _presented_unit != null:
		_animate_card_in()


# === Compact strip cards ===

func rebuild() -> void:
	if _strip == null:
		return
	for child in _strip.get_children():
		# Detach BEFORE queue_free: the free is deferred, so a still-attached corpse would be
		# counted by the same-frame _layout_fan below — the panel came out double-wide with the
		# real cards bunched in its right half (maintainer screenshot, 2026-07-20).
		_strip.remove_child(child)
		child.queue_free()
	_cards.clear()
	# Sort: living units before wiped ones, then by name (⑨ grouping) — applied only on rebuild so
	# live status changes don't reshuffle the row under the player's cursor.
	var units := _local_units()
	units.sort_custom(_sort_units)
	for unit in units:
		_add_card(unit)
	_refresh_status()
	_layout_fan()
	_refit_gen += 1
	_refit_strip_heights(_refit_gen)


## Deferred SECOND height fit (maintainer screenshot 2026-07-20: rule lines spilled past the
## card's bottom edge). The synchronous measure in _add_card runs before the layout pass, so
## the HFlow rules rows — whose min height depends on the card WIDTH they have not been given
## yet — report a single row and long rule lists under-size the card. Re-measure after the
## tree has laid out, then re-fan. Generation-guarded against overlapping rebuilds.
func _refit_strip_heights(gen: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if gen != _refit_gen or _strip == null or not is_inside_tree():
		return
	# Cards may take up to ~40% of the screen: real full-face cards (weapons + wrapped rule
	# rows) need 270+ px — the old hard 240 cap CUT the last rule row (maintainer screenshot
	# 2026-07-20, second finding). The strip band then hugs the tallest card.
	var cap: float = maxf(240.0, get_viewport_rect().size.y * 0.4 - STRIP_FAN_ARC_PX - 22.0)
	var tallest: float = float(STRIP_CARD_H)
	for child in _strip.get_children():
		var cv := child as CardVisual
		if cv == null or cv.is_queued_for_deletion():
			continue
		var h: float = clampf(cv.content_min_height(), float(STRIP_CARD_H), cap)
		tallest = maxf(tallest, h)
		if absf(h - cv.size.y) > 0.5:
			cv.size = Vector2(cv.size.x, h)
	var new_strip_h: float = maxf(float(STRIP_H), tallest + STRIP_FAN_ARC_PX + 22.0)
	_strip_h = new_strip_h
	# ALWAYS re-seat, even when nothing changed height: a rebuild that ran before the first
	# real layout (tutorial/startup army auto-load) centred the panel against a zero-width
	# viewport and parked it hard left — this pass, two frames later, sees the real viewport
	# (maintainer finding 2026-07-20). Idempotent when geometry is already right.
	_layout()


## Arrange the strip cards as a playing-card hand: a slight per-card rotation arc and horizontal overlap,
## centred in the panel. Overlap tightens automatically so 12+ cards still fit (names stay readable);
## the fan angle is capped at the edges. Each CardVisual springs to its slot.
func _layout_fan() -> void:
	if _strip == null:
		return
	# Only live CardVisuals count: a queued-for-deletion or foreign child must neither widen
	# the panel nor consume a fan slot (it would leave a visible hole where it sat).
	var cards: Array = []
	for child in _strip.get_children():
		if child is CardVisual and not child.is_queued_for_deletion():
			cards.append(child)
	var n := cards.size()
	if n == 0:
		return
	var vp := get_viewport_rect().size
	var step: float = float(CARD_W - STRIP_OVERLAP_PX)
	var natural_w: float = float(CARD_W) + float(n - 1) * step
	# The fan may not exceed most of the screen; tighten overlap if it would (many units).
	var avail: float = vp.x * 0.94 - 2.0 * float(STRIP_SIDE_MARGIN)
	if natural_w > avail and n > 1:
		step = maxf(16.0, (avail - float(CARD_W)) / float(n - 1))
		natural_w = float(CARD_W) + float(n - 1) * step
	# The background hugs the fan (+ a small side margin) and is centred, so it grows with the card count
	# instead of spanning the whole screen (maintainer #1).
	var panel_w: float = natural_w + 2.0 * float(STRIP_SIDE_MARGIN)
	if _strip_panel != null:
		_strip_panel.size.x = panel_w
		_strip_panel.position.x = (vp.x - panel_w) * 0.5
	var start_x: float = float(STRIP_SIDE_MARGIN)
	var mid: float = float(n - 1) * 0.5
	for i in n:
		var cv := cards[i] as CardVisual
		if cv == null:
			continue
		var rot: float = clampf((float(i) - mid) * STRIP_FAN_DEG_PER_CARD, -STRIP_FAN_MAX_DEG, STRIP_FAN_MAX_DEG)
		var t: float = (float(i) - mid) / maxf(mid, 1.0)   # -1..1 across the fan
		var y: float = 6.0 + t * t * STRIP_FAN_ARC_PX      # top-aligned (cards vary in height)
		cv.spring_to(Vector2(start_x + float(i) * step, y), rot, 1.0)


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
	# A CardVisual placed directly in the fan holder — it self-positions (spring), so _layout_fan gives
	# it a rotated, overlapping hand-of-cards slot. The approved CardFace design (dark-navy rounded face,
	# bevel, drop shadow, hover lift/tilt); NO legacy blue panel frame.
	var cv := CardVisual.new()
	cv.size = Vector2(CARD_W, STRIP_CARD_H)
	cv.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cv.gui_input.connect(_on_card_input.bind(unit))
	cv.mouse_entered.connect(_on_card_hover.bind(unit, true))
	cv.mouse_exited.connect(_on_card_hover.bind(unit, false))
	_strip.add_child(cv)
	# Content only after the card is in the tree, so CardVisual._ready has built its content holder.
	# ONE card design (bus 033): the strip shows the SAME full CardFace as the focus card, minus the
	# action bar (include_actions=false). Weapons block stays full here — collapse_weapons is the
	# strip-density fallback if the maintainer finds it illegible.
	var data := _card_data(unit)
	var content := CardFace.build_presented(data, Callable(), false)
	cv.set_content_node(content)
	# Same rule/spell tooltips as the focus card — the strip links were never wired, so hovering
	# them popped an EMPTY tooltip panel (maintainer 2026-07-20).
	_wire_rules_hover(content, unit)
	cv.size = Vector2(CARD_W, clampf(content.get_combined_minimum_size().y, float(STRIP_CARD_H), 240.0))
	_cards[unit.unit_id] = {"card": cv, "sig": data.hash()}


# === Live status ===

func _refresh_status() -> void:
	for unit: GameUnit in _local_units():
		var entry = _cards.get(unit.unit_id)
		if entry == null:
			continue
		var card := entry["card"] as CardVisual
		var dim: bool = unit.is_activated or unit.get_alive_count() == 0
		card.modulate = Color(1, 1, 1, 0.45) if dim else Color(1, 1, 1, 1)
		# Rebuild the full CardFace ONLY when the unit's data actually changed — a blind 0.4 s rebuild
		# churned the fan + destroyed any hovered rule button (maintainer "keine Ruhe").
		var data := _card_data(unit)
		var sig: int = data.hash()
		if int(entry.get("sig", 0)) == sig:
			continue
		entry["sig"] = sig
		var content := CardFace.build_presented(data, Callable(), false)
		card.set_content_node(content)
		card.size = Vector2(CARD_W, clampf(content.get_combined_minimum_size().y, float(STRIP_CARD_H), 240.0))
	# Presented card: same change-gate so the rule/spell hover is never interrupted under the cursor.
	if _presented_unit != null and _presented.visible and _card_data(_presented_unit).hash() != _presented_sig:
		_fill_presented(_presented_unit)


func _is_coherent(unit: GameUnit) -> bool:
	if unit.get_alive_count() <= 1:
		return true
	var res = CoherencyChecker.check_unit_coherency(unit, CoherencyChecker.is_skirmish_system(unit))
	return res.valid if res != null else true


## Builds the plain data Dictionary CardFace renders (D8 bridge). Reuses the dock's existing accessors
## and the unit's OWN OPR source data for weapons/rules — the same aggregation the old UnitCard reads,
## NOT re-derived. Pure: no UI side effects.
## True if the unit carries a Tough(X) rule (a single Tough model still tracks wounds → the wound window
## is relevant even at one model).
func _has_tough_rule(unit: GameUnit) -> bool:
	for r in unit.get_special_rules():
		var nm: String = str(r.get("name", "")) if r is Dictionary else str(r)
		if nm.begins_with("Tough"):
			return true
	return false


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
		"woundable": unit.models.size() > 1 or _has_tough_rule(unit),   # wound window applies (bus feedback)
		"weapons": [],
		"rules_list": [],
		"spells": [],
	}
	var opr: OPRApiClient.OPRUnit = null
	if unit.source_type == "opr" and unit.source_data:
		opr = unit.source_data as OPRApiClient.OPRUnit
	if opr != null:
		for w: OPRApiClient.OPRWeapon in opr.weapons:
			data["weapons"].append(_weapon_entry(w))
	# rules_list: normalized special-rule names — each is a hover target on the card (bus 033). A rule an
	# item GRANTS (Combat Shield → Shielded) is reached through the item's tooltip cascade, not listed as
	# a flat sibling; duplicates are collapsed (an item name can sit in both equipment + special_rules).
	var unit_grants := _item_grants_of(unit)
	var granted_by_item := {}
	for it in unit_grants:
		for g in unit_grants[it]:
			granted_by_item[str(g)] = true
	var seen_rules := {}
	for r in unit.get_special_rules():
		var nm: String = str(r.get("name", "")) if r is Dictionary else str(r)
		if not nm.is_empty() and not granted_by_item.has(nm) and not seen_rules.has(nm):
			seen_rules[nm] = true
			data["rules_list"].append(nm)
	# spells (casters): {name, threshold, effect} from the army glossary, for the hoverable spell list.
	if unit.is_caster() and army_manager != null and army_manager.has_method("get_spells_for_unit"):
		data["spells"] = army_manager.get_spells_for_unit(unit)
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
		named.append(r)                          # AND list every rule (incl. AP) as a hoverable link (feedback)
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
	_clear_spell_ring()   # never let a spell-range ring outlive the card it was hovered from (maintainer)
	if unit == null:
		# select_objects re-selects via _deselect_all + _add_to_selection, EACH emitting
		# selection_changed — so every re-select of an already-shown unit sends a transient empty
		# selection first. Acting on it immediately nulled _presented_unit and the follow-up present
		# re-dealt the whole card (the down/up wobble on every click — maintainer). Defer the card-out
		# to end of frame; a real present arriving in the same frame cancels it.
		if not _null_present_queued:
			_null_present_queued = true
			_apply_null_present.call_deferred()
		return
	_null_present_queued = false   # a re-present in the same frame cancels the pending card-out
	var same: bool = unit == _presented_unit
	_presented_unit = unit
	# Re-presenting the SAME unit with unchanged data is a no-op (clicking the card re-selects the unit →
	# selection_changed → present_unit again): rebuilding here re-measured the card rough-then-exact and
	# made it bob up/down on every click, fighting the double-click focus (maintainer). Only rebuild when
	# the unit or its data actually changed.
	if not (same and _presented.visible and _card_data(unit).hash() == _presented_sig):
		_fill_presented(unit)
	if _dock_open:
		_presented.visible = false
		return
	if same and _presented.visible:
		return
	_animate_card_in()


## Deferred card-out (see present_unit): only fires if no re-present cancelled it within the frame.
func _apply_null_present() -> void:
	if not _null_present_queued:
		return
	_null_present_queued = false
	_presented_unit = null
	_animate_card_out()


func _fill_presented(unit: GameUnit) -> void:
	# Rebuild the CardFace content; the action chips route back through _card_action (dispatch proven by
	# card_action_dispatch_test). Record the data signature so _refresh_status only rebuilds on a real
	# change — rebuilding under the cursor destroyed the rule LinkButtons mid-hover (tooltip never settled,
	# spell ring flickered — maintainer "keine Ruhe").
	var data := _card_data(unit)
	_presented_sig = data.hash()
	var content := CardFace.build_presented(data, _card_action)
	_presented.set_content_node(content)
	_wire_rules_hover(content, unit)   # bus 033: the focus card absorbs the old Info card's rule/spell tooltips
	_resize_presented_to_fit(content)


## Size the presented card to its content, bottom-anchored above the tab. The chip/rule/spell rows are
## FLOW containers and the tooltip labels wrap, so their true height is only known AFTER laying out at
## the card's width — a single pre-layout measure assumed one row and casters/heavily-equipped units
## spilled out of the card (maintainer). Measure once for a rough fit, let the layout settle two frames,
## then re-measure and re-seat the card.
func _resize_presented_to_fit(content: Control) -> void:
	var cap: float = minf(float(PCARD_MAX_H), get_viewport_rect().size.y * 0.82)
	# Rough pre-layout size only while hidden (first present): applying it to a visible card shrank it
	# for two frames before the exact measure grew it back — a visible bob on every rebuild.
	if not _presented.visible:
		_presented.size = Vector2(PCARD_W, clampf(content.get_combined_minimum_size().y, float(PCARD_H), cap))
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(content) or not content.is_inside_tree():
		return   # card was rebuilt meanwhile — the newer pass sizes itself
	var h: float = clampf(content.get_combined_minimum_size().y, float(PCARD_H), cap)
	if absf(h - _presented.size.y) > 1.0:
		_presented.size = Vector2(PCARD_W, h)
		if _presented.visible:
			_presented.spring_to(_presented_rest_pos(), 0.0, 1.0)   # re-seat smoothly (no snap-jump mid-deal)


func set_range_ring_controller(rrc: Node) -> void:
	range_ring_controller = rrc


## Wire hover + click for every rule/spell/weapon-rule LinkButton in the presented card. The description
## uses Godot's BUILT-IN tooltip (tooltip_text) — reliable through the card's nested content, unlike the
## custom mouse_entered popup which fired erratically for weapon rules (maintainer). Spells additionally
## show the range ring on hover. No click popup — the card no longer rebuilds under the cursor (see
## _refresh_status), so the hover tooltip is stable on its own.
func _wire_rules_hover(content: Control, unit: GameUnit) -> void:
	for node in content.find_children("*", "LinkButton", true, false):
		var lb := node as LinkButton
		if lb == null or not lb.has_meta("rule_meta"):
			continue
		var meta_key := str(lb.get_meta("rule_meta", ""))
		lb.tooltip_text = _rule_description(meta_key, unit)
		if meta_key.begins_with("spell:"):
			lb.mouse_entered.connect(_show_spell_ring.bind(meta_key.substr(6)))
			lb.mouse_exited.connect(_clear_spell_ring)


## Plain-text rule/spell description for a link's wrapping tooltip, WITH the old UnitCard's cascades
## (ported, issue #74): a spell/rule whose text references another known rule (e.g. a spell granting
## Blast(3)) appends that rule's description too, and an ITEM entry shows the rule(s) it grants instead
## of its own (usually empty) description.
func _rule_description(meta_key: String, unit: GameUnit) -> String:
	var title := meta_key.trim_prefix("spell:")
	if army_manager == null:
		return title
	var grants := _item_grants_of(unit)
	var out: String
	if meta_key.begins_with("spell:"):
		var effect := _spell_effect(title, unit).strip_edges()
		out = "%s — %s" % [title, effect] if not effect.is_empty() else title
		out += _referenced_rules_text(effect, "")
	elif grants.has(title):
		out = "%s — grants:" % title
		for g in grants[title]:
			var gd := str(army_manager.get_rule_description(str(g))).strip_edges()
			out += "\n\n%s — %s" % [str(g), gd if not gd.is_empty() else "(no description)"]
	else:
		var desc := str(army_manager.get_rule_description(meta_key)).strip_edges()
		out = "%s — %s" % [title, desc] if not desc.is_empty() else title
		out += _referenced_rules_text(desc, title)
	return out


## For each OTHER known rule named in `text`, append its name + description — so an Aura / spell / rule
## that references another rule (Blast, Poison, …) reveals that rule's explanation in the same tooltip.
## `exclude` (and its parameterless base) is the hovered entry itself, skipped so it is not repeated.
func _referenced_rules_text(text: String, exclude: String) -> String:
	if text.is_empty() or not army_manager.has_method("rules_referenced_in"):
		return ""
	var paren := exclude.find("(")
	var base := exclude.substr(0, paren).strip_edges() if paren > 0 else exclude
	var out := ""
	for r in army_manager.rules_referenced_in(text):
		var rname := str(r)
		if rname == exclude or rname == base:
			continue
		var d := str(army_manager.get_rule_description(rname)).strip_edges()
		if not d.is_empty():
			out += "\n\n%s — %s" % [rname, d]
	return out


## item → granted rules for a unit, read from unit_properties so the cascade survives save/load + MP
## sync (a synced unit may not carry the live OPRUnit object). Ported from the old card.
func _item_grants_of(unit: GameUnit) -> Dictionary:
	if unit != null and unit.unit_properties is Dictionary:
		var g: Variant = unit.unit_properties.get("item_grants", {})
		if g is Dictionary:
			return g
	return {}


func _spell_effect(spell_name: String, unit: GameUnit = null) -> String:
	if unit == null:
		unit = _presented_unit
	if unit == null or army_manager == null or not army_manager.has_method("get_spells_for_unit"):
		return ""
	for s in army_manager.get_spells_for_unit(unit):
		if str((s as Dictionary).get("name", "")) == spell_name:
			return str((s as Dictionary).get("effect", ""))
	return ""


func _show_spell_ring(spell_name: String) -> void:
	if range_ring_controller == null or not range_ring_controller.has_method("show_spell_preview"):
		return
	range_ring_controller.show_spell_preview(_presented_model_nodes(), OPRApiClient.spell_radius_inches(_spell_effect(spell_name)))


func _clear_spell_ring() -> void:
	if range_ring_controller != null and range_ring_controller.has_method("clear_spell_preview"):
		range_ring_controller.clear_spell_preview()


func _presented_model_nodes() -> Array:
	var out: Array = []
	if _presented_unit != null:
		for m in _presented_unit.models:
			if m.node != null and is_instance_valid(m.node):
				out.append(m.node)
	return out


func _animate_card_in() -> void:
	# Deal-in feel WITHOUT scaling: snap below with a slight tilt, then spring up to rest at scale 1.0.
	# Scaling the card broke mouse input to its nested RichText rules list (Godot picks scaled children
	# unreliably) — keeping scale fixed at 1.0 makes the rule-hover tooltips work (maintainer #3).
	var rest := _presented_rest_pos()
	_presented.modulate.a = 1.0
	_presented.visible = true
	_presented.snap_to(rest + Vector2(40, 240), 7.0, 1.0)
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
	_handle_card_click(event, unit, true)


func _on_presented_input(event: InputEvent) -> void:
	if _presented_unit != null:
		_handle_card_click(event, _presented_unit, false)


func _handle_card_click(event: InputEvent, unit: GameUnit, from_strip: bool) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if not from_strip:
		# Presented/detail card: its unit is by definition already selected, so a single click does
		# NOTHING (re-selecting re-dealt the card and played N select sounds — maintainer: "entfernen").
		# Only a double-click acts: solid camera focus on the unit.
		if mb.double_click:
			_focus_camera_on(unit)
		return
	# Strip card: select IMMEDIATELY (instant cyan feedback in the fan) but DEFER the collapse+present
	# past the double-click window, so the strip never collapses between the two clicks of a double-click
	# (that collapse exposed the table, the second click deselected, and the card "jumped away").
	# A double-click cancels the pending single and does select + present + camera-focus in one shot.
	if mb.double_click:
		_click_defer_timer.stop()
		_pending_click_unit = null
		_activate_strip_card(unit, true)
	else:
		_select_unit(unit)
		_pending_click_unit = unit
		_click_defer_timer.start()


func _on_click_defer_timeout() -> void:
	if _pending_click_unit != null:
		var u := _pending_click_unit
		_pending_click_unit = null
		_activate_strip_card(u, false)


## Select the unit, collapse the strip to present its detail card, and (on a double-click) focus the
## camera on it — as one clean action so the card deals in exactly once.
func _activate_strip_card(unit: GameUnit, do_focus: bool) -> void:
	_select_unit(unit)
	if _dock_open:
		_collapse_dock_and_present(unit)
	if do_focus:
		_focus_camera_on(unit)


func _collapse_dock_and_present(unit: GameUnit) -> void:
	_dock_open = false
	_tab.text = "▲  Units"
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_strip_panel, "position:y", _strip_target_y(false), 0.2).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_tab, "position:y", _tab_target_y(false), 0.2).set_trans(Tween.TRANS_CUBIC)
	present_unit(unit)


func _on_card_hover(unit: GameUnit, entered: bool) -> void:
	# Pull the hovered card ABOVE its neighbours in the fan (like lifting a card from a hand); on exit it
	# drops back, unless it is the selected card, which stays raised.
	var entry = _cards.get(unit.unit_id)
	if entry != null:
		var cv := entry["card"] as CardVisual
		if cv != null:
			cv.z_index = 2 if entered else (1 if cv._selected else 0)
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
			var sel: bool = selected_ids.has(uid)
			card.set_selected(sel)
			card.z_index = 1 if sel else 0   # a selected card stays raised above the fan


# === Styles ===

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.14, 0.92)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.3, 0.55, 0.7, 0.7)
	return sb



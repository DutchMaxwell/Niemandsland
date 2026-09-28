extends GdUnitTestSuite
## E2E — the radial (action) menu, row 7 of the UI inventory (radial PR 1: the ring itself in the house
## style; maintainer D53 = b). Pins TODAY's FULL function set before the restyle: the menu opens the way a
## right-click opens it (object_manager.context_menu_requested -> main -> the radial controller), every
## entry is reached by a REAL pointer move + click on what is drawn for it, and its handler does what it
## does today. Three menus: (a) a plain squad, (b) a lone caster hero carrying every rule that adds a
## verb (the crowded case of NML-979), (c) a loaded transport (Unload) and a squad beside it (Embark).
## test_the_inventory_check_can_fail proves the reach check and the handler check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254
const OPEN_AT := Vector2(960, 520)
const FEAT_FLAG := "speed_feat_used_speed_feat"

## Today's entries per menu, in the order the test clicks them (what ends the unit's life goes last;
## the Walkers' Delete is undone by a revive so their Embark can still be clicked).
## The three Automodus verbs (NML-202): the engine moves the unit and rolls the attack for the
## clicked target. Menu-construction order (solo_combat_items) puts them right after solo_fight.
const AUTO := ["solo_auto_charge", "solo_auto_advance", "solo_auto_rush"]
const PLAIN := ["add_marker", "toggle_fatigued", "toggle_shaken", "toggle_activate", "solo_shoot",
	"solo_fight", "solo_auto_charge", "solo_auto_advance", "solo_auto_rush", "delete_unit"]
const HERO := ["wounds", "casts", "add_marker", "select_unit", "toggle_fatigued", "toggle_shaken",
	"toggle_activate", "solo_shoot", "solo_fight", "solo_auto_charge", "solo_auto_advance", "solo_auto_rush",
	"solo_cast", "solo_spot", "solo_speed_feat", "solo_pass", "reinforce", "delete_model"]
const TRUCK := ["add_marker", "select_unit", "toggle_fatigued", "toggle_shaken", "toggle_activate",
	"solo_shoot", "solo_fight", "solo_auto_charge", "solo_auto_advance", "solo_auto_rush",
	"unload_cargo_0", "delete_model"]
const WALKERS := ["add_marker", "toggle_fatigued", "toggle_shaken", "toggle_activate", "solo_shoot",
	"solo_fight", "solo_auto_charge", "solo_auto_advance", "solo_auto_rush", "delete_unit", "embark_0"]
## D53 = b: the core verbs a crowded menu keeps on its ring, in PRIORITY order — the ring fills up to
## RING_MAX-1 of these before the rest spill to the second tier (radial_menu.gd's own list, mirrored
## here so a drift between the two is a test failure, not a silent surprise).
## D90 = b (maintainer, in chat): Charge/Advance/Rush outrank Spot/Speed Feat/Pass — the three
## Automodus verbs stay on a crowded ring, the three demoted ones move to "More" instead.
const RING_VERBS := ["solo_shoot", "solo_fight", "solo_cast", "solo_auto_charge", "solo_auto_advance",
	"solo_auto_rush", "toggle_activate", "solo_spot", "solo_speed_feat", "solo_pass"]
const TIER_WEDGE := "more"
const RING_MAX := 8

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _picked: Array = []


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_picked.clear()
	_menu().action_selected.connect(func(id: String, _ctx: Dictionary) -> void: _picked.append(id))


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


# === fixtures =================================================================================

func _rmc() -> RadialMenuController:
	return _main.radial_menu_controller


func _menu() -> RadialMenu:
	return _main.radial_menu_controller.radial_menu


func _unit(pid: int, unit_name: String, positions: Array, rules: Array = []) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	u.unit_properties["special_rules"] = rules
	# Spawned models carry their ModelInstance as meta; the single-model (model menu) path reads it.
	for m in u.models:
		(m as ModelInstance).node.set_meta("model_instance", m)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Solo game in play, with one AI unit far off so Shoot / Fight are offered.
func _solo_playing_on() -> void:
	_unit(2, "Raiders", [Vector3(1.2, 0, 0.8)])
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING


## (b) the research's FULL case: a lone Tough(3) caster hero with Precision Spotter, the Speed Feat,
## Delayed Action and Reinforcement (orcs, AoF — the registry's "Speed Feat"). 0 spell tokens, so a
## Shoot click asks no "cast first?" question.
func _hero() -> GameUnit:
	var u := _unit(1, "Warboss", [Vector3.ZERO],
		["Caster(2)", "Precision Spotter", "Speed Feat", "Delayed Action", "Reinforcement", "Tough(3)"])
	u.unit_properties["game_system"] = "aof"
	u.unit_properties["faction_folder"] = "orcs"
	u.casts_current = 0
	var m := u.models[0] as ModelInstance
	m.wounds_max = 3
	m.wounds_current = 3
	return u


func _nodes(u: GameUnit) -> Array:
	var out: Array = []
	for m in u.models:
		out.append((m as ModelInstance).node)
	return out


func _log_count() -> int:
	return _main.battle_log.entries().size()


func _log_since(n: int) -> String:
	var text := ""
	var entries: Array = _main.battle_log.entries()
	for i in range(n, entries.size()):
		text += str((entries[i] as Dictionary)["text"]) + "\n"
	return text


func _spell_picker() -> SpellPickerDialog:
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if n is SpellPickerDialog and not n.is_queued_for_deletion():
			return n
	return null


# === the menu ================================================================================

## Opens the menu on `u` the way a right-click does and waits out the open animation.
func _open(u: GameUnit) -> void:
	_main.object_manager.context_menu_requested.emit(OPEN_AT, _nodes(u))
	await get_tree().create_timer(0.2).timeout
	await _runner.simulate_frames(2)


func _ids() -> Array:
	var out: Array = []
	for it in _menu()._items:
		out.append(str((it as RadialMenu.RadialMenuItem).id))
	return out


## The second tier's entries (D53 = b), [] while the menu has none.
func _tier_ids() -> Array:
	var out: Array = []
	var tier = _menu().get("_tier")
	for it in (tier if tier != null else []):
		out.append(str((it as RadialMenu.RadialMenuItem).id))
	return out


## Where the player points to pick `id` in the open menu (canvas coordinates): the middle of its
## wedge, measured from the menu's own centre the way its hit test does, or of its pill in the second
## tier. INF = nothing drawn for it.
func _reach_point(id: String) -> Vector2:
	var m := _menu()
	var k := _tier_ids().find(id)
	if k >= 0:
		return m.get_global_transform_with_canvas() * (m.get("_pills")[k] as Rect2).get_center()
	var n := m._items.size()
	for i in n:
		if (m._items[i] as RadialMenu.RadialMenuItem).id == id:
			var a := -PI / 2.0 + i * TAU / n
			var local := m._center_pos + Vector2(cos(a), sin(a)) * (m.menu_radius + m.center_radius) / 2.0
			return m.get_global_transform_with_canvas() * local
	return Vector2.INF


## A real pointer move onto the entry and a real left click there. True when the menu handed exactly
## `id` to the action pipe.
func _pick(id: String) -> bool:
	var vp := _menu().get_viewport()
	if _tier_ids().has(id):   # the second tier: point at its wedge first, then its pills stand beside the ring
		E2EBoot.motion_canvas(vp, _reach_point(TIER_WEDGE))
		await _runner.simulate_frames(1)
	var at := _reach_point(id)
	if at == Vector2.INF:
		return false
	_picked.clear()
	E2EBoot.motion_canvas(vp, at)
	await _runner.simulate_frames(1)
	E2EBoot.click_canvas(vp, at, true)
	E2EBoot.click_canvas(vp, at, false)
	await _runner.simulate_frames(3)
	return _picked == [id]


## What today's handler of `id` leaves behind, read right after the click. `lines` = the battle-log
## lines the click wrote.
func _did(id: String, u: GameUnit, lines: String) -> bool:
	match id:
		"solo_shoot":
			return lines.contains("pick a target (shooting)")
		"solo_fight":
			return lines.contains("pick a target (melee)")
		"solo_auto_charge", "solo_auto_advance", "solo_auto_rush":
			return _main._solo_target_mode.has("auto_verb") and lines.contains("pick a target for")
		"solo_cast":
			return _spell_picker() != null or lines.contains("spell")
		"solo_spot":
			return not lines.is_empty() or not _main._solo_target_mode.is_empty()
		"solo_pass":
			return lines.contains("Delayed Action")
		"solo_speed_feat":
			return bool(u.unit_properties.get(FEAT_FLAG, false))
		"reinforce":
			return lines.contains("Reinforcement")
		"toggle_activate":
			return u.is_activated
		"toggle_fatigued":
			return u.is_fatigued
		"toggle_shaken":
			return u.is_shaken
		"add_marker":
			return _rmc().marker_dialog.visible
		"wounds":
			return _rmc().wounds_dialog.visible
		"casts":
			return _rmc().casts_dialog.visible
		"select_unit":
			return _main.object_manager.get_selected_objects().size() == u.models.size()
		"delete_model", "delete_unit":
			return not (u.models[0] as ModelInstance).is_alive
		"embark_0":
			return _main.opr_army_manager.transport_of(u) != null
		"unload_cargo_0":
			return _main.opr_army_manager.cargo_units(u).is_empty()
	return false


## Puts the table back between two clicks: dialogs shut, targeting ended, flags off, the dead revived,
## an embarked unit back on the table.
func _reset(u: GameUnit) -> void:
	for d: Control in [_rmc().wounds_dialog, _rmc().casts_dialog, _rmc().marker_dialog]:
		if d.visible:
			d.call("close")
	var picker := _spell_picker()
	if picker != null:
		for b in picker.find_children("*", "Button", true, false):
			if (b as Button).text == "Cancel":
				(b as Button).pressed.emit()
	if not _main._solo_target_mode.is_empty():
		_main._solo_end_targeting()
	if not (u.models[0] as ModelInstance).is_alive:
		_rmc()._revive_unit_models(u)
	if u.is_activated:
		u.deactivate()
	if _main.opr_army_manager.transport_of(u) != null:
		_main.opr_army_manager.set_unit_embarked(u, null, false)
	u.is_fatigued = false
	u.is_shaken = false
	await E2EBoot.settle(get_tree())


## Opens `u`'s menu once per entry, checks it offers exactly `ids`, clicks each entry and checks its
## handler ran. Returns the misses as readable lines (empty = every entry reached and handled).
func _walk(u: GameUnit, ids: Array) -> Array:
	var misses: Array = []
	await _open(u)
	var offered := _ids() + _tier_ids()
	offered.erase(TIER_WEDGE)
	offered.sort()
	var want := ids.duplicate()
	want.sort()
	if offered != want:
		misses.append("%s offers %s, today's menu is %s" % [u.get_name(), offered, want])
	_menu().close()
	await _runner.simulate_frames(2)
	for id in ids:
		await _open(u)
		var before := _log_count()
		if not await _pick(id):
			misses.append("%s: '%s' not reached by a click (picked %s)" % [u.get_name(), id, _picked])
		elif not _did(id, u, _log_since(before)):
			misses.append("%s: '%s' reached, its handler left no trace (log: %s)" % [u.get_name(), id, _log_since(before).strip_edges()])
		await _reset(u)
	return misses


# === today's function set (GREEN on main) =====================================================

func test_a_plain_squad_reaches_every_entry(timeout := 180000) -> void:
	var squad := _unit(1, "Wardens", [Vector3.ZERO, Vector3(1.2 * INCH, 0, 0), Vector3(2.4 * INCH, 0, 0)])
	_solo_playing_on()
	assert_array(await _walk(squad, PLAIN)).is_empty()


func test_a_hero_with_many_entries_reaches_every_entry(timeout := 240000) -> void:
	var hero := _hero()
	_solo_playing_on()
	assert_array(await _walk(hero, HERO)).is_empty()


func test_a_transport_and_its_neighbour_reach_every_entry(timeout := 240000) -> void:
	var truck := _unit(1, "Truck", [Vector3.ZERO], ["Transport(6)"])
	var riders := _unit(1, "Riders", [Vector3(0.04, 0, 0)])
	var walkers := _unit(1, "Walkers", [Vector3(0, 0, 0.04), Vector3(1.2 * INCH, 0, 0.04)])
	# Loaded before play starts: no activation is spent, so the Unload entry stays live.
	_rmc()._embark_unit({"game_unit": riders, "embark_target": truck})
	assert_object(_main.opr_army_manager.transport_of(riders)).override_failure_message("fixture: Riders are not aboard").is_equal(truck)
	_solo_playing_on()
	var misses: Array = await _walk(walkers, WALKERS)
	misses.append_array(await _walk(truck, TRUCK))
	assert_array(misses).is_empty()


# === the check can fail ======================================================================

func test_the_inventory_check_can_fail(timeout := 120000) -> void:
	var squad := _unit(1, "Wardens", [Vector3.ZERO, Vector3(1.2 * INCH, 0, 0)])
	_solo_playing_on()
	await _open(squad)
	assert_bool(await _pick("no_such_entry")).override_failure_message("an entry the menu does not have was 'reached'").is_false()
	await _open(squad)
	var before := _log_count()
	assert_bool(await _pick("toggle_fatigued")).is_true()
	assert_bool(_did("toggle_shaken", squad, _log_since(before))) \
		.override_failure_message("the handler check credits Shaken for a Fatigued click").is_false()
	await _reset(squad)
	var misses: Array = await _walk(squad, ["toggle_fatigued", "delete_unit"])
	assert_bool(misses.size() > 0).override_failure_message("a menu with 7 entries passed as a 2-entry menu").is_true()


# === the house-style ring (RED on main 17c1cebb) ==============================================

## A colour spelled out (numbers, a hex string, a named colour) or an old HUD token, in code — not in
## comments. A token tint such as Color(HouseStyle.ACCENT, HouseStyle.HOVER_ALPHA) is not a literal.
const LITERAL := "Color8?\\(\\s*[\"'0-9.-]|Color\\.[A-Z_]+|HudTokens\\."
## The widest tooltip box the ring may draw (the mockup's tooltip is ~340 px of text).
const TOOLTIP_MAX_W := 420.0


func _colour_literals(source: String) -> Array:
	var re := RegEx.create_from_string(LITERAL)
	var hits: Array = []
	var lines := source.split("\n")
	for i in lines.size():
		if re.search(lines[i].split("#")[0]) != null:
			hits.append("%d: %s" % [i + 1, lines[i].strip_edges()])
	return hits


## Every wedge label as drawn: [text, Rect2 in the menu's px]. The menu's own layout when it has one;
## before the house-style ring, today's formula (the full label centred on the wedge's middle radius).
func _label_boxes() -> Array:
	var m := _menu()
	var font: Font = m._font
	var fs := HouseStyle.FONT_BODY
	var layout: Array = m.call("_label_layout", font) if m.has_method("_label_layout") else []
	var out: Array = []
	var n := m._items.size()
	for i in n:
		var text: String = m._items[i].label
		var a := -PI / 2.0 + i * TAU / n
		var p := m._center_pos + Vector2(cos(a), sin(a)) * (m.menu_radius - 4.0 + m.center_radius) / 2.0
		var ls := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var base := Vector2(p.x - ls.x / 2.0, p.y + ls.y * 0.32)
		if not layout.is_empty():
			text = layout[i][0]
			base = layout[i][1]
		var size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)   # a label may take two lines
		out.append([text, Rect2(base.x, base.y - font.get_ascent(fs), size.x, size.y)])
	return out


## Labels that leave the ring or lie on another label (NML-979), as readable lines.
func _bursts(who: String) -> Array:
	var m := _menu()
	var boxes := _label_boxes()
	var out: Array = []
	for i in boxes.size():
		var r: Rect2 = boxes[i][1]
		if str(boxes[i][0]).is_empty():
			continue
		for c: Vector2 in [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]:
			if c.distance_to(m._center_pos) > m.menu_radius:
				out.append("%s: '%s' reaches %.0f px past the ring" % [who, boxes[i][0], c.distance_to(m._center_pos) - m.menu_radius])
				break
		for j in range(i + 1, boxes.size()):
			if not str(boxes[j][0]).is_empty() and r.intersects(boxes[j][1]):
				out.append("%s: '%s' lies on '%s'" % [who, boxes[i][0], boxes[j][0]])
	return out


func test_the_ring_paints_only_house_style_tokens() -> void:
	# The scan can fail: literals and old HUD tokens are caught, a token tint and a comment are not.
	assert_array(_colour_literals("var a := Color(1.0, 1.0, 1.0, 0.06)\nvar b := Color.RED\nvar c := HudTokens.CYAN\nvar d := Color8(1, 2, 3)\nvar e := Color(\"e9e9df\")")).has_size(5)
	assert_array(_colour_literals("var t := Color(HouseStyle.ACCENT, HouseStyle.HOVER_ALPHA)  # not Color(1, 0, 0)")).is_empty()
	assert_array(_colour_literals(FileAccess.get_file_as_string("res://scripts/radial_menu.gd"))) \
		.override_failure_message("radial_menu.gd paints colours HouseStyle does not own:\n%s" % "\n".join(
			_colour_literals(FileAccess.get_file_as_string("res://scripts/radial_menu.gd")))).is_empty()


func test_no_label_leaves_the_ring_or_covers_another(timeout := 120000) -> void:
	var squad := _unit(1, "Wardens", [Vector3.ZERO, Vector3(1.2 * INCH, 0, 0), Vector3(2.4 * INCH, 0, 0)])
	var hero := _hero()
	hero.models[0].node.global_position = Vector3(0.3, 0, 0)
	var truck := _unit(1, "Battle Wagon Transport", [Vector3(-0.3, 0, 0)], ["Transport(6)"])
	var walkers := _unit(1, "Wolf Brothers Pack Veterans", [Vector3(-0.3, 0, 0.04), Vector3(-0.3 + 1.2 * INCH, 0, 0.04)])
	var riders := _unit(1, "Custodian Brothers Retinue", [Vector3(-0.26, 0, 0)])
	_rmc()._embark_unit({"game_unit": riders, "embark_target": truck})
	_solo_playing_on()
	var bursts: Array = []
	for u: GameUnit in [squad, hero, walkers, truck]:
		await _open(u)
		bursts.append_array(_bursts(u.get_name()))
		_menu().close()
		await _runner.simulate_frames(2)
	assert_array(bursts).override_failure_message("labels burst the ring:\n%s" % "\n".join(bursts)).is_empty()


func test_a_long_tooltip_wraps_and_a_cut_label_reads_in_full(timeout := 120000) -> void:
	var hero := _hero()
	_solo_playing_on()
	await _open(hero)
	var m := _menu()
	var boxes := _label_boxes()
	var wide: Array = []
	for i in m._items.size():
		var it := m._items[i] as RadialMenu.RadialMenuItem
		var tip: String = m.call("_tooltip_text", it, boxes[i][0]) if m.has_method("_tooltip_text") else it.tooltip
		var w: float = m._tooltip_box_size(m._font, tip).x
		if w > TOOLTIP_MAX_W:
			wide.append("'%s' tooltip is %.0f px wide" % [it.label, w])
		if boxes[i][0] != it.label and not tip.contains(it.label):
			wide.append("'%s' is shown as '%s' and its tooltip never names it in full" % [it.label, boxes[i][0]])
	m.close()
	assert_array(wide).override_failure_message("\n".join(wide)).is_empty()


# === the second tier (D53 = b; RED on the ring-only commit 08e853f0) ===========================

## Ring labels cut to an ellipsis or to nothing, as readable lines (a dropped note — "Speed Feat" for
## "Speed Feat (once per game)" — still reads; its tooltip names it in full).
func _cut_labels(who: String) -> Array:
	var out: Array = []
	var boxes := _label_boxes()
	for i in boxes.size():
		var label := str((_menu()._items[i] as RadialMenu.RadialMenuItem).label)
		if str(boxes[i][0]).is_empty() or str(boxes[i][0]).ends_with("…"):
			out.append("%s: '%s' reads '%s' on the ring" % [who, label, boxes[i][0]])
	return out


## D53 = b, priority cap: the first RING_MAX-1 entries of RING_VERBS (in that declared order) present
## in `ids` stay on the ring; every overflow verb plus every non-verb entry goes to the second tier.
## Computed independently of radial_menu.gd's own logic — this is the DOCUMENTED rule, fresh each
## call, so a drift between the two reads as a test failure instead of a silent agreement.
func _expected_ring_ids(ids: Array) -> Array:
	var out: Array = []
	for verb in RING_VERBS:
		if out.size() >= RING_MAX - 1:
			break
		if ids.has(verb):
			out.append(verb)
	return out


func test_a_crowded_menu_keeps_its_verbs_on_the_ring_and_the_rest_in_a_second_tier(timeout := 120000) -> void:
	var squad := _unit(1, "Wardens", [Vector3.ZERO, Vector3(1.2 * INCH, 0, 0), Vector3(2.4 * INCH, 0, 0)])
	var hero := _hero()
	hero.models[0].node.global_position = Vector3(0.3, 0, 0)
	_solo_playing_on()
	var misses: Array = []
	# The everyday menu (10 raw entries, past RING_MAX) still fits every one of its 6 verbs on the
	# ring — a "More" wedge appears, but nothing it would carry is actually truncated off the ring.
	await _open(squad)
	var want_ring_plain := _expected_ring_ids(PLAIN)
	for id in PLAIN:
		var want_ring: bool = id in want_ring_plain
		if want_ring != _ids().has(id) or want_ring == _tier_ids().has(id):
			misses.append("Wardens: '%s' belongs %s (ring %s, tier %s)" % [id, "on the ring" if want_ring else "in the second tier", _ids(), _tier_ids()])
	misses.append_array(_cut_labels("Wardens"))
	_menu().close()
	await _runner.simulate_frames(2)
	# The crowded hero: at most RING_MAX wedges. Its 10 ring-tagged verbs exceed the RING_MAX-1 cap, so
	# Spot/Speed Feat/Pass (last in RING_VERBS' priority order under D90 = b) spill to the second tier —
	# Shoot/Fight/Cast/Charge/Advance/Rush/Activate keep the ring seats.
	await _open(hero)
	var ring := _ids()
	if ring.size() > RING_MAX:
		misses.append("the hero's ring carries %d wedges, D53 allows %d" % [ring.size(), RING_MAX])
	var want_ring_hero := _expected_ring_ids(HERO)
	for id in HERO:
		var want_ring: bool = id in want_ring_hero
		if want_ring != ring.has(id) or want_ring == _tier_ids().has(id):
			misses.append("'%s' belongs %s (ring %s, tier %s)" % [id, "on the ring" if want_ring else "in the second tier", ring, _tier_ids()])
	misses.append_array(_cut_labels("Warboss"))
	# Pointing at the tier's wedge opens the tier.
	if ring.has(TIER_WEDGE):
		E2EBoot.motion_canvas(_menu().get_viewport(), _reach_point(TIER_WEDGE))
		await _runner.simulate_frames(2)
		if not bool(_menu().get("_tier_open")):
			misses.append("pointing at the '%s' wedge did not open the second tier" % TIER_WEDGE)
	_menu().close()
	await _runner.simulate_frames(2)
	# Opened at the left screen edge, the tier stands right of the ring, on screen.
	_main.object_manager.context_menu_requested.emit(Vector2(20, 520), _nodes(hero))
	await _runner.simulate_frames(2)
	var view := _menu().get_viewport_rect()
	for p in (_menu().get("_pills") if _menu().get("_pills") != null else []):
		if not view.encloses(p) or (p as Rect2).position.x < _menu()._center_pos.x:
			misses.append("at the left edge a tier pill sits at %s (ring centre %s, screen %s)" % [p, _menu()._center_pos, view.size])
			break
	_menu().close()
	assert_array(misses).override_failure_message("\n".join(misses)).is_empty()

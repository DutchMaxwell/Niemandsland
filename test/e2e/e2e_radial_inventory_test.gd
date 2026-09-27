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
const PLAIN := ["add_marker", "toggle_fatigued", "toggle_shaken", "toggle_activate", "solo_shoot",
	"solo_fight", "delete_unit"]
const HERO := ["wounds", "casts", "add_marker", "select_unit", "toggle_fatigued", "toggle_shaken",
	"toggle_activate", "solo_shoot", "solo_fight", "solo_cast", "solo_spot", "solo_speed_feat", "solo_pass",
	"reinforce", "delete_model"]
const TRUCK := ["add_marker", "select_unit", "toggle_fatigued", "toggle_shaken", "toggle_activate",
	"solo_shoot", "solo_fight", "unload_cargo_0", "delete_model"]
const WALKERS := ["add_marker", "toggle_fatigued", "toggle_shaken", "toggle_activate", "solo_shoot",
	"solo_fight", "delete_unit", "embark_0"]

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


## Where the player points to pick `id` in the open menu (canvas coordinates): the middle of its
## wedge, measured from the menu's own centre the way its hit test does. INF = nothing drawn for it.
func _reach_point(id: String) -> Vector2:
	var m := _menu()
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
	var at := _reach_point(id)
	if at == Vector2.INF:
		return false
	var vp := _menu().get_viewport()
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
	var offered := _ids()
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

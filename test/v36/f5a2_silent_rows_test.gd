extends GdUnitTestSuite
## W31-F5a2 (release 0.3.15): Piercing Spotter, Precision Spotter and Slayer in the books that field them without a
## mechanics row. The "is it automated?" test reads the static `modeled` list for every book, while the readers below
## ask the registry PER BOOK, so a book with no row neither applied the rule nor told the player to do it by hand.
## Each case builds a unit of the book the way the army import writes it (system + faction slug + the unit's own
## rules), drives the table's own reader and asserts the effect AND the battle-log line / name of the BOOK rule.
## Every rule has a control book that already had its row.
## Precision Spotter is the odd one: the table reads that rule by NAME (a green case on main, kept as the proof that
## the table already applied it); only the Rust core needed the row. Rust twin:
## `core/nml-core/src/tests/unit/v36_data_rows/f5a2_rows.rs`.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	RulesRegistry.reset_cache()
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	await E2EBoot.settle(get_tree())
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null
	AiActRecorder.rules_epoch = _epoch0
	RulesRegistry.reset_cache()


## A unit of `faction` carrying `rules`, with one ranged weapon on its OPR source (the spot reach and sight gates read it).
func _unit(pid: int, unit_name: String, pos: Vector3, system: String, faction: String, rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["quality"] = 4
	u.unit_properties["game_system"] = system
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = rules
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 36
	w.attacks = 2
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## Piercing Spotter: the AI rolls its printed 4+ die (seed 1 is a forced hit) and the log names the book rule.
func _piercing_spotter_log(faction: String) -> String:
	_main.seed_tray_rng(1)
	var spotter := _unit(2, "Watcher", Vector3.ZERO, "aof", faction, ["Piercing Spotter"])
	_unit(1, "Marked", Vector3(10.0 * INCH, 0, 0), "aof", "beastmen", [])
	_main.opr_army_manager.current_round = 1
	await _main._solo_apply_piercing_tag(spotter)
	return _log_text()


func test_piercing_spotter_control_mummified_undead() -> void:
	assert_str(await _piercing_spotter_log("mummified_undead")).contains("Piercing Spotter: Watcher places 1 marker on Marked")


func test_piercing_spotter_places_its_marker_in_duchies_of_vinci() -> void:
	var text: String = await _piercing_spotter_log("duchies_of_vinci")
	assert_str(text).override_failure_message("aof/duchies_of_vinci: Piercing Spotter silently dropped (log: %s)" % text) \
		.contains("Piercing Spotter: Watcher places 1 marker on Marked")


func test_piercing_spotter_places_its_marker_in_sky_city_dwarves() -> void:
	var text: String = await _piercing_spotter_log("sky_city_dwarves")
	assert_str(text).override_failure_message("aof/sky_city_dwarves: Piercing Spotter silently dropped (log: %s)" % text) \
		.contains("Piercing Spotter: Watcher places 1 marker on Marked")


## Precision Spotter: the AI spots at the end of its activation; the table reads the rule by name, so this is green
## on main as well (a control that the table side already applied it; the core was the silent one).
func _precision_spot_log(faction: String) -> String:
	_main.seed_tray_rng(1)
	var spotter := _unit(2, "Eyes", Vector3.ZERO, "aof", faction, ["Precision Spotter"])
	_unit(1, "Marked", Vector3(10.0 * INCH, 0, 0), "aof", "beastmen", [])
	_main.opr_army_manager.current_round = 1
	await _main._solo_try_precision_spot(spotter)
	return _log_text()


func test_precision_spotter_control_duchies_of_vinci() -> void:
	assert_str(await _precision_spot_log("duchies_of_vinci")).contains("Precision Spotter: Eyes marks Marked")


func test_precision_spotter_already_marks_in_saurians_on_the_table() -> void:
	assert_str(await _precision_spot_log("saurians")).contains("Precision Spotter: Eyes marks Marked")


## Slayer: AP(+2) on a charge against a Tough(3)+ target; the named part is what the strike's log prints.
func _slayer_parts(faction: String) -> Array:
	var striker := _unit(2, "Charger", Vector3.ZERO, "aof", faction, ["Slayer"])
	var target := _unit(1, "Brute", Vector3(2.0 * INCH, 0, 0), "aof", "beastmen", ["Tough(6)"])
	return _main._solo_conditional_ap_parts({"name": "Blade", "range": 0, "rules": []}, striker, target, true, 2.0, true)


func _slayer_ok(parts: Array) -> bool:
	return parts.size() == 1 and str((parts[0] as Dictionary).get("name", "")) == "Slayer" \
		and int((parts[0] as Dictionary).get("bonus", 0)) == 2


func test_slayer_control_duchies_of_vinci() -> void:
	var parts := _slayer_parts("duchies_of_vinci")
	assert_bool(_slayer_ok(parts)).override_failure_message("control book lost its row: %s" % [parts]).is_true()


func test_slayer_adds_its_ap_in_high_elves() -> void:
	var parts := _slayer_parts("high_elves")
	assert_bool(_slayer_ok(parts)).override_failure_message("aof/high_elves: Slayer silently dropped (parts: %s)" % [parts]).is_true()

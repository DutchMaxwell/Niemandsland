extends GdUnitTestSuite

## Destroyer Boost (STANDALONE_SWEEP_E_2026-09-14 row `Destroyer Boost`, DIVERGES) — the table twin
## of the core's Shred UPGRADE stamp (core/nml-core/src/unit.rs, stamp arm 6b: `shred_low` /
## `shred_over_in` behind the entry's `upgrades` base rule) and its volley consumption
## (core/nml-core/src/dice.rs, `shred_low` read: past the entry's own `over_in` the save-fail window
## widens from 1 to `save_fail_max`). The table's Shred window was hardwired to unmodified 1s, so a
## Boosted Destroyer (aof/ogres) shredded only on failed saves of 1 where the sim shreds on 1-2
## when shooting over 9".

const Boot := preload("res://test/e2e/e2e_boot.gd")
var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array


func before_test() -> void:
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


func _unit(rules: Array, unit_id: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = unit_id
	u.unit_properties = {"player_id": 2, "name": "Fixture", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "aof", "faction_folder": "ogres"}
	var model := ModelInstance.new()
	model.is_alive = true
	u.models.append(model)
	return u


func _log_text(start: int) -> String:
	var text := ""
	for entry in _main.battle_log.entries().slice(start):
		text += str(entry["text"]) + "\n"
	return text


func test_boosted_destroyer_shreds_failed_save_2s_from_twelve_inches_plain_shred_does_not() -> void:
	# The tray mirror: `_solo_batch` mode draws one `_tray_rng.randi_range(1, 6)` per save die, so a
	# fresh seed with the same roll count replays the exact faces. 60 defense saves at 4+ — the 2s
	# fail, and the widened window must turn them into extra wounds.
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = 1300
	var ones := 0
	var twos := 0
	for _i in range(60):
		var f := expected_rng.randi_range(1, 6)
		if f == 1:
			ones += 1
		elif f == 2:
			twos += 1
	assert_int(twos).is_greater(0)
	var boosted := _unit(["Destroyer", "Destroyer Boost"], "destroyer_boosted")
	var plain := _unit(["Destroyer"], "destroyer_plain")
	var foe := _unit([], "destroyer_foe")
	var volley: Dictionary = {"range": 24, "ap": 0, "rules": [],
		"shred": _main._solo_shred_facet_applies(boosted, 24)}
	var plain_volley: Dictionary = {"range": 24, "ap": 0, "rules": [],
		"shred": _main._solo_shred_facet_applies(plain, 24)}
	# Baseline volley: no shred flag, identical tray consumption.
	_main.seed_tray_rng(1300)
	var baseline: int = await _main._solo_resolve_saves(foe, foe, "Blade", [], 60, 4,
		{"range": 24, "ap": 0, "rules": []}, false, false, true, false, 12.0)
	# Boosted Destroyer shooting from 12": failed saves of 1-2 each take the extra wound.
	_main.seed_tray_rng(1300)
	var boosted_wounds: int = await _main._solo_resolve_saves(boosted, foe, "Blade", [], 60, 4,
		volley, false, false, true, false, 12.0)
	# A plain Shred unit from 12" stays on the base window: 1s only.
	_main.seed_tray_rng(1300)
	var plain_wounds: int = await _main._solo_resolve_saves(plain, foe, "Blade", [], 60, 4,
		plain_volley, false, false, true, false, 12.0)
	# ROT: the same boosted unit from 6" is inside the over_in gate — no widening.
	_main.seed_tray_rng(1300)
	var boosted_close: int = await _main._solo_resolve_saves(boosted, foe, "Blade", [], 60, 4,
		volley, false, false, true, false, 6.0)
	assert_int(boosted_wounds - baseline).is_equal(ones + twos)
	assert_int(plain_wounds - baseline).is_equal(ones)
	assert_int(boosted_close - baseline).is_equal(ones)


func test_boosted_destroyer_shred_log_names_the_rule_and_the_window() -> void:
	# Rules-must-log: the Shred trace names the Boost rule and the widened window.
	var boosted := _unit(["Destroyer", "Destroyer Boost"], "destroyer_boosted_log")
	var foe := _unit([], "destroyer_foe_log")
	var volley: Dictionary = {"range": 24, "ap": 0, "rules": [],
		"shred": _main._solo_shred_facet_applies(boosted, 24)}
	_main.seed_tray_rng(1300)
	var log_start: int = _main.battle_log.entries().size()
	await _main._solo_resolve_saves(boosted, foe, "Blade", [], 60, 4,
		volley, false, false, true, false, 12.0)
	assert_str(_log_text(log_start)) \
		.contains("Destroyer Boost: Shred on failed saves of 1-2 (over 9\")")

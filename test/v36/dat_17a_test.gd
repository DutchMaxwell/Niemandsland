extends GdUnitTestSuite
## Rules 3.6 wave, row DAT-17a: a granted Regeneration (the Regeneration Buff, or a spell's "gets Regeneration
## once") is spent by the FIRST EXCHANGE THAT WOUNDS ITS HOLDER, not by the holder's own attack and not by an
## exchange that wounds nobody. From EPOCH_73_V36; below it the old generic spend (any exchange) stays.
## The records are written the way the Utility Buff seam writes them (the registry entries are not flipped yet);
## the core's twin is core/nml-core/src/tests/sim/v36_dat_17a.rs.

const Boot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
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
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, x: float) -> GameUnit:
	var unit := Boot.make_unit(_main, pid, unit_name, [Vector3(x, 0, 0), Vector3(x + 1.0, 0, 0)])
	unit.unit_properties["game_system"] = "gf"
	unit.unit_properties["faction_folder"] = "plague_disciples"
	unit.unit_properties["special_rules"] = []
	return unit


## The record the Utility Buff seam writes for a Regeneration Buff pick.
func _grant(unit: GameUnit) -> void:
	_main._solo_record_spell_mod(unit, "Regeneration Buff", {"modifier": {}, "grants_rule": "Regeneration",
		"duration": "once"})


func _records(unit: GameUnit) -> Array:
	return _main._solo_spell_mods.get(unit.get_instance_id(), [])


func _log_text() -> String:
	var text := ""
	for entry in _main.battle_log.entries():
		text += str(entry["text"]) + "\n"
	return text


func test_the_table_rolls_a_granted_regeneration_at_5_plus() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var holder := _unit(2, "Plague Bearers", 0.0)
	_grant(holder)
	assert_int(_main._solo_regen_target(holder)).override_failure_message("the overlay is read as plain Regeneration").is_equal(5)


func test_the_holders_own_attack_does_not_spend_the_grant() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var holder := _unit(2, "Plague Bearers", 0.0)
	var foe := _unit(1, "Shield Wall", 20.0)
	_grant(holder)
	_main._solo_consume_once_mods(holder, foe, false)
	assert_int(_records(holder).size()).override_failure_message("the attacker side keeps the grant").is_equal(1)
	assert_int(_main._solo_regen_target(holder)).is_equal(5)


func test_an_exchange_without_wounds_keeps_the_grant() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var holder := _unit(2, "Plague Bearers", 0.0)
	var foe := _unit(1, "Shield Wall", 20.0)
	_grant(holder)
	_main._solo_consume_once_mods(foe, holder, false)
	assert_int(_records(holder).size()).override_failure_message("no wound reached the holder - no use").is_equal(1)


func test_an_exchange_that_wounds_the_holder_spends_the_grant_and_logs_it() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var holder := _unit(2, "Plague Bearers", 0.0)
	var foe := _unit(1, "Shield Wall", 20.0)
	_grant(holder)
	await _main._solo_apply_regeneration(holder, 2)
	_main._solo_consume_once_mods(foe, holder, false)
	assert_int(_records(holder).size()).override_failure_message("the wounding exchange spends the grant").is_equal(0)
	assert_int(_main._solo_regen_target(holder)).override_failure_message("and the Regeneration is gone").is_equal(0)
	assert_str(_log_text()).override_failure_message("rules-must-log: the spend names the buff").contains("\"Regeneration Buff\" on Plague Bearers is consumed")


func test_below_73_the_old_generic_spend_stays() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var holder := _unit(2, "Plague Bearers", 0.0)
	var foe := _unit(1, "Shield Wall", 20.0)
	_grant(holder)
	_main._solo_consume_once_mods(holder, foe, false)
	assert_int(_records(holder).size()).override_failure_message("epoch 72: the holder's own attack still spends it").is_equal(0)

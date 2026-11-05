extends GdUnitTestSuite
## AI-G2 row R7 (release 0.3.15, rules epoch 73): the Eternal Wardens' `Enhanced Warden` printed the same
## `incoming_ap_reduction` as `Warden` (1) and the table's Fortified-family loop applied a flat 1 for the first
## entry it met, so the enhanced form changed nothing and the log never named it. The book gives the enhanced form a
## LARGER cut (2 instead of 1) that REPLACES the base value; it never stacks on it. Below epoch 73 the table keeps
## the flat 1. The defender is a real unit of the book, hit through the table's own save batch.
## Rust twin: `core/nml-core/src/tests/unit/v36_data_rows/aig2_r7.rs`.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

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


func _unit(pid: int, unit_name: String, pos: Vector3, system: String, faction: String, rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["quality"] = 4
	u.unit_properties["game_system"] = system
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The save log of three AP(2) hits on a Wardens unit carrying `rules`.
func _wardens_log(rules: Array) -> String:
	var defender := _unit(1, "Wardens", Vector3.ZERO, "aof", "eternal_wardens", rules)
	var striker := _unit(2, "Raiders", Vector3(0.5, 0.0, 0.5), "aof", "dwarves", [])
	await _main._solo_save_batch(striker, defender, "Rifle", 3, 4, 2, {"name": "Rifle", "ap": 2, "deadly": 0, "rules": []}, false, false)
	return _log_text()


func test_the_enhanced_form_cuts_two_ap_and_names_itself() -> void:
	var text: String = await _wardens_log(["Warden", "Enhanced Warden"])
	assert_str(text).override_failure_message(
		"Enhanced Warden should cut AP(2) to AP(0), replacing Warden's cut of 1 (log: %s)" % text).contains(
		"Enhanced Warden: Wardens takes the hits at AP(0) instead of AP(2)")
	assert_int(text.count("takes the hits at AP")).override_failure_message(
		"one cut, one line: the base must not log a second, stacked cut (log: %s)" % text).is_equal(1)


func test_the_aura_granted_form_cuts_two_ap_like_the_printed_one() -> void:
	var text: String = await _wardens_log(["Warden", "Enhanced Warden Aura", "Enhanced Warden"])
	assert_str(text).contains("Enhanced Warden: Wardens takes the hits at AP(0) instead of AP(2)")


func test_the_base_alone_still_cuts_one_ap() -> void:
	var text: String = await _wardens_log(["Warden"])
	assert_str(text).contains("Warden: Wardens takes the hits at AP(1) instead of AP(2)")


func test_below_epoch_73_the_enhanced_form_keeps_the_flat_cut_of_one() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var text: String = await _wardens_log(["Warden", "Enhanced Warden"])
	assert_str(text).override_failure_message("epoch 72 must stay byte-identical (flat cut, first entry named)").contains(
		"Warden: Wardens takes the hits at AP(1) instead of AP(2)")
	assert_str(text).not_contains("Enhanced Warden: Wardens")

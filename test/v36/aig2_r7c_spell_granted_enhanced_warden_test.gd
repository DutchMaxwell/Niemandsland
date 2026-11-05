extends GdUnitTestSuite
## AI-G2 row R7c (release 0.3.15, rules epoch 73), follow-up of R7: the spell `Warding Cloud` hands one friendly unit
## Enhanced Warden once. The table lays a spell's granted rule onto the unit as a live overlay (`_solo_apply_grant`), so
## the Fortified-family loop sees it like a printed rule: from epoch 73 the granted form cuts TWO AP (replacing Warden's
## cut of one), names itself in the log and is spent by the exchange that used it. The spell is recorded through the real
## seam (`_solo_record_spell_mod`) with the effect read from the shipped spell row, and the defender is hit through the
## table's own save batch. Rust twin: `core/nml-core/src/tests/sim/fold_gate_fixture.rs` (live-grant leg).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const SPELLS := "res://assets/solo/spells_mechanics_aof.json"

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


func _unit(pid: int, unit_name: String, pos: Vector3, faction: String, rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	u.unit_properties["quality"] = 4
	u.unit_properties["game_system"] = "aof"
	u.unit_properties["faction_folder"] = faction
	u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The effect of the shipped `Warding Cloud` row (the Eternal Wardens' own spell list).
func _warding_cloud_effect() -> Dictionary:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPELLS))
	var found: Dictionary = {}
	var stack: Array = [doc]
	while not stack.is_empty():
		var node: Variant = stack.pop_back()
		if node is Dictionary:
			if str((node as Dictionary).get("name", "")) == "Warding Cloud" and (node as Dictionary).has("effect"):
				found = (node as Dictionary)["effect"]
			else:
				stack.append_array((node as Dictionary).values())
		elif node is Array:
			stack.append_array(node)
	return found


func _hit(striker: GameUnit, defender: GameUnit) -> void:
	await _main._solo_save_batch(striker, defender, "Rifle", 3, 4, 2, {"name": "Rifle", "ap": 2, "deadly": 0, "rules": []}, false, false)


func test_the_cloud_cuts_two_ap_names_itself_and_is_spent_by_the_exchange() -> void:
	var effect := _warding_cloud_effect()
	assert_str(str(effect.get("grants_rule", ""))).override_failure_message(
		"fixture: the shipped Warding Cloud row must grant Enhanced Warden (found: %s)" % effect).is_equal("Enhanced Warden")
	var defender := _unit(1, "Wardens", Vector3.ZERO, "eternal_wardens", ["Warden"])
	var striker := _unit(2, "Raiders", Vector3(0.5, 0.0, 0.5), "dwarves", [])
	_main._solo_record_spell_mod(defender, "Warding Cloud", effect)
	await _hit(striker, defender)
	var text := _log_text()
	assert_str(text).override_failure_message(
		"the cloud's Enhanced Warden should cut AP(2) to AP(0) (log: %s)" % text).contains(
		"Enhanced Warden: Wardens takes the hits at AP(0) instead of AP(2)")
	_main._solo_consume_once_mods(striker, defender, false)
	await _hit(striker, defender)
	assert_str(_log_text()).override_failure_message("once spent, the unit is back to Warden's cut of one").contains(
		"Warden: Wardens takes the hits at AP(1) instead of AP(2)")


func test_below_epoch_73_the_granted_form_keeps_the_flat_cut_of_one() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var defender := _unit(1, "Wardens", Vector3.ZERO, "eternal_wardens", ["Warden"])
	var striker := _unit(2, "Raiders", Vector3(0.5, 0.0, 0.5), "dwarves", [])
	_main._solo_record_spell_mod(defender, "Warding Cloud", _warding_cloud_effect())
	await _hit(striker, defender)
	var text := _log_text()
	assert_str(text).override_failure_message("epoch 72 stays byte-identical (flat cut, first entry named)").contains(
		"Warden: Wardens takes the hits at AP(1) instead of AP(2)")
	assert_str(text).not_contains("Enhanced Warden: Wardens takes")

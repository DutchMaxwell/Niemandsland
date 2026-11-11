extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-IPS: a carrier of Infiltrating Precision Strike (gf elven_jesters) strikes one
## better in melee in its arrival round (its Ambush/Infiltrate arrival stamp equals the current round).
## From the rules 3.6 epoch (73) on; at 72 nothing changes. Not on later rounds, not for a unit that
## deployed normally, not for a unit without the rule, and never on a shot.

const MainScript := preload("res://scripts/main.gd")
const RULE := "Infiltrating Precision Strike"

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	# statics leak across gdUnit tests — restore
	AiActRecorder.rules_epoch = _epoch0


func _unit(pid: int, rules: Array, arrived_round: int = -1) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "mel_ips_%d" % pid
	u.unit_properties = {"player_id": pid, "name": "Unit %d" % pid, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": "elven_jesters"}
	if arrived_round >= 0:
		u.unit_properties["ambush_arrived_round"] = arrived_round
	var m := ModelInstance.new()
	m.is_alive = true
	var n := Node3D.new()
	add_child(n)
	m.node = n
	u.models.append(m)
	return u


func _main(round_no: int) -> Node3D:
	var main: Node3D = auto_free(MainScript.new())
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.current_round = round_no
	main.opr_army_manager = army
	return main


func _melee_info(striker: GameUnit, round_no: int) -> Dictionary:
	return _main(round_no)._solo_hit_mod_info(striker, _unit(1, []), 0.0, true, true)


func test_arrival_round_melee_gets_plus_one_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var info := _melee_info(_unit(2, [RULE], 2), 2)
	assert_int(int(info.get("mod", 0))) \
		.override_failure_message("rules 3.6: +1 to hit in melee on the arrival round, got %s" % info) \
		.is_equal(1)
	assert_str(str(info.get("note", ""))) \
		.override_failure_message("rules-must-log: the note names the rule") \
		.contains(RULE)


func test_arrival_round_melee_is_unchanged_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var info := _melee_info(_unit(2, [RULE], 2), 2)
	assert_int(int(info.get("mod", 0))).is_equal(0)
	assert_str(str(info.get("note", ""))).not_contains(RULE)


func test_the_round_after_arrival_gets_nothing_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_int(int(_melee_info(_unit(2, [RULE], 2), 3).get("mod", 0))).is_equal(0)


func test_a_unit_deployed_normally_gets_nothing_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_int(int(_melee_info(_unit(2, [RULE]), 2).get("mod", 0))).is_equal(0)


func test_an_arrival_without_the_rule_gets_nothing_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_int(int(_melee_info(_unit(2, [], 2), 2).get("mod", 0))).is_equal(0)


func test_a_shot_on_the_arrival_round_gets_nothing_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var info: Dictionary = _main(2)._solo_hit_mod_info(_unit(2, [RULE], 2), _unit(1, []), 12.0, false)
	assert_int(int(info.get("mod", 0))).is_equal(0)

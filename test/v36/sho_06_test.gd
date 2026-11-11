extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-06: a shot at an Artillery unit takes -1 to hit only past 12", only while
## most models carry the rule and the unit has NOT moved this round (any move takes the protection
## away). Below epoch 73 the old -2 / 9" reading stays. The hit-info note names Artillery and the
## 12" gate when the penalty lands (rules-must-log).

const MainScript := preload("res://scripts/main.gd")

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	# statics leak across gdUnit tests — restore
	AiActRecorder.rules_epoch = _epoch0


func _unit(rules: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": 1, "name": uid, "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": "machine_cults"}
	var m := ModelInstance.new()
	m.is_alive = true
	var n := Node3D.new()
	add_child(n)
	m.node = n
	u.models.append(m)
	return u


## A bare main in round 1; `target_moved` stamps the TARGET as having moved this round.
func _info(target_moved: bool, dist_in: float) -> Dictionary:
	var main: Node3D = auto_free(MainScript.new())
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.current_round = 1
	main.opr_army_manager = army
	var solo: SoloController = auto_free(SoloController.new())
	main.solo_controller = solo
	var shooter := _unit([], "sho06_rifle")
	var target := _unit(["Artillery"], "sho06_gun")
	if target_moved:
		target.unit_properties["moved_round"] = 1
	return main._solo_hit_mod_info(shooter, target, dist_in, false)


func test_an_unmoved_artillery_target_at_13in_takes_minus_one_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var info := _info(false, 13.0)
	assert_int(int(info["mod"])).override_failure_message("unmoved gun at 13\": %s" % info.get("note", "")).is_equal(-1)
	assert_str(str(info["note"])).contains("Artillery").contains("12")


func test_an_unmoved_artillery_target_at_10in_takes_nothing_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var info := _info(false, 10.0)
	assert_int(int(info["mod"])).override_failure_message("unmoved gun at 10\": %s" % info.get("note", "")).is_equal(0)
	assert_str(str(info["note"])).contains("Artillery").contains("12")


func test_an_artillery_target_that_moved_takes_nothing_at_13in_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var info := _info(true, 13.0)
	assert_int(int(info["mod"])).override_failure_message("a moved gun at 13\": %s" % info.get("note", "")).is_equal(0)
	assert_str(str(info["note"])).contains("Artillery").contains("moved")


func test_an_artillery_target_that_moved_takes_nothing_at_10in_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var info := _info(true, 10.0)
	assert_int(int(info["mod"])).override_failure_message("a moved gun at 10\": %s" % info.get("note", "")).is_equal(0)


func test_a_moved_artillery_target_keeps_the_old_minus_two_at_13in_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var info := _info(true, 13.0)
	assert_int(int(info["mod"])).is_equal(-2)
	assert_str(str(info["note"])).contains("Artillery target -2")


func test_an_artillery_target_at_10in_keeps_the_old_minus_two_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var info := _info(true, 10.0)
	assert_int(int(info["mod"])).is_equal(-2)
	assert_str(str(info["note"])).contains("Artillery target -2")

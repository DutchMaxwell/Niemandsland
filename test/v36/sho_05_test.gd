extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-05: an Artillery shooter's +1 to hit needs a Hold AND a target over 12" from
## the rules 3.6 epoch (73) on; at epoch 72 any shot over 9" still earns it. "Held" on the table = the
## unit has not moved this round (its moved_round stamp). The hit-info note names the rule and, when the
## +1 does not apply, the reason (rules-must-log).

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


## A bare main in round 1; `moved` stamps the shooter as having moved this round.
func _info(moved: bool, dist_in: float) -> Dictionary:
	var main: Node3D = auto_free(MainScript.new())
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.current_round = 1
	main.opr_army_manager = army
	var solo: SoloController = auto_free(SoloController.new())
	main.solo_controller = solo
	var shooter := _unit(["Artillery"], "sho05_gun")
	if moved:
		shooter.unit_properties["moved_round"] = 1
	var target := _unit([], "sho05_foe")
	return main._solo_hit_mod_info(shooter, target, dist_in, false)


func test_artillery_that_moved_gets_no_plus_one_at_10in_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var info := _info(true, 10.0)
	assert_int(int(info["mod"])).override_failure_message("a moved gun at 10\": %s" % info.get("note", "")).is_equal(0)
	assert_str(str(info["note"])).contains("Artillery").contains("Hold")


func test_artillery_that_moved_gets_no_plus_one_at_13in_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var info := _info(true, 13.0)
	assert_int(int(info["mod"])).override_failure_message("a moved gun at 13\": %s" % info.get("note", "")).is_equal(0)
	assert_str(str(info["note"])).contains("Artillery").contains("Hold")


func test_artillery_that_held_gets_no_plus_one_at_10in_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var info := _info(false, 10.0)
	assert_int(int(info["mod"])).override_failure_message("a held gun at 10\": %s" % info.get("note", "")).is_equal(0)
	assert_str(str(info["note"])).contains("Artillery").contains("12")


func test_artillery_that_held_gets_plus_one_at_13in_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var info := _info(false, 13.0)
	assert_int(int(info["mod"])).is_equal(1)
	assert_str(str(info["note"])).contains("Artillery +1")


func test_artillery_that_moved_keeps_the_plus_one_at_10in_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var info := _info(true, 10.0)
	assert_int(int(info["mod"])).is_equal(1)
	assert_str(str(info["note"])).contains("Artillery +1")

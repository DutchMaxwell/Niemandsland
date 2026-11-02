extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-19-fix: only Versatile Expert skips the pick's distance
## condition at EPOCH_73_V36; Versatile Warrior keeps the 9" shot / 6" charge band.
## Below the epoch both spellings keep the old gates.

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0
	RulesRegistry.reset_cache()


func _unit(rules: Array, faction: String = "watch_brothers") -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "sho19fix_%s" % faction
	u.unit_properties = {"player_id": 2, "name": "U", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": faction}
	var mi := ModelInstance.new()
	mi.is_alive = true
	u.models.append(mi)
	return u


## RED on main: Warrior is wrongly ungated, so a 6" shot and a 3" charge still pick.
func test_warrior_keeps_the_distance_gate_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var main: Node = auto_free(preload("res://scripts/main.gd").new())
	var warrior := _unit(["Versatile Warrior"])
	assert_bool(main._solo_versatile_over(warrior, 6.0, false, 0.0)) \
		.override_failure_message("a 6\" shot stays inside the 9\" gate").is_false()
	assert_bool(main._solo_versatile_over(warrior, 0.0, true, 3.0)) \
		.override_failure_message("a 3\" charge stays inside the 6\" gate").is_false()
	assert_bool(main._solo_versatile_over(warrior, 10.0, false, 0.0)) \
		.override_failure_message("a 10\" shot clears the 9\" gate").is_true()
	assert_bool(main._solo_versatile_over(warrior, 0.0, true, 7.0)) \
		.override_failure_message("a 7\" charge clears the 6\" gate").is_true()


## The Expert spelling keeps the ungated pick at any distance.
func test_expert_keeps_the_ungated_pick_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var main: Node = auto_free(preload("res://scripts/main.gd").new())
	assert_bool(main._solo_versatile_over(_unit(["Versatile Expert"]), 5.0, false, 0.0)) \
		.override_failure_message("Versatile Expert fires a 5\" shot").is_true()
	assert_bool(main._solo_versatile_over(_unit(["Versatile Expert"]), 0.0, true, 3.0)) \
		.override_failure_message("Versatile Expert fires a 3\" charge").is_true()


## The pin: below 73 both spellings keep the old distance gates.
func test_below_epoch_73_the_old_distance_gates_return() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var main: Node = auto_free(preload("res://scripts/main.gd").new())
	assert_bool(main._solo_versatile_over(_unit(["Versatile Warrior"]), 6.0, false, 0.0)) \
		.override_failure_message("72 keeps the 9\" shot gate for Warrior").is_false()
	assert_bool(main._solo_versatile_over(_unit(["Versatile Expert"]), 5.0, false, 0.0)) \
		.override_failure_message("72 keeps the 9\" shot gate for Expert").is_false()

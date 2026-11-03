extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-19: the charge-gated Versatile families need over 6" charging at
## EPOCH_73_V36, Versatile Expert carries no distance gate, and Havocbound's charge leg
## reads the same 6" band. Below the epoch the old answers stay.

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0
	RulesRegistry.reset_cache()


func _unit(rules: Array, faction: String = "watch_brothers") -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "sho19_%s" % faction
	u.unit_properties = {"player_id": 2, "name": "U", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": faction}
	var mi := ModelInstance.new()
	mi.is_alive = true
	u.models.append(mi)
	return u


## RED on main: the base families keep the 9" shot gate but read the shared 6" charge gate.
func test_the_base_families_charge_over_six_inches_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var main: Node = auto_free(preload("res://scripts/main.gd").new())
	var watch := _unit(["Watchborn"])
	assert_bool(main._solo_versatile_over(watch, 0.0, true, 7.0)) \
		.override_failure_message("a 7\" charge clears the 6\" gate").is_true()
	assert_bool(main._solo_versatile_over(watch, 0.0, true, 5.0)) \
		.override_failure_message("a 5\" charge stays inside the 6\" gate").is_false()
	assert_bool(main._solo_versatile_over(watch, 10.0, false, 0.0)) \
		.override_failure_message("a 10\" shot clears the 9\" gate").is_true()
	assert_bool(main._solo_versatile_over(watch, 5.0, false, 0.0)) \
		.override_failure_message("a 5\" shot stays inside the 9\" gate").is_false()


## RED on main: Versatile Expert skips the distance gate at 73.
func test_versatile_expert_skips_the_gate_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var main: Node = auto_free(preload("res://scripts/main.gd").new())
	assert_bool(main._solo_versatile_over(_unit(["Versatile Expert"]), 5.0, false, 0.0)) \
		.override_failure_message("Versatile Expert fires a 5\" shot").is_true()
	assert_bool(main._solo_versatile_over(_unit(["Versatile Expert"]), 0.0, true, 3.0)) \
		.override_failure_message("Versatile Expert fires a 3\" charge").is_true()


## The old side: below 73 the old gates return for every spelling.
func test_below_epoch_73_the_old_distance_gates_return() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var main: Node = auto_free(preload("res://scripts/main.gd").new())
	assert_bool(main._solo_versatile_over(_unit(["Versatile Expert"]), 5.0, false, 0.0)) \
		.override_failure_message("72 keeps the old 9\" shot gate").is_false()
	assert_bool(main._solo_versatile_over(_unit(["Watchborn"]), 0.0, true, 7.0)) \
		.override_failure_message("72 keeps the old 9\" charge gate for the base").is_false()


## RED on main: Havocbound's charge AP needs over 6" at 73; below 73 it fires at 4".
func test_havocbound_charge_ap_needs_over_six_inches_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var main: Node = auto_free(preload("res://scripts/main.gd").new())
	main.battle_log = auto_free(BattleLog.new())
	var striker := _unit(["Havocbound"], "havoc_brothers")
	var target := _unit([], "war_disciples")
	var profile := {"name": "Blade", "rules": [], "range": 0}
	main._solo_alias_charge_in = 7.0
	var far: Array = main._solo_conditional_ap_parts(profile, striker, target, true, -1.0, true)
	assert_int(int(far[0]["bonus"]) if not far.is_empty() else 0) \
		.override_failure_message("a 7\" charge pays AP(+1)").is_equal(1)
	main._solo_alias_charge_in = 4.0
	var near: Array = main._solo_conditional_ap_parts(profile, striker, target, true, -1.0, true)
	assert_int(int(near[0]["bonus"]) if not near.is_empty() else 0) \
		.override_failure_message("a 4\" charge pays no AP").is_equal(0)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	main._solo_alias_charge_in = 4.0
	var old: Array = main._solo_conditional_ap_parts(profile, striker, target, true, -1.0, true)
	assert_int(int(old[0]["bonus"]) if not old.is_empty() else 0) \
		.override_failure_message("below 73 the 4\" charge still pays").is_equal(1)

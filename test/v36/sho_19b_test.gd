extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-19b: an Enhanced Watchborn token/carrier skips the 9"/6" distance
## gate at EPOCH_73_V36; the base Watchborn keeps the old gate and below the epoch nothing opens.

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0
	RulesRegistry.reset_cache()


func _unit(rules: Array, faction: String = "watch_brothers") -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "sho19b_%s" % faction
	u.unit_properties = {"player_id": 2, "name": "U", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": "gf", "faction_folder": faction}
	var mi := ModelInstance.new()
	mi.is_alive = true
	u.models.append(mi)
	return u


## RED on main: Enhanced Watchborn skips the distance gate at 73; the base form does not.
func test_enhanced_watchborn_skips_the_gate_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var main: Node = auto_free(preload("res://scripts/main.gd").new())
	var enhanced := _unit(["Watchborn", "Enhanced Watchborn"])
	assert_bool(main._solo_versatile_no_gate(enhanced)) \
		.override_failure_message("Enhanced Watchborn carries the no-gate pick").is_true()
	assert_bool(main._solo_versatile_over(enhanced, 5.0, false, 0.0)) \
		.override_failure_message("Enhanced Watchborn fires a 5\" shot").is_true()
	assert_bool(main._solo_versatile_over(enhanced, 0.0, true, 3.0)) \
		.override_failure_message("Enhanced Watchborn fires a 3\" charge").is_true()
	assert_bool(main._solo_versatile_over(_unit(["Watchborn"]), 5.0, false, 0.0)) \
		.override_failure_message("the base Watchborn keeps the 9\" shot gate").is_false()


## The old side: below 73 the token reads nothing and the old gates return.
func test_below_epoch_73_the_enhanced_token_opens_nothing() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var main: Node = auto_free(preload("res://scripts/main.gd").new())
	var enhanced := _unit(["Watchborn", "Enhanced Watchborn"])
	assert_bool(main._solo_versatile_no_gate(enhanced)) \
		.override_failure_message("72 keeps the token inert").is_false()
	assert_bool(main._solo_versatile_over(enhanced, 5.0, false, 0.0)) \
		.override_failure_message("72 keeps the old 9\" shot gate").is_false()
	assert_bool(main._solo_versatile_over(enhanced, 0.0, true, 3.0)) \
		.override_failure_message("72 keeps the old 9\" charge gate").is_false()

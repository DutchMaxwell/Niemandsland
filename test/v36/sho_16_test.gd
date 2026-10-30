extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-16: Cumbersome (37 units). From the rules 3.6 epoch (73) on, a Cumbersome
## unit may only Hold or Advance and never shoots after it moved; below it (72) it plays as before.
## The map carries the rule for both systems (so the inventory stops listing it "by hand"), and the
## player's engine verbs refuse Rush and Charge for it and keep the shot pick shut after an Advance.

const MainScript := preload("res://scripts/main.gd")

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	RulesRegistry.reset_cache()


func after_test() -> void:
	# statics leak across gdUnit tests — restore
	AiActRecorder.rules_epoch = _epoch0
	RulesRegistry.reset_cache()


func _unit_with(rules: Array, system: String) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = "t_1"
	u.unit_properties = {"player_id": 2, "name": "Walker", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": "some_book"}
	return u


## main.gd's static helpers are called by name on a bare instance, so a tree without them fails on
## the assertion below, not on a missing symbol.
func _main_static(fn: String, args: Array, fallback: Variant) -> Variant:
	var main: Node = auto_free(MainScript.new())
	return main.callv(fn, args) if main.has_method(fn) else fallback


func test_cumbersome_resolves_from_the_map_in_both_systems() -> void:
	for system in ["gf", "aof"]:
		var u := _unit_with(["Cumbersome"], system)
		assert_bool(RulesRegistry.unit_rule_active(u, "Cumbersome")) \
			.override_failure_message("%s: the map must carry Cumbersome in common" % system).is_true()


func test_cumbersome_is_active_only_from_epoch_73() -> void:
	var u := _unit_with(["Cumbersome"], "gf")
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	assert_bool(bool(_main_static("cumbersome_active", [u], false))) \
		.override_failure_message("rules 3.6: the rule is live").is_true()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_bool(bool(_main_static("cumbersome_active", [u], false))) \
		.override_failure_message("rules 3.5 has no Cumbersome").is_false()


func test_an_ordinary_unit_is_never_cumbersome_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var u := _unit_with(["Tough(3)"], "gf")
	assert_bool(bool(_main_static("cumbersome_active", [u], false))).is_false()


func test_rush_and_charge_are_refused_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var u := _unit_with(["Cumbersome"], "aof")
	for verb in [AiDecision.Action.RUSH, AiDecision.Action.CHARGE]:
		var why := str(_main_static("cumbersome_refusal", [u, verb], ""))
		assert_str(why).override_failure_message("rules 3.6: verb %d must be refused" % verb) \
			.contains("Cumbersome")


func test_rush_and_charge_stay_open_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var u := _unit_with(["Cumbersome"], "aof")
	for verb in [AiDecision.Action.RUSH, AiDecision.Action.CHARGE]:
		assert_str(str(_main_static("cumbersome_refusal", [u, verb], ""))).is_empty()


func test_advance_is_not_refused_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var u := _unit_with(["Cumbersome"], "gf")
	assert_str(str(_main_static("cumbersome_refusal", [u, AiDecision.Action.ADVANCE], ""))).is_empty()

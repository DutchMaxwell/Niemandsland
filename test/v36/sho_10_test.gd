extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-10: the save re-roll window is data. A re-roll entry may name the target
## condition that opens it — the SAME predicate the conditional-AP leg runs (AiCombatMath.cond_met).
## No shipped entry spells the new optional params, so this builds a probe book: at epoch 72 the
## condition is ignored (the old unconditional window), at 73 it opens or shuts the whole re-roll.

const PROBE_BOOK := {"common": {
	"Probe Base": {"primitive": "Bane", "params": {"reroll_save_sixes": true}},
	"Probe Bane": {"primitive": "Bane", "params": {
		"condition": "def_5_6", "reroll_save_low": 5, "upgrades": "Probe Base"}},
	"Probe Far": {"primitive": "Bane", "params": {
		"condition": "over_half_range", "reroll_save_low": 5, "upgrades": "Probe Base"}}}}

const ATT := {"quality": 4, "models": 5}


func before_test() -> void:
	RulesRegistry.reset_cache()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func after_test() -> void:
	RulesRegistry.reset_cache()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36


func _book() -> void:
	RulesRegistry.reset_cache()
	RulesRegistry._cache["gf"] = PROBE_BOOK.duplicate(true)


func _unit(rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "u_sho10"
	u.unit_properties = {"player_id": 1, "name": "U", "quality": 4, "defense": 3,
		"special_rules": rules, "game_system": "gf", "faction_folder": ""}
	return u


func _rifle(over: Dictionary = {}) -> Dictionary:
	var p := {"name": "Probe Gun", "attacks": 8, "ap": 0, "deadly": 0, "relentless": false, "blast": 0,
		"reliable": false, "surge": false, "rending": false, "bane": true, "thrust": false,
		"counter": false, "range": 24, "rules": []}
	for k in over:
		p[k] = over[k]
	return p


func test_cond_met_is_the_shared_target_condition_test() -> void:
	assert_bool(AiCombatMath.cond_met("def_5_6", 0, 1, 5, false)).is_true()
	assert_bool(AiCombatMath.cond_met("def_5_6", 0, 1, 4, false)).is_false()
	assert_bool(AiCombatMath.cond_met("over_half_range", 0, 1, 4, false, 13.0, false,
		{"weapon_range_in": 24.0})).is_true()
	assert_bool(AiCombatMath.cond_met("over_half_range", 0, 1, 4, false, 10.0, false,
		{"weapon_range_in": 24.0})).is_false()
	assert_bool(AiCombatMath.cond_met("vs_tough_ge", 3, 3, 4, false)).is_true()
	assert_bool(AiCombatMath.cond_met("vs_tough_ge", 3, 2, 4, false)).is_false()


func test_the_window_carries_the_entry_condition_and_gates_on_the_target() -> void:
	_book()
	var u := _unit(["Probe Base", "Probe Bane"])
	var win: Dictionary = AiEv.bane_boost_window(u, true)
	assert_int(int(win.get("low", 0))).is_equal(5)
	assert_str(str(win.get("condition", ""))).is_equal("def_5_6")
	var rifle := _rifle()
	var r: Dictionary = AiEv.stamp_sergeant([rifle], u)[0]
	assert_bool(AiEv.bane_applies(r, 1, 3, 12.0, false)) \
		.override_failure_message("Defense 3 does not meet def_5_6").is_false()
	assert_bool(AiEv.bane_applies(r, 1, 5, 12.0, false)).is_true()
	assert_bool(AiEv.bane_applies(r, 1, 6, 12.0, false)).is_true()


func test_over_half_range_opens_only_beyond_half_the_weapon_range() -> void:
	_book()
	var u := _unit(["Probe Base", "Probe Far"])
	var rifle := _rifle()
	var r: Dictionary = AiEv.stamp_sergeant([rifle], u)[0]
	assert_bool(AiEv.bane_applies(r, 1, 4, 13.0, false)).is_true()
	assert_bool(AiEv.bane_applies(r, 1, 4, 10.0, false)) \
		.override_failure_message("10\" is inside half of 24\"").is_false()


func test_the_ev_prices_the_gated_window_only_when_the_condition_holds() -> void:
	var baned := _rifle({"bane": true, "bane_condition": "def_5_6"})
	var plain := _rifle({"bane": false})
	var soft := {"defense": 3, "tough": 1, "models": 5}
	var hard := {"defense": 5, "tough": 1, "models": 5}
	assert_float(AiEv.profile_ev(baned, ATT, soft, 12.0, false)) \
		.is_equal_approx(AiEv.profile_ev(plain, ATT, soft, 12.0, false), 0.0001)
	assert_bool(AiEv.profile_ev(baned, ATT, hard, 12.0, false)
		< AiEv.profile_ev(plain, ATT, hard, 12.0, false)).is_true()


func test_the_stamp_reads_the_condition_only_from_epoch_73() -> void:
	_book()
	var u := _unit(["Probe Base", "Probe Bane"])
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var old: Array = AiEv.stamp_sergeant([_rifle()], u)
	assert_bool((old[0] as Dictionary).has("bane_condition")) \
		.override_failure_message("epoch 72 ignores the condition").is_false()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var now: Array = AiEv.stamp_sergeant([_rifle()], u)
	assert_str(str((now[0] as Dictionary).get("bane_condition", ""))).is_equal("def_5_6")

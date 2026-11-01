extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-14e: the AI's shooting ESTIMATE twin of SHO-14. A Pierce weapon's
## expected wounds drop the target's POSITIVE Defense modifiers (Cover, Shielded, Guarded) at
## EPOCH_73_V36, while Armor and Fortified stay; below 73 the old numbers come back. The
## over-half-range AP(+1) is pure data on the conditional-AP hook and reaches the estimate already.
##
## An estimate adds no battle-log line: the rules-must-log rule covers APPLIED rules only, and the
## estimate applies nothing. Only the price changes.

const DEF_PLAIN := {"defense": 4, "tough": 1, "models": 5}
const ATT := {"quality": 4, "models": 5}

## 6 Quality-4 attacks into Defense 4+.
const FREE: float = 1.5


var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0


func _profile(pierce: bool, cond_ap: Array = []) -> Dictionary:
	return {"name": "Rifle", "attacks": 6, "ap": 0, "range": 24,
		"rules": (["Pierce"] if pierce else []), "cond_ap": cond_ap}


func _ev(profile: Dictionary, def_ctx: Dictionary, dist_in: float) -> float:
	return AiEv.profile_ev(profile, ATT, def_ctx, dist_in, false)


func test_a_covered_target_is_priced_at_armor_only_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var covered := {"defense": 4, "tough": 1, "models": 5, "in_cover": true}
	assert_float(_ev(_profile(true), covered, 12.0)).is_equal_approx(FREE, 0.0001)
	assert_bool(_ev(_profile(false), covered, 12.0) < FREE).is_true()


func test_a_shielded_target_is_priced_at_armor_only_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var shielded := {"defense": 3, "tough": 1, "models": 5, "shielded": true}
	assert_float(_ev(_profile(true), shielded, 12.0)).is_equal_approx(1.0, 0.0001)
	assert_bool(_ev(_profile(false), shielded, 12.0) < 1.0).is_true()


func test_a_guarded_target_is_priced_at_armor_only_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var guarded := {"defense": 4, "tough": 1, "models": 5, "guarded": true}
	assert_float(_ev(_profile(true), guarded, 12.0)).is_equal_approx(FREE, 0.0001)
	assert_bool(_ev(_profile(false), guarded, 12.0) < FREE).is_true()


func test_the_over_half_range_ap_bonus_reaches_the_estimate_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var armed := _profile(true, [{"condition": "over_half_range", "ap_bonus": 1}])
	assert_float(_ev(armed, DEF_PLAIN, 18.0)).is_equal_approx(2.0, 0.0001)
	assert_float(_ev(armed, DEF_PLAIN, 12.0)).is_equal_approx(FREE, 0.0001)


func test_the_old_numbers_come_back_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var covered := {"defense": 4, "tough": 1, "models": 5, "in_cover": true}
	assert_float(_ev(_profile(true), covered, 12.0)).is_equal_approx(
		_ev(_profile(false), covered, 12.0), 0.0001)


func test_the_plain_weapon_is_unchanged_at_both_epochs() -> void:
	var covered := {"defense": 4, "tough": 1, "models": 5, "in_cover": true}
	for epoch in [AiActRecorder.EPOCH_72_PLAYTEST_RULES, AiActRecorder.EPOCH_73_V36]:
		AiActRecorder.rules_epoch = epoch
		var plain := _ev(_profile(false), covered, 12.0)
		assert_float(plain).is_equal_approx(1.0, 0.0001)

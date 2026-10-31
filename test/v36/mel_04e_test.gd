extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-04e: the AI's Impact estimate sees a defender's Brace cut, so a charge
## into a braced unit is priced lower. Epoch 72 keeps today's value; a Fatigued braced defender
## cuts nothing in the estimate either; a unit without Brace is the control.

const ATT := {"quality": 4, "impact": 3, "models": 2}

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests


## `models` alive models, one melee weapon carrying `weapon_rules`.
func _brace_unit(models: int, weapon_rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_properties = {"player_id": 1, "name": "Defender", "quality": 4, "defense": 4, "special_rules": []}
	for i in range(models):
		var mi := ModelInstance.new()
		mi.is_alive = true
		u.models.append(mi)
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Blade"
	w.range_value = 0
	w.attacks = 1
	w.special_rules.assign(weapon_rules)
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	var opr := OPRApiClient.OPRUnit.new()
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	return u


func test_the_estimate_sees_two_brace_models_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var braced: Dictionary = AiEv.ctx_for(_brace_unit(2, ["Brace(1)"]))
	var plain: Dictionary = AiEv.ctx_for(_brace_unit(2, []))
	assert_int(int(braced.get("brace_models", 0))).is_equal(2)
	assert_bool(AiEv.impact_ev(ATT, braced) < AiEv.impact_ev(ATT, plain)).is_true()


func test_the_estimate_ignores_brace_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var braced: Dictionary = AiEv.ctx_for(_brace_unit(2, ["Brace(1)"]))
	var plain: Dictionary = AiEv.ctx_for(_brace_unit(2, []))
	assert_int(int(braced.get("brace_models", 0))).is_equal(0)
	assert_float(AiEv.impact_ev(ATT, braced)).is_equal_approx(AiEv.impact_ev(ATT, plain), 0.0001)


func test_a_fatigued_braced_defender_cuts_nothing_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var braced: Dictionary = AiEv.ctx_for(_brace_unit(2, ["Brace(1)"]))
	braced["fatigued"] = true
	var plain: Dictionary = AiEv.ctx_for(_brace_unit(2, []))
	assert_float(AiEv.impact_ev(ATT, braced)).is_equal_approx(AiEv.impact_ev(ATT, plain), 0.0001)


func test_a_control_unit_without_brace_is_unchanged() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var newer: float = AiEv.impact_ev(ATT, AiEv.ctx_for(_brace_unit(2, [])))
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var older: float = AiEv.impact_ev(ATT, AiEv.ctx_for(_brace_unit(2, [])))
	assert_float(newer).is_equal_approx(older, 0.0001)

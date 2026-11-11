extends GdUnitTestSuite
## Rules 3.6 wave, row SHO-17e: the AI's expected-wound estimate is the twin of SHO-17. From
## EPOCH_73_V36 the Guarded family's +1 Defense needs the charge to start over 6" (the W1.5b
## pre-charge edge gap `melee_ev` is handed); the shot leg keeps the shared over-9" gate. Below
## the epoch the stamped gate is 0.0 and the old estimate numbers return. The core twin is
## core/nml-core/src/tests/dice/v36_shoot_rows/sho_17e.rs.

const ATT := {"quality": 4, "models": 5}

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore
	RulesRegistry.reset_cache()


func _blade() -> Dictionary:
	return {"name": "Blade", "attacks": 10, "count": 1, "range": 0, "rules": []}


func _rifle() -> Dictionary:
	return {"name": "Rifle", "attacks": 10, "count": 1, "range": 24, "rules": []}


## One living model carrying `rules`, at the fixture's Defense 4+.
func _unit(rules: Array) -> GameUnit:
	var u := GameUnit.new()
	u.unit_properties = {"player_id": 2, "name": "U", "quality": 4, "defense": 4,
		"special_rules": rules}
	var mi := ModelInstance.new()
	mi.is_alive = true
	u.models.append(mi)
	return u


func _ctx(rules: Array, epoch: int) -> Dictionary:
	AiActRecorder.rules_epoch = epoch
	return AiEv.ctx_for(_unit(rules))


## RED on main: the Guarded family's charge gate is stamped on the EV context from the epoch on.
func test_ctx_stamps_the_six_inch_charge_gate_at_epoch_73() -> void:
	var ctx := _ctx(["Guarded"], AiActRecorder.EPOCH_73_V36)
	assert_float(float(ctx.get("guarded_charge_over_in", -1.0))) \
		.override_failure_message("epoch 73: the Guarded charge leg reads the shared 6\" gate") \
		.is_equal_approx(6.0, 0.0001)


func test_ctx_stamps_no_charge_gate_at_epoch_72() -> void:
	var ctx := _ctx(["Guarded"], AiActRecorder.EPOCH_72_PLAYTEST_RULES)
	assert_float(float(ctx.get("guarded_charge_over_in", -1.0))) \
		.override_failure_message("epoch 72: the old estimate keeps no charge gate") \
		.is_equal_approx(0.0, 0.0001)


## RED on main: a charge from 7" saves one better at the epoch; from 5" the bare Defense stays.
func test_guarded_charge_from_seven_inches_saves_one_better_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var guarded_ev := AiEv.melee_ev([_blade()], ATT, AiEv.ctx_for(_unit(["Guarded"])), true, 7.0)
	var plain_ev := AiEv.melee_ev([_blade()], ATT, AiEv.ctx_for(_unit([])), true, 7.0)
	assert_float(guarded_ev).override_failure_message("charged from over 6\": 4+ becomes 3+") \
		.is_less(plain_ev)


func test_guarded_charge_from_five_inches_keeps_the_bare_save_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var guarded_ev := AiEv.melee_ev([_blade()], ATT, AiEv.ctx_for(_unit(["Guarded"])), true, 5.0)
	var plain_ev := AiEv.melee_ev([_blade()], ATT, AiEv.ctx_for(_unit([])), true, 5.0)
	assert_float(guarded_ev).override_failure_message("5\" is not over the 6\" gate") \
		.is_equal_approx(plain_ev, 0.0001)


## The shot leg keeps its shared over-9" gate: 7" earns nothing, 10" the +1.
func test_guarded_shot_from_seven_inches_gets_no_bonus_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var guarded_ev := AiEv.profile_ev(_rifle(), ATT, AiEv.ctx_for(_unit(["Guarded"])), 7.0, false)
	var plain_ev := AiEv.profile_ev(_rifle(), ATT, AiEv.ctx_for(_unit([])), 7.0, false)
	assert_float(guarded_ev).override_failure_message("the charge gate never reaches a shot") \
		.is_equal_approx(plain_ev, 0.0001)


func test_guarded_shot_from_over_nine_inches_gets_the_bonus_at_epoch_73() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	var guarded_ev := AiEv.profile_ev(_rifle(), ATT, AiEv.ctx_for(_unit(["Guarded"])), 10.0, false)
	var plain_ev := AiEv.profile_ev(_rifle(), ATT, AiEv.ctx_for(_unit([])), 10.0, false)
	assert_float(guarded_ev).override_failure_message("over 9\" still pays the +1") \
		.is_less(plain_ev)


## THE OLD SIDE: below the epoch the old numbers return at every gap.
func test_guarded_charge_keeps_the_old_numbers_at_epoch_72() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var guarded_ctx := AiEv.ctx_for(_unit(["Guarded"]))
	var plain_ctx := AiEv.ctx_for(_unit([]))
	for gap in [5.0, 7.0, 10.0]:
		assert_float(AiEv.melee_ev([_blade()], ATT, guarded_ctx, true, gap)) \
			.override_failure_message("%s\" at 72: the old unconditional number" % str(gap)) \
			.is_equal_approx(AiEv.melee_ev([_blade()], ATT, plain_ctx, true, gap), 0.0001)

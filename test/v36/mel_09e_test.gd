extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-09e: the AI's melee EV twin of MEL-09 (test/v36/mel_09_test.gd). From
## EPOCH_73_V36 a Fatigued striker's sixes still hit but fire no rule, so profile_ev must not price
## the Rending on-6 AP(+4) sub-batch; epoch 72 keeps today's reading. The core twin is
## core/nml-core/src/tests/dice/v36_melee_rows/mel_09e.rs.

const ATT := {"quality": 4, "models": 10}

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore


func _blade(rending: bool) -> Dictionary:
	return {"name": "Claw", "attacks": 12, "count": 1, "range": 0, "rending": rending, "rules": []}


## The EV of the Quality 4 striker's 12-attack melee profile into a Defense 4 unit of 10 at `epoch`.
func _ev(rending: bool, fatigued: bool, epoch: int) -> float:
	AiActRecorder.rules_epoch = epoch
	var att: Dictionary = ATT.duplicate()
	att["fatigued"] = fatigued
	return AiEv.profile_ev(_blade(rending), att, {"defense": 4, "models": 10, "tough": 1}, 0.0, false)


func test_fatigued_rending_ev_still_rends_at_epoch_72() -> void:
	assert_float(_ev(true, true, AiActRecorder.EPOCH_72_PLAYTEST_RULES)) \
		.override_failure_message("epoch 72: a fatigued striker's sixes still save at AP(+4)") \
		.is_greater(_ev(false, true, AiActRecorder.EPOCH_72_PLAYTEST_RULES))


func test_fatigued_rending_ev_drops_the_on6_bonus_at_epoch_73() -> void:
	assert_float(_ev(true, true, AiActRecorder.EPOCH_73_V36)) \
		.override_failure_message("epoch 73: the muted sixes save at the plain Defense") \
		.is_equal_approx(_ev(false, true, AiActRecorder.EPOCH_73_V36), 0.0001)


func test_a_fresh_rending_striker_still_rends_in_the_ev_at_epoch_73() -> void:
	assert_float(_ev(true, false, AiActRecorder.EPOCH_73_V36)) \
		.override_failure_message("a rested rending strike keeps the AP(+4) on its sixes") \
		.is_greater(_ev(false, false, AiActRecorder.EPOCH_73_V36))

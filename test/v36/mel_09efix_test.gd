extends GdUnitTestSuite
## Rules 3.6 wave, row MEL-09e-fix: a Fatigued melee striker's unmodified 6s still hit
## but fire no rule, so AiEv.profile_ev must not price the Surge, Furious or Sergeant
## bonus hits from EPOCH_73_V36. Epoch 72 keeps the old reading and a fresh striker
## keeps every bonus. The core twin is
## core/nml-core/src/tests/dice/v36_melee_rows/mel_09e.rs.

const ATT := {"quality": 4, "models": 10}
const DEF := {"defense": 4, "models": 10, "tough": 1}

var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests — restore


func _blade(extra: Dictionary = {}) -> Dictionary:
	var p := {"name": "Claw", "attacks": 12, "count": 1, "range": 0, "rules": []}
	p.merge(extra)
	return p


## The EV of the Quality 4 striker's 12-attack melee profile at `epoch`. The
## profile and context are the same shape the table plan path hands to
## profile_ev; `att_extra` adds the unit-level facets (Furious).
func _ev(profile: Dictionary, fatigued: bool, epoch: int, att_extra: Dictionary = {}) -> float:
	AiActRecorder.rules_epoch = epoch
	var att: Dictionary = ATT.duplicate()
	att["fatigued"] = fatigued
	att.merge(att_extra)
	return AiEv.profile_ev(profile, att, DEF, 0.0, true)


func _plain(epoch: int, fatigued: bool) -> float:
	return _ev(_blade(), fatigued, epoch)


func test_fatigued_surge_ev_drops_the_six_bonus_at_epoch_73() -> void:
	assert_float(_ev(_blade({"surge": true}), true, AiActRecorder.EPOCH_73_V36)) \
		.override_failure_message("73: a Fatigued Surge striker's sixes add no hit") \
		.is_equal_approx(_plain(AiActRecorder.EPOCH_73_V36, true), 0.0001)


func test_fatigued_furious_ev_drops_the_six_bonus_at_epoch_73() -> void:
	assert_float(_ev(_blade(), true, AiActRecorder.EPOCH_73_V36, {"furious": true})) \
		.override_failure_message("73: a Fatigued Furious charge's sixes add no hit") \
		.is_equal_approx(_plain(AiActRecorder.EPOCH_73_V36, true), 0.0001)


func test_fatigued_sergeant_ev_drops_the_six_bonus_at_epoch_73() -> void:
	assert_float(_ev(_blade({"sergeant_attacks": 12}), true, AiActRecorder.EPOCH_73_V36)) \
		.override_failure_message("73: a Fatigued Sergeant's sixes add no hit") \
		.is_equal_approx(_plain(AiActRecorder.EPOCH_73_V36, true), 0.0001)


func test_a_fresh_striker_keeps_every_six_bonus_at_epoch_73() -> void:
	var plain := _plain(AiActRecorder.EPOCH_73_V36, false)
	assert_float(_ev(_blade({"surge": true}), false, AiActRecorder.EPOCH_73_V36)) \
		.override_failure_message("a rested Surge strike keeps its hit") \
		.is_greater(plain)
	assert_float(_ev(_blade(), false, AiActRecorder.EPOCH_73_V36, {"furious": true})) \
		.override_failure_message("a rested Furious charge keeps its hit") \
		.is_greater(plain)
	assert_float(_ev(_blade({"sergeant_attacks": 12}), false, AiActRecorder.EPOCH_73_V36)) \
		.override_failure_message("a rested Sergeant keeps its hit") \
		.is_greater(plain)


func test_fatigued_extras_still_pay_at_epoch_72() -> void:
	var plain := _plain(AiActRecorder.EPOCH_72_PLAYTEST_RULES, true)
	assert_float(_ev(_blade({"surge": true}), true, AiActRecorder.EPOCH_72_PLAYTEST_RULES)) \
		.override_failure_message("72: a Fatigued Surge strike still adds its hit") \
		.is_greater(plain)
	assert_float(_ev(_blade(), true, AiActRecorder.EPOCH_72_PLAYTEST_RULES, {"furious": true})) \
		.override_failure_message("72: a Fatigued Furious charge still adds its hit") \
		.is_greater(plain)
	assert_float(_ev(_blade({"sergeant_attacks": 12}), true, AiActRecorder.EPOCH_72_PLAYTEST_RULES)) \
		.override_failure_message("72: a Fatigued Sergeant still adds its hit") \
		.is_greater(plain)

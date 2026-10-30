extends GdUnitTestSuite
## OPR "Who Can Strike" (GF/AoF Advanced Rules v3.5.1 p.9): "All models that are within 2"
## horizontally and 4" vertically of an enemy model from the target unit, may attack it."
## SoloSim's self-play board is a flat 2D abstraction (no height dimension, see solo_sim.gd
## header) and stays out of this phase's scope (Finding 6, PLAN_heights_2026-09-27.md) — only
## the table-facing SoloController is covered here.

const INCH: float = SoloController.INCHES_TO_METERS


func test_within_melee_height_is_true_at_exactly_4in_false_just_beyond() -> void:
	# The 3.5 records' 4"; rules 3.6 reach 3" up from EPOCH_73_V36 (test/v36/mel_08_test.gd).
	var saved_epoch := AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	assert_bool(SoloController.within_melee_height(0.0, 4.0 * INCH)).is_true()
	assert_bool(SoloController.within_melee_height(0.0, 4.01 * INCH)).is_false()
	AiActRecorder.rules_epoch = saved_epoch


func test_striking_models_ignores_a_striker_five_inches_above() -> void:
	var enemy := [Vector3(0.0, 0.0, 0.0)]
	var striker := [Vector3(1.0 * INCH, 5.0 * INCH, 0.0)]
	assert_int(SoloController.striking_models(striker, enemy)).is_equal(0)


func test_striking_models_counts_a_striker_three_inches_above() -> void:
	var enemy := [Vector3(0.0, 0.0, 0.0)]
	var striker := [Vector3(1.0 * INCH, 3.0 * INCH, 0.0)]
	assert_int(SoloController.striking_models(striker, enemy)).is_equal(1)

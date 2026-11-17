extends GdUnitTestSuite
## U1: the two research seams around the D-wave leaf blend, as the GDScript side reads them: NML_DEPTH_DISCOUNT overrides the
## geometric discount (default 0.5, junk falls back), NML_SEAT_DEPTH picks the seat mode (off=0 and unset=0, on=1, inv=2). Both are lazy env
## reads cached in static vars (stamped into the core's header knobs, so they stay); every case restores env + statics.
## The blend arithmetic these knobs steer (AiPlanner._blend_score) is the core's: tests/rollout.rs G3 and the in-tree
## `the_seat_branch_is_load_bearing`, `leaf_opener_only_off_is_todays_rollout_value` (P4.D-92).

## Dynamic dispatch keeps this file PARSING pre-fix (a direct AiPlanner.seat_mode()
## reference would be a parse error). has_method() is required, not optional: a
## bare .call() to a truly nonexistent method throws mid-run and (observed on
## this engine) crashes the gdUnit CI runner outright instead of just failing
## the one test case — has_method() records a clean assertion failure instead.
func _dyn(method: String) -> Variant:
	var inst := AiPlanner.new()
	if inst.has_method(method):
		return inst.call(method)
	assert_bool(false).override_failure_message(
		"%s() not implemented yet (pre-fix RED)" % method).is_true()
	return 0


## Order dependence: solo_controller sets AiPlanner.opener_seat on every real pick and never
## resets it, and both lazy env statics leak across cases the same way.
func before_test() -> void:
	AiPlanner.opener_seat = false
	AiPlanner._seat_env = -1
	AiPlanner.new().set("_dd_env", -1.0)


func after_test() -> void:
	OS.set_environment("NML_SEAT_DEPTH", "")
	OS.set_environment("NML_DEPTH_DISCOUNT", "")
	AiPlanner.opener_seat = false
	AiPlanner._seat_env = -1
	AiPlanner.new().set("_dd_env", -1.0)


## NML_SEAT_DEPTH: off -> 0, unset -> 0 (the U-wave promoted seat_off to reference 24.08.), on -> 1 (the pre-U opener vote stays
## reachable for research), inv -> 2.
func test_seat_depth_env_values() -> void:
	for pair in [["off", 0], ["", 0], ["on", 1], ["inv", 2]]:
		OS.set_environment("NML_SEAT_DEPTH", str(pair[0]))
		AiPlanner._seat_env = -1
		assert_int(int(_dyn("seat_mode"))).override_failure_message("NML_SEAT_DEPTH='%s'" % pair[0]).is_equal(int(pair[1]))


## NML_DEPTH_DISCOUNT=1.0: every boundary weighs equally; 0.25: the deeper round is almost muted.
func test_depth_discount_env_reweights_the_blend() -> void:
	for pair in [["1.0", 1.0], ["0.25", 0.25]]:
		OS.set_environment("NML_DEPTH_DISCOUNT", str(pair[0]))
		AiPlanner.new().set("_dd_env", -1.0)
		assert_float(float(_dyn("depth_discount"))).is_equal_approx(float(pair[1]), 0.0001)


## Junk NML_DEPTH_DISCOUNT (empty/non-numeric/out of (0,1]) falls back to the documented default 0.5 — same as no env at all.
func test_depth_discount_env_junk_falls_back_to_default() -> void:
	for junk in ["banana", "0", "1.5", "-1", ""]:
		OS.set_environment("NML_DEPTH_DISCOUNT", junk)
		AiPlanner.new().set("_dd_env", -1.0)
		assert_float(float(_dyn("depth_discount"))).override_failure_message(
			"junk '%s' must fall back to 0.5" % junk).is_equal_approx(0.5, 0.0001)

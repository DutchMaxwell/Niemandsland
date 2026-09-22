extends GdUnitTestSuite
## WAITTAIL — the [ACT_PHASE] instrument (scripts/solo/solo_controller.gd, NML_ACT_WALL switch).
## The phase accumulators are per-activation: _phase_begin() must drop everything the previous
## activation measured, so a line cannot leak another activation's phases. _phase_mark() adds only.


func test_phase_accumulators_reset_per_activation() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	solo._phase_begin()
	solo._phase_us["select"] = 111
	var t0 := Time.get_ticks_usec() - 1000
	solo._phase_mark("act", t0)
	assert_int(int(solo._phase_us.get("select", 0))).is_equal(111)
	assert_int(int(solo._phase_us.get("act", 0))).is_greater(0)
	solo._phase_begin()   # a new activation: no phase from the previous one survives
	assert_bool(solo._phase_us.is_empty()).is_true()
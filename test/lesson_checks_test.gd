extends GdUnitTestSuite
## Unit tests for LessonChecks: each check gets a RED case (now == base, must not pass) and a GREEN
## case (now shows the goal), proving the check can actually fail before it can pass.


func _step(check_name: String, args: Dictionary) -> Dictionary:
	return {"all": [{"check": check_name, "args": args}]}


func test_camera_turned() -> void:
	var step := _step("camera_turned", {"deg": 20})
	var base := {"yaw": 0.0}
	assert_bool(LessonChecks.passes(step, base, base)).is_false()
	var now := {"yaw": deg_to_rad(25.0)}
	assert_bool(LessonChecks.passes(step, now, base)).is_true()


func test_camera_zoomed() -> void:
	var step := _step("camera_zoomed", {"ratio": 0.18})
	var base := {"cam_dist": 10.0}
	assert_bool(LessonChecks.passes(step, base, base)).is_false()
	var now := {"cam_dist": 15.0}
	assert_bool(LessonChecks.passes(step, now, base)).is_true()


func test_camera_panned() -> void:
	var step := _step("camera_panned", {"m": 0.15})
	var base := {"pivot": Vector3.ZERO}
	assert_bool(LessonChecks.passes(step, base, base)).is_false()
	var now := {"pivot": Vector3(0.2, 0.0, 0.0)}
	assert_bool(LessonChecks.passes(step, now, base)).is_true()


func test_counter_grew() -> void:
	var step := _step("counter_grew", {"key": "measure"})
	var base := {"counters": {"measure": 0}}
	assert_bool(LessonChecks.passes(step, base, base)).is_false()
	var now := {"counters": {"measure": 1}}
	assert_bool(LessonChecks.passes(step, now, base)).is_true()


func test_flag() -> void:
	var step := _step("flag", {"key": "ready"})
	var base := {"ready": false}
	assert_bool(LessonChecks.passes(step, base, base)).is_false()
	var now := {"ready": true}
	assert_bool(LessonChecks.passes(step, now, base)).is_true()


func test_at_least() -> void:
	var step := _step("at_least", {"key": "units_p1", "n": 1})
	var base := {"units_p1": 0}
	assert_bool(LessonChecks.passes(step, base, base)).is_false()
	var now := {"units_p1": 1}
	assert_bool(LessonChecks.passes(step, now, base)).is_true()


func test_value_changed() -> void:
	var step := _step("value_changed", {"key": "biome"})
	var base := {"biome": "grassland"}
	assert_bool(LessonChecks.passes(step, base, base)).is_false()
	var now := {"biome": "desert"}
	assert_bool(LessonChecks.passes(step, now, base)).is_true()


func test_value_is() -> void:
	var step := _step("value_is", {"key": "phase", "value": 1})
	var base := {"phase": 0}
	assert_bool(LessonChecks.passes(step, base, base)).is_false()
	var now := {"phase": 1}
	assert_bool(LessonChecks.passes(step, now, base)).is_true()


func test_all_of_one_failing_entry_fails_the_step() -> void:
	var step := {"all": [
		{"check": "flag", "args": {"key": "a"}},
		{"check": "flag", "args": {"key": "b"}},
	]}
	var base := {"a": false, "b": false}
	var now := {"a": true, "b": false}
	assert_bool(LessonChecks.passes(step, now, base)).is_false()
	var now_both := {"a": true, "b": true}
	assert_bool(LessonChecks.passes(step, now_both, base)).is_true()


func test_unknown_check_fails() -> void:
	var step := _step("no_such_check", {})
	assert_bool(LessonChecks.passes(step, {}, {})).is_false()

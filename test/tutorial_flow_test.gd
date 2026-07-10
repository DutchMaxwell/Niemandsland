extends GdUnitTestSuite
## Unit tests for the pure tutorial lesson/step FSM (TutorialFlow): the T1 tool-track
## definition, event-gated step advancement, lesson boundaries, chapter jumps and skips.
## No scene, no signals — pure state machine.

const Flow := preload("res://scripts/tutorial_flow.gd")


func _new_flow() -> TutorialFlow:
	return Flow.new(Flow.build_tool_track())


## ===== Track definition =====

func test_tool_track_has_six_lessons_w1_to_w6() -> void:
	var track := Flow.build_tool_track()
	assert_int(track.size()).is_equal(6)
	assert_array(Flow.ids(track)).is_equal(["W1", "W2", "W3", "W4", "W5", "W6"])


func test_every_step_is_fully_defined() -> void:
	for lesson in Flow.build_tool_track():
		assert_str(String(lesson.get("title", ""))).is_not_empty()
		var steps: Array = lesson.get("steps", [])
		assert_int(steps.size()).is_greater(1)
		for step in steps:
			assert_str(String(step.get("id", ""))).is_not_empty()
			assert_str(String(step.get("text", ""))).is_not_empty()
			assert_int(int(step.get("event", Flow.Event.NONE))).is_not_equal(Flow.Event.NONE)
			assert_bool(step.has("target")).is_true()
			assert_bool(step.get("mask") is bool).is_true()


func test_title_lookup() -> void:
	var track := Flow.build_tool_track()
	assert_str(Flow.title_of(track, "W4")).is_equal("Dice & measuring")
	assert_str(Flow.title_of(track, "W9")).is_equal("")


## ===== Event-gated advancement =====

func test_only_the_required_event_advances() -> void:
	var flow := _new_flow()  # starts at W1/orbit
	var before := flow.step_index
	# Every wrong event is ignored.
	for event in [Flow.Event.DICE_ROLLED, Flow.Event.UNIT_SELECTED, Flow.Event.CAMERA_ZOOM, Flow.Event.NONE]:
		var result := flow.consume(event)
		assert_bool(result.advanced).is_false()
	assert_int(flow.step_index).is_equal(before)
	# The right one advances by exactly one step.
	var ok := flow.consume(Flow.Event.CAMERA_ORBIT)
	assert_bool(ok.advanced).is_true()
	assert_str(String(ok.lesson_completed)).is_empty()
	assert_int(flow.step_index).is_equal(before + 1)


func test_lesson_boundary_reports_completion_and_moves_on() -> void:
	var flow := _new_flow()
	flow.consume(Flow.Event.CAMERA_ORBIT)
	flow.consume(Flow.Event.CAMERA_ZOOM)
	var result := flow.consume(Flow.Event.CAMERA_PAN)  # last W1 step
	assert_bool(result.advanced).is_true()
	assert_str(String(result.lesson_completed)).is_equal("W1")
	assert_bool(result.finished).is_false()
	assert_str(String(flow.current_lesson().get("id", ""))).is_equal("W2")
	assert_int(flow.step_index).is_equal(0)


func test_full_walk_finishes_the_track() -> void:
	var flow := _new_flow()
	var completed: Array[String] = []
	var guard := 0
	while not flow.finished and guard < 60:
		guard += 1
		var event := int(flow.current_step().get("event", Flow.Event.NONE)) as TutorialFlow.Event
		var result := flow.consume(event)
		assert_bool(result.advanced).is_true()
		if not String(result.lesson_completed).is_empty():
			completed.append(String(result.lesson_completed))
	assert_bool(flow.finished).is_true()
	assert_array(completed).is_equal(["W1", "W2", "W3", "W4", "W5", "W6"])
	assert_int(guard).is_equal(18)  # 3+3+4+3+3+2 steps


func test_finished_flow_ignores_events() -> void:
	var flow := _new_flow()
	flow.finish_track()
	var result := flow.consume(Flow.Event.CAMERA_ORBIT)
	assert_bool(result.advanced).is_false()
	assert_bool(result.finished).is_true()


## ===== Chapter jump / skip =====

func test_start_at_jumps_to_lesson_start() -> void:
	var flow := _new_flow()
	assert_bool(flow.start_at("W4")).is_true()
	assert_str(String(flow.current_lesson().get("id", ""))).is_equal("W4")
	assert_int(flow.step_index).is_equal(0)
	assert_str(String(flow.current_step().get("id", ""))).is_equal("measure")


func test_start_at_unknown_lesson_is_rejected() -> void:
	var flow := _new_flow()
	assert_bool(flow.start_at("W9")).is_false()
	assert_str(String(flow.current_lesson().get("id", ""))).is_equal("W1")


func test_skip_current_lesson_completes_and_advances() -> void:
	var flow := _new_flow()
	flow.consume(Flow.Event.CAMERA_ORBIT)  # mid-lesson
	var result := flow.skip_current_lesson()
	assert_bool(result.advanced).is_true()
	assert_str(String(result.lesson_completed)).is_equal("W1")
	assert_str(String(flow.current_lesson().get("id", ""))).is_equal("W2")


func test_skip_on_last_lesson_finishes() -> void:
	var flow := _new_flow()
	flow.start_at("W6")
	var result := flow.skip_current_lesson()
	assert_str(String(result.lesson_completed)).is_equal("W6")
	assert_bool(result.finished).is_true()
	assert_bool(flow.finished).is_true()


## ===== T2 rule track (R1-R3) + full track =====

func test_rule_track_has_three_lessons_r1_to_r3() -> void:
	var track := Flow.build_rule_track()
	assert_int(track.size()).is_equal(3)
	assert_array(Flow.ids(track)).is_equal(["R1", "R2", "R3"])


func test_full_track_is_tool_plus_rule() -> void:
	var track := Flow.build_full_track()
	assert_array(Flow.ids(track)).is_equal(["W1", "W2", "W3", "W4", "W5", "W6", "R1", "R2", "R3"])
	# The full track must not mutate the sub-track builders (fresh arrays each call).
	assert_int(Flow.build_tool_track().size()).is_equal(6)
	assert_int(Flow.build_rule_track().size()).is_equal(3)


func test_full_track_every_step_is_fully_defined() -> void:
	for lesson in Flow.build_full_track():
		assert_str(String(lesson.get("title", ""))).is_not_empty()
		var steps: Array = lesson.get("steps", [])
		assert_int(steps.size()).is_greater(0)
		for step in steps:
			assert_str(String(step.get("id", ""))).is_not_empty()
			assert_str(String(step.get("text", ""))).is_not_empty()
			assert_int(int(step.get("event", Flow.Event.NONE))).is_not_equal(Flow.Event.NONE)
			assert_bool(step.has("target")).is_true()
			assert_bool(step.get("mask") is bool).is_true()


func test_r2_concept_step_is_ack_gated() -> void:
	# R2 has a single concept card advanced by the coach "GOT IT" button (Event.ACK),
	# flagged ack:true so the director shows that button (no on-board regiment to act on).
	var rule := Flow.build_rule_track()
	var r2_steps: Array = rule[1].get("steps", [])
	assert_int(r2_steps.size()).is_equal(1)
	assert_int(int(r2_steps[0].get("event", Flow.Event.NONE))).is_equal(Flow.Event.ACK)
	assert_bool(r2_steps[0].get("ack", false)).is_true()


func test_rule_track_walk_via_events() -> void:
	# R1 activate -> round, R2 ack, R3 coherency broken -> restored.
	var flow := Flow.new(Flow.build_full_track())
	assert_bool(flow.start_at("R1")).is_true()
	assert_bool(flow.consume(Flow.Event.UNIT_ACTIVATED).advanced).is_true()
	var r1_done := flow.consume(Flow.Event.ROUND_ADVANCED)
	assert_str(String(r1_done.lesson_completed)).is_equal("R1")
	# R2: only ACK advances the concept card.
	assert_bool(flow.consume(Flow.Event.DICE_ROLLED).advanced).is_false()
	var r2_done := flow.consume(Flow.Event.ACK)
	assert_str(String(r2_done.lesson_completed)).is_equal("R2")
	# R3: broken then restored finishes the whole track.
	assert_bool(flow.consume(Flow.Event.COHERENCY_BROKEN).advanced).is_true()
	var r3_done := flow.consume(Flow.Event.COHERENCY_RESTORED)
	assert_str(String(r3_done.lesson_completed)).is_equal("R3")
	assert_bool(flow.finished).is_true()


func test_full_walk_finishes_all_nine_lessons() -> void:
	var flow := Flow.new(Flow.build_full_track())
	var completed: Array[String] = []
	var guard := 0
	while not flow.finished and guard < 80:
		guard += 1
		var event := int(flow.current_step().get("event", Flow.Event.NONE)) as TutorialFlow.Event
		var result := flow.consume(event)
		assert_bool(result.advanced).is_true()
		if not String(result.lesson_completed).is_empty():
			completed.append(String(result.lesson_completed))
	assert_array(completed).is_equal(["W1", "W2", "W3", "W4", "W5", "W6", "R1", "R2", "R3"])
	assert_int(guard).is_equal(23)  # 18 tool steps + R1(2) + R2(1) + R3(2)

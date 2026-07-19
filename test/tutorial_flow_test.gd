extends GdUnitTestSuite
## Unit tests for the pure tutorial lesson/step FSM (TutorialFlow): the T1 tool-track
## definition, event-gated step advancement, lesson boundaries, chapter jumps and skips.
## No scene, no signals — pure state machine.

const Flow := preload("res://scripts/tutorial_flow.gd")


func _new_flow() -> TutorialFlow:
	return Flow.new(Flow.build_tool_track())


## ===== Track definition =====

func test_tool_track_order_wave1() -> void:
	# Wave 1 (toolstrack spec §13/§15): T-01..T-04 lead; the not-yet-superseded W chapters follow.
	var track := Flow.build_tool_track()
	assert_int(track.size()).is_equal(9)
	assert_array(Flow.ids(track)).is_equal(["T-01", "T-02", "T-03", "T-04", "T-05", "T-06", "T-07", "W2", "W7"])


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
	assert_str(Flow.title_of(track, "T-02")).is_equal("Selecting")
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
	assert_str(String(result.lesson_completed)).is_equal("T-01")
	assert_bool(result.finished).is_false()
	assert_str(String(flow.current_lesson().get("id", ""))).is_equal("T-02")
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
	assert_array(completed).is_equal(["T-01", "T-02", "T-03", "T-04", "T-05", "T-06", "T-07", "W2", "W7"])
	assert_int(guard).is_equal(54)  # 3+5+10+7+8+10+4+3+4 steps


func test_finished_flow_ignores_events() -> void:
	var flow := _new_flow()
	flow.finish_track()
	var result := flow.consume(Flow.Event.CAMERA_ORBIT)
	assert_bool(result.advanced).is_false()
	assert_bool(result.finished).is_true()


## ===== Chapter jump / skip =====

func test_start_at_jumps_to_lesson_start() -> void:
	var flow := _new_flow()
	assert_bool(flow.start_at("T-04")).is_true()
	assert_str(String(flow.current_lesson().get("id", ""))).is_equal("T-04")
	assert_int(flow.step_index).is_equal(0)
	assert_str(String(flow.current_step().get("id", ""))).is_equal("measure")


func test_start_at_unknown_lesson_is_rejected() -> void:
	var flow := _new_flow()
	assert_bool(flow.start_at("W9")).is_false()
	assert_str(String(flow.current_lesson().get("id", ""))).is_equal("T-01")


func test_skip_current_lesson_completes_and_advances() -> void:
	var flow := _new_flow()
	flow.consume(Flow.Event.CAMERA_ORBIT)  # mid-lesson
	var result := flow.skip_current_lesson()
	assert_bool(result.advanced).is_true()
	assert_str(String(result.lesson_completed)).is_equal("T-01")
	assert_str(String(flow.current_lesson().get("id", ""))).is_equal("T-02")


func test_skip_on_last_lesson_finishes() -> void:
	var flow := _new_flow()
	flow.start_at("W7")
	var result := flow.skip_current_lesson()
	assert_str(String(result.lesson_completed)).is_equal("W7")
	assert_bool(result.finished).is_true()
	assert_bool(flow.finished).is_true()


## ===== W7 movement wave (the #131 movement-bundle lesson) =====

func test_w7_movement_wave_steps_and_gating_events() -> void:
	var track := Flow.build_tool_track()
	assert_str(Flow.title_of(track, "W7")).is_equal("Movement & trails")
	var flow := _new_flow()
	assert_bool(flow.start_at("W7")).is_true()
	# Step 1 — the game-phase gate: only GAME_STARTED advances it.
	assert_str(String(flow.current_step().get("id", ""))).is_equal("start_game")
	assert_bool(flow.consume(Flow.Event.MOVE_CAPPED).advanced).is_false()
	assert_bool(flow.consume(Flow.Event.GAME_STARTED).advanced).is_true()
	# Step 2 — path painting: a real model drop (UNIT_MOVED).
	assert_str(String(flow.current_step().get("id", ""))).is_equal("trail")
	assert_bool(flow.consume(Flow.Event.UNIT_MOVED).advanced).is_true()
	# Step 3 — the dry-brush cap: MOVE_CAPPED.
	assert_str(String(flow.current_step().get("id", ""))).is_equal("cap")
	assert_bool(flow.consume(Flow.Event.UNIT_MOVED).advanced).is_false()
	assert_bool(flow.consume(Flow.Event.MOVE_CAPPED).advanced).is_true()
	# Step 4 — the 1" spacing wall: MODELS_SEPARATED, and it completes the track.
	assert_str(String(flow.current_step().get("id", ""))).is_equal("spacing")
	var last := flow.consume(Flow.Event.MODELS_SEPARATED)
	assert_bool(last.advanced).is_true()
	assert_str(String(last.lesson_completed)).is_equal("W7")
	assert_bool(flow.finished).is_true()

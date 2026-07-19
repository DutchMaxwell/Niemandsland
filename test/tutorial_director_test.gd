extends GdUnitTestSuite
## Tests for the TutorialDirector's scene-free logic: the static payload predicates and
## the signal-handler -> flow wiring, driven headless. The director is created but never
## added to the tree and begin() is never called, so no coach overlay, camera or dialog
## exists — every scene-touching path is null-guarded, which is exactly what these tests
## also protect. Persistence goes to an isolated test cfg, never the player's file.

const Director := preload("res://scripts/tutorial_director.gd")
const Flow := preload("res://scripts/tutorial_flow.gd")
const Progress := preload("res://scripts/tutorial_progress.gd")
const TEST_CFG := "user://test_tutorial_director.cfg"


func before_test() -> void:
	_delete_test_cfg()


func after_test() -> void:
	_delete_test_cfg()


func _delete_test_cfg() -> void:
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))


## A director with a live flow + isolated progress, positioned at `lesson`. Not in the
## tree; scene refs stay null (guarded), so only the pure wiring runs.
func _new_director(lesson: String) -> TutorialDirector:
	var director := auto_free(Director.new()) as TutorialDirector
	director.flow = Flow.new(Flow.build_tool_track())
	director.flow.start_at(lesson)
	director.progress = Progress.new(TEST_CFG)
	director.progress.load_from_disk()
	return director


## A minimal real GameUnit (player 1) whose models wrap auto-freed Node3Ds.
func _new_unit(model_count: int) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_properties = {"name": "Test Unit", "player_id": 1}
	for i in model_count:
		var model := ModelInstance.new()
		model.node = auto_free(Node3D.new())
		model.unit = unit
		model.model_index = i
		unit.models.append(model)
	return unit


func _nodes_of(unit: GameUnit) -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	for model in unit.models:
		nodes.append(model.node)
	return nodes


## ===== Static payload predicates =====

func test_selection_hits() -> void:
	var unit := _new_unit(2)
	var nodes := _nodes_of(unit)
	var other: Node3D = auto_free(Node3D.new())
	assert_bool(Director.selection_hits([nodes[0]], nodes)).is_true()
	assert_bool(Director.selection_hits([other, nodes[1]], nodes)).is_true()
	assert_bool(Director.selection_hits([other], nodes)).is_false()
	assert_bool(Director.selection_hits([], nodes)).is_false()


func test_moves_hit() -> void:
	var unit := _new_unit(1)
	var nodes := _nodes_of(unit)
	var other: Node3D = auto_free(Node3D.new())
	assert_bool(Director.moves_hit([{"node": nodes[0], "inches": 2.0}], nodes)).is_true()
	assert_bool(Director.moves_hit([{"node": nodes[0], "inches": 0.0}], nodes)).is_false()
	assert_bool(Director.moves_hit([{"node": other, "inches": 5.0}], nodes)).is_false()
	assert_bool(Director.moves_hit([], nodes)).is_false()


## ===== T-02: selection composition (wave 1) =====

## Models carry the game_unit meta the composition classifier reads.
func _new_meta_unit(model_count: int) -> GameUnit:
	var unit := _new_unit(model_count)
	for model in unit.models:
		model.node.set_meta("game_unit", unit)
	return unit


func test_t02_selection_composition_walk() -> void:
	var director := _new_director("T-02")
	var unit := _new_meta_unit(2)
	var second := _new_meta_unit(2)
	director._target_unit = unit
	director._target_nodes = _nodes_of(unit)
	var stranger: Node3D = auto_free(Node3D.new())

	# A stranger does nothing; clicking a target model advances single -> unit.
	director._on_selection_changed([stranger])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("single")
	director._on_selection_changed([director._target_nodes[0]])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("unit")

	# The whole unit selected (double-click result) advances unit -> multi.
	director._on_selection_changed([director._target_nodes[0], director._target_nodes[1]])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("multi")

	# Two distinct units in the selection (Alt+click result) advance multi -> box.
	director._on_selection_changed([director._target_nodes[0], _nodes_of(second)[0]])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("box")

	# A jump in selection size across units (rubber-band result) advances box -> cancel.
	director._on_selection_changed([director._target_nodes[0], director._target_nodes[1],
		_nodes_of(second)[0], _nodes_of(second)[1]])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("cancel")

	# Esc (empty selection) completes the lesson.
	var completions: Array = []
	director.lesson_completed.connect(func(id: String) -> void: completions.append(id))
	director._on_selection_changed([])
	assert_array(completions).is_equal(["T-02"])
	assert_bool(director.progress.is_lesson_completed("T-02")).is_true()
	assert_str(String(director.flow.current_lesson().get("id", ""))).is_equal("T-03")


func test_t03_walk_via_real_signal_handlers() -> void:
	var director := _new_director("T-03")
	var unit := _new_meta_unit(2)
	director._target_unit = unit
	director._target_nodes = _nodes_of(unit)
	director._on_selection_dropped([{"node": director._target_nodes[0], "inches": 3.0}])
	var rotated: Array[Node3D] = []
	director._on_rotation_committed(rotated)   # aim
	director._on_rotation_committed(rotated)   # group_rotate
	director._on_rotation_committed(rotated)   # snap
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("arrange")
	director._on_arrangement_applied("rows")
	director._on_arrangement_applied("arrow")
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("duplicate")
	director._on_objects_pasted([auto_free(Node3D.new())])
	director._on_lock_state_changed([], true)
	director._on_model_deleted(null)
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("undo")
	var completions: Array = []
	director.lesson_completed.connect(func(id: String) -> void: completions.append(id))
	director._on_action_undone("Move 2 objects")
	assert_array(completions).is_equal(["T-03"])
	assert_str(String(director.flow.current_lesson().get("id", ""))).is_equal("T-04")


func test_events_out_of_step_are_ignored() -> void:
	var director := _new_director("T-02")
	director._on_roll_finnished(6)
	director._on_action_undone("whatever")
	var rotated: Array[Node3D] = []
	director._on_rotation_committed(rotated)
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("single")


## ===== W6: kill / revive =====

func test_t07_casualty_loop_advances_to_w2() -> void:
	var director := _new_director("T-07")
	var unit := _new_meta_unit(2)
	director._target_unit = unit
	director._target_nodes = _nodes_of(unit)
	director._on_loose_model_dead_changed(director._target_nodes[0], true)    # kill
	director._on_loose_model_dead_changed(director._target_nodes[0], false)   # revive
	director._on_loose_model_dead_changed(director._target_nodes[0], false)   # multi_revive (same signal)
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("return_unit")
	var completions: Array = []
	director.lesson_completed.connect(func(id: String) -> void: completions.append(id))
	director._on_radial_action_selected("return_unit_3", {})
	assert_array(completions).is_equal(["T-07"])
	assert_str(String(director.flow.current_lesson().get("id", ""))).is_equal("W2")

## ===== W7: movement bundle (game-phase gate, trail, dry-brush cap, 1" spacing) =====

func test_w7_movement_wave_via_real_signal_handlers() -> void:
	var director := _new_director("W7")
	var unit := _new_unit(2)
	director._target_unit = unit
	director._target_nodes = _nodes_of(unit)
	var finished := [null]
	director.tutorial_finished.connect(func(completed: bool) -> void: finished[0] = completed)

	# Step 1 — game-phase gate: only the PLAYING transition advances it.
	director._on_game_phase_changed(0)  # still DEPLOYMENT (no army_manager -> _game_started false)
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("start_game")
	director._on_event(Flow.Event.GAME_STARTED)  # simulate the PLAYING edge
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("trail")

	# Step 2 — path painting: a real model drop advances trail -> cap.
	director._on_selection_dropped([{"node": director._target_nodes[0], "inches": 4.0}])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("cap")

	# Step 3 — dry-brush cap: a NON-dry cap report is ignored; the dry one advances cap -> spacing.
	director._on_movement_capped(3.0, 6.0, false)
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("cap")
	director._on_movement_capped(6.0, 6.0, true)
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("spacing")

	# Step 4 — the 1" spacing wall: drop_separated finishes the track.
	director._on_drop_separated(true)
	assert_bool(director.flow.finished).is_true()
	assert_bool(finished[0]).is_true()
	assert_bool(director.progress.is_lesson_completed("W7")).is_true()


## ===== Lesson jumping: resume skips completed, chapter replay does not =====

func test_completed_lessons_are_skipped_after_a_boundary() -> void:
	var director := _new_director("T-01")
	director.progress.mark_lesson_completed("T-02")
	for _i in 3:  # orbit, zoom, pan
		director._force_complete_current_step()
	# T-01 done; T-02 already completed -> the cursor lands on T-03.
	assert_str(String(director.flow.current_lesson().get("id", ""))).is_equal("T-03")


func test_replay_mode_plays_completed_lessons_too() -> void:
	var director := _new_director("T-01")
	director._replay_mode = true
	director.progress.mark_lesson_completed("T-02")
	for _i in 3:
		director._force_complete_current_step()
	assert_str(String(director.flow.current_lesson().get("id", ""))).is_equal("T-02")


## ===== Skip lesson (escape hatch) =====

func test_skip_lesson_marks_completed_and_moves_on() -> void:
	var director := _new_director("T-04")
	var completions: Array = []
	director.lesson_completed.connect(func(id: String) -> void: completions.append(id))
	director._on_skip_lesson()
	assert_array(completions).is_equal(["T-04"])
	assert_bool(director.progress.is_lesson_completed("T-04")).is_true()
	assert_str(String(director.flow.current_lesson().get("id", ""))).is_equal("T-05")

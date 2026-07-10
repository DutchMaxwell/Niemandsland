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


## As above but over the FULL track (tool + rule), so R1-R3 lessons are reachable.
func _new_full_director(lesson: String) -> TutorialDirector:
	var director := auto_free(Director.new()) as TutorialDirector
	director.flow = Flow.new(Flow.build_full_track())
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


## ===== W3: target-bound select/move, generic rotate/undo =====

func test_w3_walk_via_real_signal_handlers() -> void:
	var director := _new_director("W3")
	var unit := _new_unit(2)
	director._target_unit = unit
	director._target_nodes = _nodes_of(unit)
	var stranger: Node3D = auto_free(Node3D.new())

	# Selecting something else does nothing; selecting the unit advances select -> move.
	director._on_selection_changed([stranger])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("select")
	director._on_selection_changed([director._target_nodes[0]])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("move")

	# A drop that moved a unit model advances move -> rotate.
	director._on_selection_dropped([{"node": director._target_nodes[1], "inches": 3.0}])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("rotate")

	# Any committed rotation advances rotate -> undo.
	var rotated: Array[Node3D] = []
	director._on_rotation_committed(rotated)
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("undo")

	# Undo completes the lesson; completion is persisted and the flow moved to W4.
	var completions: Array = []
	director.lesson_completed.connect(func(id: String) -> void: completions.append(id))
	director._on_action_undone("Move 2 objects")
	assert_array(completions).is_equal(["W3"])
	assert_bool(director.progress.is_lesson_completed("W3")).is_true()
	assert_str(String(director.flow.current_lesson().get("id", ""))).is_equal("W4")


func test_events_out_of_step_are_ignored() -> void:
	var director := _new_director("W3")
	director._on_roll_finnished(6)
	director._on_action_undone("whatever")
	var rotated: Array[Node3D] = []
	director._on_rotation_committed(rotated)
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("select")


## ===== W6: kill / revive =====

func test_w6_kill_then_revive_finishes_the_track() -> void:
	var director := _new_director("W6")
	var casualty: Node3D = auto_free(Node3D.new())
	var finished := [null]
	director.tutorial_finished.connect(func(completed: bool) -> void: finished[0] = completed)

	director._on_loose_model_dead_changed(casualty, true)
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("revive")
	assert_object(director._parked_node).is_equal(casualty)

	director._on_loose_model_dead_changed(casualty, false)
	assert_bool(director.flow.finished).is_true()
	assert_bool(finished[0]).is_true()
	assert_bool(director.progress.is_lesson_completed("W6")).is_true()


## ===== Lesson jumping: resume skips completed, chapter replay does not =====

func test_completed_lessons_are_skipped_after_a_boundary() -> void:
	var director := _new_director("W1")
	director.progress.mark_lesson_completed("W2")
	for _i in 3:  # orbit, zoom, pan
		director._force_complete_current_step()
	# W1 done; W2 already completed -> the cursor lands on W3.
	assert_str(String(director.flow.current_lesson().get("id", ""))).is_equal("W3")


func test_replay_mode_plays_completed_lessons_too() -> void:
	var director := _new_director("W1")
	director._replay_mode = true
	director.progress.mark_lesson_completed("W2")
	for _i in 3:
		director._force_complete_current_step()
	assert_str(String(director.flow.current_lesson().get("id", ""))).is_equal("W2")


## ===== Skip lesson (escape hatch) =====

func test_skip_lesson_marks_completed_and_moves_on() -> void:
	var director := _new_director("W4")
	var completions: Array = []
	director.lesson_completed.connect(func(id: String) -> void: completions.append(id))
	director._on_skip_lesson()
	assert_array(completions).is_equal(["W4"])
	assert_bool(director.progress.is_lesson_completed("W4")).is_true()
	assert_str(String(director.flow.current_lesson().get("id", ""))).is_equal("W5")


## ===== T2 rule track: R1 activation rhythm =====

func test_r1_activate_then_round_advances() -> void:
	var director := _new_full_director("R1")
	var unit := _new_unit(1)
	# Activating a unit advances activate -> round.
	director._on_unit_activated(unit)
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("round")
	# Advancing the round completes R1 and moves to R2.
	var completions: Array = []
	director.lesson_completed.connect(func(id: String) -> void: completions.append(id))
	director._on_round_advanced(2)
	assert_array(completions).is_equal(["R1"])
	assert_bool(director.progress.is_lesson_completed("R1")).is_true()
	assert_str(String(director.flow.current_lesson().get("id", ""))).is_equal("R2")


## ===== T2 rule track: R2 regiments concept card (ACK) =====

func test_r2_concept_card_completes_on_continue() -> void:
	var director := _new_full_director("R2")
	var completions: Array = []
	director.lesson_completed.connect(func(id: String) -> void: completions.append(id))
	# A non-ack event must not advance the concept card.
	director._on_roll_finnished(4)
	assert_str(String(director.flow.current_lesson().get("id", ""))).is_equal("R2")
	# The coach "GOT IT" button (continue) completes it and moves to R3.
	director._on_continue()
	assert_array(completions).is_equal(["R2"])
	assert_bool(director.progress.is_lesson_completed("R2")).is_true()
	assert_str(String(director.flow.current_lesson().get("id", ""))).is_equal("R3")


## ===== T2 rule track: R3 coherency broken -> restored =====

func _coherency_result(valid: bool) -> CoherencyChecker.CoherencyResult:
	var result := CoherencyChecker.CoherencyResult.new()
	result.valid = valid
	return result


func test_r3_coherency_broken_then_restored_finishes_track() -> void:
	var director := _new_full_director("R3")
	var finished := [null]
	director.tutorial_finished.connect(func(completed: bool) -> void: finished[0] = completed)

	# A coherent-first report must NOT satisfy the restore step (nothing broke yet).
	director._on_coherency_visualized(_coherency_result(true))
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("spread")

	# Breaking coherency advances spread -> restore.
	director._on_coherency_visualized(_coherency_result(false))
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("restore")

	# Restoring coherency completes R3 and finishes the whole track.
	director._on_coherency_visualized(_coherency_result(true))
	assert_bool(director.flow.finished).is_true()
	assert_bool(finished[0]).is_true()
	assert_bool(director.progress.is_lesson_completed("R3")).is_true()

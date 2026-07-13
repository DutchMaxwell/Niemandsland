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


## ===== T2 rule track: R1 activation rhythm (activate -> shoot -> end round) =====

func test_r1_activate_shoot_then_round_advances() -> void:
	var director := _new_full_director("R1")
	var unit := _new_unit(1)
	# Activating a unit advances activate -> shoot.
	director._on_unit_activated(unit)
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("shoot")
	# Rolling the dice (the shot) advances shoot -> round.
	director._on_roll_finnished(5)
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("round")
	# Ending the round completes R1 and moves to R3 (R2 is no longer in the track).
	var completions: Array = []
	director.lesson_completed.connect(func(id: String) -> void: completions.append(id))
	director._on_round_advanced(2)
	assert_array(completions).is_equal(["R1"])
	assert_bool(director.progress.is_lesson_completed("R1")).is_true()
	assert_str(String(director.flow.current_lesson().get("id", ""))).is_equal("R3")


## ===== T2 rule track: R3 coherency (pick -> spread -> restore) =====

## A GameUnit (player 1) whose model nodes are real, in-tree Node3Ds at the given table
## positions, so CoherencyChecker computes true edge-to-edge distances against them.
func _r3_unit(positions: Array) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_properties = {"name": "R3 Unit", "player_id": 1, "base_size_round": 32}
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)  # in the tree so global_position is well-defined
	for i in positions.size():
		var node := Node3D.new()
		root.add_child(node)
		node.position = positions[i]
		var model := ModelInstance.new()
		model.node = node
		model.unit = unit
		model.model_index = i
		unit.models.append(model)
	return unit


func _coherency_result(valid: bool) -> CoherencyChecker.CoherencyResult:
	var result := CoherencyChecker.CoherencyResult.new()
	result.valid = valid
	return result


## The redesigned R3 opens by asking the player to click ONE designated model; only that
## model satisfies the pick step (so the world-marker guidance lines up with what moves).
func test_r3_pick_requires_the_designated_model() -> void:
	var director := _new_full_director("R3")
	var unit := _new_unit(3)
	director._target_unit = unit
	director._target_nodes = _nodes_of(unit)
	director._r3_mover_node = director._target_nodes[2]

	# Selecting a DIFFERENT model of the unit must not advance the pick step.
	director._on_selection_changed([director._target_nodes[0]])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("pick")
	# Selecting the designated mover advances pick -> spread.
	director._on_selection_changed([director._r3_mover_node])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("spread")


## _resolve_r3_mover designates the most peripheral model and captures both destinations
## (its origin for the restore marker, a far break spot for the spread marker) up front.
func test_r3_resolve_mover_picks_peripheral_and_captures_targets() -> void:
	var director := _new_full_director("R3")
	var unit := _r3_unit([Vector3(0, 0, 0), Vector3(0, 0, 0.04), Vector3(0, 0, 0.20)])
	director._target_unit = unit
	director._target_nodes = _nodes_of(unit)

	director._setup_r3_step(TutorialFlow.TARGET_R3_MODEL)  # pick-step setup: resolve the mover
	assert_object(director._r3_mover_node).is_equal(director._target_nodes[2])  # the outlier
	assert_bool(director._r3_origin_captured).is_true()
	assert_vector(director._r3_origin).is_equal(Vector3(0, 0, 0.20))
	# The break destination is pushed R3_BREAK_DISTANCE_M further out from the unit.
	assert_float(director._r3_break_dest.length()).is_greater(director._r3_origin.length())


## Regression net for the R3 completion bug: after moving the model back into coherency, the
## restore step must advance PURELY from the on-drop coherency re-check — no visualizer
## `visualization_completed` emission is delivered here at all, mirroring a quick drag that
## ends in a valid state without an intermediate throttled sample (the field-test failure).
func test_r3_restore_advances_from_drop_recheck_without_visualizer() -> void:
	var director := _new_full_director("R3")
	var unit := _r3_unit([Vector3(0, 0, 0), Vector3(0, 0, 0.04), Vector3(0, 0, 0.08)])
	director._target_unit = unit
	director._target_nodes = _nodes_of(unit)
	var mover: Node3D = director._target_nodes[2]
	director._r3_mover_node = mover
	var finished := [null]
	director.tutorial_finished.connect(func(completed: bool) -> void: finished[0] = completed)

	# Pick the designated model -> spread.
	director._on_selection_changed([mover])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("spread")

	# Drag the model far out and DROP: the drop re-check reports the break -> restore step.
	mover.position = Vector3(0, 0, 0.6)
	director._on_selection_dropped([{"node": mover, "inches": 22.0}])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("restore")

	# Drag it back into coherency and DROP. NO _on_coherency_visualized call — the restore
	# must fire from the drop re-check alone (this is exactly what regressed in the field).
	mover.position = Vector3(0, 0, 0.08)
	director._on_selection_dropped([{"node": mover, "inches": 22.0}])
	# Restore advances to the success card (not straight to finish); acknowledging it ends R3.
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("done")
	director._on_continue()
	assert_bool(director.flow.finished).is_true()
	assert_bool(finished[0]).is_true()
	assert_bool(director.progress.is_lesson_completed("R3")).is_true()


## A SLOW drag (many throttled visualizer samples arrive) must complete just as reliably as a
## quick one: the intermediate broken samples advance spread -> restore, and the final on-drop
## re-check clears it to the success card — no dependence on a perfectly-timed final sample.
func test_r3_slow_drag_completes_via_samples_and_drop_recheck() -> void:
	var director := _new_full_director("R3")
	var unit := _r3_unit([Vector3(0, 0, 0), Vector3(0, 0, 0.04), Vector3(0, 0, 0.08)])
	director._target_unit = unit
	director._target_nodes = _nodes_of(unit)
	var mover: Node3D = director._target_nodes[2]
	director._r3_mover_node = mover

	# Pick -> spread.
	director._on_selection_changed([mover])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("spread")

	# Slow drag OUT: several live samples fire while the model crosses the threshold.
	mover.position = Vector3(0, 0, 0.3)
	director._on_coherency_visualized(_coherency_result(false))
	mover.position = Vector3(0, 0, 0.6)
	director._on_coherency_visualized(_coherency_result(false))
	director._on_selection_dropped([{"node": mover, "inches": 22.0}])  # drop recheck (still broken)
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("restore")

	# Slow drag BACK: live samples report still-broken until the last, then the drop re-check
	# clears it — the step must reach the success card exactly once.
	mover.position = Vector3(0, 0, 0.3)
	director._on_coherency_visualized(_coherency_result(false))
	mover.position = Vector3(0, 0, 0.08)
	director._on_selection_dropped([{"node": mover, "inches": 22.0}])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("done")


## Soft-lock guard: moving a model that is NOT part of the taught unit during the spread step
## must be ignored (no crash, no false advance); the real mover still breaks coherency after.
func test_r3_moving_a_non_target_model_does_not_softlock() -> void:
	var director := _new_full_director("R3")
	var unit := _r3_unit([Vector3(0, 0, 0), Vector3(0, 0, 0.04), Vector3(0, 0, 0.08)])
	director._target_unit = unit
	director._target_nodes = _nodes_of(unit)
	var mover: Node3D = director._target_nodes[2]
	director._r3_mover_node = mover
	var stranger: Node3D = auto_free(Node3D.new())

	# Pick -> spread.
	director._on_selection_changed([mover])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("spread")

	# Dropping a stranger (not in the unit) must not advance or break anything.
	director._on_selection_dropped([{"node": stranger, "inches": 22.0}])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("spread")

	# The real mover breaking coherency still advances the step.
	mover.position = Vector3(0, 0, 0.6)
	director._on_selection_dropped([{"node": mover, "inches": 22.0}])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("restore")


## The instruction must switch from "drag it OUT" (spread) to "drag it BACK" (restore) as the
## unit goes broken, and land on the "restored ✓" confirmation once coherency is regained.
func test_r3_instruction_switches_broken_to_restored_to_confirmation() -> void:
	var director := _new_full_director("R3")
	var unit := _r3_unit([Vector3(0, 0, 0), Vector3(0, 0, 0.04), Vector3(0, 0, 0.08)])
	director._target_unit = unit
	director._target_nodes = _nodes_of(unit)
	var mover: Node3D = director._target_nodes[2]
	director._r3_mover_node = mover

	director._on_selection_changed([mover])
	var spread_text := String(director.flow.current_step().get("text", ""))
	assert_str(spread_text).contains("onto the glowing ring")  # drag it OUT

	mover.position = Vector3(0, 0, 0.6)
	director._on_selection_dropped([{"node": mover, "inches": 22.0}])
	var restore_text := String(director.flow.current_step().get("text", ""))
	assert_str(restore_text).contains("Drag it back")  # drag it BACK
	assert_str(restore_text).is_not_equal(spread_text)

	mover.position = Vector3(0, 0, 0.08)
	director._on_selection_dropped([{"node": mover, "inches": 22.0}])
	assert_str(String(director.flow.current_step().get("text", ""))).contains("✓")  # restored confirmation


## The director must drive the real coherency visualizer onto the taught unit while R3 runs, so
## the player SEES the 1"/9" chain and the broken-chain warning (not only when a unit happens to
## be selected mid-drag). A recording stub captures the calls the director makes.
func test_r3_visualizer_is_driven_on_the_taught_unit() -> void:
	var director := _new_full_director("R3")
	var unit := _r3_unit([Vector3(0, 0, 0), Vector3(0, 0, 0.04), Vector3(0, 0, 0.08)])
	director._target_unit = unit
	director._target_nodes = _nodes_of(unit)
	var visualizer: _RecordingVisualizer = auto_free(_RecordingVisualizer.new())
	director._coherency_visualizer = visualizer

	# Entering the pick step must point the visualizer at the taught unit.
	director._setup_r3_step(TutorialFlow.TARGET_R3_MODEL)
	assert_int(visualizer.calls).is_greater(0)
	assert_object(visualizer.last_unit).is_equal(unit)

	# And every on-drop re-check refreshes it too, so the broken chain is on screen the instant
	# the instruction switches.
	var before := visualizer.calls
	director._on_selection_changed([director._r3_mover_node])  # pick -> spread
	var mover: Node3D = director._r3_mover_node
	mover.position = Vector3(0, 0, 0.6)
	director._on_selection_dropped([{"node": mover, "inches": 22.0}])
	assert_int(visualizer.calls).is_greater(before)
	assert_object(visualizer.last_unit).is_equal(unit)


## The live visualizer path still works too: the throttled `visualization_completed` edge
## (broken -> restored) advances R3, and a coherent-first report never pre-satisfies restore.
func test_r3_visualizer_path_broken_then_restored_finishes_track() -> void:
	var director := _new_full_director("R3")
	var unit := _new_unit(3)
	director._target_unit = unit
	director._target_nodes = _nodes_of(unit)
	director._r3_mover_node = director._target_nodes[0]
	var finished := [null]
	director.tutorial_finished.connect(func(completed: bool) -> void: finished[0] = completed)

	# Pick -> spread.
	director._on_selection_changed([director._r3_mover_node])
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("spread")

	# A coherent-first report must NOT satisfy restore (nothing broke yet).
	director._on_coherency_visualized(_coherency_result(true))
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("spread")
	# Broken -> restore, then restored -> the success card; acknowledging it finishes the track.
	director._on_coherency_visualized(_coherency_result(false))
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("restore")
	director._on_coherency_visualized(_coherency_result(true))
	assert_str(String(director.flow.current_step().get("id", ""))).is_equal("done")
	director._on_continue()
	assert_bool(director.flow.finished).is_true()
	assert_bool(finished[0]).is_true()
	assert_bool(director.progress.is_lesson_completed("R3")).is_true()


## A minimal CoherencyVisualizer stand-in that records the director's show_coherency calls, so a
## headless test can assert the teaching visual is driven onto the right unit without any scene.
class _RecordingVisualizer extends Node:
	var calls: int = 0
	var last_unit: GameUnit = null

	func show_coherency(game_unit: GameUnit, _is_skirmish: bool = false, _animate: bool = true) -> void:
		calls += 1
		last_unit = game_unit

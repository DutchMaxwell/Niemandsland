extends GdUnitTestSuite
## Unit tests for the T0 tutorial step FSM (TutorialDirector). These exercise ONLY the pure
## step logic and the signal-handler -> advance wiring — no scene, no coach overlay, no camera.
## The director is created but never added to the tree (so `begin()`/`_ready` never build the
## overlay), and every scene-touching path in `_apply_step_visuals` is null-guarded, so driving
## the handlers here advances the FSM without any scene dependency.

const Director := preload("res://scripts/tutorial_director.gd")


func _new_director() -> TutorialDirector:
	return auto_free(Director.new()) as TutorialDirector


# ===== Pure transition table =====

func test_next_step_progression() -> void:
	assert_that(Director.next_step(Director.Step.SELECT)).is_equal(Director.Step.MOVE)
	assert_that(Director.next_step(Director.Step.MOVE)).is_equal(Director.Step.ROLL)
	assert_that(Director.next_step(Director.Step.ROLL)).is_equal(Director.Step.DONE)
	# Terminal / inactive are fixed points.
	assert_that(Director.next_step(Director.Step.DONE)).is_equal(Director.Step.DONE)
	assert_that(Director.next_step(Director.Step.INACTIVE)).is_equal(Director.Step.INACTIVE)


# ===== SELECT predicate =====

func test_selection_completes_only_in_select_with_target() -> void:
	var target: Node3D = auto_free(Node3D.new())
	var other: Node3D = auto_free(Node3D.new())
	assert_bool(Director.selection_completes(Director.Step.SELECT, [target], target)).is_true()
	assert_bool(Director.selection_completes(Director.Step.SELECT, [other, target], target)).is_true()
	# Wrong object selected, empty selection, wrong step, or no target -> no completion.
	assert_bool(Director.selection_completes(Director.Step.SELECT, [other], target)).is_false()
	assert_bool(Director.selection_completes(Director.Step.SELECT, [], target)).is_false()
	assert_bool(Director.selection_completes(Director.Step.MOVE, [target], target)).is_false()
	assert_bool(Director.selection_completes(Director.Step.SELECT, [target], null)).is_false()


# ===== MOVE predicate =====

func test_drop_completes_only_in_move_with_target_moved() -> void:
	var target: Node3D = auto_free(Node3D.new())
	var other: Node3D = auto_free(Node3D.new())
	assert_bool(Director.drop_completes(Director.Step.MOVE, [{"node": target, "inches": 2.0}], target)).is_true()
	# A zero-distance drop, a different node, the wrong step, or no moves -> no completion.
	assert_bool(Director.drop_completes(Director.Step.MOVE, [{"node": target, "inches": 0.0}], target)).is_false()
	assert_bool(Director.drop_completes(Director.Step.MOVE, [{"node": other, "inches": 5.0}], target)).is_false()
	assert_bool(Director.drop_completes(Director.Step.ROLL, [{"node": target, "inches": 2.0}], target)).is_false()
	assert_bool(Director.drop_completes(Director.Step.MOVE, [], target)).is_false()


# ===== ROLL predicate =====

func test_roll_completes_only_in_roll() -> void:
	assert_bool(Director.roll_completes(Director.Step.ROLL)).is_true()
	assert_bool(Director.roll_completes(Director.Step.SELECT)).is_false()
	assert_bool(Director.roll_completes(Director.Step.MOVE)).is_false()
	assert_bool(Director.roll_completes(Director.Step.DONE)).is_false()


# ===== Full event-gated drive =====

func test_real_signals_advance_select_move_roll_then_finish() -> void:
	var director := _new_director()
	var target: Node3D = auto_free(Node3D.new())
	director._target_unit = target
	director.current_step = Director.Step.SELECT

	var finished := [null]
	director.tutorial_finished.connect(func(completed: bool) -> void: finished[0] = completed)

	# Step 1: selecting the target advances SELECT -> MOVE.
	director._on_selection_changed([target])
	assert_that(director.current_step).is_equal(Director.Step.MOVE)

	# Step 2: dropping the moved target advances MOVE -> ROLL.
	director._on_selection_dropped([{"node": target, "inches": 3.5}])
	assert_that(director.current_step).is_equal(Director.Step.ROLL)

	# Step 3: any dice roll advances ROLL -> DONE and reports a completed tutorial.
	director._on_roll_finnished(4)
	assert_that(director.current_step).is_equal(Director.Step.DONE)
	assert_bool(finished[0]).is_true()


func test_wrong_signals_do_not_advance_the_step() -> void:
	var director := _new_director()
	var target: Node3D = auto_free(Node3D.new())
	director._target_unit = target
	director.current_step = Director.Step.SELECT

	# A roll or a drop while SELECT is active, and an empty selection, are all ignored.
	director._on_roll_finnished(6)
	director._on_selection_dropped([{"node": target, "inches": 4.0}])
	director._on_selection_changed([])
	assert_that(director.current_step).is_equal(Director.Step.SELECT)


func test_skip_finishes_incomplete() -> void:
	var director := _new_director()
	director.current_step = Director.Step.SELECT
	var finished := [null]
	director.tutorial_finished.connect(func(completed: bool) -> void: finished[0] = completed)

	director._on_skip_pressed()
	assert_bool(finished[0]).is_false()

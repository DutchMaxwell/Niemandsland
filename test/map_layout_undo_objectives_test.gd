extends GdUnitTestSuite
## R4 (Map editor plan): objectives are part of the undo snapshot - placing, removing and clearing them can
## be undone and redone with the same Undo / Redo as terrain.

const SCENE := preload("res://scenes/map_layout.tscn")

var _ed: Control


func before_test() -> void:
	_ed = auto_free(SCENE.instantiate())
	add_child(_ed)
	await get_tree().process_frame


func after_test() -> void:
	_ed = null


func test_r4_place_objective_then_undo_removes_it_and_redo_restores_it() -> void:
	_ed._toggle_objective_at_position(Vector2(36, 45))
	assert_int(_ed.mission_objectives.size()).is_equal(1)
	_ed.undo()
	assert_int(_ed.mission_objectives.size()).override_failure_message("R4 — Undo did not remove the objective").is_equal(0)
	_ed.redo()
	assert_int(_ed.mission_objectives.size()).is_equal(1)


func test_r4_removing_an_objective_is_undoable() -> void:
	_ed._toggle_objective_at_position(Vector2(36, 45))
	_ed._toggle_objective_at_position(Vector2(36, 45))  # click it again: removed
	assert_int(_ed.mission_objectives.size()).is_equal(0)
	_ed.undo()
	assert_int(_ed.mission_objectives.size()).is_equal(1)


func test_r4_clear_objectives_is_undoable_and_announces_the_change() -> void:
	_ed._toggle_objective_at_position(Vector2(30, 40))
	_ed._toggle_objective_at_position(Vector2(50, 50))
	var announced := [0]
	_ed.objectives_changed.connect(func(_o): announced[0] += 1)
	_ed._on_objectives_clear()
	assert_int(_ed.mission_objectives.size()).is_equal(0)
	_ed.undo()
	assert_int(_ed.mission_objectives.size()).is_equal(2)
	assert_int(announced[0]).override_failure_message("R4 — the 3D table was not told about the undo").is_greater(1)


func test_r4_clearing_an_empty_list_leaves_no_undo_step() -> void:
	_ed._on_objectives_clear()
	assert_int(_ed._undo_stack.size()).is_equal(0)

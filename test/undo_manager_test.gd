extends GdUnitTestSuite
## Tests the UndoManager history and its Move / Rotate / Delete actions.
## A null network manager is passed throughout; broadcasts are guarded and skipped.


func _make_node() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	return auto_free(n)


func _make_manager() -> UndoManager:
	var mgr := UndoManager.new()
	add_child(mgr)
	return auto_free(mgr)


func _move_action(node: Node3D, from_pos: Vector3, to_pos: Vector3) -> UndoManager.MoveAction:
	var objects: Array[Node3D] = [node]
	var froms: Array[Vector3] = [from_pos]
	var tos: Array[Vector3] = [to_pos]
	return UndoManager.MoveAction.new(objects, froms, tos, null)


func test_initial_state_has_no_history() -> void:
	var mgr := _make_manager()
	assert_bool(mgr.can_undo()).is_false()
	assert_bool(mgr.can_redo()).is_false()
	assert_str(mgr.undo()).is_equal("")
	assert_str(mgr.redo()).is_equal("")


func test_move_action_undo_redo() -> void:
	var mgr := _make_manager()
	var node := _make_node()
	# Simulate the move that already happened.
	node.global_position = Vector3(1.0, 0.0, 2.0)
	mgr.push(_move_action(node, Vector3.ZERO, Vector3(1.0, 0.0, 2.0)))

	assert_bool(mgr.can_undo()).is_true()
	assert_bool(mgr.can_redo()).is_false()

	mgr.undo()
	assert_float(node.global_position.x).is_equal_approx(0.0, 0.001)
	assert_float(node.global_position.z).is_equal_approx(0.0, 0.001)
	assert_bool(mgr.can_redo()).is_true()

	mgr.redo()
	assert_float(node.global_position.x).is_equal_approx(1.0, 0.001)
	assert_float(node.global_position.z).is_equal_approx(2.0, 0.001)


func test_rotate_action_undo_redo() -> void:
	var mgr := _make_manager()
	var node := _make_node()
	node.rotation.y = 1.0
	var objects: Array[Node3D] = [node]
	var froms: Array[float] = [0.0]
	var tos: Array[float] = [1.0]
	mgr.push(UndoManager.RotateAction.new(objects, froms, tos, null))

	mgr.undo()
	assert_float(node.rotation.y).is_equal_approx(0.0, 0.0001)
	mgr.redo()
	assert_float(node.rotation.y).is_equal_approx(1.0, 0.0001)


func test_delete_action_restores_model() -> void:
	var mgr := _make_manager()
	var node := _make_node()
	var model := ModelInstance.new()
	model.node = node
	model.wounds_max = 2
	model.wounds_current = 2
	model.is_alive = true

	var models: Array[ModelInstance] = [model]
	var prev_wounds: Array[int] = [2]
	var prev_alive: Array[bool] = [true]
	var no_nodes: Array[Node3D] = []
	var action := UndoManager.DeleteAction.new(models, prev_wounds, prev_alive, no_nodes, null)

	action.redo()  # perform the deletion (casualty semantics)
	assert_bool(model.is_alive).is_false()
	assert_int(model.wounds_current).is_equal(0)
	assert_bool(node.visible).is_false()
	assert_bool(node.get_meta("deleted", false)).is_true()

	mgr.push(action)
	mgr.undo()  # restore
	assert_bool(model.is_alive).is_true()
	assert_int(model.wounds_current).is_equal(2)
	assert_bool(node.visible).is_true()
	assert_bool(node.get_meta("deleted", true)).is_false()


func test_delete_action_hides_generic_node() -> void:
	var node := _make_node()
	node.visible = true
	var no_models: Array[ModelInstance] = []
	var no_wounds: Array[int] = []
	var no_alive: Array[bool] = []
	var nodes: Array[Node3D] = [node]
	var action := UndoManager.DeleteAction.new(no_models, no_wounds, no_alive, nodes, null)

	action.redo()
	assert_bool(node.visible).is_false()
	assert_bool(node.get_meta("deleted", false)).is_true()

	action.undo()
	assert_bool(node.visible).is_true()
	assert_bool(node.get_meta("deleted", true)).is_false()


func test_delete_action_undo_removes_stain_and_guard() -> void:
	# Undo of a deletion must REMOVE the model's blood/oil residue and clear its "stained" guard, so a
	# later delete (e.g. after the player moves the model) stains the model's CURRENT position instead
	# of re-showing the old stain at its previous spot (#72).
	var node := _make_node()
	var model := ModelInstance.new()
	model.node = node
	model.wounds_max = 1
	model.wounds_current = 1
	model.is_alive = true

	var models: Array[ModelInstance] = [model]
	var prev_wounds: Array[int] = [1]
	var prev_alive: Array[bool] = [true]
	var no_nodes: Array[Node3D] = []
	var action := UndoManager.DeleteAction.new(models, prev_wounds, prev_alive, no_nodes, null)
	action.redo()  # delete; in the real flow the stain is created just AFTER this

	# Simulate the residue battlefield_stains leaves on the removed model node.
	var stain := Node3D.new()
	node.add_child(stain)
	auto_free(stain)
	var stain_nodes: Array[Node3D] = [stain]
	node.set_meta("stain_nodes", stain_nodes)
	node.set_meta("stained", true)

	action.undo()  # restore the model -> remove its residue and clear the guard
	assert_bool(node.has_meta("stain_nodes")).is_false()
	assert_bool(node.has_meta("stained")).is_false()


func test_new_push_clears_redo_stack() -> void:
	var mgr := _make_manager()
	var node := _make_node()
	mgr.push(_move_action(node, Vector3.ZERO, Vector3.ONE))
	mgr.undo()
	assert_bool(mgr.can_redo()).is_true()
	# A fresh action starts a new branch and discards the redo stack.
	mgr.push(_move_action(node, Vector3.ZERO, Vector3.ONE))
	assert_bool(mgr.can_redo()).is_false()


func test_history_is_capped_at_max() -> void:
	var mgr := _make_manager()
	var node := _make_node()
	for i in UndoManager.MAX_HISTORY + 5:
		mgr.push(_move_action(node, Vector3.ZERO, Vector3.ONE))
	var undone := 0
	while mgr.undo() != "":
		undone += 1
	assert_int(undone).is_equal(UndoManager.MAX_HISTORY)


func test_clear_empties_history() -> void:
	var mgr := _make_manager()
	var node := _make_node()
	mgr.push(_move_action(node, Vector3.ZERO, Vector3.ONE))
	mgr.clear()
	assert_bool(mgr.can_undo()).is_false()
	assert_bool(mgr.can_redo()).is_false()

extends GdUnitTestSuite
## #162 — MoveTakebackAction: restores position AND facing, erases the drop's chalk +
## ledger proof, is NOT redoable (a redone take-back would re-place models without
## their proof), and expires when the window closes — while plain Move/Rotate actions
## (terrain bookkeeping) survive the expiry untouched.


func _node_at(pos: Vector3, rot: float) -> Node3D:
	var n: Node3D = auto_free(Node3D.new())
	add_child(n)
	n.global_position = pos
	n.rotation.y = rot
	return n


func test_takeback_restores_position_facing_and_erases_the_proof() -> void:
	var um: UndoManager = auto_free(UndoManager.new())
	add_child(um)
	var trails: MoveTrails = auto_free(MoveTrails.new())
	add_child(trails)
	trails.commit_trail(1, "u1", "Unit 1", 7,
		PackedVector2Array([Vector2(0, 0), Vector2(1, 1)]), 0.02, 1, 100)
	var n := _node_at(Vector3(1, 0, 1), 0.5)   # post-drop pose (auto-faced)
	var nodes: Array[Node3D] = [n]
	var from_pos: Array[Vector3] = [Vector3.ZERO]
	var from_rot: Array[float] = [0.0]
	um.push(UndoManager.MoveTakebackAction.new(nodes, from_pos, from_rot,
		1, "u1", "Unit 1", 100, trails, null, null, 0))
	assert_str(um.undo_for(0)).contains("Take back")
	# Model back at its pre-drop spot AND pre-drop facing (auto-face is reverted).
	assert_vector(n.global_position).is_equal(Vector3.ZERO)
	assert_float(n.rotation.y).is_equal_approx(0.0, 0.001)
	# The drop's chalk + ledger proof are gone — the move never happened.
	assert_int(trails._trails.size()).is_equal(0)
	assert_int(trails.ledger.entries.size()).is_equal(0)
	# NOT redoable: the redo stack stays empty.
	assert_bool(um.can_redo()).is_false()


func test_expire_clears_takebacks_but_keeps_plain_moves() -> void:
	var um: UndoManager = auto_free(UndoManager.new())
	add_child(um)
	var n := _node_at(Vector3(2, 0, 0), 0.0)
	var nodes: Array[Node3D] = [n]
	var from_pos: Array[Vector3] = [Vector3.ZERO]
	var from_rot: Array[float] = [0.0]
	um.push(UndoManager.MoveTakebackAction.new(nodes, from_pos, from_rot,
		1, "u1", "Unit 1", 1, null, null, null, 0))
	var to_pos: Array[Vector3] = [Vector3(2, 0, 0)]
	um.push(UndoManager.MoveAction.new(nodes, from_pos, to_pos, null, 0))
	um.expire_move_takebacks()
	# The plain MoveAction (terrain) survives the expiry; the take-back is gone.
	assert_bool(um.can_undo()).is_true()
	assert_str(um.undo_for(0)).contains("Move")
	assert_str(um.undo_for(0)).is_equal("")

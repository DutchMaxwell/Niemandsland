extends GdUnitTestSuite
## Tests that undo/redo only act on the local player's OWN actions (per-peer
## filtering), so in multiplayer one player never undoes another's action.

const UndoManagerScript := preload("res://scripts/undo_manager.gd")


func _action(desc: String, peer: int):
	var a = UndoManagerScript.UndoableAction.new()
	a.description = desc
	a.peer_id = peer
	return a


func _make() -> UndoManager:
	return auto_free(UndoManagerScript.new()) as UndoManager


func test_can_undo_for_only_true_for_own_actions() -> void:
	var um := _make()
	um.push(_action("a", 1))
	um.push(_action("b", 2))
	assert_that(um.can_undo_for(1)).is_true()
	assert_that(um.can_undo_for(2)).is_true()
	assert_that(um.can_undo_for(3)).is_false()


func test_undo_for_skips_other_players_actions() -> void:
	var um := _make()
	um.push(_action("p1-first", 1))
	um.push(_action("p2", 2))
	um.push(_action("p1-second", 1))
	# Player 1 undoes their most recent action (p1-second), NOT p2's newer-on-stack action.
	assert_that(um.undo_for(1)).is_equal("p1-second")
	# Player 2 undoes their own action even though a p1 action is below it.
	assert_that(um.undo_for(2)).is_equal("p2")
	# Player 1 undoes their remaining action.
	assert_that(um.undo_for(1)).is_equal("p1-first")
	# Nothing left for anyone.
	assert_that(um.undo_for(1)).is_equal("")
	assert_that(um.can_undo_for(1)).is_false()


func test_undo_for_returns_empty_when_only_remote_actions() -> void:
	var um := _make()
	um.push(_action("remote", 2))
	assert_that(um.undo_for(1)).is_equal("")  # peer 1 has nothing of their own
	assert_that(um.can_undo_for(1)).is_false()
	# The remote action is untouched and still undoable by its owner.
	assert_that(um.can_undo_for(2)).is_true()


func test_redo_for_reapplies_own_action() -> void:
	var um := _make()
	um.push(_action("mine", 1))
	um.undo_for(1)
	assert_that(um.can_redo_for(1)).is_true()
	assert_that(um.redo_for(1)).is_equal("mine")
	assert_that(um.can_redo_for(1)).is_false()
	# Back on the undo stack.
	assert_that(um.can_undo_for(1)).is_true()

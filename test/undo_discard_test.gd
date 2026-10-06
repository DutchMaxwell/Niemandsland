extends GdUnitTestSuite
## Lead D15 (b): an action dropped for good — from the redo branch when a new action starts a branch, or off the end
## of the 100-step history — gets discard(), and a table theme frees the pieces it was hiding then. 20 apply/undo/
## apply cycles keep the node count flat instead of growing by 14 hidden pieces per cycle.


class CountingAction extends UndoManager.UndoableAction:
	var discarded := 0

	func discard() -> void:
		discarded += 1


func _hooks() -> Dictionary:
	return {"started": func() -> bool: return false, "biome_get": func() -> String: return "",
		"biome_set": func(_b: String) -> void: pass, "mood_get": func() -> String: return "",
		"mood_set": func(_m: String) -> void: pass}


func test_theme_apply_undo_cycles_keep_the_node_count_flat() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	om.solid_models_library().apply_manifest_text("{}")   # no model downloads in tests
	var um: UndoManager = auto_free(UndoManager.new())
	add_child(um)
	var theme := TableTheme.load_theme("ruined_borderland")
	var counts: Array[int] = []
	for i in 20:
		um.push(theme.apply(om, _hooks()))   # a new branch: the undone theme before it is dropped for good
		um.undo()
		await get_tree().process_frame
		counts.append(om.get_child_count())
	assert_int(counts[19]).override_failure_message("children per cycle: %s" % [counts]).is_equal(counts[1])


func test_actions_dropped_from_the_redo_branch_or_the_history_are_discarded() -> void:
	var um: UndoManager = auto_free(UndoManager.new())
	add_child(um)
	var first := CountingAction.new()
	um.push(first)
	for i in UndoManager.MAX_HISTORY:
		um.push(CountingAction.new())
	assert_int(first.discarded).is_equal(1)   # pushed off the end of the history
	var undone := CountingAction.new()
	um.push(undone)
	um.undo()
	um.push(CountingAction.new())   # a new branch
	assert_int(undone.discarded).is_equal(1)

extends GdUnitTestSuite
## Step 17 (26.10.): after loading a save the left-panel "NACHTMAHR:" section and its "AI plays P<n>"
## rows must come back. A fresh process holds an empty opr_army_manager.armies, and the load path only
## rebuilds the trays — so the Solo panel stayed hidden and _solo_player_label degraded to "P1".

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _tmp_saves: Array[String] = []


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	for p in _tmp_saves:
		DirAccess.remove_absolute(p)
	_tmp_saves.clear()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _two_army_save() -> String:
	for pid in [1, 2]:
		var army := OPRApiClient.OPRArmy.new()
		army.name = "Synthetic Host %d" % pid
		_main.opr_army_manager.armies[pid] = army
		var u := E2EBoot.make_unit(_main, pid, "Squad %d" % pid, [Vector3(0.1 * pid, 0, 0)])
		_main.opr_army_manager.game_units[u.unit_id] = u
	var path := "user://e2e_solo_panel_%d.nml" % Time.get_ticks_usec()
	_tmp_saves.append(path)
	assert_int(_main.save_manager.save_game(path)).is_equal(OK)
	return path


func _row_texts() -> Array:
	var out: Array = []
	for c in _main.solo_panel_box.get_children():
		if c is CheckButton and (c as CheckButton).text.begins_with("AI plays "):
			out.append((c as CheckButton).text)
	return out


func test_a_loaded_two_army_save_restores_the_solo_panel(timeout := 120000) -> void:
	var path := _two_army_save()
	_main.opr_army_manager.armies.clear()   # a fresh process after CONTINUE: only the load rebuilds
	await _main.save_manager.load_game(path)
	_main._refresh_solo_panel()
	await _runner.simulate_frames(2)
	assert_bool(_main.solo_panel_box.visible) \
		.override_failure_message("after a load the Solo (NACHTMAHR:) section stays hidden") \
		.is_true()
	var rows := _row_texts()
	assert_int(rows.size()) \
		.override_failure_message("the loaded Solo panel has no per-army row (got %s)" % str(rows)) \
		.is_equal(2)
	assert_bool(rows.has("AI plays P1 — Synthetic Host 1")) \
		.override_failure_message("the loaded Solo panel does not name P1's army (got %s)" % str(rows)) \
		.is_true()
	assert_bool(rows.has("AI plays P2 — Synthetic Host 2")) \
		.override_failure_message("the loaded Solo panel does not name P2's army (got %s)" % str(rows)) \
		.is_true()
	assert_str(_main._solo_player_label(1)) \
		.override_failure_message("the player label of a loaded army degrades to 'P1'") \
		.is_equal("P1 (Synthetic Host 1)")
	await E2EBoot.settle(get_tree())

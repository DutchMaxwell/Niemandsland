extends GdUnitTestSuite
## E2E — audit S6-U1: a mission game's objective markers and their captured owners must survive the
## two things a player does mid-game — closing the Map Layout window and save/load. The mission wrote
## its markers straight into the 3D overlay and never into the Map Layout editor's list, while both
## the window close and the save read THAT list (and close rebuilt the overlay without owners) — so
## the markers vanished, `_solo_auto_seize` returned early and the mission stopped scoring. Even a
## hand-placed (Duel) marker lost its owner on close. Proven on the REAL scenes/main.tscn.

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
	SoloController.mission_reset("end", {})   # statics: never leak this game's mission into the next suite
	for p in _tmp_saves:
		DirAccess.remove_absolute(p)
	_tmp_saves.clear()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## A Sabotage game as the table starts it: the REAL mission-apply seam places two owned markers, then
## the two sides capture one each (owner ids 1 and 2 — the p1/p2 palette).
func _start_mission_with_owners() -> void:
	_main._solo_mission_id = "sabotage"
	_main._solo_apply_mission_if_chosen()
	assert_int(_main.terrain_overlay.get_objectives().size()) \
		.override_failure_message("fixture: the mission placed no markers on the overlay") \
		.is_equal(2)
	_main.terrain_overlay.set_objective_owner(0, 1)
	_main.terrain_overlay.set_objective_owner(1, 2)


func _assert_markers_kept(before: Array, owners: Array, what: String) -> void:
	var after: Array = _main.terrain_overlay.get_objectives()
	assert_int(after.size()) \
		.override_failure_message("%s wiped the mission markers: %d on the overlay before, %d after — _solo_auto_seize now finds no objectives and the mission stops scoring" % [what, before.size(), after.size()]) \
		.is_equal(before.size())
	if after.size() != before.size():
		return   # the size line above already reported it; indexing further would only crash the run
	for i in range(before.size()):
		assert_bool((after[i] as Vector3).is_equal_approx(before[i])) \
			.override_failure_message("%s moved marker %d: %s -> %s" % [what, i + 1, str(before[i]), str(after[i])]) \
			.is_true()
	assert_array(_main.terrain_overlay.get_objective_owners()) \
		.override_failure_message("%s reset the captured owners to neutral" % what) \
		.is_equal(owners)


# === S6-U1 trigger 1 — closing the Map Layout window =============================================

func test_closing_the_map_layout_window_keeps_the_mission_markers_and_owners() -> void:
	_start_mission_with_owners()
	var before: Array = _main.terrain_overlay.get_objectives()

	_main._on_map_layout_closed()

	_assert_markers_kept(before, [1, 2], "closing the Map Layout window")


## Duel: the hand-placed markers ARE in the editor list, yet closing the window still rebuilt the
## overlay without owners — every captured marker went back to neutral.
func test_closing_the_map_layout_window_keeps_the_owners_of_hand_placed_markers() -> void:
	_main.map_layout_editor.mission_objectives.assign([Vector2(30.0, 20.0), Vector2(50.0, 28.0)])
	_main.terrain_overlay.update_objectives(_main.map_layout_editor.get_objectives_for_overlay())
	_main.terrain_overlay.set_objective_owner(0, 1)
	var before: Array = _main.terrain_overlay.get_objectives()

	_main._on_map_layout_closed()

	_assert_markers_kept(before, [1, 0], "closing the Map Layout window")


## The new editor inverse must hold on a ROTATED grid too (the Map Tool lets the player rotate it): a
## table-centred inch has to come back out of get_objectives_for_overlay() as the same world metre.
func test_the_editor_inverse_round_trips_on_a_rotated_grid() -> void:
	var ed = _main.map_layout_editor
	ed.grid_rotation_degrees = 30.0
	ed.set_objectives_from_table_inches([Vector2(10.0, 5.0), Vector2(-14.0, 8.0)])

	var world: Array = ed.get_objectives_for_overlay()

	assert_int(world.size()).is_equal(2)
	if world.size() == 2:
		assert_bool((world[0] as Vector3).is_equal_approx(Vector3(10.0 * 0.0254, 0.0, 5.0 * 0.0254))) \
			.override_failure_message("marker 1 came back as %s on a 30-degree grid" % str(world[0])).is_true()
		assert_bool((world[1] as Vector3).is_equal_approx(Vector3(-14.0 * 0.0254, 0.0, 8.0 * 0.0254))) \
			.override_failure_message("marker 2 came back as %s on a 30-degree grid" % str(world[1])).is_true()


# === S6-U1 trigger 2 — save and load =============================================================

func test_a_saved_mission_game_loads_with_its_markers_and_owners() -> void:
	_start_mission_with_owners()
	var before: Array = _main.terrain_overlay.get_objectives()
	# COUPLING with the load-integrity fix (local/fix-load-integrity): a load that finds an EMPTY
	# objective list now CLEARS the overlay. A mission game used to save exactly that (the mission wrote
	# only to the overlay, the save reads only the editor list), so the save itself must carry the markers
	# and their owners — proven on the serialized table, independent of the load code below.
	var saved: Array = _main.save_manager.serialize_game_state()["table"]["mission_objectives"]
	assert_int(saved.size()) \
		.override_failure_message("the save carries no objective list for a mission game (%s)" % str(saved)) \
		.is_equal(2)
	if saved.size() == 2:
		assert_array([int(saved[0]["owner"]), int(saved[1]["owner"])]).is_equal([1, 2])
	var path := "user://e2e_mission_objectives_%d.nml" % Time.get_ticks_usec()
	_tmp_saves.append(path)
	assert_int(_main.save_manager.save_game(path)).is_equal(OK)
	# What a fresh process holds after CONTINUE: no markers anywhere yet.
	_main.terrain_overlay.update_objectives([])
	_main.map_layout_editor.mission_objectives.clear()

	await _main.save_manager.load_game(path)

	_assert_markers_kept(before, [1, 2], "the save/load round trip")
	await E2EBoot.settle(get_tree())

extends GdUnitTestSuite
## E2E — audit S1-16: a saved Solo game must remember WHICH army NACHTMAHR plays. The designation
## (main.solo_ai_slots) lived only in RAM, so CONTINUE / Load Game handed back a table with no AI slot:
## no grade on the controller, no round-start sequence, and the implicit "P2 = AI" default for a human
## who sat at P2. Proven on the REAL scenes/main.tscn through save_manager's own save_game / load_game.

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


func _save_to_tmp() -> String:
	var path := "user://e2e_solo_ai_slots_%d.nml" % Time.get_ticks_usec()
	_tmp_saves.append(path)
	assert_int(_main.save_manager.save_game(path)).is_equal(OK)
	return path


## The AI plays P1 (the human sits at P2 — the case the implicit "P2 = AI" default gets wrong). The
## save goes to disk, the designation is wiped to what a fresh process holds, then the real load runs.
func test_a_loaded_solo_game_keeps_the_ai_slot() -> void:
	_main.solo_ai_slots = {1: true}
	var path := _save_to_tmp()
	_main.solo_ai_slots = {}   # a fresh process after CONTINUE: nothing designated yet

	await _main.save_manager.load_game(path)

	assert_array(_main.solo_ai_slots.keys()) \
		.override_failure_message("the save never stored solo_ai_slots: a loaded Solo game has no designated AI army (got %s)" % str(_main.solo_ai_slots)) \
		.is_equal([1])
	assert_int(_main._solo_ai_slot()) \
		.override_failure_message("the AI's side after the load must be P1 (the saved designation), not the implicit P2") \
		.is_equal(1)
	await E2EBoot.settle(get_tree())


## What the restored designation buys: the controller built after the load is graded for the AI's slot
## (no grade = the naive baseline the live playtest exposed), and the unit check follows the saved side.
func test_the_restored_slot_is_graded_and_drives_the_unit_check() -> void:
	_main.solo_ai_slots = {1: true}
	var path := _save_to_tmp()
	_main.solo_ai_slots = {}

	await _main.save_manager.load_game(path)
	_main._ensure_solo_controller()

	assert_bool(_main.solo_controller != null and _main.solo_controller.difficulty_by_slot.has(1)) \
		.override_failure_message("the controller of a loaded Solo game carries no difficulty grade for the AI slot") \
		.is_true()
	var ai_unit := E2EBoot.make_unit(_main, 1, "AiSide", [Vector3(-0.2, 0, 0.2)])
	var human_unit := E2EBoot.make_unit(_main, 2, "HumanSide", [Vector3(0.2, 0, 0.2)])
	assert_bool(_main._solo_is_ai_unit(ai_unit)).is_true()
	assert_bool(_main._solo_is_ai_unit(human_unit)) \
		.override_failure_message("the human's army (P2) is treated as the AI's after the load") \
		.is_false()
	await E2EBoot.settle(get_tree())


## CONTROL: a save from an older build carries no "solo_ai_slots" key. It must leave the live
## designation exactly as it was (an absent key is not an empty designation).
func test_a_save_without_the_key_leaves_the_designation_alone() -> void:
	var state: Dictionary = _main.save_manager.serialize_game_state()
	state.erase("solo_ai_slots")
	var path := "user://e2e_solo_ai_slots_old_%d.nml" % Time.get_ticks_usec()
	_tmp_saves.append(path)
	assert_int(_main.save_manager.save_state_to_file(state, path)).is_equal(OK)
	_main.solo_ai_slots = {2: true}

	await _main.save_manager.load_game(path)

	assert_array(_main.solo_ai_slots.keys()).is_equal([2])
	await E2EBoot.settle(get_tree())

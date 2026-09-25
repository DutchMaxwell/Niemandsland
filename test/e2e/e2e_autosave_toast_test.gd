extends GdUnitTestSuite

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _autosave_toasts() -> Array:
	var out: Array = []
	for child in _main.get_node("UI").get_children():
		if child is Label and (child as Label).text.begins_with("Autosaved — "):
			out.append(child)
	return out


func _log_has_autosave() -> bool:
	for entry in _main.battle_log.entries():
		if str((entry as Dictionary)["text"]).contains("Autosaved (autosave_1.nml)"):
			return true
	return false


func test_autosave_does_not_cover_ai_explanation_during_battle() -> void:
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_show_explain("NACHTMAHR explains this activation")
	_main._autosave_controller.autosaved.emit("user://autosave_1.nml")
	assert_array(_autosave_toasts()).is_empty()
	assert_str((_main._solo_toast as Label).text).is_equal("NACHTMAHR explains this activation")
	assert_bool(_log_has_autosave()).is_true()


func test_autosave_before_battle_still_shows_one_notice() -> void:
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.DEPLOYMENT
	_main._autosave_controller.autosaved.emit("user://autosave_1.nml")
	assert_int(_autosave_toasts().size()).is_equal(1)
	assert_bool(_log_has_autosave()).is_true()

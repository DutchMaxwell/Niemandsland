extends GdUnitTestSuite
## D14: a human picks once per joined unit whether its hero takes morale tests.

const Boot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _prompts_seen := 0


func before_test() -> void:
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = false
	_prompts_seen = 0


func after_test() -> void:
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


func _joined_human() -> GameUnit:
	var host := Boot.make_unit(_main, 1, "Squad", [Vector3.ZERO])
	host.unit_properties["quality"] = 5
	var hero := Boot.make_unit(_main, 1, "Captain", [Vector3(0.0254, 0, 0)])
	hero.unit_properties["quality"] = 3
	hero.unit_properties["special_rules"] = ["Hero"]
	hero.unit_properties["attached_to"] = host
	host.unit_properties["attached_heroes"] = [hero]
	host.is_shaken = true  # no die UI: the first morale test auto-fails
	return host


func _schedule_answer(accept: bool) -> void:
	var main := _main
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		if not is_instance_valid(main):
			return
		for child in main.get_children():
			if child is PromptCard and child.visible and child.title == "Hero morale":
				_prompts_seen += 1
				if accept:
					child.ok_button.pressed.emit()
				else:
					child.cancel_button.pressed.emit())


func test_decline_is_remembered_and_uses_host_quality() -> void:
	var host := _joined_human()
	_schedule_answer(false)
	await _main._solo_morale_test(host, "You")
	assert_int(_prompts_seen).is_equal(1)
	assert_bool(bool(host.unit_properties.get("hero_tests_morale", true))).is_false()
	assert_int(_main._solo_morale_quality(host)).is_equal(5)
	_schedule_answer(true)  # a reopened prompt would be counted
	await _main._solo_morale_test(host, "You")
	await get_tree().create_timer(0.3).timeout
	assert_int(_prompts_seen).is_equal(1)
	await Boot.settle(get_tree())


func test_accept_is_remembered_and_uses_hero_quality() -> void:
	var host := _joined_human()
	_schedule_answer(true)
	await _main._solo_morale_test(host, "You")
	assert_int(_prompts_seen).is_equal(1)
	assert_bool(bool(host.unit_properties.get("hero_tests_morale", false))).is_true()
	assert_int(_main._solo_morale_quality(host)).is_equal(3)
	await Boot.settle(get_tree())

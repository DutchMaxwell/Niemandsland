extends GdUnitTestSuite
## Optional native integration: real scene/controller, independent loopback fake.
const Boot := preload("res://test/e2e/e2e_boot.gd")
var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _server_pid := -1
var _env := {}
var _core_env := -1


func before_test() -> void:
	for key in ["NML_CORE", "NML_BRAIN_URL", "NML_BRAIN_W", "NML_BRAIN_TIMEOUT_MS"]:
		_env[key] = OS.get_environment(key)
	_core_env = BattleSim._core_env
	OS.set_environment("NML_CORE", "1")
	OS.set_environment("NML_BRAIN_URL", "")
	OS.set_environment("NML_BRAIN_W", "1")
	OS.set_environment("NML_BRAIN_TIMEOUT_MS", "200")
	BattleSim._core_env = -1
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	if _server_pid > 0 and OS.is_process_running(_server_pid):
		OS.kill(_server_pid)
	_server_pid = -1
	for key in _env:
		OS.set_environment(key, _env[key])
	BattleSim._core_env = _core_env
	Boot.free_stray_root_nodes(get_tree(), _roots)


func _controller() -> SoloController:
	var army: OPRArmyManager = _main.opr_army_manager
	army.game_units = {}
	army.current_round = 1
	for side in [1, 2]:
		var u := Boot.make_unit(_main, side, "brain_unit_%d" % side,
			[Vector3(float(side - 1) * 0.75, 0, 0)])
		var data := OPRApiClient.OPRUnit.new()
		var weapon := OPRApiClient.OPRWeapon.new()
		weapon.name = "CCW"
		weapon.attacks = 1
		weapon.count = 1
		data.weapons.append(weapon)
		u.source_type = "opr"
		u.source_data = data
		u.models[0].wounds_current = 1
		army.game_units[u.unit_id] = u
	var sc: SoloController = auto_free(SoloController.new())
	_main.add_child(sc)
	sc.setup(army, null, null, 1, 2)
	sc.game_rounds = 4
	sc.objectives_provider = func() -> Array: return [Vector3(0.1, 0, 0.3)]
	sc.objective_owner_of = func(_i: int) -> int: return 0
	sc.set_difficulty(2, SoloDifficulty.for_grade("planner_v0"))
	return sc


func _pick(sc: SoloController) -> GameUnit:
	var pool: Array = []
	for u in sc.army_manager.game_units.values():
		if int(u.unit_properties.player_id) == 2:
			pool.append(u)
	return sc._planner_pick_unit(pool)


func test_fake_brain_is_in_decisions_and_killed_server_declines(
		do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "Build/install NmlCore to exercise the developer brain bridge") -> void:
	var port_file := "user://brain_port_%d.txt" % Time.get_ticks_usec()
	_server_pid = OS.create_process("python3", [ProjectSettings.globalize_path(
		"res://test/e2e/brain_fixture.py"), ProjectSettings.globalize_path(port_file)])
	assert_int(_server_pid).is_greater(0)
	for _i in range(300):
		if FileAccess.file_exists(port_file):
			break
		await get_tree().process_frame
	assert_bool(FileAccess.file_exists(port_file)).is_true()
	var port := FileAccess.get_file_as_string(port_file).strip_edges()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(port_file))
	OS.set_environment("NML_BRAIN_URL", "http://127.0.0.1:" + port)
	var sc := _controller()
	_main.solo_controller = sc
	_main.solo_ai_slots = {2: true}
	_main._solo_difficulty_grades = {}
	_main._solo_apply_difficulty()
	assert_bool(sc.difficulty_by_slot[2].planner).is_true()
	assert_bool(sc.difficulty_by_slot.has(1)).is_false()
	assert_bool(sc.auto_interference).is_false()
	assert_object(_pick(sc)).is_not_null()
	assert_int(sc._core_calls).is_greater(0)
	assert_str(JSON.stringify(sc.decision_log)).contains("constant-test")
	OS.kill(_server_pid)
	_server_pid = -1
	assert_object(_pick(sc)).is_not_null()
	assert_str(str(sc._core_declines)).contains("LeafValue")
	await Boot.settle(get_tree())


func test_unset_url_preserves_the_interactive_grade() -> void:
	var sc := _controller()
	_main.solo_controller = sc
	_main.solo_ai_slots = {2: true}
	_main._solo_difficulty_grades = {}
	_main._solo_apply_difficulty()
	assert_bool(sc.difficulty_by_slot[2].planner).is_false()
	assert_bool(sc.difficulty_by_slot.has(1)).is_false()
	assert_bool(sc.auto_interference).is_false()
	await Boot.settle(get_tree())


func test_unset_url_keeps_decisions_identical(
		do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "Build/install NmlCore to exercise the developer brain bridge") -> void:
	var sc := _controller()
	assert_object(_pick(sc)).is_not_null()
	var expected := JSON.stringify(sc.decision_log)
	sc.decision_log.clear()
	assert_object(_pick(sc)).is_not_null()
	assert_str(JSON.stringify(sc.decision_log)).is_equal(expected)
	assert_str(expected).not_contains('"kind":"brain"')
	await Boot.settle(get_tree())

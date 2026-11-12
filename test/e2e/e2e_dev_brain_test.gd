extends GdUnitTestSuite
## Optional native integration: real scene/controller, independent loopback fake.
const Boot := preload("res://test/e2e/e2e_boot.gd")
var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array
var _server_pid := -1
var _env := {}
var _core_env := -1
var _planner_statics: Array = []


func before_test() -> void:
	for key in ["NML_CORE", "NML_BRAIN_URL", "NML_BRAIN_W", "NML_BRAIN_TIMEOUT_MS"]:
		_env[key] = OS.get_environment(key)
	_core_env = BattleSim._core_env
	_planner_statics = _planner_statics_now()
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
	_restore_planner_statics(_planner_statics)
	Boot.free_stray_root_nodes(get_tree(), _roots)


## `_planner_pick_unit` stamps the planner's per-preset STATICS (SoloController._apply_aifix and friends, here the
## planner_v0 grade) and they outlive the test: a later suite in the same process (v36/ai_06 in a CI shard) then reads
## the aifix morale and reply laws. The values are saved before the test and put back after it.
func _planner_statics_now() -> Array:
	return [AiPlanner.opener_by_finish, AiPlanner.no_end_threat, AiPlanner.brain_knobs, AiPlanner.leaf_opener,
		AiPlanner.brain_breadth, AiPlanner.points_strength, AiPlanner.table_fidelity, AiPlanner.playout_search,
		BattleSim.morale_by_probability, BattleSim.reply_v2, BattleSim.reply_skip_activated, BattleSim.reply_hold_gate,
		BattleSim.hero_fold, AiMissionEval.fit_mode, AiMissionEval.eval_variant]


func _restore_planner_statics(v: Array) -> void:
	AiPlanner.opener_by_finish = v[0]
	AiPlanner.no_end_threat = v[1]
	AiPlanner.brain_knobs = v[2]
	AiPlanner.leaf_opener = v[3]
	AiPlanner.brain_breadth = v[4]
	AiPlanner.points_strength = v[5]
	AiPlanner.table_fidelity = v[6]
	AiPlanner.playout_search = v[7]
	BattleSim.morale_by_probability = v[8]
	BattleSim.reply_v2 = v[9]
	BattleSim.reply_skip_activated = v[10]
	BattleSim.reply_hold_gate = v[11]
	BattleSim.hero_fold = v[12]
	AiMissionEval.fit_mode = v[13]
	AiMissionEval.eval_variant = v[14]


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


func test_fake_brain_is_in_decisions_and_killed_server_declines() -> void:
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


## Ship path (22.09.): without a developer URL the grade follows the SHIPPED brain —
## planner iff the core is up and the packed model was accepted, else the tree. Without
## the extension (CI's gdUnit job) that is the tree, byte-identical to before.
func test_unset_url_follows_the_shipped_brain_else_the_tree() -> void:
	var sc := _controller()
	_main.solo_controller = sc
	_main.solo_ai_slots = {2: true}
	_main._solo_difficulty_grades = {}
	_main._solo_apply_difficulty()
	var shipped := sc.shipped_brain_ready()
	assert_bool(sc.difficulty_by_slot[2].planner).is_equal(shipped)
	assert_bool(sc.difficulty_by_slot.has(1)).is_false()
	assert_bool(sc.auto_interference).is_false()
	await Boot.settle(get_tree())


func test_unset_url_keeps_decisions_identical() -> void:
	var sc := _controller()
	assert_object(_pick(sc)).is_not_null()
	var expected := _without_batch_us(sc.decision_log)
	var brain_names: Array = []
	for rec in sc.decision_log:
		if rec is Dictionary and rec.get("kind") == "brain":
			brain_names.append(str(rec["data"].get("name", "")))
	sc.decision_log.clear()
	assert_object(_pick(sc)).is_not_null()
	assert_str(_without_batch_us(sc.decision_log)).is_equal(expected)
	# Unset URL = no DEVELOPER brain; the shipped brain, when ready, still records its own line.
	assert_bool(brain_names.is_empty()).is_equal(not sc.shipped_brain_ready())
	for brain_name in brain_names:
		assert_str(brain_name).is_equal("onnx")
	await Boot.settle(get_tree())


## The decision log as JSON without the brain's wall-time field `batch_us` (differs per pick).
func _without_batch_us(entries: Array) -> String:
	var copy := entries.duplicate(true)
	for rec in copy:
		if rec is Dictionary and rec.get("kind") == "brain" and rec.get("data") is Dictionary:
			rec["data"].erase("batch_us")
	return JSON.stringify(copy)

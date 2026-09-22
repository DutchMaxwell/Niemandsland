extends GdUnitTestSuite
## E2E — a mid-game save/load keeps the shipped AI path on the NEW SoloController the load hands
## back: the chosen preset, a rebuilt core node + re-sent game header, the shipped brain sha.
## Modelled on e2e_rule_state_reload_test.gd (before/after, _reload) + e2e_dev_brain_test.gd.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _env_core := ""
var _core_env := -1


func before_test() -> void:
	_env_core = OS.get_environment("NML_CORE")
	_core_env = BattleSim._core_env
	OS.set_environment("NML_CORE", "1")   # the test binary is a debug build — core off by default
	BattleSim._core_env = -1
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	OS.set_environment("NML_CORE", _env_core)
	BattleSim._core_env = _core_env
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## Fresh-process wipe. The sibling's rule-bookkeeping resets are omitted (nothing here writes them);
## a fresh Main also has NO SoloController (main.gd:13722-13724), so the load must build a NEW one.
func _wipe_to_fresh_process() -> void:
	if _main.solo_controller != null:
		_main.solo_controller.queue_free()
		_main.solo_controller = null


## A real reload — copied verbatim from e2e_rule_state_reload_test.gd:56-73 (copy, don't import).
func _reload(units: Array) -> Array:
	var sm = _main.save_manager
	var wire_state: Dictionary = JSON.parse_string(JSON.stringify(sm._serialize_game_state()))
	var wire_units: Array = []
	for u in units:
		wire_units.append(JSON.parse_string(JSON.stringify((u as GameUnit).to_dict())))
	_wipe_to_fresh_process()
	var out: Array = []
	for w in wire_units:
		var nu := GameUnit.from_dict(w)
		_main.opr_army_manager.game_units[nu.unit_id] = nu
		out.append(nu)
	sm._deserialize_game_state(wire_state)
	sm._restore_hero_attachments_after_load()
	_main._on_load_completed(0)
	return out


func _arm() -> SoloController:
	_main.solo_ai_slots = {2: true}
	_main._solo_difficulty_grades = {}
	_main._ensure_solo_controller()
	_main._solo_apply_difficulty()
	return _main.solo_controller


## e2e_dev_brain_test.gd:65-71 — one real planner activation (drives _core_plan when the core is on).
func _pick(sc: SoloController) -> GameUnit:
	var pool: Array = []
	for u in sc.army_manager.game_units.values():
		if int(u.unit_properties.player_id) == 2:
			pool.append(u)
	return sc._planner_pick_unit(pool)


func test_reload_keeps_the_chosen_preset(timeout := 120000) -> void:
	var sc := _arm()
	var planner: bool = sc.difficulty_by_slot[2].planner
	var sha := sc.shipped_brain_sha
	var old_id := sc.get_instance_id()
	_reload([])
	var sc2 := _arm()   # the load's NEW controller, difficulty re-applied on it
	assert_int(sc2.get_instance_id()).is_not_equal(old_id)
	assert_bool(sc2.difficulty_by_slot[2].planner).is_equal(planner)
	assert_str(sc2.shipped_brain_sha).is_equal(sha)
	if FileAccess.file_exists("res://assets/solo/brains/erlkoenig.onnx"):
		assert_bool(ClassDB.class_exists("NmlCore")).is_equal(sc2.shipped_brain_sha != "")


func test_reload_rebuilds_the_core_node_and_header(timeout := 120000,
		do_skip := not ClassDB.class_exists("NmlCore"), skip_reason := "needs the NmlCore extension") -> void:
	var sc := _arm()   # a game in progress: controller A, its core already warm
	_reload([])
	# The explicit grade takes _solo_apply_difficulty's early return (main.gd:1847-1851): nothing asks
	# shipped_brain_ready(), so the fresh controller still has no node, no header, and must build both.
	_main._solo_difficulty_grades = {2: "nachtmahr"}
	_main._ensure_solo_controller()
	sc = _main.solo_controller
	assert_bool(sc._core_node == null).is_true()
	assert_bool(sc._core_header_done).is_false()
	for side in [1, 2]:
		var u := E2EBoot.make_unit(_main, side, "core_ai_%d" % side, [Vector3(float(side - 1) * 0.75, 0, 0)])
		var w := OPRApiClient.OPRWeapon.new(); w.name = "CCW"; w.attacks = 1; w.count = 1
		var d := OPRApiClient.OPRUnit.new(); d.weapons.append(w)
		u.source_type = "opr"; u.source_data = d; u.models[0].wounds_current = 1
		_main.opr_army_manager.game_units[u.unit_id] = u
	assert_object(_pick(sc)).is_not_null()
	assert_int(sc._core_calls).is_greater(0)
	assert_bool(sc._core_header_done).is_true()
	assert_str(str(sc._core_declines)).not_contains("rules registry").not_contains("unreadable")
	await E2EBoot.settle(get_tree())


func test_without_the_extension_the_tree_is_chosen_and_logged(timeout := 120000,
		do_skip := ClassDB.class_exists("NmlCore"), skip_reason := "runs only without the NmlCore extension") -> void:
	var sc := _arm()
	assert_bool(sc.difficulty_by_slot[2].planner).is_false()

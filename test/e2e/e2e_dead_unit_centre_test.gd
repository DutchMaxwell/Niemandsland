extends GdUnitTestSuite
## Dead units have no table centre. These tests drive the game callers that used the
## empty anchor as world origin after the last model was removed.

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
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	if _main != null and _main.rule_floats != null:
		_main.rule_floats.clear()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, name: String, pos: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, name, [pos])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _kill(u: GameUnit) -> void:
	for m in u.models:
		(m as ModelInstance).is_alive = false


func test_deadly_kill_does_not_float_at_world_origin(timeout := 120000) -> void:
	var target := _unit(2, "Last Ogre", Vector3(0.3, 0, 0.2))
	target.unit_properties["special_rules"] = ["Tough(3)"]
	(target.models[0] as ModelInstance).wounds_max = 3
	(target.models[0] as ModelInstance).wounds_current = 3
	_main.rule_floats.force_for_tests = true
	_main._solo_batch = false
	var dealt: int = await _main._solo_land_deadly_wounds(target, "Hammer", 3, 0, 1)
	assert_int(dealt).is_equal(3)
	assert_int(SoloController.combined_alive(target)).is_equal(0)
	var labels: Array = _main.rule_floats.get_children().filter(func(n: Node) -> bool: return n is Label3D)
	assert_int(labels.size()) \
		.override_failure_message("Deadly floated over Vector3.ZERO after killing the last model") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())


func test_dead_scout_has_no_table_anchor() -> void:
	var scout := _unit(2, "Dead Scout", Vector3(0.3, 0, 0.2))
	scout.unit_properties["special_rules"] = ["Scout"]
	_kill(scout)
	assert_bool(_main.opr_army_manager._anchor_off_table(scout)) \
		.override_failure_message("empty Scout anchor was treated as Vector3.ZERO inside the table") \
		.is_true()


func test_dead_scout_is_not_a_tray_group_resident() -> void:
	var scout := _unit(2, "Dead Scout", Vector3(0.3, 0, 0.2))
	scout.unit_properties["special_rules"] = ["Scout"]
	_kill(scout)
	var tray := Node3D.new()
	_main.add_child(tray)
	_main.opr_army_manager.army_trays[2] = tray
	_main.opr_army_manager.rebuild_tray_groups(2)
	var headers := tray.get_children().filter(func(n: Node) -> bool: return str(n.name).begins_with("TrayGroupHeader"))
	assert_int(headers.size()) \
		.override_failure_message("a destroyed Scout was classified as a live tray resident") \
		.is_equal(0)


func test_stale_target_is_refused_before_range_uses_origin() -> void:
	var attacker := _unit(1, "Shooter", Vector3(0.2, 0, 0.2))
	var target := _unit(2, "Dead Target", Vector3(0.3, 0, 0.2))
	_kill(target)
	assert_str(_main._solo_validate_target(attacker, target, false)) \
		.override_failure_message("stale target was measured against Vector3.ZERO") \
		.contains("destroyed")


func test_human_shooting_rejects_stale_target_before_any_volley(timeout := 120000) -> void:
	var attacker := _unit(1, "Shooter", Vector3(0.2, 0, 0.2))
	var target := _unit(2, "Dead Target", Vector3(0.3, 0, 0.2))
	_kill(target)
	var before: int = _main.battle_log.entries().size()
	await _main._run_human_shooting(attacker, target)
	assert_int(_main.battle_log.entries().size()) \
		.override_failure_message("stale target entered a shooting volley measured against Vector3.ZERO") \
		.is_equal(before)
	await E2EBoot.settle(get_tree())

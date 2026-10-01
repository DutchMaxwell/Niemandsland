extends GdUnitTestSuite
## NML-1010 wave D, D2a — Attack & Defend roles on the table. No shipped mission has `roles` yet
## (the six land in D14), so a synthetic catalog entry is the fixture. The roll-off dice are random,
## so the pieces the roll-off calls are driven directly: the gate, the human pick, the AI pick,
## the ledger, the log line, the capture stamp and the save round trip.

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
	var cat := MissionCatalog._catalog()
	cat["roles_fixture"] = {"name": "Roles Fixture", "family": "attack_defend", "rounds": 6, "scoring": "end",
		"deployment": "front_line", "roles": true, "attacker_points_factor": 1.25,
		"markers": {"count": 1, "placement": "table_centre"}}
	cat["no_bonus_fixture"] = (cat["roles_fixture"] as Dictionary).duplicate()
	cat["no_bonus_fixture"]["attacker_points_factor"] = 1.0
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()


func after_test() -> void:
	SoloController.mission_reset("end", {})
	MissionCatalog.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func _log_text() -> String:
	var lines: PackedStringArray = []
	for e in _main.battle_log.entries():
		lines.append(str((e as Dictionary).get("text", "")))
	return "\n".join(lines)


func test_only_a_roles_mission_asks_for_roles() -> void:
	_main._solo_mission_id = "roles_fixture"
	assert_bool(_main._solo_mission_has_roles()).is_true()
	_main._solo_mission_id = "domination"
	assert_bool(_main._solo_mission_has_roles()).is_false()
	_main._solo_mission_id = ""
	assert_bool(_main._solo_mission_has_roles()).is_false()


func test_the_human_pick_fills_the_ledger_logs_and_opens_the_zone_prompt() -> void:
	_main._solo_mission_id = "roles_fixture"
	_main._solo_apply_mission_if_chosen()
	assert_that(SoloController.mission_roles).is_equal({})
	_main._solo_roles_chosen("attacker", 5, 3)
	assert_that(SoloController.mission_roles).is_equal({"attacker": 1, "defender": 2})
	assert_str(_log_text()).contains("Roll-off: P1 attacks, P2 defends")
	assert_bool((_main._solo_deploy_ui as CanvasLayer).visible).is_true()


func test_the_ai_takes_the_bonus_side_else_defends() -> void:
	assert_str(SoloController.roles_ai_pick(MissionCatalog.get_mission("roles_fixture"))).is_equal("attacker")
	assert_str(SoloController.roles_ai_pick(MissionCatalog.get_mission("no_bonus_fixture"))).is_equal("defender")
	assert_that(SoloController.roles_assign(2, 1, "attacker")).is_equal({"attacker": 2, "defender": 1})


func test_roles_reach_the_capture_and_the_save_but_a_roles_less_mission_stays_clean() -> void:
	SoloController.mission_roles = {"attacker": 2, "defender": 1}
	assert_int(int(_main.solo_controller.capture_board().get("attacker", 0))).is_equal(2)
	var saved := SoloController.mission_state_to_dict("roles_fixture")
	SoloController.mission_reset("end", {})
	assert_that(SoloController.mission_roles).is_equal({})
	assert_that(_main.solo_controller.capture_board().has("attacker")).is_false()
	SoloController.mission_state_from_dict(JSON.parse_string(JSON.stringify(saved)))
	assert_that(SoloController.mission_roles).is_equal({"attacker": 2, "defender": 1})

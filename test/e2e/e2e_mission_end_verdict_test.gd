extends GdUnitTestSuite
## NML-1010 wave D, D14.0 — the end-of-game referee of the role missions. SoloController.end_verdict is
## the one call the summary and the arena result make: `escort` / `extract` are decided on the board
## (BattleSim.role_winner), every other scoring id still goes to BattleSim.mission_winner unchanged.

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
	_main.solo_ai_slots = {2: true}   # plan 2.2: no implicit NACHTMAHR — this table designates player 2 explicitly
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	var u := E2EBoot.make_unit(_main, 2, "Far", [Vector3(100.0, 0, 100.0)])
	_main.opr_army_manager.game_units[u.unit_id] = u
	SoloController.mission_roles = {"attacker": 1, "defender": 2}


func after_test() -> void:
	SoloController.mission_reset("end", {})
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _verdict(scoring: String, marker: Dictionary, x_in: float, z_in: float, owners := [0]) -> String:
	SoloController.mission_reset(scoring, {}, [marker])
	SoloController.mission_roles = {"attacker": 1, "defender": 2}
	_main.terrain_overlay.update_objectives([Vector3(x_in * 0.0254, 0, z_in * 0.0254)], owners)
	return _main.solo_controller.end_verdict(owners, 1, 1)


func test_extract_is_decided_by_the_relic_at_the_table_edge() -> void:
	assert_str(_verdict("extract", {"carry": true, "carried_by": ""}, 30.0, 0.0)).is_equal("p1")
	assert_str(_verdict("extract", {"carry": true, "carried_by": ""}, 0.0, 0.0)).is_equal("p2")


func test_escort_is_decided_by_the_vip_at_the_target_edge() -> void:
	var vip := {"mobile": true, "deploy_edge": 1}
	assert_str(_verdict("escort", vip, 0.0, -18.0)).is_equal("p2")   # defender: 6" from the far edge
	assert_str(_verdict("escort", vip, 0.0, 0.0)).is_equal("p1")


func test_every_other_scoring_id_keeps_the_marker_referee() -> void:
	assert_str(_verdict("end", {}, 30.0, 0.0, [1])).is_equal("p1")
	assert_str(_verdict("end", {}, 30.0, 0.0, [2])).is_equal("p2")

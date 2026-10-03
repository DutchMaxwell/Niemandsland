extends GdUnitTestSuite
## NML-1010 wave D, D14.4 (core + AI side): the VIP Escort marker is set up once the defender is known —
## the AI rule's start spot on the defender's own table edge, `deploy_edge` on the marker, the objective on
## the table owned by the defender, and the runtime zone style "marker_disc_12" the defender's deployment
## phase names. The catalog entry itself lands last, so a synthetic entry is the fixture here.

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
	cat["vip_fixture"] = {"name": "VIP Fixture", "family": "attack_defend", "rounds": 6, "scoring": "escort",
		"deployment": "front_line", "roles": true,
		"markers": {"count": 1, "placement": "vip_edge", "mobile": true}}
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main._solo_mission_id = "vip_fixture"


func after_test() -> void:
	SoloController.mission_reset("end", {})
	MissionCatalog.reset_cache()
	DeploymentCatalog.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func test_the_ai_rule_picks_the_defenders_own_edge() -> void:
	var p1 := MissionCatalog.vip_start(1)
	assert_float((p1["pos"] as Vector2).y).is_equal_approx(-21.0, 0.0001)
	assert_int(int(p1["deploy_edge"])).is_equal(-1)
	var p2 := MissionCatalog.vip_start(2, 48.0)
	assert_float((p2["pos"] as Vector2).y).is_equal_approx(21.0, 0.0001)
	assert_int(int(p2["deploy_edge"])).is_equal(1)
	assert_float((p2["pos"] as Vector2).x).is_equal(0.0)


func test_the_roles_step_sets_up_the_marker_and_the_disc_zone() -> void:
	_main._solo_apply_mission_if_chosen()
	_main._solo_roles_set(1, "attacker")   # P1 attacks, P2 defends
	assert_int(SoloController.mission_markers.size()).is_equal(1)
	assert_int(int(SoloController.mission_markers[0]["deploy_edge"])).is_equal(1)
	var spots: Array = _main.terrain_overlay.get_objectives()
	assert_int(spots.size()).is_equal(1)
	assert_float((spots[0] as Vector3).z / 0.0254).is_equal_approx(21.0, 0.001)
	assert_int(_main.terrain_overlay.get_objective_owner(0)).is_equal(2)
	var disc := DeploymentCatalog.get_style("marker_disc_12")
	assert_bool(DeploymentCatalog.in_zone(disc, 2, Vector2(0, 21 - 11))).is_true()
	assert_bool(DeploymentCatalog.in_zone(disc, 2, Vector2(0, 21 - 13))).is_false()
	assert_bool(DeploymentCatalog.in_zone(disc, 1, Vector2(11, 21))).is_true()


func test_a_mission_without_a_mobile_marker_is_left_alone() -> void:
	_main._solo_mission_id = "duel"
	_main._solo_vip_setup()
	assert_bool(DeploymentCatalog.style_ids().has("marker_disc_12")).is_false()

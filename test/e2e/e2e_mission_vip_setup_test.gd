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


func test_the_shipped_entry_drives_the_same_setup() -> void:
	_main._solo_mission_id = "vip_escort"
	_main._solo_apply_mission_if_chosen()
	assert_int(_main.solo_controller.game_rounds).is_equal(6)
	assert_str(SoloController.mission_scoring).is_equal("escort")
	_main._solo_batch = true   # no pick UI for the human defender: the AI rule starts the VIP
	_main._solo_roles_set(2, "attacker")   # P2 attacks, so P1 defends
	assert_int(int(SoloController.mission_markers[0]["deploy_edge"])).is_equal(-1)
	assert_float((_main.terrain_overlay.get_objectives()[0] as Vector3).z / 0.0254).is_equal_approx(-21.0, 0.001)
	assert_bool(DeploymentCatalog.style_ids().has("marker_disc_12")).is_true()


func test_a_mission_without_a_mobile_marker_is_left_alone() -> void:
	_main._solo_mission_id = "duel"
	_main._solo_vip_setup()
	assert_bool(DeploymentCatalog.style_ids().has("marker_disc_12")).is_false()


## Maintainer choice B: a HUMAN VIP defender gets the Map Tool with both 6" bands and ONE click places the
## marker AND sets deploy_edge. RED (the parent): the human defender silently got the AI's edge.
func _human_defender_opens_the_pick() -> Control:
	_main._solo_mission_id = "vip_escort"
	_main._solo_apply_mission_if_chosen()
	_main._solo_batch = false
	_main.solo_controller.human_slot = 1
	_main._solo_roles_set(2, "attacker")   # NACHTMAHR attacks, the human defends
	return _main.map_layout_editor


func _click_table_spot(editor: Control, x_in: float, z_in: float) -> void:
	var inch: Vector2 = editor._relic_world_to_inch(Vector3(x_in * 0.0254, 0.0, z_in * 0.0254))
	var canvas_pos: Vector2 = editor.grid_container.get_global_transform() * editor._inch_to_screen_pos(inch)
	E2EBoot.motion_canvas(get_viewport(), canvas_pos)
	E2EBoot.click_canvas(get_viewport(), canvas_pos, true)
	E2EBoot.click_canvas(get_viewport(), canvas_pos, false)


func test_a_human_defender_clicks_the_far_band_and_the_edge_follows_the_click() -> void:
	var editor := _human_defender_opens_the_pick()
	await _runner.simulate_frames(2)
	assert_bool(editor.vip_pick_active).is_true()
	assert_int(_main.terrain_overlay.get_objectives().size()).is_equal(0)   # no marker is on the table before the click
	_click_table_spot(editor, 12.0, 21.0)   # the +z band, NOT the human's own (-z) edge
	assert_bool(editor.visible).is_false()
	assert_int(int(SoloController.mission_markers[0]["deploy_edge"])).is_equal(1)
	var spot: Vector3 = _main.terrain_overlay.get_objectives()[0]
	assert_float(spot.x / 0.0254).is_equal_approx(12.0, 0.3)
	assert_float(spot.z / 0.0254).is_equal_approx(21.0, 0.3)
	assert_bool(DeploymentCatalog.in_zone(DeploymentCatalog.get_style("marker_disc_12"), 1, Vector2(12, 11))).is_true()


func test_a_click_outside_the_bands_keeps_the_pick_open_and_escape_takes_the_ai_rule() -> void:
	var editor := _human_defender_opens_the_pick()
	await _runner.simulate_frames(2)
	_click_table_spot(editor, 0.0, 0.0)
	assert_bool(editor.vip_pick_active).is_true()
	editor._on_close_pressed()   # Esc / close
	assert_int(int(SoloController.mission_markers[0]["deploy_edge"])).is_equal(-1)   # P1's own edge
	assert_float((_main.terrain_overlay.get_objectives()[0] as Vector3).z / 0.0254).is_equal_approx(-21.0, 0.001)

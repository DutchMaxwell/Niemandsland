extends GdUnitTestSuite
## NML-1010 wave D, D1 — the match length comes from the mission catalog, not from a constant.
## Every shipped mission is 4 rounds, so a synthetic 6-round catalog entry is the only way to prove
## the table reads the catalog: the controller's game_rounds, the live total and the game-over round.

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
	MissionCatalog._catalog()["six_round_fixture"] = {
		"name": "Six Round Fixture", "family": "face_off", "rounds": 6, "scoring": "end",
		"deployment": "front_line", "markers": {"count": 3, "placement": "table_centre"}}
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()


func after_test() -> void:
	SoloController.mission_reset("end", {})
	MissionCatalog.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func test_a_six_round_mission_sets_the_controller_match_length() -> void:
	assert_object(_main.solo_controller).is_not_null()
	_main._solo_mission_id = "six_round_fixture"
	_main._solo_apply_mission_if_chosen()
	assert_int(_main.solo_controller.game_rounds).is_equal(6)


## The match length IS the catalog's `rounds`: the face-off and progressive missions stay at four, the
## Attack & Defend ones (D14: so far Smash & Grab, GF/AoF v3.5.1 p.27/p.26) play six.
func test_every_shipped_mission_plays_its_catalog_rounds() -> void:
	for id in MissionCatalog.mission_ids():
		if id != "six_round_fixture":
			_main._solo_mission_id = id
			_main._solo_apply_mission_if_chosen()
			var want := 6 if str(MissionCatalog.get_mission(id).get("family", "")) == "attack_defend" else 4
			assert_int(_main.solo_controller.game_rounds).is_equal(want)
			assert_int(want).is_equal(int(MissionCatalog.get_mission(id)["rounds"]))


func test_round_four_does_not_end_a_six_round_game_but_round_six_does() -> void:
	_main._solo_mission_id = "six_round_fixture"
	_main._solo_apply_mission_if_chosen()
	_main.opr_army_manager.current_round = 4
	_main._solo_end_round()
	assert_bool(_main._solo_game_finished).is_false()
	_main.opr_army_manager.current_round = 6
	_main._solo_end_round()
	assert_bool(_main._solo_game_finished).is_true()

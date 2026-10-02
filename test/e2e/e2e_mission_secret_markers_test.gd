extends GdUnitTestSuite
## NML-1010 wave D, D12a — Smash & Grab secret markers on the live table: the AI defender hides trap
## and relic (relic = farthest from every edge, trap = nearest); the attacker's round-end seize turns
## a marker up: relic stays and is picked up, a trap hits the seizer (D6+1 hits) and goes away, an
## empty marker goes away; a marker the defender holds stays hidden. No shipped mission has `secret`
## yet (D14.6), so the markers are set directly.

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
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true
	_main.terrain_overlay.update_objectives([Vector3.ZERO])
	SoloController.mission_roles = {"attacker": 1, "defender": 2}


func after_test() -> void:
	SoloController.mission_reset("end", {})
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var lines: PackedStringArray = []
	for entry in _main.battle_log.entries():
		lines.append(str((entry as Dictionary).get("text", "")))
	return "\n".join(lines)


func _seize_with(secret: String, side: int) -> GameUnit:
	SoloController.mission_markers = [{"secret": secret, "revealed": false}]
	if secret == "relic":
		SoloController.mission_markers[0]["carry"] = true
		SoloController.mission_markers[0]["carried_by"] = ""
	var u := E2EBoot.make_unit(_main, side, "Seizer", [Vector3.ZERO])
	_main.opr_army_manager.game_units[u.unit_id] = u
	_main._solo_auto_seize()
	return u


func test_ai_assignment_relic_farthest_trap_nearest_from_the_edges() -> void:
	var kinds := SoloController.secret_assign([Vector2(0, 0), Vector2(30, 0), Vector2(-34, 0)], 72.0, 48.0)
	assert_that(kinds).is_equal(["relic", "", "trap"])
	assert_that(SoloController.secret_assign([Vector2(0, 0)], 72.0, 48.0)).is_equal(["relic"])


func test_assignment_runs_when_the_roles_are_set() -> void:
	_main.terrain_overlay.update_objectives([Vector3.ZERO, Vector3(30 * 0.0254, 0, 0), Vector3(-34 * 0.0254, 0, 0)])
	SoloController.mission_markers = [{"secret": "", "revealed": false}, {"secret": "", "revealed": false},
		{"secret": "", "revealed": false}]
	_main._solo_secret_markers_assign()
	assert_str(String(SoloController.mission_markers[0]["secret"])).is_equal("relic")
	assert_bool(bool(SoloController.mission_markers[0]["carry"])).is_true()
	assert_str(String(SoloController.mission_markers[2]["secret"])).is_equal("trap")
	assert_bool(SoloController.mission_markers[1].has("carry")).is_false()


func test_an_empty_marker_is_removed_when_the_attacker_seizes_it() -> void:
	_seize_with("", 1)
	assert_bool(bool(SoloController.mission_markers[0]["revealed"])).is_true()
	assert_bool(bool(SoloController.mission_markers[0]["destroyed"])).is_true()
	assert_bool(_main.terrain_overlay.objective_meshes[0].visible).is_false()
	assert_int(_main.terrain_overlay.get_objective_owner(0)).is_equal(0)
	assert_str(_log_text()).contains("revealed by Seizer")


func test_the_relic_stays_and_is_picked_up() -> void:
	var u := _seize_with("relic", 1)
	assert_bool(bool(SoloController.mission_markers[0]["revealed"])).is_true()
	assert_bool(bool(SoloController.mission_markers[0].get("destroyed", false))).is_false()
	assert_str(String(SoloController.mission_markers[0]["carried_by"])).is_equal(u.unit_id)


func test_a_trap_hits_the_seizer_and_goes_away() -> void:
	_seize_with("trap", 1)
	await _runner.simulate_frames(10)
	assert_bool(bool(SoloController.mission_markers[0]["destroyed"])).is_true()
	assert_str(_log_text()).contains("Trap: Seizer takes")


func test_a_marker_the_defender_holds_stays_hidden() -> void:
	_seize_with("trap", 2)
	assert_bool(bool(SoloController.mission_markers[0]["revealed"])).is_false()
	assert_bool(bool(SoloController.mission_markers[0].get("destroyed", false))).is_false()

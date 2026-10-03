extends GdUnitTestSuite
## Smash & Grab, the hand flow (GF v3.5.1 p.27 / AoF v3.5.1 p.26: "the defender must set up a total of
## D3+2 objective markers"): the human places markers BEFORE the deployment roll-off, so a human who turns
## out to be the attacker had placed the defender's markers. RED (the parent): after the roll-off the
## attacker's hand-placed markers stand. GREEN: an AI defender replaces them with its own D3+2 layout; a
## human defender keeps what he placed.

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
	_main.solo_controller.human_slot = 1
	_main._solo_batch = true   # no pick UI: the AI rule hides trap and relic
	_main._solo_mission_id = "smash_and_grab"
	_main._solo_apply_mission_if_chosen()
	_main.terrain_overlay.update_objectives([Vector3(5 * 0.0254, 0, 5 * 0.0254), Vector3(-5 * 0.0254, 0, 7 * 0.0254)])


func after_test() -> void:
	SoloController.mission_reset("end", {})
	MissionCatalog.reset_cache()
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func _log_text() -> String:
	var lines: PackedStringArray = []
	for e in _main.battle_log.entries():
		lines.append(str((e as Dictionary).get("text", "")))
	return "\n".join(lines)


func test_the_catalog_names_the_defender_as_the_placer() -> void:
	assert_str(str(MissionCatalog.get_mission("smash_and_grab")["markers"]["placer"])).is_equal("defender")


func test_an_ai_defender_replaces_the_attackers_hand_placed_markers() -> void:
	_main._solo_roles_set(1, "attacker")   # the human attacks, NACHTMAHR defends
	var spots: Array = _main.terrain_overlay.get_objectives()
	assert_int(spots.size()).is_between(3, 5)   # D3+2
	for s in spots:
		assert_bool(is_equal_approx((s as Vector3).x, 5 * 0.0254) and is_equal_approx((s as Vector3).z, 5 * 0.0254)).is_false()
	assert_int(SoloController.mission_markers.size()).is_equal(spots.size())   # trap + relic hidden among them
	assert_str(_log_text()).contains("places the")
	assert_str(_log_text()).contains("the 2 you placed were removed")


func test_a_human_defender_keeps_the_markers_he_placed() -> void:
	_main._solo_roles_set(2, "attacker")   # NACHTMAHR attacks, the human defends
	var spots: Array = _main.terrain_overlay.get_objectives()
	assert_int(spots.size()).is_equal(2)
	assert_float((spots[0] as Vector3).x).is_equal_approx(5 * 0.0254, 0.0001)
	assert_str(_log_text()).not_contains("you placed were removed")

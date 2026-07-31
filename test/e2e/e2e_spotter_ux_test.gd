extends GdUnitTestSuite
## E2E — Spotter UX (maintainer 31.07.): Precision Spotter is a radial action with the
## player's own target pick (DAO Union 3.5.2: "Once per activation, pick one enemy unit
## within 36" and in line of sight of this model and roll one die, on a 4+ place a marker
## on it. Friendly units may remove markers from their target before rolling to hit to get
## +X to hit rolls when attacking, where X is the number of removed [markers]"). Removal
## is the attacker's CHOICE (caster-points style dialog); headless keeps take-all.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

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


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _reg(u: GameUnit) -> GameUnit:
	# make_unit does not register with the army manager — solo_begin_spot scans it.
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _spotter(pos: Vector3) -> GameUnit:
	var u := _reg(E2EBoot.make_unit(_main, 1, "Eyes", [pos]))
	u.unit_properties["special_rules"] = ["Precision Spotter"]
	return u


func test_begin_spot_marks_candidates_within_36_and_click_stamps_the_round() -> void:
	var spotter := _spotter(Vector3.ZERO)
	var near := _reg(E2EBoot.make_unit(_main, 2, "Near", [Vector3(20.0 * INCH, 0, 0)]))
	var far := _reg(E2EBoot.make_unit(_main, 2, "Far", [Vector3(45.0 * INCH, 0, 0)]))
	_main.solo_begin_spot(spotter)
	var valid: Array = _main._solo_target_mode.get("spot_valid", [])
	assert_bool(valid.has(near)) \
		.override_failure_message("an enemy at 20\" in line of sight must be spottable") \
		.is_true()
	assert_bool(valid.has(far)) \
		.override_failure_message("36\" is the book's limit — 45\" may not be offered") \
		.is_false()
	assert_str(_log_text()).contains("pick a target to spot")
	_main._solo_spot_click(near)
	assert_int(int(spotter.unit_properties.get("spotted_round", -1))) \
		.override_failure_message("the pick must burn the once-per-activation spot") \
		.is_equal(_main.opr_army_manager.current_round)
	assert_bool(_main._solo_target_mode.is_empty()).is_true()
	# Re-open in the same round: refused with the named gate.
	_main.solo_begin_spot(spotter)
	assert_bool(_main._solo_target_mode.is_empty()).is_true()
	assert_str(_log_text()).contains("already spotted this round")


func test_marker_placement_is_visible_and_consumption_is_partial() -> void:
	var spotter := _spotter(Vector3.ZERO)
	var target := E2EBoot.make_unit(_main, 2, "Marked", [Vector3(10.0 * INCH, 0, 0)])
	_main._solo_place_spot_marker(spotter, target)
	_main._solo_place_spot_marker(spotter, target)
	assert_int(int(target.unit_properties.get("spot_markers", 0))).is_equal(2)
	assert_str(_log_text()).contains("Precision Spotter: Eyes marks Marked")
	var lib = _main.radial_menu_controller.token_library
	assert_bool(lib != null and lib.has("Spotted")) \
		.override_failure_message("the mark must exist as a VISIBLE token definition") \
		.is_true()
	# Partial removal (the attacker's choice): one of two — one stays lying.
	assert_int(_main._solo_consume_spot_markers(target, 1)).is_equal(1)
	assert_int(int(target.unit_properties.get("spot_markers", 0))).is_equal(1)
	assert_str(_log_text()).contains("1 marker removed — +1 to hit this volley (1 remains)")
	# Take-all clears the property.
	assert_int(_main._solo_consume_spot_markers(target)).is_equal(1)
	assert_int(int(target.unit_properties.get("spot_markers", 0))).is_equal(0)


func test_headless_offer_keeps_take_all_policy() -> void:
	var spotter := _spotter(Vector3.ZERO)
	var attacker := E2EBoot.make_unit(_main, 1, "Guns", [Vector3(0, 0, 5.0 * INCH)])
	var target := E2EBoot.make_unit(_main, 2, "Marked", [Vector3(10.0 * INCH, 0, 0)])
	_main._solo_place_spot_marker(spotter, target)
	_main._solo_place_spot_marker(spotter, target)
	var got: int = await _main._solo_offer_spot_markers(attacker, target)
	assert_int(got).is_equal(2)
	assert_int(int(target.unit_properties.get("spot_markers", 0))).is_equal(0)

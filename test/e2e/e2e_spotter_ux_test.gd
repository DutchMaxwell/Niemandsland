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


## A shooter whose OPR source carries one ranged weapon — the shape _solo_attack_groups reads
## (mirrors _armed in e2e_range_bonus_volley_test.gd).
func _armed(pid: int, unit_name: String, positions: Array, weapons: Array) -> GameUnit:
	var u := _reg(E2EBoot.make_unit(_main, pid, unit_name, positions))
	var i := 0
	for m in u.models:
		(m as ModelInstance).model_index = i
		i += 1
	var ws: Array[OPRApiClient.OPRWeapon] = []
	for wd in weapons:
		var d := wd as Dictionary
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(d.get("name", "Gun"))
		w.range_value = int(d.get("range", 24))
		w.attacks = int(d.get("attacks", 2))
		w.count = int(d.get("count", 1))
		ws.append(w)
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = ws
	u.source_type = "opr"
	u.source_data = src
	return u


## The AI volley makes the HUMAN roll their own saves (`_solo_prompt_saves` spins frames on a
## ConfirmationDialog) — press OK for the absent player, the morale suite's pump pattern.
func _arm_save_pump() -> void:
	var pump := Timer.new()
	pump.name = "NML970Pump"
	pump.wait_time = 0.02
	pump.one_shot = false
	get_tree().root.add_child(pump)   # freed by free_stray_root_nodes in after_test
	pump.timeout.connect(func() -> void:
		if _main == null or not is_instance_valid(_main):
			return
		for c in _main.get_children():
			var dlg := c as AcceptDialog
			if dlg != null and dlg.title == "Incoming fire!":
				dlg.confirmed.emit())
	pump.start()


## ONE AI shot in the shape `_run_ai_shooting` builds (mirrors _shots in e2e_volley_morale_test.gd).
func _shots(attacker: GameUnit, weapon_name: String, attacks: int, range_in: int) -> Array:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = weapon_name
	w.range_value = range_in
	w.attacks = attacks
	w.count = 1
	var profiles: Array = AiShooting.profiles_in_range([w], 0.0)
	return [{"member": attacker, "quality": attacker.get_quality(),
		"alive": attacker.get_alive_count(), "max": attacker.models.size(),
		"reach": range_in, "profile": profiles[0]}]


func test_human_to_hit_line_names_the_spent_spot_bonus(timeout := 120000) -> void:
	# NML-970: the marker spend is visible (the token vanishes) and the threshold proves it
	# counted — but the To-hit breakdown never NAMED it. Transparency doctrine: every applied
	# bonus writes its label.
	var spotter := _spotter(Vector3.ZERO)
	var attacker := _armed(1, "Guns", [Vector3(0, 0, 5.0 * INCH)],
		[{"name": "Rifle", "range": 24, "attacks": 2}])
	var target := _reg(E2EBoot.make_unit(_main, 2, "Marked", [Vector3(10.0 * INCH, 0, 0)]))
	_main._solo_place_spot_marker(spotter, target)
	_main._solo_place_spot_marker(spotter, target)
	_main._solo_batch = true
	await _main._run_human_shooting(attacker, target)
	assert_str(_log_text()) \
		.override_failure_message("NML-970 — the volley consumed 2 markers but the To-hit line never named the bonus:\n%s" % _log_text()) \
		.contains("Spotted +2")


func test_ai_to_hit_line_names_the_spot_bonus_too(timeout := 120000) -> void:
	# The AI's volley spends markers through the same arithmetic — its breakdown owes the
	# same label (rules-must-log holds for both sides).
	# The spotter stands OFF the firing lane — a third unit on the segment would block the
	# per-model sighting (unit-as-blocker LOS) and the volley would roll nothing.
	var eyes := _reg(E2EBoot.make_unit(_main, 2, "Eyes", [Vector3(0, 0, 8.0 * INCH)]))
	eyes.unit_properties["special_rules"] = ["Precision Spotter"]
	var ai := _armed(2, "Sturm", [Vector3.ZERO], [{"name": "Autogun", "range": 24, "attacks": 2}])
	# Four models so two attacks can never WIPE the unit — the volley must end on the dice,
	# not wander into the destruction bookkeeping this case is not about.
	var target := _reg(E2EBoot.make_unit(_main, 1, "Marked", [Vector3(10.0 * INCH, 0, -1.0 * INCH),
		Vector3(10.0 * INCH, 0, 0), Vector3(10.0 * INCH, 0, 1.0 * INCH), Vector3(10.0 * INCH, 0, 2.0 * INCH)]))
	_main._solo_place_spot_marker(eyes, target)
	_main._solo_batch = true
	_arm_save_pump()
	await _main._solo_resolve_ai_volley(ai, target, _shots(ai, "Autogun", 2, 24), false)
	assert_str(_log_text()) \
		.override_failure_message("NML-970 — the AI volley consumed a marker but its To-hit line never named the bonus:\n%s" % _log_text()) \
		.contains("Spotted +1")

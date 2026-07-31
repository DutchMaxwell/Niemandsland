extends GdUnitTestSuite
## E2E — pacing grill 2026-07-31: the SOLO volley seams feed the combat stage. A forced
## stage (hold 0) rides a real human volley on main.tscn and must come out with the
## Declaration → per-weapon → Result phase history. Plain e2e suites stay untouched
## because an unforced stage is inert headless.

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
	GraphicsSettings.combat_stage_hold_s = 2.5
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _armed(pid: int, unit_name: String, pos: Vector3, weapon_names: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	var opr := OPRApiClient.OPRUnit.new()
	var ws: Array[OPRApiClient.OPRWeapon] = []
	for wn in weapon_names:
		var w := OPRApiClient.OPRWeapon.new()
		w.name = str(wn)
		w.range_value = 24
		w.attacks = 2
		ws.append(w)
	opr.weapons = ws
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func test_human_volley_walks_the_stage_phases(timeout := 240000) -> void:
	var shooter := _armed(1, "Tank", Vector3.ZERO, ["Rifle"])
	var foe := _armed(2, "Foe", Vector3(8.0 * INCH, 0, 0), [])
	_main.combat_stage.force_for_tests = true
	GraphicsSettings.combat_stage_hold_s = 0.0
	await _main._run_human_shooting(shooter, foe)
	var titles: Array = []
	for ph in _main.combat_stage._phases:
		titles.append(str((ph as Dictionary)["title"]))
	assert_array(titles) \
		.override_failure_message("the volley must feed the stage (got: %s)" % str(titles)) \
		.contains(["Declaration", "Rifle"])
	# The declaration card carries the volley's rule lines from the COMBAT log stream.
	var decl := _main.combat_stage._phases[0] as Dictionary
	var decl_text := ""
	for l in (decl["lines"] as Array):
		decl_text += str(l) + "\n"
	assert_str(decl_text).contains("line of sight")


func test_unforced_stage_stays_inert_for_plain_e2e() -> void:
	var shooter := _armed(1, "Tank", Vector3.ZERO, ["Rifle"])
	var foe := _armed(2, "Foe", Vector3(8.0 * INCH, 0, 0), [])
	GraphicsSettings.combat_stage_hold_s = 2.5   # would stall for seconds per phase if active
	var t0 := Time.get_ticks_msec()
	await _main._run_human_shooting(shooter, foe)
	assert_array(_main.combat_stage._phases) \
		.override_failure_message("an unforced headless stage must not capture or hold") \
		.is_empty()
	assert_bool(Time.get_ticks_msec() - t0 < 60000).is_true()


func test_a_full_miss_weapon_still_closes_its_phase_card() -> void:
	# CI find: the 0-hit `continue` skipped the phase boundary — the miss line bled into
	# the Result card and the weapon phase vanished. A guaranteed all-miss cannot exist
	# (a natural 6 always hits), so: 1 attack at the worst quality exercises the 0-hit
	# path in 5/6 of runs, and the DETERMINISTIC claim is two-fold — the weapon card
	# always closes, and the fires-line never lands in the Result card.
	var shooter := _armed(1, "Tank", Vector3.ZERO, ["Rifle"])
	shooter.unit_properties["quality"] = 7   # clamps to 6+ — only a natural 6 hits
	(shooter.source_data.weapons[0] as OPRApiClient.OPRWeapon).attacks = 1
	var foe := _armed(2, "Foe", Vector3(8.0 * INCH, 0, 0), [])
	_main.combat_stage.force_for_tests = true
	GraphicsSettings.combat_stage_hold_s = 0.0
	await _main._run_human_shooting(shooter, foe)
	var titles: Array = []
	for ph in _main.combat_stage._phases:
		titles.append(str((ph as Dictionary)["title"]))
	assert_array(titles) \
		.override_failure_message("the weapon card must close on hit AND on full miss (got: %s)" % str(titles)) \
		.contains(["Rifle"])
	for ph in _main.combat_stage._phases:
		var phd := ph as Dictionary
		if str(phd["title"]) != "Rifle":
			var text := ""
			for l in (phd["lines"] as Array):
				text += str(l) + "\n"
			assert_str(text) \
				.override_failure_message("the fires-line bled out of its weapon card into '%s'" % str(phd["title"])) \
				.not_contains("fires Rifle")

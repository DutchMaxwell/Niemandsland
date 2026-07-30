extends GdUnitTestSuite
## E2E — #224 (transparency wave stage 1): rules-must-log covers NON-application. The
## Artillery +1 is range-conditional (GF v3.5.1 p.13: "over 9\" away") and CORRECT — but
## silent below 9", which two testers independently reported as a missing rule. The to-hit
## note now names the does-not-apply case.

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


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_artillery_names_the_bonus_and_its_absence(timeout := 120000) -> void:
	var gun := E2EBoot.make_unit(_main, 1, "Gun", [Vector3.ZERO])
	gun.unit_properties["special_rules"] = ["Artillery"]
	var foe := E2EBoot.make_unit(_main, 2, "Foe", [Vector3.ZERO])
	for u in [gun, foe]:
		_main.opr_army_manager.game_units[u.unit_id] = u
	# Beyond 9": the bonus applies and is named.
	var far: Dictionary = _main._solo_hit_mod_info(gun, foe, 14.0, false)
	assert_int(int(far["mod"])).is_equal(1)
	assert_str(str(far["note"])).contains("Artillery +1")
	# Within 9": no bonus — and the line SAYS so instead of staying silent (#224).
	var near: Dictionary = _main._solo_hit_mod_info(gun, foe, 6.0, false)
	assert_int(int(near["mod"])).is_equal(0)
	assert_str(str(near["note"])) \
		.override_failure_message("#224 — the within-9\" case stays silent: testers read the conditional bonus as a missing rule (note: '%s')" % str(near["note"])) \
		.contains("no +1")


func test_reserve_drag_logs_no_phantom_march(timeout := 120000) -> void:
	# #223 — "Dark Drop Pod moves 155\"": the tray→table drag of a RESERVE unit is placement,
	# not movement; a normal unit's drop keeps its line.
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	var pod := E2EBoot.make_unit(_main, 1, "Pod", [Vector3.ZERO])
	pod.unit_properties["ambush_reserve"] = true
	var walker := E2EBoot.make_unit(_main, 1, "Walker", [Vector3(0.1, 0, 0)])
	for u in [pod, walker]:
		_main.opr_army_manager.game_units[u.unit_id] = u
	_main._on_battle_log_dropped([{"node": (pod.models[0] as ModelInstance).node, "arc_in": 155.0}])
	_main._on_battle_log_dropped([{"node": (walker.models[0] as ModelInstance).node, "arc_in": 5.0}])
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	assert_str(text) \
		.override_failure_message("#223 — the reserve drag logged a phantom march (log: %s)" % text.strip_edges()) \
		.not_contains("Pod moves")
	assert_str(text).contains("Walker moves 5")


func test_stealth_and_artillery_target_name_their_absence(timeout := 120000) -> void:
	# #224 sweep: the DEFENDER-side range conditionals get their negative lines too.
	var shooter := E2EBoot.make_unit(_main, 1, "Shooter", [Vector3.ZERO])
	var sneak := E2EBoot.make_unit(_main, 2, "Sneak", [Vector3.ZERO])
	sneak.unit_properties["special_rules"] = ["Stealth"]
	var gun2 := E2EBoot.make_unit(_main, 2, "FoeGun", [Vector3.ZERO])
	gun2.unit_properties["special_rules"] = ["Artillery"]
	for u in [shooter, sneak, gun2]:
		_main.opr_army_manager.game_units[u.unit_id] = u
	# Stealth bites only over 9": far names -1, near names the absence.
	assert_str(str(_main._solo_hit_mod_info(shooter, sneak, 14.0, false)["note"])).contains("Stealth -1")
	assert_str(str(_main._solo_hit_mod_info(shooter, sneak, 6.0, false)["note"])).contains("Stealth: no -1")
	# Shooting AT an Artillery piece: -2 over 9", named absence below.
	assert_str(str(_main._solo_hit_mod_info(shooter, gun2, 14.0, false)["note"])).contains("Artillery target -2")
	assert_str(str(_main._solo_hit_mod_info(shooter, gun2, 6.0, false)["note"])).contains("Artillery target: no -2")


func test_hover_label_names_the_aircraft_reach_penalty(timeout := 120000) -> void:
	# #231 — the range ring is target-agnostic; the hover label's reach note must NAME the
	# Aircraft shrink so the -12" never looks missing (enforcement lives in validate).
	var shooter := E2EBoot.make_unit(_main, 1, "Gunner", [Vector3.ZERO])
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	opr.weapons = ws
	shooter.source_type = "opr"
	shooter.source_data = opr
	var flyer := E2EBoot.make_unit(_main, 2, "Flyer", [Vector3(0.3, 0, 0)])
	flyer.unit_properties["special_rules"] = ["Aircraft"]
	var note: String = _main._solo_reach_note(shooter, flyer)
	assert_str(note) \
		.override_failure_message("#231 — hovering an Aircraft yields no reach note (got: '%s')" % note) \
		.contains("Aircraft -12")
	assert_str(note).contains("reach 12")
	# A plain target shrinks nothing — the note stays empty.
	var infantry := E2EBoot.make_unit(_main, 2, "Grunts", [Vector3(0.4, 0, 0)])
	assert_str(_main._solo_reach_note(shooter, infantry)).is_equal("")

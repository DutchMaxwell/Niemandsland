extends GdUnitTestSuite
## E2E — wave 3 S1-02: GF/AoF v3.5.1 p.10 SHAKEN UNITS: "Shaken units must stay idle, but may strike
## back counting as fatigued". The strike groups carried only `member.is_fatigued`, so a Shaken defender
## struck back at its full Quality (4+) instead of unmodified 6s — and nothing said why.

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
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func _hit_roll_text() -> String:
	for e in _main.battle_log.entries():
		var line := str((e as Dictionary)["text"])
		if line.begins_with("You:") and line.contains("→"):
			return line
	return ""


## A Q4 striker whose OPR source carries one plain MELEE weapon (the e2e_thrust_strikeback shape).
func _melee_armed(pid: int, unit_name: String, pos: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	(u.models[0] as ModelInstance).model_index = 0
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Club"
	w.range_value = 0
	w.attacks = 2
	w.count = 1
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _plain_foe() -> GameUnit:
	var foe := E2EBoot.make_unit(_main, 2, "Grunts", [Vector3(0.5 * INCH, 0, -0.5 * INCH),
		Vector3(0.5 * INCH, 0, 0.5 * INCH)])
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	return foe


## The claim: a Shaken defender strikes back (charging = false) at unmodified 6s, and the log says why.
func test_shaken_unit_strikes_back_counting_as_fatigued() -> void:
	var striker := _melee_armed(1, "Guards", Vector3.ZERO)
	striker.is_shaken = true
	var foe := _plain_foe()
	await _main._solo_melee_strike_phase(striker, foe, false, 0)   # 0 = SoloStrike.ALL, charging = false
	var text := _log_text()
	assert_str(_hit_roll_text()) \
		.override_failure_message("S1-02 — the Shaken strike-back must roll as fatigued (6+) (log: %s)" % text.strip_edges()) \
		.ends_with("(6+)")
	assert_str(text) \
		.override_failure_message("rules-must-log — the Shaken strike-back must name the rule (log: %s)" % text.strip_edges()) \
		.contains("Shaken: Guards strikes back counting as fatigued (6+)")
	await E2EBoot.settle(get_tree())


## CONTROL: the same strike-back without Shaken rolls at the plain Quality (4+) and claims nothing.
func test_steady_unit_strikes_back_at_plain_quality() -> void:
	var striker := _melee_armed(1, "Guards", Vector3.ZERO)
	var foe := _plain_foe()
	await _main._solo_melee_strike_phase(striker, foe, false, 0)
	var text := _log_text()
	assert_str(_hit_roll_text()) \
		.override_failure_message("a steady Q4 strike-back rolls at 4+ (log: %s)" % text.strip_edges()) \
		.ends_with("(4+)")
	assert_str(text).not_contains("counting as fatigued")
	await E2EBoot.settle(get_tree())

extends GdUnitTestSuite
## E2E — S1-01 (wave-2 audit): Thrust ("When charging, gets +1 to hit rolls and AP(+1) in melee",
## GF/AoF v3.5.1 p.14) applied its +1 to hit on EVERY melee strike. The strike phase handed the weapon's
## Thrust flag to AiCombatMath.thrust_to_hit as `is_charging`, so the strike-back of a charged unit
## (charging = false) hit one better than the book says — and the rule was never logged.

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


## A striker whose OPR source carries one MELEE weapon (range 0) with the given weapon rules
## (mirrors _melee_armed in e2e_unstoppable_melee_test.gd).
func _melee_armed(pid: int, unit_name: String, pos: Vector3, weapon_rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	(u.models[0] as ModelInstance).model_index = 0
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Lance"
	w.range_value = 0
	w.attacks = 2
	w.count = 1
	var rules: Array[String] = []
	for r in weapon_rules:
		rules.append(str(r))
	w.special_rules = rules
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


## The claim: a Thrust weapon that is NOT charging (the strike-back) hits at the plain Quality (4+).
func test_thrust_weapon_strikes_back_at_plain_quality() -> void:
	var striker := _melee_armed(1, "Lancers", Vector3.ZERO, ["Thrust"])
	var foe := _plain_foe()
	await _main._solo_melee_strike_phase(striker, foe, false, 0)   # 0 = SoloStrike.ALL, charging = false
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("S1-01 — the strike-back rolled with Thrust's +1 to hit (3+) although nothing charged (log: %s)" % text.strip_edges()) \
		.not_contains("(3+)")
	assert_str(text) \
		.override_failure_message("fixture broken: a Q4 strike-back must roll at 4+ (log: %s)" % text.strip_edges()) \
		.contains("(4+)")
	assert_str(text) \
		.override_failure_message("Thrust does nothing off the charge — the log may not claim it (log: %s)" % text.strip_edges()) \
		.not_contains("Thrust")
	await E2EBoot.settle(get_tree())


## CONTROL + LOG: on the charge the +1 to hit stands (3+) and the rule says so in the battle log.
func test_thrust_weapon_charging_hits_one_better_and_logs() -> void:
	var striker := _melee_armed(1, "Lancers", Vector3.ZERO, ["Thrust"])
	var foe := _plain_foe()
	await _main._solo_melee_strike_phase(striker, foe, true, 0)   # charging = true
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the charging Thrust weapon must roll at 3+ (log: %s)" % text.strip_edges()) \
		.contains("(3+)")
	assert_str(text) \
		.override_failure_message("rules-must-log — the charge's Thrust bonus is applied and must be named (log: %s)" % text.strip_edges()) \
		.contains("Thrust")
	await E2EBoot.settle(get_tree())


## CONTROL: a plain weapon on the charge gets nothing — the fix must not hand out Thrust for free.
func test_plain_weapon_charging_rolls_plain_quality() -> void:
	var striker := _melee_armed(1, "Brawlers", Vector3.ZERO, [])
	var foe := _plain_foe()
	await _main._solo_melee_strike_phase(striker, foe, true, 0)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("a weapon without Thrust rolls at the plain Quality on the charge (log: %s)" % text.strip_edges()) \
		.contains("(4+)")
	assert_str(text).not_contains("Thrust")
	await E2EBoot.settle(get_tree())

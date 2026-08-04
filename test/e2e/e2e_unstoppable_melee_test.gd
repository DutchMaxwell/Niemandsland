extends GdUnitTestSuite
## E2E — NML-974: Unstoppable ("this weapon ignores negative modifiers to its rolls",
## GF v3.5.1 p.15) says WEAPON, not gun — but only the two volley paths clamped the
## negative modifiers. The melee strike phase composed Evasive's -1 into an Unstoppable
## weapon's to-hit silently: no clamp, no log line, the player's own dice one worse than
## the book says. Found by the NML-918 verification (residual R1).

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


## A striker whose OPR source carries one MELEE weapon (range 0) with the given weapon
## rules — the shape _solo_attack_groups reads (mirrors _armed in the volley e2e suites).
func _melee_armed(pid: int, unit_name: String, pos: Vector3, weapon_rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	(u.models[0] as ModelInstance).model_index = 0
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Runeblade"
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


func _evasive_foe() -> GameUnit:
	var foe := E2EBoot.make_unit(_main, 2, "Grunts", [Vector3(0.5 * INCH, 0, -0.5 * INCH),
		Vector3(0.5 * INCH, 0, 0.5 * INCH)])
	foe.unit_properties["special_rules"] = ["Evasive"]
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	return foe


func test_unstoppable_melee_weapon_ignores_evasive(timeout := 240000) -> void:
	var striker := _melee_armed(1, "Brawlers", Vector3.ZERO, ["Unstoppable"])
	var foe := _evasive_foe()
	await _main._solo_melee_strike_phase(striker, foe, false, 0)   # 0 = SoloStrike.ALL
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("NML-974 — the Unstoppable strike still rolled at Evasive's -1 and said nothing (log: %s)" % text.strip_edges()) \
		.contains("Unstoppable: negative to-hit modifiers ignored")
	assert_str(text) \
		.override_failure_message("the strike must roll at the unmodified Quality (4+), not at 5+ (log: %s)" % text.strip_edges()) \
		.not_contains("(5+)")
	await E2EBoot.settle(get_tree())


func test_a_plain_melee_weapon_still_pays_evasive(timeout := 240000) -> void:
	# The counter-probe that keeps the clamp a RULE: without the flag the -1 stands and
	# the log never claims a rule that did nothing.
	var striker := _melee_armed(1, "Brawlers", Vector3.ZERO, [])
	var foe := _evasive_foe()
	await _main._solo_melee_strike_phase(striker, foe, false, 0)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("fixture broken: a plain melee weapon must strike an Evasive foe at 5+ (log: %s)" % text.strip_edges()) \
		.contains("(5+)")
	assert_str(text) \
		.override_failure_message("no Unstoppable weapon in the fixture — the log may not claim the rule (log: %s)" % text.strip_edges()) \
		.not_contains("Unstoppable")
	await E2EBoot.settle(get_tree())

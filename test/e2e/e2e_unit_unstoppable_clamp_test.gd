extends GdUnitTestSuite
## E2E — NML-975: unit-level Unstoppable granted by a SPELL or an AURA family must reach the to-hit
## modifier strip ("ignores negative modifiers to its rolls", GF/AoF v3.5.1 p.15), not only the
## Regeneration bypass. Both paths were built after the ticket (EPOCH 34/35/37, sweep C) and the
## melee spell-grant leg had no test; this pins them in melee against an Evasive foe (-1 to hit ->
## a plain strike rolls at 5+, a stripped one at 4+).
##
## The log line "(5+)" / "(4+)" is written by the tray roll BEFORE any die, so nothing sits behind a die.

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
	_main.opr_army_manager.current_round = 1
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


## A striker whose only MELEE weapon is plain (no Unstoppable on the weapon) and whose UNIT carries
## `unit_rules` — so any strip must come from the unit-level rule.
func _striker(unit_rules: Array) -> GameUnit:
	var u := E2EBoot.make_unit(_main, 1, "Brawlers", [Vector3.ZERO])
	(u.models[0] as ModelInstance).model_index = 0
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Runeblade"
	w.range_value = 0
	w.attacks = 2
	w.count = 1
	w.special_rules = [] as Array[String]
	var src := OPRApiClient.OPRUnit.new()
	src.weapons = [w]
	u.source_type = "opr"
	u.source_data = src
	u.unit_properties["special_rules"] = unit_rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _evasive_foe() -> GameUnit:
	var foe := E2EBoot.make_unit(_main, 2, "Grunts", [Vector3(0.5 * INCH, 0, -0.5 * INCH),
		Vector3(0.5 * INCH, 0, 0.5 * INCH)])
	foe.unit_properties["special_rules"] = ["Evasive"]
	_main.opr_army_manager.game_units[foe.unit_id] = foe
	return foe


func _strike_log(striker: GameUnit) -> String:
	await _main._solo_melee_strike_phase(striker, _evasive_foe(), false, 0)   # 0 = SoloStrike.ALL
	return _log_text()


func test_control_a_plain_unit_still_pays_evasive(timeout := 240000) -> void:
	var text: String = await _strike_log(_striker([]))
	assert_str(text) \
		.override_failure_message("fixture broken: a plain strike must roll at 5+ (log: %s)" % text.strip_edges()) \
		.contains("(5+)")
	await E2EBoot.settle(get_tree())


func test_a_spell_granted_unstoppable_strips_the_melee_modifier(timeout := 240000) -> void:
	# A friendly Utility-Buff spell (Drain Spirit shape: grants_rule Unstoppable, scope melee, once)
	# lands its record on the striker — the same seam the real cast drives.
	var striker := _striker([])
	_main._solo_record_spell_mod(striker, "Drain Spirit",
		{"grants_rule": "Unstoppable", "scope": "melee", "duration": "once"})
	var text: String = await _strike_log(striker)
	assert_str(text) \
		.override_failure_message("a spell-granted Unstoppable must strip Evasive's -1 in melee (log: %s)" % text.strip_edges()) \
		.contains("Unstoppable: negative to-hit modifiers ignored")
	assert_str(text).not_contains("(5+)")
	await E2EBoot.settle(get_tree())


func test_an_aura_expanded_unstoppable_in_melee_strips_the_modifier(timeout := 240000) -> void:
	# "Unstoppable in Melee Aura" -> the expansion stamps the bare "Unstoppable in Melee" onto the unit.
	var text: String = await _strike_log(_striker(["Unstoppable in Melee"]))
	assert_str(text) \
		.override_failure_message("the aura-granted Unstoppable in Melee must strip Evasive's -1 (log: %s)" % text.strip_edges()) \
		.contains("Unstoppable in Melee: negative to-hit modifiers ignored")
	assert_str(text).not_contains("(5+)")
	await E2EBoot.settle(get_tree())


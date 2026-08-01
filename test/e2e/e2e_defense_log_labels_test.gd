extends GdUnitTestSuite
## E2E — NML-932: an attack's save step NAMES the rule behind every Defense contribution it folded in.
##
## What was broken: all three attack sites (the AI's volley, the human's volley, the melee strike
## phase) reported the WHOLE composite as one string — "<unit> is Shielded: +1 Defense". That was true
## while Shielded was the only thing that could raise the number; since #264 the parts seam
## (_solo_defense_parts) also carries growth markers and spell tokens, so the line credited a rule the
## unit does not even have, a second contribution vanished into the sum, and a hex that cancelled a
## bonus made the whole line disappear (#224: a silent rule reads exactly like a missing one).
##
## The suites ride the REAL main.tscn attack paths, so the names in the log come from the same single
## truth the arithmetic folds — the log can never claim what the dice do not see.

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
	# Batch mode is the harness lever for the physics dice tray: fair faces, drawn instantly.
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


func _count(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).contains(needle):
			n += 1
	return n


## A registered unit — the fixture has to live in opr_army_manager.game_units, or the AI-ownership,
## morale and wound plumbing the attack walks through never sees it.
func _unit(pid: int, unit_name: String, pos: Vector3, models: int = 3) -> GameUnit:
	var positions: Array = []
	for i in range(models):
		positions.append(pos + Vector3(0.0, 0.0, 0.02 * i))
	var u := E2EBoot.make_unit(_main, pid, unit_name, positions)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


## Your shooter: Quality 2+ with 8 attacks at 24", so the volley definitely reaches its save step.
func _shooter() -> GameUnit:
	var s := _unit(1, "Tank", Vector3.ZERO, 1)
	s.unit_properties["quality"] = 2
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = 24
	w.attacks = 8
	var ws: Array[OPRApiClient.OPRWeapon] = [w]
	opr.weapons = ws
	s.source_type = "opr"
	s.source_data = opr
	return s


func _foe(unit_name: String) -> GameUnit:
	return _unit(2, unit_name, Vector3(8.0 * INCH, 0, 0))


func _buff(unit_name: String, target: GameUnit, def_mod: int) -> void:
	_main._solo_place_spell_tokens(unit_name, [target],
		{"kind": ("buff" if def_mod > 0 else "debuff"), "modifier": {"def_mod": def_mod}})


# ===== (1) the ROT case: a token bonus announced under a rule the unit does not have =====

func test_a_defense_token_is_named_by_ITS_rule_when_shot(timeout := 240000) -> void:
	var shooter := _shooter()
	var foe := _foe("Grunts")   # Defense 4+ (E2EBoot fixture), no Shielded anywhere
	_buff("Warding Chant", foe, 1)
	await _main._run_human_shooting(shooter, foe)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the contribution must carry its OWN rule's name (log: %s)" % text.strip_edges()) \
		.contains("Grunts is Warding Chant: +1 Defense (saves on 3+)")
	assert_str(text) \
		.override_failure_message("the unit has no Shielded — the old collective label credited a rule it does not carry (log: %s)" % text.strip_edges()) \
		.not_contains("is Shielded")
	await E2EBoot.settle(get_tree())


# ===== (2) counter-check: Shielded still reads exactly as it always did =====

func test_shielded_still_logs_shielded(timeout := 240000) -> void:
	var shooter := _shooter()
	var foe := _foe("Guards")
	foe.unit_properties["special_rules"] = ["Shielded"]
	await _main._run_human_shooting(shooter, foe)
	assert_str(_log_text()) \
		.override_failure_message("the standing line must not change for the rule it was written for:\n%s" % _log_text()) \
		.contains("Guards is Shielded: +1 Defense (saves on 3+)")
	await E2EBoot.settle(get_tree())


# ===== (3) two contributions = two lines, both at the Defense the dice actually roll =====

func test_every_contribution_gets_its_own_line(timeout := 240000) -> void:
	var shooter := _shooter()
	var foe := _foe("Guards")
	foe.unit_properties["special_rules"] = ["Shielded"]
	_buff("Warding Chant", foe, 1)
	assert_int(_main._solo_defense_vs(foe, AiCombatMath.HIT_SOURCE_SHOOTING)) \
		.override_failure_message("fixture check: both contributions must actually fold into the save") \
		.is_equal(2)
	await _main._run_human_shooting(shooter, foe)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("the rule half of the composite lost its line (log: %s)" % text.strip_edges()) \
		.contains("Guards is Shielded: +1 Defense (saves on 2+)")
	assert_str(text) \
		.override_failure_message("the token half of the composite lost its line (log: %s)" % text.strip_edges()) \
		.contains("Guards is Warding Chant: +1 Defense (saves on 2+)")
	await E2EBoot.settle(get_tree())


# ===== (4) the silence case: a hex that cancels a bonus used to erase BOTH from the log =====

func test_a_cancelling_hex_no_longer_silences_both_rules(timeout := 240000) -> void:
	var shooter := _shooter()
	var foe := _foe("Guards")
	foe.unit_properties["special_rules"] = ["Shielded"]
	_buff("Withering Hex", foe, -1)
	assert_int(_main._solo_defense_vs(foe, AiCombatMath.HIT_SOURCE_SHOOTING)) \
		.override_failure_message("fixture check: the two contributions must cancel out to the printed Defense") \
		.is_equal(4)
	await _main._run_human_shooting(shooter, foe)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("#224: the bonus that DID apply must be named even when the net number is unchanged (log: %s)" % text.strip_edges()) \
		.contains("Guards is Shielded: +1 Defense (saves on 4+)")
	assert_str(text) \
		.override_failure_message("the hex the player can see on the unit must say what it did (log: %s)" % text.strip_edges()) \
		.contains("Guards is Withering Hex: -1 Defense (saves on 4+)")
	await E2EBoot.settle(get_tree())


# ===== (5) the melee strike phase reads the same truth =====

func test_the_melee_path_names_the_same_contribution(timeout := 240000) -> void:
	# The striker carries no melee weapon on purpose: the defence lines are written BEFORE any
	# weapon group is rolled, so this exercises the seam without a whole fight around it.
	var striker := _unit(1, "Brawlers", Vector3.ZERO, 1)
	var foe := _unit(2, "Grunts", Vector3(0.5 * INCH, 0, 0))
	_buff("Warding Chant", foe, 1)
	await _main._solo_melee_strike_phase(striker, foe, false, 0)   # 0 = SoloStrike.ALL
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("melee read the same parts seam but printed the old collective label (log: %s)" % text.strip_edges()) \
		.contains("Grunts is Warding Chant: +1 Defense (saves on 3+)")
	assert_int(_count("is Shielded")) \
		.override_failure_message("no model in the fixture carries Shielded (log: %s)" % text.strip_edges()) \
		.is_equal(0)
	await E2EBoot.settle(get_tree())

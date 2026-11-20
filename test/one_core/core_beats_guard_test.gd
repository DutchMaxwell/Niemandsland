extends GdUnitTestSuite
## PLAN H, the beats guard (H-5 = Mend; H-6..H-9 add one case per beat). The AI body resolved a bearer's pre-attack beat itself
## and a core that took the activation resolved it a second time from the board it captured before the beat (PR #3029 denied the
## family). The guard: when the core takes the activation, the body does NOT run the beat (`report["core_beats"]`); the core's one
## call resolves it, and the table pays it (`_solo_pay_dangerous`) only when that call is not made or refused.
## One real AI activation per seed, deny slice, door ON against door OFF (the probes of the beats lane): the beat's die rolls exactly
## once, the end state is equal, and the beat's battle-log lines are equal.
## RED: delete the `core_takes and _solo_has_mend(unit)` guard in main.gd (the body runs Mend again) -> the door-on run rolls the
## Mend die twice on every seed. RED for the pay path: drop `report.erase("core_beats")` from `_solo_pay_dangerous` -> a refused
## activation never mends.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")
const RosterSweep := preload("res://test/one_core/roster_sweep.gd")
const DICE := "user://beats_guard_dice"
const SEEDS := 16

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	CoreSlice.path_override = CoreSlice.DENY_PATH
	CoreSlice.reset_cache()
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	RosterSweep.arm(_main, ProjectSettings.globalize_path(DICE))
	CoreActivation._env = 1
	CoreActivation.ai_runs = 0


func after_test() -> void:
	CoreSlice.path_override = ""
	CoreSlice.reset_cache()
	RosterSweep.disarm(_main)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## The dice the activation threw, one string per roll ("count@target:owner").
func _rolls() -> Array:
	AiDiceRecorder.close()
	var out: Array = []
	for r in ParityTable._read_dice(ProjectSettings.globalize_path(DICE)):
		out.append("%d@%d:%s" % [int(r["count"]), int(r["target"]), str(r["owner"])])
	return out


## What the comparison reads off the board: alive models and wounds per unit.
func _digest(units: Array) -> Dictionary:
	var out := {}
	for u in units:
		var gu := u as GameUnit
		var wounds: Array = gu.get_alive_models().map(func(m: ModelInstance) -> int: return m.wounds_current)
		wounds.sort()
		out[gu.get_name()] = {"alive": gu.get_alive_count(), "wounds": wounds, "shaken": gu.is_shaken, "fatigued": gu.is_fatigued}
	return out


## One whole AI activation (`_solo_activate_one_ai`) of a Mend bearer with a wounded Tough model, a target 7 in away. `target_rules` /
## `target_faction`: the target's rules (a denied rule makes the core refuse the call, so the table pays the beat).
func _activation(seed_n: int, door: bool, target_rules: Array = [], target_faction := "battle_brothers", beat := "Mend", x_in := 7.0, att_faction := "battle_brothers") -> Dictionary:
	CoreActivation._env = 1 if door else 0
	var side := {"quality": 4, "defense": 4, "tough": 3, "z_step_in": 1.2, "game_system": "gf", "faction_folder": "battle_brothers"}
	var att := ParityTable._make_unit(_main, side.merged({"player": 2, "name": "Att", "models": 5, "x_in": -x_in, "rules": [beat], "faction_folder": att_faction}, true),
		{"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})
	(att.models[4] as ModelInstance).wounds_current = 1   # the patient: a wounded Tough model within 3 in
	var foe := ParityTable._make_unit(_main, side.merged({"player": 1, "name": "Def", "models": 5, "x_in": x_in, "rules": target_rules,
		"faction_folder": target_faction}, true), {"name": "Rifle", "range_in": 24, "attacks": 1, "count": 5, "rules": []})
	var units: Array = [att, foe]
	_main.seed_tray_rng(seed_n)
	var runs_before := CoreActivation.ai_runs
	var lines: Array = []
	var tap: Callable = Harness._line_tap(lines)
	_main.battle_log.entry_added.connect(tap)
	await _main._solo_activate_one_ai()
	_main.battle_log.entry_added.disconnect(tap)
	var rolls := _rolls()
	var latches: Array = att.unit_properties.keys().filter(func(k) -> bool: return str(k).begins_with("storm_used_") and bool(att.unit_properties[k]))
	var out := {"ran": CoreActivation.ai_runs - runs_before, "rolls": rolls, "mend_dice": rolls.filter(func(r: String) -> bool: return r.begins_with("1@1:")).size(),
		"mend_lines": lines.filter(func(l: String) -> bool: return l.contains("Mend")), "digest": _digest(units),
		"latches": latches, "lines": lines.filter(func(l: String) -> bool: return not l.contains("[core]")), "beat_dice": rolls.filter(func(r: String) -> bool: return r.begins_with("1@2:")).size()}
	Harness._free_units(_main, units)
	_main.solo_controller._peeked_unit = null
	await _main.get_tree().process_frame
	return out


## The door takes the activation: Mend's die rolls exactly once (the core's), the end state and the Mend line equal the table's.
func test_a_mend_bearer_the_core_takes_mends_once_and_lands_what_the_table_lands() -> void:
	var mended := 0
	for s in SEEDS:
		var on := await _activation(s, true)
		var off := await _activation(s, false)
		assert_int(int(off["mend_dice"])).override_failure_message("seed %d: the table's own run rolled Mend %d times" % [s, off["mend_dice"]]).is_equal(1)
		assert_int(int(on["ran"])).override_failure_message("seed %d: the core did not take the activation" % s).is_equal(1)
		assert_int(int(on["mend_dice"])).override_failure_message("seed %d: door on rolled the Mend die %d times (rolls %s)" % [s, on["mend_dice"], on["rolls"]]).is_equal(1)
		assert_dict(on["digest"]).override_failure_message("seed %d: end state differs: %s / %s" % [s, on["digest"], off["digest"]]).is_equal(off["digest"])
		assert_array(on["mend_lines"]).override_failure_message("seed %d: Mend lines differ: %s / %s" % [s, on["mend_lines"], off["mend_lines"]]).is_equal(off["mend_lines"])
		mended += 1 if not (off["mend_lines"] as Array).is_empty() else 0
	assert_int(mended).override_failure_message("the patient was never healed: the check proved nothing").is_greater(0)


## The core refuses the call (the target carries a rule the slice denies): the body's guard left the beat to the table, which pays it
## once, in front of its own volley - the same dice and state as the door off.
func test_a_refused_call_pays_the_mend_on_the_table_once() -> void:
	for s in SEEDS:
		var on := await _activation(s, true, ["Grounded Protection"])
		var off := await _activation(s, false, ["Grounded Protection"])
		assert_int(int(on["ran"])).override_failure_message("seed %d: the core took a volley at a denied target" % s).is_equal(0)
		assert_int(int(on["mend_dice"])).override_failure_message("seed %d: the refused activation rolled Mend %d times" % [s, on["mend_dice"]]).is_equal(1)
		assert_dict(on["digest"]).override_failure_message("seed %d: end state differs" % s).is_equal(off["digest"])
		assert_array(on["mend_lines"]).is_equal(off["mend_lines"])


## H-6: a Breath Attack bearer 4 in from its target (the breath reaches 6 in): the trigger die rolls once (the core's), the end state
## and the whole battle log of the activation equal the table's. RED: delete the Breath half of the guard (the body breathes, then the
## core breathes again from its capture) -> two trigger dice.
func test_a_breath_bearer_the_core_takes_breathes_once_and_lands_what_the_table_lands() -> void:
	var breathed := 0
	for s in SEEDS:
		var on := await _activation(s, true, [], "battle_brothers", "Breath Attack", 2.0, "alien_hives")
		var off := await _activation(s, false, [], "battle_brothers", "Breath Attack", 2.0, "alien_hives")
		assert_int(int(on["ran"])).override_failure_message("seed %d: the core did not take the activation" % s).is_equal(1)
		assert_int(int(on["beat_dice"])).override_failure_message("seed %d: door on rolled %s / off %s" % [s, on["rolls"], off["rolls"]]).is_equal(int(off["beat_dice"]))
		assert_array(on["rolls"]).override_failure_message("seed %d: dice differ" % s).is_equal(off["rolls"])
		assert_dict(on["digest"]).override_failure_message("seed %d: end state differs: %s / %s" % [s, on["digest"], off["digest"]]).is_equal(off["digest"])
		assert_array(on["lines"]).override_failure_message("seed %d: lines differ:\n%s\n---\n%s" % [s, "\n".join(on["lines"]), "\n".join(off["lines"])]).is_equal(off["lines"])
		breathed += 1 if (off["lines"] as Array).any(func(l: String) -> bool: return l.contains("breathes on")) else 0
	assert_int(breathed).override_failure_message("no seed breathed: the check proved nothing").is_greater(0)


## H-7: a Storm Attack bearer of each facet (War = AP(1), Lust = surge, Plague = Bane, Change = Shred) 8 in from its target: every die,
## the end state, every battle-log line and the once-per-game latch equal the table's. RED: delete the Storm half of the guard (the
## body storms, then the core storms again from its capture) -> the trigger dice roll twice.
func test_a_storm_bearer_the_core_takes_storms_once_and_lands_what_the_table_lands() -> void:
	var stormed := 0
	for facet in [["Storm of War", "daemons_of_war"], ["Storm of Lust", "daemons_of_lust"], ["Storm of Plague", "daemons_of_plague"],
			["Storm of Change", "daemons_of_change"]]:
		for s in 8:
			var on := await _activation(s, true, [], "battle_brothers", facet[0], 4.0, facet[1])
			var off := await _activation(s, false, [], "battle_brothers", facet[0], 4.0, facet[1])
			var tag := "%s seed %d" % [facet[0], s]
			assert_int(int(on["ran"])).override_failure_message("%s: the core did not take the activation" % tag).is_equal(1)
			assert_array(on["rolls"]).override_failure_message("%s: dice differ: %s / %s" % [tag, on["rolls"], off["rolls"]]).is_equal(off["rolls"])
			assert_dict(on["digest"]).override_failure_message("%s: end state differs: %s / %s" % [tag, on["digest"], off["digest"]]).is_equal(off["digest"])
			assert_array(on["lines"]).override_failure_message("%s: lines differ:\n%s\n---\n%s" % [tag, "\n".join(on["lines"]), "\n".join(off["lines"])]).is_equal(off["lines"])
			assert_array(on["latches"]).override_failure_message("%s: latch %s / %s" % [tag, on["latches"], off["latches"]]).is_equal(off["latches"])
			stormed += 1 if (off["lines"] as Array).any(func(l: String) -> bool: return l.contains("unleashes the storm")) else 0
	assert_int(stormed).override_failure_message("no seed stormed: the check proved nothing").is_greater(0)

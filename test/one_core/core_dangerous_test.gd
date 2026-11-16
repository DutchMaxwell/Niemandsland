extends GdUnitTestSuite
## One core P4.D-18: `CoreActivation.run_ai(..., owns_dangerous = true)` - the core takes the activation's Dangerous test
## (and the end-of-activation morale from its wounds) with the volley, or alone when the unit has no shot.
## The witness is the golden fixture of the OLD table (test/fixtures/one_core/golden_dangerous.json, P4.D-10): its four
## shapes x 8 seeds (advance, half strength, no target, cannot shoot) run here through the REAL core (NmlCore loaded, the
## flag ON) on the same units, the same painted Dangerous block and the same seeds. The final state of both units, the
## tray rng and the dice and morale lines must equal the fixture's. Two things are left out of the comparison on both
## sides, each for a stated reason: the attacker's own Dangerous sentences ("takes one Dangerous terrain test ...",
## "takes N wounds from dangerous terrain", its wound count) are not part of the core's step lines yet (see
## _verdict_lines), and WHICH of the attacker's identical models a Dangerous wound removes (see _tie_blind).
## Real: the main scene, NmlCore, `run_ai`, the tray. Constructed: the plain units and the painted Dangerous block (the
## golden harness's own), an Advance report that names no Dangerous dice (the table rolled nothing).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const Harness := preload("res://test/one_core/golden_witness_harness.gd")
const ParityTable := preload("res://test/parity/parity_table.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {1: true, 2: true}   # both seats AI: a human defender would wait for a save click
	_main._ensure_solo_controller()
	_main.solo_controller.ai_slot = 2
	_main.solo_controller.human_slot = 1
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_batch = true
	CoreActivation._env = 1
	CoreActivation.ai_runs = 0
	CoreActivation.ai_refusals = 0


func after_test() -> void:
	CoreActivation.reset_all(_main)
	CoreActivation._env = -1
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


## What this suite compares of a case's battle log: the tray's dice lines and the morale verdicts. The rest of the
## table's Dangerous sequence is attacker-side wording the core does not print (its landing line comes in another
## place than the table's); the dice lines plus the tray rng pin that the same dice were thrown in the same order.
static func _verdict_lines(lines: Array) -> Array:
	return lines.filter(func(l: Variant) -> bool: return str(l).begins_with("COMBAT|AI (") or str(l).contains(" morale"))


## The attacker's per-model slots reduced to the multiset of (alive, wounds) pairs. A Dangerous wound lands on the
## casualty order's first model, and a straight row of identical models has exact distance ties (the first and the last
## of four stand equally far from the centroid): the table's unsorted tie and the core's stable sort pick different ones
## of the two (slot 0 vs slot 3) - the same number of models, the same wounds. The defender's slots stay exact.
static func _tie_blind(final: Array) -> Array:
	var out: Array = (final as Array).duplicate(true)
	var pairs: Array = []
	for t in (out[0]["slots"] as Array):
		pairs.append([int(t[1]), int(t[2])])
	pairs.sort()
	out[0]["slots"] = pairs.map(func(p: Array) -> Array: return [pairs.find(p), p[0], p[1]])
	return out


## One golden shape x seed through the core: the golden's units and painted block, the AI body's call (an Advance that
## moved) with `owns_dangerous`. The target is null when the shape has no volley (the unit cannot shoot, or the defender
## is out of range: the body's `_run_ai_shooting` decides that).
func _core_case(sc: Dictionary, seed: int) -> Dictionary:
	var att := ParityTable._make_unit(_main, sc["attacker"], (sc["weapon"] as Dictionary).duplicate(true))
	# The golden's defender has no weapon (a generic unit, never plain); the core door needs a plain target, so it gets
	# the attacker's rifle: a defender's own weapons play no part in the exchange.
	var dfn := ParityTable._make_unit(_main, sc["defender"], (sc["weapon"] as Dictionary).merged({"count": 5}, true))
	Harness._kill_models(att, int(sc.get("dead", 0)))
	var painted: Dictionary = Harness._paint_cover(_main, att, _main.terrain_overlay.TerrainType.DANGEROUS)
	var gap_in := float((sc["defender"] as Dictionary)["x_in"]) - float((sc["attacker"] as Dictionary)["x_in"])
	var shoots: bool = bool(sc.get("can_shoot", true)) and gap_in <= float((sc["weapon"] as Dictionary)["range_in"])
	var dice := OPRArmyManager.dangerous_dice_for(att)
	_main.seed_tray_rng(seed)
	var h := CoreActivation.capture(_main)
	var lines: Array = []
	var tap: Callable = Harness._line_tap(lines)
	_main.battle_log.entry_added.connect(tap)
	var report := {"action": AiDecision.Action.ADVANCE, "moved": true}
	var took: bool = await CoreActivation.run_ai(_main, att, report, dfn if shoots else null, h, [], true)
	_main.battle_log.entry_added.disconnect(tap)
	_main.solo_controller._core_node_ready().release(h)
	var rec := {"scenario": str(sc["name"]), "seed": seed, "epoch": AiActRecorder.rules_epoch,
		"lines": _verdict_lines(lines), "final": _tie_blind(Harness._final([att, dfn])), "rng": Harness._rng_state(_main),
		"extra": {"dice": str(dice)}}
	if not took:
		rec = {"scenario": str(sc["name"]), "seed": seed, "error": "the core refused the activation"}
	Harness._unpaint_cover(_main, painted)
	Harness._free_units(_main, [att, dfn])
	await _main.get_tree().process_frame
	return rec


## The golden fixture with every case's log cut to the lines this suite compares.
func _want() -> Dictionary:
	var want := Harness.load_fixture(Harness.DANGEROUS_FIXTURE_PATH)
	for c in want.get("cases", []):
		c["lines"] = _verdict_lines(c["lines"])
		c["final"] = _tie_blind(c["final"])
	return want


func _core_grid() -> Dictionary:
	var out := {"schema": Harness.SCHEMA, "family": Harness.DANGEROUS_FAMILY, "provenance": Harness.provenance(),
		"cases": []}
	for sc in Harness.dangerous_scenarios():
		for seed in sc.get("seeds", Harness.SEEDS):
			out["cases"].append(await _core_case(sc, int(seed)))
	return out


## The golden's 32 cases (advance, half strength, no target, cannot shoot) through the core with `owns_dangerous`. RED:
## the core path without the flag refuses (the clause) -> every case errors; a core that rolls the test twice, or not
## at all for a unit with no shot, moves the tray rng and the final state off the fixture.
func test_the_core_equals_the_golden_for_every_dangerous_shape() -> void:
	var want := _want()
	assert_bool(want.is_empty()).override_failure_message("fixture missing: %s" % Harness.DANGEROUS_FIXTURE_PATH).is_false()
	var got := await _core_grid()
	assert_int((got["cases"] as Array).size()).is_equal(32)
	var problems := Harness.compare(want, got)
	assert_array(problems).override_failure_message(
		"the core's Dangerous activation differs from the old table (%s):\n%s" % [
			Harness.describe_provenance(want, got), "\n".join(problems.slice(0, 12))]).is_empty()
	assert_int(CoreActivation.ai_refusals).override_failure_message("the core refused an activation").is_equal(0)


## RED: the comparison itself - one planted slot in a copy of the fixture is reported, once.
func test_a_planted_difference_in_the_fixture_is_reported() -> void:
	var want := _want()
	var got := await _core_grid()
	var slot: Array = want["cases"][0]["final"][1]["slots"][0]
	slot[1] = not bool(slot[1])
	var problems := Harness.compare(want, got)
	assert_int(problems.size()).override_failure_message("a changed slot went unnoticed: %s" % [problems]).is_equal(1)


## The production default (owns_dangerous false): a report naming Dangerous dice means the table rolled the test, so the
## core refuses before any call - no die thrown, no refusal counted. RED: without the clause the core rolls it again.
func test_the_default_refuses_a_dangerous_test_the_table_rolled() -> void:
	var sc: Dictionary = Harness.dangerous_scenarios()[0]
	var att := ParityTable._make_unit(_main, sc["attacker"], (sc["weapon"] as Dictionary).duplicate(true))
	var dfn := ParityTable._make_unit(_main, sc["defender"], (sc["weapon"] as Dictionary).merged({"count": 5}, true))
	var painted: Dictionary = Harness._paint_cover(_main, att, _main.terrain_overlay.TerrainType.DANGEROUS)
	_main.seed_tray_rng(7)
	var rng_before := Harness._rng_state(_main)
	var h := CoreActivation.capture(_main)
	var report := {"action": AiDecision.Action.ADVANCE, "moved": true, "dangerous_dice": 4}
	var took: bool = await CoreActivation.run_ai(_main, att, report, dfn, h, [])
	assert_bool(took).override_failure_message("the core took a volley whose Dangerous test the table rolled").is_false()
	assert_str(Harness._rng_state(_main)).override_failure_message("a die was thrown").is_equal(rng_before)
	assert_int(CoreActivation.ai_refusals).is_equal(0)
	# A shotless call only makes sense when the core owns the test: without the flag there is nothing for it to do.
	var shotless: bool = await CoreActivation.run_ai(_main, att, {"action": AiDecision.Action.ADVANCE}, null, h, [])
	assert_bool(shotless).override_failure_message("a call with no target and no Dangerous test ran").is_false()
	assert_str(Harness._rng_state(_main)).override_failure_message("a die was thrown").is_equal(rng_before)
	_main.solo_controller._core_node_ready().release(h)
	Harness._unpaint_cover(_main, painted)
	Harness._free_units(_main, [att, dfn])


## A one-model unit whose own Dangerous test kills it (one die, a 1) fires nothing and tests no morale. No golden shape
## covers it, so the table is the oracle here: the same unit and seed through `_run_ai_dangerous` then the body's guard
## (a destroyed unit stops) must leave the same final state and tray rng as the core's one call. Seeds 0-39; the
## case needs at least three seeds that wipe the unit and three that leave it standing.
func _lone_case(seed: int, via_core: bool) -> Dictionary:
	var spec: Dictionary = (Harness.dangerous_scenarios()[0]["attacker"] as Dictionary).merged({"models": 1}, true)
	var rifle: Dictionary = (Harness.RIFLE as Dictionary).merged({"count": 1}, true)
	var att := ParityTable._make_unit(_main, spec, rifle)
	var dfn := ParityTable._make_unit(_main, Harness.dangerous_scenarios()[0]["defender"], rifle.merged({"count": 5}, true))
	var painted: Dictionary = Harness._paint_cover(_main, att, _main.terrain_overlay.TerrainType.DANGEROUS)
	_main.seed_tray_rng(seed)
	var h := CoreActivation.capture(_main) if via_core else 0
	if via_core:
		var ok: bool = await CoreActivation.run_ai(_main, att, {"action": AiDecision.Action.ADVANCE, "moved": true}, dfn, h, [], true)
		assert_bool(ok).override_failure_message("the core refused a lone unit's activation (seed %d)" % seed).is_true()
		_main.solo_controller._core_node_ready().release(h)
	else:
		await _main._run_ai_dangerous(att, OPRArmyManager.dangerous_dice_for(att))
		if not att.is_destroyed():
			await _main._run_ai_shooting({"unit": att, "moved": true})
			if not att.is_destroyed():
				await _main._solo_shooting_morale(att, 1, _main._roller_label(att), 1, "Dangerous terrain")
	var rec := {"final": Harness._final_rows(Harness._final([att, dfn])), "rng": Harness._rng_state(_main),
		"gone": att.is_destroyed()}
	Harness._unpaint_cover(_main, painted)
	Harness._free_units(_main, [att, dfn])
	await _main.get_tree().process_frame
	return rec


func test_a_unit_wiped_by_its_own_test_fires_nothing() -> void:
	var gone := 0
	var stands := 0
	for seed in 40:
		var table := await _lone_case(seed, false)
		var core := await _lone_case(seed, true)
		assert_dict(core).override_failure_message("seed %d: table %s, core %s" % [seed, table, core]).is_equal(table)
		gone += 1 if bool(core["gone"]) else 0
		stands += 0 if bool(core["gone"]) else 1
	assert_bool(gone >= 3 and stands >= 3).override_failure_message("gone %d, stands %d" % [gone, stands]).is_true()

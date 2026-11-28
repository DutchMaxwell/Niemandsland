extends GdUnitTestSuite
## Feature test FT-23: one round human vs AI, Firefight (gff) and Skirmish (aofs). FF36 p.7 l.487-507 (AS36 the same): the
## sides alternate one unit each; the round ends when all units have activated.
## Scene: P1 (the human) has two 1-model units, P2 (the AI seat) two, rifles in range, round 1. P1's Rangers advances 2 in
## and shoots; the AI answers; P1's Scouts advances and shoots; the AI answers; the round ends.
## Asserted: after each human activation exactly ONE AI unit activates, through the core (CoreActivation.ai_runs + 1, no
## refusal), with its action and volley lines; round 2 opens with every unit fresh.
## Real: the main scene, the solo seat, the card's Activate, the real drag, the radial targeting and click, the solo
## alternation, the AI planner and the core's AI activation.

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "S")


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _ai_spent(ai: Array) -> int:
	return ai.filter(func(u: GameUnit) -> bool: return u.is_activated).size()


## The human's advance-and-shoot with `u` at `target`, then the AI's answer: one more AI unit spent, one more core run.
func _human_then_ai(sys: String, u: GameUnit, target: GameUnit, ai: Array) -> void:
	var spent := _ai_spent(ai)
	var runs := CoreActivation.ai_runs
	var refusals := CoreActivation.ai_refusals
	assert_bool(await _t.start(u)).override_failure_message("%s: %s starts: %s" % [sys, u.get_name(), _t.lines]).is_true()
	await _t.walk(u, 2.0, 0.0, CoreActivation.CAP_ADVANCE)
	await _t.aim(u, target)
	var guard := 0
	while _ai_spent(ai) == spent and guard < 300:
		await _t.runner.simulate_frames(3)
		guard += 1
	assert_bool(u.is_activated or _t.main.opr_army_manager.current_round == 2) \
		.override_failure_message("%s: %s spent: %s" % [sys, u.get_name(), _t.lines]).is_true()
	assert_int(CoreActivation.ai_runs - runs).override_failure_message("%s: one AI activation through the core: %s" % [sys, _t.lines]).is_equal(1)
	assert_int(CoreActivation.ai_refusals - refusals).override_failure_message("%s: no core refusal" % sys).is_equal(0)


func _case(sys: String) -> void:
	var u1 := _t.unit(sys, 1, "Rangers", 1, 3, -10.0, -5.0)
	var u2 := _t.unit(sys, 1, "Scouts", 1, 3, -10.0, 5.0)
	var ai := [_t.unit(sys, 2, "Raiders", 1, 3, 10.0, -5.0), _t.unit(sys, 2, "Reavers", 1, 3, 10.0, 5.0)]
	_t.main.seed_tray_rng(0)
	await _human_then_ai(sys, u1, ai[0], ai)
	assert_bool(_t.lines.any(func(l: String) -> bool: return l.begins_with("Raiders fires") or l.begins_with("Reavers fires"))) \
		.override_failure_message("%s: the AI's volley line: %s" % [sys, _t.lines]).is_true()
	await _human_then_ai(sys, u2, ai[1], ai)
	assert_int(_t.main.opr_army_manager.current_round).override_failure_message("%s: round 2: %s" % [sys, _t.lines]).is_equal(2)
	for u in [u1, u2] + ai:
		assert_bool((u as GameUnit).is_activated).override_failure_message("%s: fresh in round 2" % sys).is_false()


func test_gff_one_round_against_the_ai(timeout := 300000) -> void:
	await _case("gff")


func test_aofs_one_round_against_the_ai(timeout := 300000) -> void:
	await _case("aofs")

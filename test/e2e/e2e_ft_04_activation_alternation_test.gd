extends GdUnitTestSuite
## Feature test FT-4: activation and alternation on a hot-seat table, Firefight (gff) and Skirmish (aofs). FF36 p.7
## l.487-507 (AS36 the same): one unit per turn, the turns alternate, a side with no unit left waits while the other
## keeps activating, and the next round opens with the side that finished activating first.
## Scene: P1 has two 1-model units, P2 three, out of rifle range. P1 U1; P1 U2 too early (refused); P2 U3; P1 U2;
## P2 U4 and U5 in a row; round 2 opens by itself with P1 on turn and every unit fresh.
## Real: the main scene, the two-human turn state, the card's Activate / End doors, the battle log.

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _has(needle: String) -> bool:
	return _t.lines.any(func(l: String) -> bool: return l.find(needle) != -1)


## The card's Activate, then its End when the activation opened (a refused start opens nothing).
func _activate(u: GameUnit) -> void:
	if await _t.start(u):
		await _t.end(u)
	await _t.runner.simulate_frames(4)


func _case(sys: String) -> void:
	var u1 := _t.unit(sys, 1, "Alpha", 1, 1, -15.0, -6.0)
	var u2 := _t.unit(sys, 1, "Bravo", 1, 1, -15.0, 6.0)
	var u3 := _t.unit(sys, 2, "Crows", 1, 1, 15.0, -10.0)
	var u4 := _t.unit(sys, 2, "Dogs", 1, 1, 15.0, 0.0)
	var u5 := _t.unit(sys, 2, "Eels", 1, 1, 15.0, 10.0)
	await _activate(u1)
	assert_bool(u1.is_activated).override_failure_message("%s: P1 opens with U1: %s" % [sys, _t.lines]).is_true()
	await _activate(u2)
	assert_bool(u2.is_activated).override_failure_message("%s: P1's second unit in a row is refused" % sys).is_false()
	assert_bool(_has("It is P2's turn")).override_failure_message("%s: the refusal names P2: %s" % [sys, _t.lines]).is_true()
	await _activate(u3)
	await _activate(u2)
	assert_bool(u3.is_activated and u2.is_activated).override_failure_message("%s: P2 then P1: %s" % [sys, _t.lines]).is_true()
	await _activate(u4)
	assert_bool(u4.is_activated).override_failure_message("%s: P2 on turn" % sys).is_true()
	await _activate(u5)   # P1 is spent: P2 keeps activating, and its last unit ends the round
	assert_int(_t.main.opr_army_manager.current_round).override_failure_message("%s: round 2 opens by itself: %s" % [sys, _t.lines]).is_equal(2)
	for u in [u1, u2, u3, u4, u5]:
		assert_bool((u as GameUnit).is_activated).override_failure_message("%s: %s fresh in round 2" % [sys, u.unit_id]).is_false()
	# P1 finished first in round 1 (its last unit went before P2's U4 and U5), so P1 opens round 2.
	await _activate(u3)
	assert_bool(u3.is_activated).override_failure_message("%s: P2 may not open round 2: %s" % [sys, _t.lines]).is_false()
	assert_bool(_has("It is P1's turn")).override_failure_message("%s: the refusal names P1: %s" % [sys, _t.lines]).is_true()
	await _activate(u1)
	assert_bool(u1.is_activated).override_failure_message("%s: P1 opens round 2: %s" % [sys, _t.lines]).is_true()


func test_firefight_alternates_and_the_first_finisher_opens(timeout := 180000) -> void:
	await _case("gff")


func test_skirmish_alternates_and_the_first_finisher_opens(timeout := 180000) -> void:
	await _case("aofs")

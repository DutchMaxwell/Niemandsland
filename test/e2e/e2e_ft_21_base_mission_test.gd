extends GdUnitTestSuite
## Feature test FT-21: the base mission and the end of the game on a hot-seat Firefight (gff) table. FF36 p.6 l.358-362,
## l.376-391: at each round's end a marker is seized by a side with a unit within 3 in and no enemy unit within 3 in; it
## stays seized after the unit leaves; both sides near = contested, it stays as it is; the game lasts 4 rounds and the
## side holding most markers wins.
## Scene: M1 with P1's U1 1 in off it (and P2's V4 parked 5 in off it), M2 with P1's U2 and P2's V2 both near, M3 bare.
## Every activation is idle (Activate, End) except U1, which advances 6 in off M1 in round 2.
## (The Shaken lock on seizing is FT-11's case.)
## Real: the main scene, the card's Activate / End, the real drag, the hot-seat round end, its seize, the game summary.

const INCH := 0.0254
const BASE_IN := 32.0 / 25.4

var _t: SkirmishTable


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _idle(u: GameUnit) -> void:
	if await _t.start(u):
		await _t.end(u)
	await _t.runner.simulate_frames(4)


func _owners() -> Array:
	return [_t.main.terrain_overlay.get_objective_owner(0), _t.main.terrain_overlay.get_objective_owner(1),
		_t.main.terrain_overlay.get_objective_owner(2)]


func test_markers_seized_held_contested_and_the_game_ends_after_round_4(timeout := 300000) -> void:
	var m1 := Vector3(-14.0 * INCH, 0, 0)
	var m2 := Vector3.ZERO
	var m3 := Vector3(14.0 * INCH, 0, 0)
	_t.main.terrain_overlay.update_objectives([m1, m2, m3], [0, 0, 0])
	var u1 := _t.unit("gff", 1, "Holder", 1, 1, -14.0, -1.0 - BASE_IN / 2.0)          # 1 in off M1 (base edge)
	var u2 := _t.unit("gff", 1, "Claimant", 1, 1, -2.0 - BASE_IN / 2.0, 0.0)        # 2 in off M2
	var v2 := _t.unit("gff", 2, "Rival", 1, 1, 2.0 + BASE_IN / 2.0, 0.0)            # 2 in off M2
	var v3 := _t.unit("gff", 2, "Idler", 1, 1, 0.0, 20.0)
	var v4 := _t.unit("gff", 2, "Watcher", 1, 1, -14.0, 5.0 + BASE_IN / 2.0)        # 5 in off M1: no contest
	var order := [u1, v2, u2, v3, v4]   # P1, P2, P1, P2, P2 (P1 spent): P2 ends each round, so P1 opens the next
	for u in order:
		await _idle(u)
	assert_array(_owners()).override_failure_message("after round 1: %s" % [_t.lines]).is_equal([1, 0, 0])
	assert_bool(await _t.start(u1)).is_true()
	await _t.walk(u1, 0.0, -6.0, CoreActivation.CAP_ADVANCE)   # off M1
	await _t.end(u1)
	for u in [v2, u2, v3, v4]:
		await _idle(u)
	assert_array(_owners()).override_failure_message("M1 stays P1's after U1 left: %s" % [_t.lines]).is_equal([1, 0, 0])
	assert_int(_t.main.opr_army_manager.current_round).is_equal(3)
	for r in [3, 4]:
		assert_str(_t.summary_text()).override_failure_message("no summary before round %d ends" % r).is_empty()
		for u in order:
			await _idle(u)
	assert_int(_t.main.opr_army_manager.current_round).override_failure_message("no round 5: %s" % [_t.lines]).is_equal(4)
	assert_str(_t.summary_text()).override_failure_message("the game ends after round 4").contains("4 rounds played.")
	for want in ["P1: 1", "P2: 0", "Neutral: 2"]:
		assert_str(_t.summary_text()).override_failure_message("summary line %s" % want).contains(want)
	assert_str(_t.summary_text().strip_edges()).override_failure_message("most markers wins").ends_with("P1 wins")

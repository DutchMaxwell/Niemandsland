extends GdUnitTestSuite
## Feature test FT-3: Ambush on a hot-seat Firefight (gff) table. FF36 p.13 l.1136-1141: an Ambush unit is set aside and
## arrives at the start of any round after the first, over 9 in from enemy units; in its arrival round it may neither
## seize nor contest objectives.
## Scene: P1's Am (one model, Ambush) in reserve on the tray, P1's X and P2's E (centre) on the table, a marker M 12 in
## off E. Round 1 = X and E idle; at the round-2 start P1 places Am 10 in (base to base) from E and 1 in from M and
## hands over with "✓ Unit placed"; round 2 and round 3 play idle. Twin: Am placed 8 in from E.
## FINDING #3865 (R-FT2): the 8 in arrival stands with a warning line (honor system); the book case stays, skipped.
## Real: the main scene, the hot-seat round end and its Ambush arrival step (the board prompt and its button), the card's
## Activate / End, the round-end seize with its arrival lock.

const INCH := 0.0254
const BASE_IN := 32.0 / 25.4

var _t: SkirmishTable
var _x: GameUnit
var _am: GameUnit
var _e: GameUnit


func before_test() -> void:
	_t = await SkirmishTable.boot(self, "H")
	_x = _t.unit("gff", 1, "Xan", 1, 1, -20.0, 20.0)
	_am = _t.unit("gff", 1, "Stalkers", 1, 1, 0.0, 0.0, {}, ["Ambush"])
	_am.unit_properties["ambush_reserve"] = true
	(_am.models[0] as ModelInstance).node.global_position = Vector3(3.0, 0, 0)   # the tray
	_e = _t.unit("gff", 2, "Enemy", 1, 1, 0.0, 0.0)
	_t.main.terrain_overlay.update_objectives([Vector3(-12.0 * INCH, 0, 0)], [0])


func after_test() -> void:
	if _t != null:
		_t.teardown()
	_t = null


func _idle(u: GameUnit) -> void:
	if await _t.start(u):
		await _t.end(u)
	await _t.runner.simulate_frames(4)


## E's End closes round 1 and runs the round-2 arrival step, which waits on the board prompt: the player places Am
## `gap_in` (base to base) left of E and presses "✓ Unit placed". True when the step finished.
func _arrive(gap_in: float) -> bool:
	await _idle(_x)
	assert_bool(await _t.start(_e)).is_true()
	var done := [false]
	var close := func() -> void:
		await _t.end(_e)
		done[0] = true
	close.call()
	var guard := 0
	while _t.count("P1 Ambush (round 2)") == 0 and guard < 300:
		await _t.runner.simulate_frames(2)
		guard += 1
	(_am.models[0] as ModelInstance).node.global_position = Vector3(-(gap_in + BASE_IN) * INCH, 0, 0)
	assert_bool(_t.press_button("✓ Unit placed")).override_failure_message("the arrival prompt: %s" % [_t.lines]).is_true()
	guard = 0
	while not done[0] and guard < 300:
		await _t.runner.simulate_frames(2)
		guard += 1
	return done[0]


func test_an_arrival_10_in_off_stands_and_seizes_only_from_the_next_round(timeout := 180000) -> void:
	assert_bool(await _arrive(10.0)).override_failure_message("the arrival step ended: %s" % [_t.lines]).is_true()
	assert_bool(bool(_am.unit_properties.get("ambush_reserve", true))).override_failure_message("Am arrived").is_false()
	assert_float(((_am.models[0] as ModelInstance).node.global_position.x) / INCH).is_equal_approx(-10.0 - BASE_IN, 0.01)
	for u in [_x, _e, _am]:   # round 2: P1 opens (P2 took round 1's last activation)
		await _idle(u)
	assert_int(_t.main.opr_army_manager.current_round).override_failure_message("round 3: %s" % [_t.lines]).is_equal(3)
	assert_int(_t.count("Objective 1: Stalkers arrived from Ambush this round and cannot seize or contest")) \
		.override_failure_message("the arrival-round lock line: %s" % [_t.lines]).is_equal(1)
	assert_int(_t.main.terrain_overlay.get_objective_owner(0)).override_failure_message("neutral after round 2").is_equal(0)
	for u in [_e, _x, _am]:   # round 3: P2 opens (P1 took round 2's last activation)
		await _idle(u)
	assert_int(_t.main.terrain_overlay.get_objective_owner(0)).override_failure_message("P1's after round 3: %s" % [_t.lines]).is_equal(1)


@warning_ignore("unused_parameter")
func test_an_arrival_8_in_off_is_refused(timeout := 120000, do_skip := true,
		skip_reason := "FINDING #3865: a human Ambush arrival within 9 in stands with a warning") -> void:
	await _arrive(8.0)
	assert_bool(bool(_am.unit_properties.get("ambush_reserve", false))) \
		.override_failure_message("an arrival 8 in from an enemy is refused: %s" % [_t.lines]).is_true()

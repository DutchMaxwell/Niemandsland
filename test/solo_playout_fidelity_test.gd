extends GdUnitTestSuite
## S-wave PS1/PS3 — the whole-game playout as a MEASURING INSTRUMENT.
## solo_playout_search_test.gd pins the search that CONSUMES a playout; this
## suite pins the playout's own contract, because the fidelity gate replays
## real arena games through it and compares the answers:
##   * same board + same seed = the same game, twice (or a replay proves nothing)
##   * the game's own dice are never touched (or the replay changes the very
##     game it is measuring)
##   * a playout ALWAYS ends — an unbounded one does not fail the arena, it
##     hangs it
##   * one hand-checkable behaviour, which also nails down the sim's biggest
##     known divergence from the table rule.

const IN2M := 0.0254


## Weaponless on purpose (no OPR source data = no weapon profiles): nothing
## shoots, charges or dies, so a playout over these fixtures is PURE GEOMETRY
## and every expected number below is checkable by hand.
func _unit(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = 1
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


## Armed twin — a shooting unit, so the playout really draws from its rng
## (BattleSim's stochastic wound rounding). Determinism is only a claim worth
## making about a game that HAS dice in it.
func _armed(pid: int, positions: Array, uid: String, range_in: int) -> GameUnit:
	var u := _unit(pid, positions, uid)
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Rifle"
	w.range_value = range_in
	w.attacks = 4
	w.count = 1
	opr.weapons.append(w)
	u.source_type = "opr"
	u.source_data = opr
	return u


func _state(units: Array, objectives: Array, round_no := 1, rounds_total := 4) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	return BattleSim.capture(army, func() -> Array: return objectives,
		func(_i: int) -> int: return 0, round_no, rounds_total)


func _row(pid: int, positions: Array) -> Dictionary:
	return {"player": pid, "positions": positions}


func _duel() -> Dictionary:
	return _state([_armed(1, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0),
			Vector3(2.0 * IN2M, 0, 0)], "Shooter", 24),
		_armed(2, [Vector3(12.0 * IN2M, 0, 0), Vector3(13.0 * IN2M, 0, 0),
			Vector3(14.0 * IN2M, 0, 0)], "Foe", 24)],
		[Vector3(6.0 * IN2M, 0, 0)])


## The opening volley: guarantees the very first resolve draws from the prng,
## so "deterministic per seed" is a statement about a game with dice in it.
func _open_fire() -> Dictionary:
	return {"unit": "Shooter", "kind": AiDecision.Action.HOLD, "shoot": "Foe"}


# (a) DETERMINISM ------------------------------------------------------------

func test_same_board_and_seed_replay_the_same_game() -> void:
	var state := _duel()
	var a := AiPlanner.full_playout_seeded(state, _open_fire(), 1, 7)
	var b := AiPlanner.full_playout_seeded(state, _open_fire(), 1, 7)
	assert_str(JSON.stringify(a)).is_equal(JSON.stringify(b))
	# and the result speaks the ARENA's vocabulary, so a sim game and a real
	# arena_match game are a direct comparison, not a translation exercise
	for k in ["p1", "p2", "vp", "objectives", "survivors", "rounds_played", "winner"]:
		assert_bool(a.has(k)).is_true()
	assert_array(["p1", "p2", "draw"]).contains([str(a["winner"])])


## Determinism must not be VACUOUS: if the fixture never rolled a die, "same
## seed = same game" says nothing. The passed-in generator has to have moved.
func test_the_playout_actually_draws_from_its_local_generator() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var before: int = rng.state
	AiPlanner.full_playout(_duel(), _open_fire(), 1, rng)
	assert_bool(rng.state != before).is_true()


# (b) THE GAME'S DICE STAY UNTOUCHED ----------------------------------------

## A playout runs on a LOCAL generator. If it drew from the global stream, a
## replay would move the dice of the game it is supposed to be measuring —
## the measurement would create the difference it reports.
func test_a_playout_never_moves_the_global_dice_stream() -> void:
	seed(4242)
	var clean := [randi(), randi(), randi()]
	seed(4242)
	var first := randi()
	AiPlanner.full_playout_seeded(_duel(), _open_fire(), 1, 3)
	assert_array([first, randi(), randi()]).is_equal(clean)


func test_a_playout_never_edits_the_board_it_was_handed() -> void:
	var state := _duel()
	var before := JSON.stringify(BattleSim.board_rows(state))
	AiPlanner.full_playout_seeded(state, _open_fire(), 1, 3)
	assert_str(JSON.stringify(BattleSim.board_rows(state))).is_equal(before)


# (c) IT ALWAYS ENDS --------------------------------------------------------

## A mission ends on its own round count, from round 1 or from the middle of
## the game. A nonsense rounds_total is clamped by PLAYOUT_MAX_ROUNDS and the
## playout still RETURNS — the cap is insurance against a hang, and it binds
## visibly so this test can see it.
func test_a_playout_always_ends_and_the_round_cap_binds() -> void:
	var units := [_unit(1, [Vector3(6.0 * IN2M, 0, 0)], "Blue"),
		_unit(2, [Vector3(-6.0 * IN2M, 0, 0)], "Red")]
	var act := {"unit": "Blue", "kind": AiDecision.Action.HOLD}
	assert_int(int(AiPlanner.full_playout_seeded(
		_state(units, [Vector3.ZERO], 1, 4), act, 1, 1)["rounds_played"])).is_equal(4)
	assert_int(int(AiPlanner.full_playout_seeded(
		_state(units, [Vector3.ZERO], 3, 4), act, 1, 1)["rounds_played"])).is_equal(4)
	assert_int(int(AiPlanner.full_playout_seeded(
		_state(units, [Vector3.ZERO], 1, 500), act, 1, 1)["rounds_played"])) \
		.is_equal(AiPlanner.PLAYOUT_MAX_ROUNDS)


# (d) ONE HAND-CHECKABLE BEHAVIOUR — and the divergence it exposes ----------

## Two of my units and one of yours all stand inside the marker's 3" ring in
## the final round; nobody has a weapon, so nobody can change that.
##
## Both rules must answer NEUTRAL. Until 16.08. they did not: the sim counted
## UNITS and gave the marker to the majority (2 beats 1, I win the game),
## while the table rule counts SIDES PRESENT and makes a contested marker
## neutral. That was the fidelity gate's most likely failure and the exact
## shape of the risk the maintainer named — on the sim you could win a marker
## by out-bodying a contest, on the table you cannot, so a policy trained
## there would have learned to do a worthless thing well.
## The sim now follows the book. This test keeps it that way by asking BOTH
## implementations the same question and comparing their answers, rather than
## comparing the sim against a number somebody typed into a test.
func test_a_contested_marker_is_neutral_in_the_sim_exactly_as_on_the_table() -> void:
	var a_pos := [Vector3(1.0 * IN2M, 0, 0)]
	var b_pos := [Vector3(0, 0, 1.0 * IN2M)]
	var foe_pos := [Vector3(0, 0, -1.0 * IN2M)]
	var state := _state([_unit(1, a_pos, "MineA"), _unit(1, b_pos, "MineB"),
		_unit(2, foe_pos, "Yours")], [Vector3.ZERO], 4, 4)
	var got := AiPlanner.full_playout_seeded(state,
		{"unit": "MineA", "kind": AiDecision.Action.HOLD}, 1, 9)
	# TWO OF MINE, ONE OF YOURS, ALL IN THE RING. The sim used to hand this to
	# the majority; the book gives it to nobody. Both must now say NEUTRAL —
	# and the point of asserting them SIDE BY SIDE is that the simulator's
	# answer is checked against the game's own function, not against a number
	# somebody typed into a test.
	assert_int(int((got["objectives"] as Dictionary)["p1"])).is_equal(0)
	assert_int(int((got["objectives"] as Dictionary)["p2"])).is_equal(0)
	assert_int(int((got["objectives"] as Dictionary)["neutral"])).is_equal(1)
	assert_int(int((got["survivors"] as Dictionary)["p1"])).is_equal(2)   # nobody armed, nobody dies
	assert_int(int((got["survivors"] as Dictionary)["p2"])).is_equal(1)
	# THE SAME TABLEAU, judged by the rule the real game uses:
	var table: Array = SoloController.seize_objectives(
		[_row(1, a_pos), _row(1, b_pos), _row(2, foe_pos)], [Vector3.ZERO], [0])["owners"]
	assert_int(int(table[0])).is_equal(0)   # contested -> neutral
	# and the sim agrees with it, which is the whole contract
	assert_int(int(table[0])).is_equal(0 if int((got["objectives"] as Dictionary)["neutral"]) == 1 else -1)


func test_one_side_alone_in_the_ring_still_seizes_it() -> void:
	# The guard on the fix: "contested is neutral" must not become "nothing is
	# ever seized". One side alone, two units, still takes the marker.
	var a_pos := [Vector3(1.0 * IN2M, 0, 0)]
	var b_pos := [Vector3(0, 0, 1.0 * IN2M)]
	var far_pos := [Vector3(0, 0, -30.0 * IN2M)]
	var state := _state([_unit(1, a_pos, "MineA"), _unit(1, b_pos, "MineB"),
		_unit(2, far_pos, "Yours")], [Vector3.ZERO], 4, 4)
	var got := AiPlanner.full_playout_seeded(state,
		{"unit": "MineA", "kind": AiDecision.Action.HOLD}, 1, 9)
	assert_int(int((got["objectives"] as Dictionary)["p1"])).is_equal(1)
	assert_int(int((got["objectives"] as Dictionary)["neutral"])).is_equal(0)
	var table: Array = SoloController.seize_objectives(
		[_row(1, a_pos), _row(1, b_pos), _row(2, far_pos)], [Vector3.ZERO], [0])["owners"]
	assert_int(int(table[0])).is_equal(1)


# (e) THE SEIZE RULE, MEASURED THE BOOK'S WAY -------------------------------
# Added 16.08. under the ruling that the simulator follows the rulebook and
# deviations are not permitted. Each of these was a real divergence: the sim
# measured centre-to-centre in 3D and knew nothing of aircraft or ambush.

func _at(pid: int, x_in: float, y_in: float, z_in: float, uid: String,
		rules: Array = []) -> GameUnit:
	var u := _unit(pid, [Vector3(x_in * IN2M, y_in * IN2M, z_in * IN2M)], uid)
	(u.unit_properties as Dictionary)["special_rules"] = rules
	return u


func _owner(state: Dictionary) -> int:
	var owners := [0]
	BattleSim.playout_seize(state, owners)
	return int(owners[0])


func test_the_ring_is_measured_from_the_base_edge_not_the_model_centre() -> void:
	# A base radius is 0.016 m ~ 0.63". A centre at 3.5" is outside a 3" ring
	# measured centre-to-centre, and INSIDE it measured from the base edge —
	# which is how the book measures (SoloController, bug 11).
	var s := _state([_at(1, 3.5, 0, 0, "Edge")], [Vector3.ZERO], 1, 4)
	assert_int(_owner(s)).is_equal(1)
	# and far enough out that even the base edge misses, nobody seizes
	assert_int(_owner(_state([_at(1, 4.5, 0, 0, "Far")], [Vector3.ZERO], 1, 4))).is_equal(0)


func test_height_does_not_push_a_unit_out_of_the_ring() -> void:
	# MoveIntent.distance_inches ignores y. A model on a 10" ledge directly
	# above the marker holds it; a 3D measure would have thrown it out.
	var s := _state([_at(1, 0, 10.0, 0, "Ledge")], [Vector3.ZERO], 1, 4)
	assert_int(_owner(s)).is_equal(1)


func test_an_aircraft_can_neither_seize_nor_contest() -> void:
	var alone := _state([_at(1, 0.5, 0, 0, "Jet", ["Aircraft"])], [Vector3.ZERO], 1, 4)
	assert_int(_owner(alone)).is_equal(0)          # cannot seize
	# and it cannot CONTEST either: the ground unit keeps the marker
	var contest := _state([_at(1, 0.5, 0, 0, "Jet", ["Aircraft"]),
		_at(2, 0.5, 0, 1.0, "Boots")], [Vector3.ZERO], 1, 4)
	assert_int(_owner(contest)).is_equal(2)


func test_a_unit_that_arrived_from_ambush_this_round_cannot_seize_yet() -> void:
	var u := _at(1, 0.5, 0, 0, "Dropper")
	(u.unit_properties as Dictionary)["ambush_arrived_round"] = 2
	assert_int(_owner(_state([u], [Vector3.ZERO], 2, 4))).is_equal(0)   # arrived THIS round
	# the lock expires with the round — capture stores the ROUND, not a boolean
	assert_int(_owner(_state([u], [Vector3.ZERO], 3, 4))).is_equal(1)


func test_the_sim_and_the_game_agree_on_all_of_it() -> void:
	# The contract is agreement with the game's own function, not with numbers
	# typed into a test. Same tableau, both implementations, same answer.
	var pos := [Vector3(3.5 * IN2M, 0, 0)]
	var s := _state([_at(1, 3.5, 0, 0, "Edge")], [Vector3.ZERO], 1, 4)
	var table: Array = SoloController.seize_objectives(
		[{"player": 1, "positions": pos,
			"radii": [SeparationChecker.DEFAULT_BASE_RADIUS_M]}],
		[Vector3.ZERO], [0])["owners"]
	assert_int(_owner(s)).is_equal(int(table[0]))
	assert_int(int(table[0])).is_equal(1)

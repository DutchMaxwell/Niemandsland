extends GdUnitTestSuite
## What is left of the S-wave playout suite (P4.D-94): the playout's own contract (discriminates, deterministic per seed,
## arbitration on a close top-2) is the core's, pinned by core/nml-core tests/arbitration.rs G5 and tests/plan.rs G4. This file
## keeps the mission-scoring helpers the table also reads: the VP ledger and its flavours, the destroy step, demolition and the
## sabotage winner (BattleSim.vp_*, apply_destroy_step, sabotage_winner: live_helper).

## NML-1008 — VPs decide, not the final tableau: holding rounds 1-3 must
## outscore a last-round steal. Ledger arithmetic pinned directly.
func test_vp_ledger_rewards_early_control() -> void:
	var vp := [0, 0]
	BattleSim.vp_round_add([1, 1, 0], vp)   # R1: A holds 2
	BattleSim.vp_round_add([1, 1, 0], vp)   # R2: A holds 2
	BattleSim.vp_round_add([1, 1, 0], vp)   # R3: A holds 2
	BattleSim.vp_round_add([2, 2, 2], vp)   # R4: B steals everything
	BattleSim.vp_end_bonus([2, 2, 2], vp)   # end bonus goes to B
	assert_int(int(vp[0])).is_equal(6)
	assert_int(int(vp[1])).is_equal(4)
	assert_bool(vp[0] > vp[1]).is_true()    # end-state counting would call B the winner


## NML-1010 W2 — mission flavours of the VP ledger, pinned to the book:
## Domination pays the majority bonus EVERY round; Mosh Pit pays a one-time
## first-seize bonus and no end bonus; the default flavour is byte-for-byte
## the v1 ledger (majority at the end only).
func test_vp_flavour_domination_majority_each_round() -> void:
	var vp := [0, 0]
	var memo := {}
	var fl := {"majority": "round"}
	BattleSim.vp_score_round([1, 1, 1, 0], vp, fl, memo)   # A holds 3 -> +3 +1 majority
	BattleSim.vp_score_round([1, 1, 2, 2], vp, fl, memo)   # 2:2 -> no majority bonus
	BattleSim.vp_score_end([1, 1, 2, 2], vp, fl)           # majority=round: end pays nothing
	assert_int(int(vp[0])).is_equal(6)
	assert_int(int(vp[1])).is_equal(2)


func test_vp_flavour_mosh_pit_first_seize_once() -> void:
	var vp := [0, 0]
	var memo := {}
	var fl := {"majority": "none", "first_seize": true}
	BattleSim.vp_score_round([0], vp, fl, memo)   # R1: nobody on the hill
	BattleSim.vp_score_round([1], vp, fl, memo)   # R2: A seizes first -> +1 +1
	BattleSim.vp_score_round([2], vp, fl, memo)   # R3: B takes it -> +1 only
	BattleSim.vp_score_round([1], vp, fl, memo)   # R4: A again -> +1 only
	BattleSim.vp_score_end([1], vp, fl)           # mosh pit has no end bonus
	assert_int(int(vp[0])).is_equal(3)
	assert_int(int(vp[1])).is_equal(1)


func test_vp_flavour_default_is_the_v1_ledger() -> void:
	var vp := [0, 0]
	var memo := {}
	var fl := {}
	BattleSim.vp_score_round([1, 1, 0], vp, fl, memo)
	BattleSim.vp_score_round([1, 1, 0], vp, fl, memo)
	BattleSim.vp_score_round([1, 1, 0], vp, fl, memo)
	BattleSim.vp_score_round([2, 2, 2], vp, fl, memo)
	BattleSim.vp_score_end([2, 2, 2], vp, fl)
	assert_int(int(vp[0])).is_equal(6)
	assert_int(int(vp[1])).is_equal(4)


## NML-1010 W3 — destructible/owned markers, pinned to the book and the
## maintainer's table clarification (17.08.): Demolition's revenge VP starts
## IN the round the enemy marker falls (own already dead) and repeats every
## round after; destroying first and losing one's own later earns nothing;
## same-round ties break by destruction sequence.
func test_destroy_step_kills_enemy_held_owned_markers() -> void:
	var markers := [
		{"owned_by": 1, "destructible": true, "destroyed": false, "destroyed_seq": 0},
		{"owned_by": 2, "destructible": true, "destroyed": false, "destroyed_seq": 0}]
	var events: Array = BattleSim.apply_destroy_step(markers, [2, 2], [0])
	assert_int(events.size()).is_equal(1)          # only P1's marker falls (enemy 2 holds it)
	assert_bool(bool(markers[0]["destroyed"])).is_true()
	assert_bool(bool(markers[1]["destroyed"])).is_false()   # own holder never destroys it
	BattleSim.apply_destroy_step(markers, [0, 0], [1])      # contested/neutral: nothing happens
	assert_bool(bool(markers[1]["destroyed"])).is_false()


func test_demolition_revenge_pays_from_event_round_onward() -> void:
	var m := [
		{"owned_by": 1, "destructible": true, "destroyed": true, "destroyed_seq": 1},
		{"owned_by": 2, "destructible": true, "destroyed": false, "destroyed_seq": 0}]
	var vp := [0, 0]
	BattleSim.vp_score_round([0, 2], vp, {"mode": "demolition"}, {}, m)   # R2: own dead, no revenge yet
	assert_that(vp).is_equal([0, 1])               # only P2 scores own-alive
	m[1]["destroyed"] = true; m[1]["destroyed_seq"] = 2                   # R3: P1 destroys P2's marker
	BattleSim.vp_score_round([0, 0], vp, {"mode": "demolition"}, {}, m)   # revenge pays THIS round
	BattleSim.vp_score_round([0, 0], vp, {"mode": "demolition"}, {}, m)   # and every round after
	assert_that(vp).is_equal([2, 1])


func test_demolition_destroy_first_lose_later_earns_nothing() -> void:
	var m := [
		{"owned_by": 1, "destructible": true, "destroyed": true, "destroyed_seq": 2},
		{"owned_by": 2, "destructible": true, "destroyed": true, "destroyed_seq": 1}]
	var vp := [0, 0]
	BattleSim.vp_score_round([0, 0], vp, {"mode": "demolition"}, {}, m)
	BattleSim.vp_score_round([0, 0], vp, {"mode": "demolition"}, {}, m)
	assert_that(vp).is_equal([0, 2])   # P2's own fell FIRST (seq 1 < 2): P2 gets revenge, P1 gets nothing


func test_sabotage_winner_matrix() -> void:
	var alive := func(o1: bool, o2: bool) -> Array: return [
		{"owned_by": 1, "destructible": true, "destroyed": not o1, "destroyed_seq": 0},
		{"owned_by": 2, "destructible": true, "destroyed": not o2, "destroyed_seq": 0}]
	assert_str(BattleSim.sabotage_winner(alive.call(true, false))).is_equal("p1")
	assert_str(BattleSim.sabotage_winner(alive.call(false, true))).is_equal("p2")
	assert_str(BattleSim.sabotage_winner(alive.call(true, true))).is_equal("draw")
	assert_str(BattleSim.sabotage_winner(alive.call(false, false))).is_equal("draw")

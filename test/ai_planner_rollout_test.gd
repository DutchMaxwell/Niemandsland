extends GdUnitTestSuite
## R1 (round-rollout search): AiPlanner.rollout plays the rest of the round
## out under the cheap policy, alternating sides like the real rule. The tempo
## discriminator is the whole point: committing the valuable unit FIRST hands
## the un-activated enemy its reply; opening with the cheap unit makes the
## enemy commit before the valuable move, so the end-of-round rich leaf must
## prefer the cheap opener.

const IN2M := 0.0254


func _armed(pid: int, positions: Array, uid: String, weapons: Array) -> GameUnit:
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
	var opr := OPRApiClient.OPRUnit.new()
	for w in weapons:
		var ow := OPRApiClient.OPRWeapon.new()
		ow.name = str((w as Dictionary).get("name", "W"))
		ow.range_value = int((w as Dictionary).get("range", 0))
		ow.attacks = int((w as Dictionary).get("attacks", 4))
		ow.count = 1
		opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


## Marker at 30" from a long-rifle gunline (range 36", 12 attacks = 3 expected
## wounds). My Striker starts 12" behind the marker — OUT of range until it
## rushes on. My Screamer is a worthless far-away single model (the cheap
## opener). Round 1 of 4.
func _state(round_no := 1, rounds_total := 4) -> Dictionary:
	var gunner := _armed(1, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)],
		"Gunner", [{"name": "LongRifle", "range": 36, "attacks": 12}])
	var striker := _armed(2, [Vector3(42.0 * IN2M, 0, 0), Vector3(43.0 * IN2M, 0, 0),
		Vector3(44.0 * IN2M, 0, 0), Vector3(45.0 * IN2M, 0, 0)],
		"Striker", [{"name": "CCW", "range": 0}])
	var screamer := _armed(2, [Vector3(60.0 * IN2M, 0, 30.0 * IN2M)], "Screamer",
		[{"name": "CCW", "range": 0}])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Gunner": gunner, "Striker": striker, "Screamer": screamer}
	return BattleSim.capture(army, func() -> Array: return [Vector3(30.0 * IN2M, 0, 0)],
		func(_i: int) -> int: return 0, round_no, rounds_total)


## CI order-dependence (17.08. wave): solo_controller:2689 sets
## AiPlanner.opener_seat on every planner activation and never resets it —
## production is safe (re-set before every real pick), but THIS suite reads
## _blend_score directly, so it must own the static's documented default.
func before_test() -> void:
	AiPlanner.opener_seat = false


func _leaf(state: Dictionary, me: int) -> float:
	return AiMissionEval.score(state, me, BattleSim.reply_threat(state, me))


func test_rollout_prefers_the_cheap_opener() -> void:
	var state := _state()
	var commit := {"unit": "Striker", "kind": AiDecision.Action.RUSH,
		"dest": Vector3(30.0 * IN2M, 0, 0)}
	var bait := {"unit": "Screamer", "kind": AiDecision.Action.HOLD}
	var end_commit := AiPlanner.rollout(state, commit, 2, 1)   # horizon 1: this test pins IN-round tempo
	var end_bait := AiPlanner.rollout(state, bait, 2, 1)
	# committing first: the un-activated gunline replies into the striker
	assert_int(int((end_commit["units"]["Striker"] as Dictionary)["alive"])).is_equal(1)
	# baiting first: the gunline must commit before the striker enters range
	assert_int(int((end_bait["units"]["Striker"] as Dictionary)["alive"])).is_equal(4)
	assert_float(_leaf(end_bait, 2)).is_greater(_leaf(end_commit, 2))


func test_rollout_activates_everyone_and_leaves_input_untouched() -> void:
	var state := _state()
	var end := AiPlanner.rollout(state,
		{"unit": "Screamer", "kind": AiDecision.Action.HOLD}, 2, 1)   # horizon 1: pins the single-round contract
	for k in end["units"]:
		assert_bool((end["units"][k] as Dictionary)["activated"]) \
			.override_failure_message("%s must have activated by round end" % k).is_true()
	for k in state["units"]:
		assert_bool((state["units"][k] as Dictionary)["activated"]).is_false()


## R2, the pick-level discriminator ON THE LAST ROUND (endgame commit timing):
## the 1-ply plan() rushes the striker straight onto the marker into the
## waiting gunline; plan_with_rollout opens with the bait so the striker
## commits AFTER the gunline spent its activation.
func test_plan_with_rollout_baits_before_committing() -> void:
	var greedy := AiPlanner.plan(_state(4, 4), 2)
	assert_str(str(greedy["unit_key"])).is_equal("Striker")
	assert_int(int((greedy["action"] as Dictionary)["kind"])).is_equal(AiDecision.Action.RUSH)
	var pick := AiPlanner.plan_with_rollout(_state(4, 4), 2)
	assert_str(str(pick["unit_key"])).is_equal("Screamer")
	assert_int(int(pick["waits"])).is_equal(1)   # the striker is deliberately kept back
	# coverage guarantee: even the tiny budget finds the same bait line now
	assert_float(float((pick["expectation"] as Dictionary)["after"])) \
		.is_equal_approx(float((AiPlanner.plan_with_rollout(_state(4, 4), 2, 1)["expectation"] as Dictionary)["after"]), 0.0001)


## top_k <= 0 is the safety valve: byte-identical degrade to plan().
func test_top_k_zero_degrades_to_plain_plan() -> void:
	assert_that(AiPlanner.plan_with_rollout(_state(), 2, 0)).is_equal(AiPlanner.plan(_state(), 2))


## Diagnosis 07.08.: the mental game must be able to PUNISH commitment. A
## squad rushing the marker lands inside the brute's charge reach — in the
## rollout the brute counter-charges and the squad bleeds. Without charges in
## the policy the commit would look free (that bug drove real round-1 losses).
func test_rollout_opponent_counter_charges_commitment() -> void:
	var brute := _armed(1, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)],
		"Brute", [{"name": "Claws", "range": 0, "attacks": 12}])
	var squad := _armed(2, [Vector3(22.0 * IN2M, 0, 0), Vector3(23.0 * IN2M, 0, 0),
		Vector3(24.0 * IN2M, 0, 0), Vector3(25.0 * IN2M, 0, 0)],
		"Squad", [{"name": "CCW", "range": 0}])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Brute": brute, "Squad": squad}
	var state := BattleSim.capture(army, func() -> Array: return [Vector3(10.0 * IN2M, 0, 0)],
		func(_i: int) -> int: return 0, 1, 4)
	var end := AiPlanner.rollout(state,
		{"unit": "Squad", "kind": AiDecision.Action.RUSH, "dest": Vector3(10.0 * IN2M, 0, 0)}, 2)
	assert_int(int((end["units"]["Squad"] as Dictionary)["alive"])) 		.override_failure_message("the brute must counter-charge the committed squad in the rollout") 		.is_less(4)


## Coverage guarantee: every un-activated unit gets a rollout even when the
## global TOP_K budget is 1 — bait moves rank low 1-ply and must never be
## prefiltered out of the tempo search.
func test_every_unit_is_rolled_out_even_with_tiny_top_k() -> void:
	var pick := AiPlanner.plan_with_rollout(_state(4, 4), 2, 1)
	var rolled: Array = pick["rolled_units"]
	rolled.sort()
	assert_that(rolled).is_equal(["Screamer", "Striker"])
	assert_str(str(pick["unit_key"])).is_equal("Screamer")   # the bait wins despite top_k=1


# === R6: cross-round horizon (parity wave depth rung, NML-995) ===

## The default rollout now plays INTO the following round: the returned state
## carries round 2 with every unit activation-spent again (round 2 was played
## to its end); the explicit horizon 1 stays on round 1 (the safety valve);
## the input state is never touched.
func test_rollout_default_horizon_crosses_into_the_next_round() -> void:
	var state := _state()
	var bait := {"unit": "Screamer", "kind": AiDecision.Action.HOLD}
	var end := AiPlanner.rollout(state, bait, 2)
	assert_int(int(end["round"])).is_equal(2)
	for k in end["units"]:
		if int((end["units"][k] as Dictionary)["alive"]) > 0:
			assert_bool((end["units"][k] as Dictionary)["activated"]).is_true()
	assert_int(int(AiPlanner.rollout(state, bait, 2, 1)["round"])).is_equal(1)
	assert_int(int(state["round"])).is_equal(1)


## The horizon never invents rounds past the game: on the last round the
## default rollout ends exactly there.
func test_horizon_stops_at_game_end() -> void:
	var end := AiPlanner.rollout(_state(4, 4),
		{"unit": "Screamer", "kind": AiDecision.Action.HOLD}, 2)
	assert_int(int(end["round"])).is_equal(4)


## _cross_round: round counter up, activation + fatigue wiped, and the OPENER
## of the imagined new round is the side that finished first — the one with
## fewer alive units under strict alternation (here: player 1 with its single
## gunline vs player 2's two units).
func test_cross_round_resets_flags_and_hands_the_opener_to_the_smaller_side() -> void:
	var state := _state()
	for k in state["units"]:
		var su: Dictionary = state["units"][k]
		su["activated"] = true
		su["fatigued"] = true
	var opener := AiPlanner._cross_round(state)
	assert_int(int(state["round"])).is_equal(2)
	assert_int(opener).is_equal(1)
	for k in state["units"]:
		assert_bool((state["units"][k] as Dictionary)["activated"]).is_false()
		assert_bool((state["units"][k] as Dictionary)["fatigued"]).is_false()


# === R7: discounted multi-round leaf (NML-995) ===

## rollout_boundaries returns one true round-end per horizon round (rounds 1
## then 2), the last entry IS rollout()'s result, and horizon 1 yields exactly
## the single round-end.
func test_rollout_boundaries_one_state_per_round() -> void:
	var state := _state()
	var bait := {"unit": "Screamer", "kind": AiDecision.Action.HOLD}
	var ends := AiPlanner.rollout_boundaries(state, bait, 2)
	assert_int(ends.size()).is_equal(2)
	assert_int(int((ends[0] as Dictionary)["round"])).is_equal(1)
	assert_int(int((ends[1] as Dictionary)["round"])).is_equal(2)
	assert_float(_leaf(ends[1], 2)).is_equal_approx(_leaf(AiPlanner.rollout(state, bait, 2), 2), 0.0001)
	var flat := AiPlanner.rollout_boundaries(state, bait, 2, 1)
	assert_int(flat.size()).is_equal(1)
	assert_int(int((flat[0] as Dictionary)["round"])).is_equal(1)


## The blend is the normalized geometric discount: one state = its plain leaf;
## two states = (l1 + 0.5*l2) / 1.5 — the current round keeps the 2/3
## majority, the imagined round refines instead of outvoting.
func test_blend_score_discounts_the_deeper_round() -> void:
	var near := _state()
	var far := AiPlanner.rollout(near, {"unit": "Screamer", "kind": AiDecision.Action.HOLD}, 2, 1)
	var l1 := _leaf(near, 2)
	var l2 := _leaf(far, 2)
	assert_float(AiPlanner._blend_score([near], 2)).is_equal_approx(l1, 0.0001)
	assert_float(AiPlanner._blend_score([near, far], 2)).is_equal_approx((l1 + 0.5 * l2) / 1.5, 0.0001)


# === R8: the patient advance (opener diagnosis, NML-995) ===

## Tier 1: gun reach = 36 + 6 advance = 42" — from 50" walk the full 6" (ends
## 44", safe), from 45" clamp at 2.5". Tier 2 (gun safety already lost):
## charge reach = rush 12" + 1" contact = 13" — from 40" walk the full 6",
## from 17.2" clamp at 4.0" (13.2" > 13"). Inside charge reach (10"): no
## patient candidate.
func test_safe_advance_walks_up_but_stays_outside_threat_reach() -> void:
	var gunner := _armed(1, [Vector3.ZERO], "Gunner", [{"name": "LongRifle", "range": 36}])
	for cfg in [[50.0, 6.0], [45.0, 2.5], [40.0, 6.0], [17.2, 4.0], [10.0, -1.0]]:
		var mine := _armed(2, [Vector3(float(cfg[0]) * IN2M, 0, 0)], "Mine", [{"name": "CCW", "range": 0}])
		var army: OPRArmyManager = auto_free(OPRArmyManager.new())
		army.game_units = {"Gunner": gunner, "Mine": mine}
		var state := BattleSim.capture(army, func() -> Array: return [Vector3.ZERO],
			func(_i: int) -> int: return 0, 1, 4)
		var cand := AiPlanner._safe_advance(state, "Mine")
		if float(cfg[1]) < 0.0:
			assert_bool(cand.is_empty()).override_failure_message(
				"inside reach at %s\" must yield no patient candidate" % cfg[0]).is_true()
			continue
		assert_bool(cand.is_empty()).override_failure_message(
			"from %s\" a patient candidate must exist" % cfg[0]).is_false()
		if cand.is_empty():
			continue
		assert_int(int(cand["kind"])).is_equal(AiDecision.Action.ADVANCE)
		var walked: float = (float(cfg[0]) * IN2M - (cand["dest"] as Vector3).x) / IN2M
		assert_float(walked).override_failure_message(
			"from %s\" expected %s\" walked, got %s" % [cfg[0], cfg[1], walked]).is_equal_approx(float(cfg[1]), 0.01)


## The rollout's self-model can now imagine patience: the policy candidate set
## of a safe far unit contains the clamped ADVANCE.
func test_policy_candidates_include_the_patient_advance() -> void:
	var gunner := _armed(1, [Vector3.ZERO], "Gunner", [{"name": "LongRifle", "range": 36}])
	var mine := _armed(2, [Vector3(50.0 * IN2M, 0, 0)], "Mine", [{"name": "CCW", "range": 0}])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Gunner": gunner, "Mine": mine}
	var state := BattleSim.capture(army, func() -> Array: return [Vector3.ZERO],
		func(_i: int) -> int: return 0, 1, 4)
	var kinds: Array = []
	for c in AiPlanner._policy_candidates(state, "Mine"):
		kinds.append(int((c as Dictionary)["kind"]))
	assert_bool(kinds.has(AiDecision.Action.ADVANCE)).override_failure_message(
		"policy candidates must contain the patient ADVANCE, got kinds %s" % [kinds]).is_true()


## The patient candidate must SURVIVE the 1-ply prefilter (same lesson as the
## bait coverage): rushing at the brute's marker ends inside its charge reach
## and gets mauled in the playout; the patient advance stays uncharged. With
## top_k=1 the rush wins 1-ply — only a pool guarantee lets patience win the
## blend. Fixup2 review (doc-only): the repaired fixture's patient move lands
## at ~14.51", clear of the reach, so it does not clamp -- coverage of
## _safe_advance's own clamping is not exercised here since S1b (a clamped
## landing on the 0.5" grid always lands in (13.0", 13.5"], never clear of
## the 13.51" reach).
func test_patient_advance_survives_the_prefilter_and_wins() -> void:
	var brute := _armed(1, [Vector3.ZERO, Vector3(1.0 * IN2M, 0, 0), Vector3(2.0 * IN2M, 0, 0)],
		"Brute", [{"name": "Claws", "range": 0, "attacks": 12}])
	# NML-1073 S1b repair: _safe_advance's own threat ESTIMATE is untouched (band
	# 12" + BattleSim.CONTACT_IN 1.0" = 13.0"), but resolve()'s corrected melee
	# trigger needs band + radii_sum (1.26", two 32mm bases) + CHARGE_CONTACT_
	# MARGIN_IN (0.25") = 13.51" to actually land a charge -- 0.51" farther than
	# the old flat estimate. The OLD fixture (17.2..20.2") left the patient move
	# only 0.2" past the OLD 13.0" estimate (13.2" landed gap) -- inside the NEW
	# 13.51" true reach, so the playout mauled the "safe" candidate too. Moved
	# 5.31" farther out so the patient's full 6" advance (still governed by the
	# unchanged 13.0" estimate, comfortably inside its own "stays safe the whole
	# advance" regime) lands at ~14.51" -- ~1.0" clear of the new 13.51" reach.
	var squad := _armed(2, [Vector3(22.51 * IN2M, 0, 0), Vector3(23.51 * IN2M, 0, 0),
		Vector3(24.51 * IN2M, 0, 0), Vector3(25.51 * IN2M, 0, 0)],
		"Squad", [{"name": "CCW", "range": 0}])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Brute": brute, "Squad": squad}
	var state := BattleSim.capture(army, func() -> Array: return [Vector3.ZERO],
		func(_i: int) -> int: return 0, 1, 4)
	var pick := AiPlanner.plan_with_rollout(state, 2, 1)
	assert_bool(bool(pick.get("used", false))).is_true()
	var act: Dictionary = pick["action"]
	assert_bool(bool(act.get("patient", false))).override_failure_message(
		"expected the PATIENT advance to win, got kind=%d dest=%s" % [
		int(act.get("kind", -1)), str(act.get("dest", "?"))]).is_true()


# === R9: danger-aware self-model (NML-995) ===

## A 12"-gun watches the marker. The CHEAP policy step (danger-blind) rushes
## our squad toward the marker into gun range; the RICH step prices the
## shooting reply and keeps the squad out of it. The self-model must use the
## rich step — otherwise every imagined future overextends our own army.
func test_rich_policy_step_avoids_the_gun_the_cheap_one_walks_into() -> void:
	var gunner := _armed(1, [Vector3.ZERO], "Gunner", [{"name": "ShortGun", "range": 12, "attacks": 8}])
	var squad := _armed(2, [Vector3(19.0 * IN2M, 0, 0), Vector3(20.0 * IN2M, 0, 0),
		Vector3(21.0 * IN2M, 0, 0), Vector3(22.0 * IN2M, 0, 0)],
		"Squad", [{"name": "CCW", "range": 0}])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Gunner": gunner, "Squad": squad}
	var state := BattleSim.capture(army, func() -> Array: return [Vector3.ZERO],
		func(_i: int) -> int: return 0, 1, 4)
	var cheap := AiPlanner._policy_step(state, 2)
	assert_int(int(cheap.get("kind", -1))).override_failure_message(
		"cheap step should rush the marker (danger-blind)").is_equal(AiDecision.Action.RUSH)
	var rich := AiPlanner._policy_step(state, 2, true)
	assert_bool(int(rich.get("kind", -1)) == AiDecision.Action.RUSH).override_failure_message(
		"rich step must NOT rush into the 12\"-gun's reply").is_false()


# === D-wave: seat-aware leaf weighting (NML-995) ===

## Opener seat: the LAST boundary alone votes (R6 mode — proven best opener
## seat); responder seat keeps the discounted blend (R7 — proven best
## responder). The static must default to responder mode.
## U-wave (24.08.) promoted seat_off (both seats blend) to default; this test
## pins the researched opener last-boundary mode via NML_SEAT_DEPTH=on.
func test_seat_aware_blend_last_boundary_votes_alone_for_the_opener() -> void:
	OS.set_environment("NML_SEAT_DEPTH", "on")
	AiPlanner._seat_env = -1
	var near := _state()
	var far := AiPlanner.rollout(near, {"unit": "Screamer", "kind": AiDecision.Action.HOLD}, 2, 1)
	var l1 := _leaf(near, 2)
	var l2 := _leaf(far, 2)
	assert_bool(AiPlanner.opener_seat).is_false()
	AiPlanner.opener_seat = true
	var deep := AiPlanner._blend_score([near, far], 2)
	AiPlanner.opener_seat = false
	assert_float(deep).is_equal_approx(l2, 0.0001)
	assert_float(AiPlanner._blend_score([near, far], 2)).is_equal_approx((l1 + 0.5 * l2) / 1.5, 0.0001)
	OS.set_environment("NML_SEAT_DEPTH", "")
	AiPlanner._seat_env = -1


## Opener-doctrine probe: each arm produces its forced round-1 shape — rush
## aims at the nearest marker, hold stands, screen sends the CHEAPEST unit
## first, patient safe-advances. plan()-shaped result so the pick path can
## consume it unchanged.
func test_doctrine_pick_arms() -> void:
	var state := _state()
	var rush := AiPlanner.doctrine_pick(state, 2, "rush")
	assert_int(int((rush["action"] as Dictionary)["kind"])).is_equal(AiDecision.Action.RUSH)
	var hold := AiPlanner.doctrine_pick(state, 2, "hold")
	assert_int(int((hold["action"] as Dictionary)["kind"])).is_equal(AiDecision.Action.HOLD)
	var screen := AiPlanner.doctrine_pick(state, 2, "screen")
	assert_str(str(screen["unit_key"])).is_equal("Screamer")   # 1 wound < striker's 4
	var patient := AiPlanner.doctrine_pick(state, 2, "patient")
	var pk := int((patient["action"] as Dictionary)["kind"])
	assert_bool(pk == AiDecision.Action.ADVANCE or pk == AiDecision.Action.HOLD).is_true()


## Leaf-row seam (glasses v4): plan_with_rollout stashes the winning
## candidate's horizon-end state — non-empty, a real state, at/after the
## root round; reset on entry so stale picks never leak.
## NML-1073 M2-0b: and the consumer TAKES it — take_last_leaf() hands the leaf
## over and empties the static in the same call, so no live state (GameUnit
## refs, the controller's Callables) is left in a script static for process
## teardown to free after its bound objects are gone (exit-134 heap corruption).
func test_plan_with_rollout_stashes_the_winning_leaf() -> void:
	var state := _state()
	AiPlanner._last_leaf_state = {"stale": true}
	var pick := AiPlanner.plan_with_rollout(state, 2)
	assert_bool(bool(pick.get("used", false))).is_true()
	var leaf := AiPlanner.take_last_leaf()
	assert_bool(leaf.has("units")).is_true()
	assert_bool(leaf.has("stale")).is_false()
	assert_int(int(leaf["round"])).is_greater_equal(int(state["round"]))
	assert_bool(AiPlanner._last_leaf_state.is_empty()).is_true()


func test_charge_illegal_callable_filters_the_menu() -> void:
	# Head wave 1: a controller-provided legality callable removes forbidden charge
	# victims from the candidate menu; without the key the menu is byte-identical
	# (lab tests and old snapshots keep their behaviour). Two melee units in easy
	# reach: baseline menu MUST contain a CHARGE, the always-illegal state none.
	var a := _armed(1, [Vector3.ZERO], "Brawler", [{"name": "CCW", "range": 0}])
	var b := _armed(2, [Vector3(3.0 * IN2M, 0, 0)], "Victim", [{"name": "CCW", "range": 0}])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Brawler": a, "Victim": b}
	var state := BattleSim.capture(army, func() -> Array: return [],
		func(_i: int) -> int: return 0, 1, 4)
	var akey := ""
	for k in state["units"]:
		if (state["units"][k] as Dictionary)["unit"] == a:
			akey = str(k)
	var kinds_plain: Array = AiPlanner.candidates(state, akey).map(
		func(c: Dictionary) -> int: return int(c["kind"]))
	assert_bool(kinds_plain.has(AiDecision.Action.CHARGE)).is_true()
	state["charge_illegal"] = func(_u: GameUnit, _t: GameUnit, _gap: float,
			_from: Vector3, _to: Vector3) -> bool: return true
	var kinds_gated: Array = AiPlanner.candidates(state, akey).map(
		func(c: Dictionary) -> int: return int(c["kind"]))
	assert_bool(kinds_gated.has(AiDecision.Action.CHARGE)).is_false()


## NML-1073 S1b/S1d: the charge-candidate gate's `gap_in` argument must be the
## table's RAW EDGE gap (radii-aware) — the very quantity the table's own
## re-gate passes (charge_illegal_why -> nearest_melee_gap_in, no slack), not
## centre distance minus the flat BattleSim.CONTACT_IN (1.0", only right for
## ~25 mm bases) and not the edge gap minus the 0.25" contact epsilon S1b
## subtracted. Two 50 mm bases (radius 0.025 m) 12.5" apart edge-to-edge sit at
## a 14.47" centre distance: the pre-S1b gate received 13.47", S1b's 12.25",
## and the table-mirroring gate 12.5".
func test_charge_gate_receives_the_base_edge_gap_not_centre_distance() -> void:
	var a := _armed(1, [Vector3.ZERO], "Brawler", [{"name": "CCW", "range": 0}])
	var b := _armed(2, [Vector3(14.468504 * IN2M, 0, 0)], "Victim", [{"name": "CCW", "range": 0}])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Brawler": a, "Victim": b}
	var state := BattleSim.capture(army, func() -> Array: return [],
		func(_i: int) -> int: return 0, 1, 4)
	(state["units"]["Brawler"] as Dictionary)["radii"] = [0.025]
	(state["units"]["Victim"] as Dictionary)["radii"] = [0.025]
	var akey := ""
	for k in state["units"]:
		if (state["units"][k] as Dictionary)["unit"] == a:
			akey = str(k)
	var seen_gap := [-1.0]   # Array: a lambda captures an outer scalar BY VALUE, not by reference
	state["charge_illegal"] = func(_u: GameUnit, _t: GameUnit, gap: float,
			_from: Vector3, _to: Vector3) -> bool:
		seen_gap[0] = gap
		return false
	AiPlanner.candidates(state, akey)
	assert_float(seen_gap[0]).is_equal_approx(12.5, 0.01)


func test_net_guided_playout_picks_within_the_menu_and_is_deterministic() -> void:
	# Net-guided playouts (head wave 1+): with a net loaded, _policy_step routes
	# through the Feldherrenblick, which chooses WITHIN each unit's candidate menu —
	# so the result must be one of that unit's own candidates, and two identical
	# calls must agree (deterministic policy steps are what rollout caching relies
	# on). playout_net is a static: reset guarded even on assert failure.
	var net := JSON.parse_string(FileAccess.get_file_as_string(
		"res://test/data/clone_parity.json")) as Dictionary
	var state := _state()
	AiPlanner.playout_net = net
	var a1: Dictionary = AiPlanner._policy_step(state, 2)
	var a2: Dictionary = AiPlanner._policy_step(state, 2)
	AiPlanner.playout_net = {}
	assert_bool(a1.is_empty()).is_false()
	assert_str(str(a1)).is_equal(str(a2))
	var legal := false
	for c in AiPlanner._policy_candidates(state, str(a1["unit"])):
		if str(c) == str(a1):
			legal = true
	assert_bool(legal).is_true()

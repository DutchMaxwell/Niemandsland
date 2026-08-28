extends GdUnitTestSuite
## AI ARENA — the difficulty knobs wired into the real SoloController decision path, plus a headless both-AI
## driver smoke. Proves: per-side presets apply and flip with the acting side; a weak grade (Rekrut) NEVER
## makes an illegal target choice (it only ever picks from the OFFICIAL tied set); the pick is reproducible
## for a fixed seed; the DEFAULT (no difficulty) path is the sharp max-EV pick; and a both-AI game runs to
## the scoring end unattended. Determinism lives game-side; the mirror SIM never constructs a SoloDifficulty.


func _unit(pid: int, positions: Array, uid: String = "") -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid if uid != "" else "p%d_%d" % [pid, positions.size()]
	u.unit_properties = {"player_id": pid, "name": (uid if uid != "" else "U%d" % pid),
		"quality": 4, "defense": 4, "special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	return u


func _army(units: Array) -> OPRArmyManager:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	army.current_round = 1
	return army


# === Per-side difficulty ===

func test_per_side_difficulty_flips_with_the_acting_side() -> void:
	var ai := _unit(2, [Vector3(0.5, 0, 0)])
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(_army([ai]), null, null, 1, 2)
	solo.difficulty_seed = 3
	var d1 := SoloDifficulty.for_grade("nachtmahr", 3)
	d1.grade_name = "side-one"   # NML-211: labels only — both sides play NACHTMAHR knobs
	var d2 := SoloDifficulty.for_grade("nachtmahr", 3)
	d2.grade_name = "side-two"
	solo.set_difficulty(1, d1)
	solo.set_difficulty(2, d2)
	# The active difficulty is side-indexed: acting side flips, the mapping follows.
	solo.ai_slot = 2
	assert_str(solo.active_difficulty().grade_name).is_equal("side-two")
	solo.ai_slot = 1
	assert_str(solo.active_difficulty().grade_name).is_equal("side-one")
	# No difficulty configured for a slot → null (the byte-identical default AI).
	solo.difficulty_by_slot.erase(1)
	assert_object(solo.active_difficulty()).is_null()


# === A genuine target tie: two equidistant, not-activated enemies; plus a nearer ACTIVATED one and a far one ===

func _tie_controller(grade: String, seed_value: int) -> Array:
	var a := _unit(1, [Vector3(0.30, 0, 0)], "A")     # not-activated, band 11
	var b := _unit(1, [Vector3(0, 0, 0.30)], "B")     # not-activated, band 11 (genuine tie with A)
	var far := _unit(1, [Vector3(0.60, 0, 0)], "Far") # band 23 — never tied
	var near_act := _unit(1, [Vector3(0.10, 0, 0)], "NearActivated")
	near_act.is_activated = true                       # nearer but activated → the official key excludes it
	var ai := _unit(2, [Vector3(0, 0, 0)], "AI")
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(_army([a, b, far, near_act, ai]), null, null, 1, 2)
	solo.difficulty_seed = seed_value
	if grade != "":
		solo.set_difficulty(2, SoloDifficulty.for_grade(grade, seed_value))
	return [solo, ai]


func test_noisy_target_pick_is_always_a_legal_tied_candidate() -> void:
	# NML-211: legality sweep of the NOISE machinery (persona rebuild ground) — across many seeds a
	# noisy/spread knob set only ever selects from the OFFICIAL tied set {A, B}, never the
	# nearer-but-activated unit nor the far one. And the noise DOES bite: both get chosen.
	var pack := _tie_controller("nachtmahr", 100)
	var solo: SoloController = pack[0]
	var ai: GameUnit = pack[1]
	var noisy := SoloDifficulty.new()
	noisy.grade_name = "noisy-tier"
	noisy.ev_noise = 0.40
	noisy.mission_focus = 0.35
	noisy.coordination = 0.0
	solo.difficulty_by_slot[2] = noisy
	var picked := {}
	for s in range(300):
		solo.difficulty_by_slot[2].base_seed = s
		var chosen: GameUnit = solo.nearest_human_unit(ai)
		var chosen_name := chosen.get_name()
		assert_bool(chosen_name == "A" or chosen_name == "B").override_failure_message(
			"noisy pick chose an ILLEGAL target '%s' (not in the tied set) at seed %d" % [chosen_name, s]).is_true()
		picked[chosen_name] = true
	assert_bool(picked.has("A")).is_true()
	assert_bool(picked.has("B")).is_true()   # the deviation actually happens


func test_kriegsherr_is_deterministic_and_reproducible() -> void:
	# The ceiling grade never deviates: the pick is identical across every seed, and identical between two
	# independent controllers with the same seed (reproducibility).
	var pack := _tie_controller("kriegsherr", 5)
	var solo: SoloController = pack[0]
	var ai: GameUnit = pack[1]
	var first := solo.nearest_human_unit(ai).get_name()
	for s in range(50):
		solo.difficulty_by_slot[2].base_seed = s
		assert_str(solo.nearest_human_unit(ai).get_name()).is_equal(first)


func test_default_null_difficulty_is_the_sharp_pick() -> void:
	# With NO difficulty configured, the tie resolves to the earliest maximum-EV candidate (the pre-existing
	# behaviour) — A here (equal EV → tie order). Kriegsherr, lacking any overlay-relevant weapon, matches it.
	var pack := _tie_controller("", 0)
	var solo: SoloController = pack[0]
	var ai: GameUnit = pack[1]
	assert_object(solo.active_difficulty()).is_null()
	assert_str(solo.nearest_human_unit(ai).get_name()).is_equal("A")
	solo.set_difficulty(2, SoloDifficulty.for_grade("kriegsherr", 0))
	assert_str(solo.nearest_human_unit(ai).get_name()).is_equal("A")


# === Official deployment roll-off (each player rolls a die, higher wins, tied dice roll again) ===
# The round-1 opener rule: the roll-off winner deploys first AND opens round 1 — the arena launcher
# passes SoloController.roll_off() through to main._solo_run_both_ai_game(first_opener).

func test_roll_off_high_die_wins_and_a_tie_rerolls() -> void:
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	# Scripted dice: the first pair TIES (3,3) → the official procedure re-rolls; the second pair is
	# decisive (5 vs 2) → P1 wins. Exactly 4 dice must have been consumed (the tie really re-rolled).
	var script: Array = [3, 3, 5, 2]
	var drawn := {"n": 0}
	var roller := func() -> int:
		drawn["n"] = int(drawn["n"]) + 1
		return int(script[int(drawn["n"]) - 1])
	assert_int(solo.roll_off(roller)).is_equal(1)
	assert_int(int(drawn["n"])).is_equal(4)
	var records: Array = solo.drain_decisions()
	assert_int(records.size()).is_equal(2)   # one record per pair: the tie, then the decisive roll
	assert_str(str((records[0] as Dictionary).get("chosen"))).contains("re-roll")
	# A decisive first pair with P2 higher → P2 wins after exactly one pair.
	var script2: Array = [2, 6]
	var drawn2 := {"n": 0}
	var roller2 := func() -> int:
		drawn2["n"] = int(drawn2["n"]) + 1
		return int(script2[int(drawn2["n"]) - 1])
	assert_int(solo.roll_off(roller2)).is_equal(2)
	assert_int(int(drawn2["n"])).is_equal(2)


func test_roll_off_default_rng_is_seed_reproducible() -> void:
	# The default roller draws from the controller's seeded _rng: same seed ⇒ same winner (the ladder's
	# reproducibility contract), and the winner is always a valid slot.
	var a: SoloController = auto_free(SoloController.new())
	add_child(a)
	var b: SoloController = auto_free(SoloController.new())
	add_child(b)
	a._rng.seed = 42
	b._rng.seed = 42
	var w: int = a.roll_off()
	assert_bool(w == 1 or w == 2).is_true()
	assert_int(b.roll_off()).is_equal(w)


func test_decision_sink_mirrors_records_without_touching_the_drain() -> void:
	# The harness capture hook: a configured sink sees every record at record time, while the dev-toggle
	# drain path keeps working unchanged (the sink is a mirror, not a diversion).
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	var seen: Array = []
	solo.decision_sink = func(rec: Dictionary) -> void: seen.append(rec)
	solo.record_decision({"kind": "probe", "unit": "U"})
	assert_int(seen.size()).is_equal(1)
	assert_str(str((seen[0] as Dictionary).get("kind"))).is_equal("probe")
	assert_int(solo.drain_decisions().size()).is_equal(1)


# === Both-AI headless game completion (minimal controller-level driver) ===

func test_both_ai_game_completes_headless_over_four_rounds() -> void:
	# Two AI armies (both sides), graded Rekrut vs Kriegsherr. Drive the OPR alternation at the controller
	# level across 4 rounds: flip the acting side + its enemy each activation, activate until both sides are
	# exhausted, reset for the next round. Proves the both-AI flow terminates unattended and activates every
	# unit each round (the native driver's core loop, without the dice tray which lives in main.gd).
	var p1a := _unit(1, [Vector3(-0.5, 0, 0.2)], "P1a")
	var p1b := _unit(1, [Vector3(-0.5, 0, -0.2)], "P1b")
	var p2a := _unit(2, [Vector3(0.5, 0, 0.2)], "P2a")
	var p2b := _unit(2, [Vector3(0.5, 0, -0.2)], "P2b")
	var army := _army([p1a, p1b, p2a, p2b])
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	solo.difficulty_seed = 777
	solo.set_difficulty(1, SoloDifficulty.for_grade("rekrut", 777))
	solo.set_difficulty(2, SoloDifficulty.for_grade("kriegsherr", 777))

	var all_units: Array = [p1a, p1b, p2a, p2b]
	var total_activations := 0
	const GAME_ROUNDS := 4
	for round_no in range(1, GAME_ROUNDS + 1):
		for u in all_units:
			(u as GameUnit).is_activated = false
		army.current_round = round_no
		var side := 1 if round_no % 2 == 1 else 2   # opener alternates
		var guard := 0
		while guard < 100:
			guard += 1
			var other := 2 if side == 1 else 1
			solo.ai_slot = side
			solo.human_slot = other
			var side_has := not solo.eligible_ai_units().is_empty()
			solo.ai_slot = other
			solo.human_slot = side
			var other_has := not solo.eligible_ai_units().is_empty()
			if not side_has and not other_has:
				break
			var act := side if side_has else other
			solo.ai_slot = act
			solo.human_slot = 2 if act == 1 else 1
			var unit: GameUnit = solo.activate_next_ai_unit()
			if unit != null:
				total_activations += 1
			side = 2 if act == 1 else 1
		# Every unit acted this round.
		for u in all_units:
			assert_bool((u as GameUnit).is_activated).override_failure_message(
				"%s never activated in round %d" % [(u as GameUnit).get_name(), round_no]).is_true()
	# 4 units × 4 rounds = 16 activations, and the driver terminated (no guard blow-out).
	assert_int(total_activations).is_equal(16)


func test_activation_counter_is_monotonic_for_deterministic_draws() -> void:
	# The per-activation seed part (_activation_seq) increments on every activation, so two activations of the
	# same unit draw different knob values — the reproducibility unit that makes a whole match replay.
	var ai := _unit(2, [Vector3(0.5, 0, 0)], "AI")
	var human := _unit(1, [Vector3(0, 0, 0)], "H")
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(_army([ai, human]), null, null, 1, 2)
	assert_int(solo._activation_seq).is_equal(0)
	solo.activate_next_ai_unit()
	assert_int(solo._activation_seq).is_equal(1)


# === Planner calibration pairing (parity wave, NML-995) ===

const ArenaMatch := preload("res://tools/arena_match.gd")


func _calib(side: int, round_no: int, before: float, after: float) -> Dictionary:
	return {"side": side, "round": round_no, "before": before, "after": after}


func test_calib_pairs_last_forecast_meets_first_measurement_per_side() -> void:
	# Round 1 has two picks (the boundary must use the LAST one's forecast); round 2's FIRST pick
	# carries the measurement. Side 2 interleaves and must pair independently of side 1.
	var pairs: Array = ArenaMatch.calib_pairs([
		_calib(1, 1, 0.50, 0.55),
		_calib(2, 1, 0.50, 0.48),
		_calib(1, 1, 0.52, 0.40),   # last side-1 record of round 1 → its forecast
		_calib(1, 2, 0.21, 0.30),   # first side-1 record of round 2 → its measurement
		_calib(1, 2, 0.35, 0.36),   # later round-2 record must NOT re-pair
		_calib(2, 3, 0.60, 0.70),   # side 2 jumps 1→3: still one boundary pair
	])
	assert_int(pairs.size()).is_equal(2)
	var p1: Dictionary = pairs[0]
	assert_int(int(p1["side"])).is_equal(1)
	assert_int(int(p1["from_round"])).is_equal(1)
	assert_int(int(p1["to_round"])).is_equal(2)
	assert_float(float(p1["predicted"])).is_equal_approx(0.40, 0.0001)
	assert_float(float(p1["measured"])).is_equal_approx(0.21, 0.0001)
	assert_float(float(p1["gap"])).is_equal_approx(-0.19, 0.0001)
	var p2: Dictionary = pairs[1]
	assert_int(int(p2["side"])).is_equal(2)
	assert_int(int(p2["from_round"])).is_equal(1)
	assert_int(int(p2["to_round"])).is_equal(3)
	assert_float(float(p2["predicted"])).is_equal_approx(0.48, 0.0001)
	assert_float(float(p2["measured"])).is_equal_approx(0.60, 0.0001)


func test_calib_pairs_without_a_boundary_is_empty() -> void:
	# All records in one round (and an empty stream): nothing to compare, nothing invented.
	assert_array(ArenaMatch.calib_pairs([])).is_empty()
	assert_array(ArenaMatch.calib_pairs([
		_calib(1, 2, 0.5, 0.6), _calib(1, 2, 0.6, 0.7)])).is_empty()


# === NML-1002: first deployer's Ambush reserve must survive the second begin ===

## Both-AI games share one controller: side 1 deploys (its Ambush unit goes
## to reserve), then side 2's deploy_begin runs — before the fix that begin
## wiped side 1's reserve, deleting the unit from the game. Now the reserve
## is side-scoped: begin clears only its own entries, ready() counts only the
## active side.
func test_second_deploy_begin_keeps_first_sides_ambush_reserve() -> void:
	var a1 := _unit(1, [Vector3(0, 0, 0)], "A1")
	a1.unit_properties["special_rules"] = ["Ambush"]
	var a2 := _unit(1, [Vector3(0.3, 0, 0)], "A2")
	var b1 := _unit(2, [Vector3(0, 0, 1.0)], "B1")
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(_army([a1, a2, b1]), null, null, 1, 2)
	var zone1 := Rect2(Vector2(-1, -1), Vector2(2, 0.3))
	var zone2 := Rect2(Vector2(-1, 0.7), Vector2(2, 0.3))
	var none := func(_p: Vector2) -> bool: return false
	solo.ai_slot = 1
	solo.human_slot = 2
	solo.deploy_army(zone1, [], none, none, 7)
	assert_int(solo.ambush_reserve.size()).override_failure_message(
		"side 1's Ambush unit must be reserved").is_equal(1)
	solo.ai_slot = 2
	solo.human_slot = 1
	solo.deploy_army(zone2, [], none, none, 8)
	assert_int(solo.ambush_reserve.size()).override_failure_message(
		"side 2's begin must NOT wipe side 1's reserve").is_equal(1)
	assert_int(solo.ambush_reserve_ready(2)).override_failure_message(
		"ready() counts only the ACTIVE side (slot 2 has no reserves)").is_equal(0)
	solo.ai_slot = 1
	assert_int(solo.ambush_reserve_ready(2)).is_equal(1)


# === Deploy record honesty: whose account a repair record lands on ===

## deploy_finish() repairs EVERY graded slot, not just the side deploying right now, so the FIRST
## deployer's finish pass emits coherency-repair records for the OTHER side's units. The harness books
## a record on the slot the controller was ACTING as, so those repairs landed on the wrong account
## (measured in a captured rekrut-vs-rekrut game: 8 of 17 deploy records were a P2 unit's repair booked
## to P1). The record must name the repaired unit's OWN seat.
func test_deploy_repair_record_names_the_repaired_units_own_seat() -> void:
	var mine := _unit(1, [Vector3(-0.5, 0, 0.0)], "P1a")
	var torn := _unit(2, [Vector3(0.5, 0, 0.0), Vector3(0.5, 0, 0.9)], "P2torn")   # ~35" apart — torn
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(_army([mine, torn]), null, null, 1, 2)
	solo.set_difficulty(1, SoloDifficulty.for_grade("rekrut", 5))
	solo.set_difficulty(2, SoloDifficulty.for_grade("rekrut", 5))
	solo.ai_slot = 1          # P1 is the acting side while ITS deploy finishes
	solo.human_slot = 2
	var seen: Array = []
	solo.decision_sink = func(rec: Dictionary) -> void:
		if str(rec.get("kind", "")) == "deploy" and str(rec.get("unit", "")) == "P2torn":
			seen.append(rec)
	solo.deploy_finish()
	assert_int(seen.size()).override_failure_message(
		"the repair pass must emit a deploy record for the torn P2 unit").is_greater(0)
	for rec in seen:
		assert_int(int((rec["data"] as Dictionary).get("slot", 0))).override_failure_message(
			"the repair record must carry the repaired unit's own seat").is_equal(2)
		assert_int(ArenaMatch.honest_side(rec, solo.ai_slot)).override_failure_message(
			"the harness must book P2's repair on P2, not on the acting slot").is_equal(2)


## The side rule for every OTHER record is unchanged: no owner hint ⇒ the acting slot, and a seize still
## names the marker's new owner (0 = contested/neutral).
func test_harness_books_records_without_an_owner_hint_on_the_acting_slot() -> void:
	assert_int(ArenaMatch.honest_side({"kind": "move", "data": {}}, 2)).is_equal(2)
	assert_int(ArenaMatch.honest_side({"kind": "deploy", "data": {"section": 1}}, 2)).is_equal(2)
	assert_int(ArenaMatch.honest_side({"kind": "seize", "data": {"owner": 1}}, 2)).is_equal(1)
	assert_int(ArenaMatch.honest_side({"kind": "seize", "data": {}}, 2)).is_equal(0)


## NML-1126: the arena's REFUSAL seam. A game whose army import produced no rule descriptions
## played on with the description-driven move modifiers silently off and was banked into the
## corpus anyway (NML-1114). `NML_REQUIRE_RULE_TEXT=1` makes arena_match.gd quit BEFORE the
## result JSON is written, so a corpus runner's "no arena_*.json" branch retries or flags the
## game instead. The env unset must stay today's behaviour exactly — a text-less game still
## records, because that is what every existing runner expects.
func test_rule_text_refusal_only_bites_under_the_env() -> void:
	# Reached through load() and call(), NOT the suite's preloaded `ArenaMatch` const: a
	# const-typed call is resolved at PARSE time, so a tree without the seam would fail to
	# load this whole suite instead of reporting one honest failure. Dynamic dispatch keeps
	# the "seam missing" case a normal red — held by the very first assert.
	var arena: Object = load("res://tools/arena_match.gd")
	var with_text := {"Tough": "Takes extra hits to kill."}
	assert_bool(arena.has_method("rule_text_refused")).is_true()
	if not arena.has_method("rule_text_refused"):
		return

	OS.set_environment("NML_REQUIRE_RULE_TEXT", "")
	assert_bool(bool(arena.call("rule_text_refused", {}))).is_false()          # default: unchanged
	assert_bool(bool(arena.call("rule_text_refused", with_text))).is_false()

	OS.set_environment("NML_REQUIRE_RULE_TEXT", "1")
	assert_bool(bool(arena.call("rule_text_refused", {}))).is_true()           # no text -> refuse
	assert_bool(bool(arena.call("rule_text_refused", with_text))).is_false()   # text -> play on

	# Only the exact "1" arms it — a stray value must never silently disarm a fleet run's gate
	# by looking set, nor arm one that meant to stay off.
	OS.set_environment("NML_REQUIRE_RULE_TEXT", "0")
	assert_bool(bool(arena.call("rule_text_refused", {}))).is_false()
	OS.set_environment("NML_REQUIRE_RULE_TEXT", "")


## NML-1115: the SECOND refusal. Text that arrived is not enough — a corpus game's text must
## come from the pinned snapshot. The army-forge books drift weekly, so a game that fetched
## live pins nothing and a corpus mixing API vintages is unreproducible by construction (both
## reference corpora already carry 224 readings today's main cannot reproduce). Env unset is
## still today's behaviour byte for byte, live text included.
func test_live_api_rule_text_is_refused_under_the_env() -> void:
	var arena: Object = load("res://tools/arena_match.gd")
	var with_text := {"Tough": "Takes extra hits to kill."}

	OS.set_environment("NML_REQUIRE_RULE_TEXT", "")
	assert_bool(bool(arena.call("rule_text_refused", with_text, "api"))).is_false()

	OS.set_environment("NML_REQUIRE_RULE_TEXT", "1")
	assert_bool(bool(arena.call("rule_text_refused", with_text, "api"))).is_true()
	assert_bool(bool(arena.call("rule_text_refused", with_text, "snapshot"))).is_false()
	# Unstamped ("none" / omitted) keeps the NML-1126 reading: only an EMPTY map refuses.
	assert_bool(bool(arena.call("rule_text_refused", with_text, "none"))).is_false()
	assert_bool(bool(arena.call("rule_text_refused", with_text))).is_false()
	assert_bool(bool(arena.call("rule_text_refused", {}, "snapshot"))).is_true()
	OS.set_environment("NML_REQUIRE_RULE_TEXT", "")

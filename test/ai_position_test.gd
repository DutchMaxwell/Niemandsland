extends GdUnitTestSuite
## AI plausibility stage 1 — the dedicated POSITION SOLVER (AiPosition): joint move×target enumeration →
## hard filters (LOS / range / cover / friendly lane) → dual-channel scoring (EV + location veto) →
## argmax within a difficulty band. These prove the pipeline's load-bearing guarantees on the PURE solver
## (all board queries are injected stub Callables, so no game engine is needed) — most importantly the
## Stage-1 INVARIANT the post-hoc scorecard cannot see: a unit never ends its activation blind (no LOS /
## range to any target) when a LOS-bearing firing spot was inside its reachable set.

const IN := 0.0254                       # metres per inch (positions are world-plane metres)
const IN_PER_M := 1.0 / 0.0254


func _rprof(range_in: int, attacks: int = 10) -> Dictionary:
	return {"name": "Rifle", "attacks": attacks, "ap": 0, "deadly": 0, "relentless": false, "blast": 0,
		"reliable": false, "surge": false, "rending": false, "bane": false, "thrust": false,
		"counter": false, "range": range_in, "rules": []}


func _base_params() -> Dictionary:
	return {
		"from": Vector2.ZERO,
		"toward": Vector2(0.0, -20.0 * IN),
		"advance_m": 6.0 * IN, "rush_m": 12.0 * IN,
		"our_profiles": [_rprof(24, 10)], "our_ctx": {"quality": 4, "models": 5}, "shoot_range_in": 24.0,
		"targets": [], "threats": [], "in_per_m": IN_PER_M, "is_shooter": true,
		"los": func(_a, _b): return true, "cover_at": func(_p): return false,
		"legal_at": func(_p): return true, "band_frac_pick": 0.0, "pick": func(_n): return 0,
	}


## THE STAGE-1 INVARIANT: a LOS-bearing firing spot is in reach ⇒ the solver takes it (never parks blind).
func test_invariant_takes_a_reachable_los_firing_spot_over_a_blind_current_spot() -> void:
	var target := Vector2(0.0, -20.0 * IN)   # 20" ahead, inside the 24" gun
	# Line of sight only exists once the unit has side-stepped east of a wall (x > 3").
	var los := func(a: Vector2, _b: Vector2) -> bool: return a.x > 3.0 * IN
	var p := _base_params()
	p["toward"] = target
	p["targets"] = [{"centre": target, "def_ctx": {"defense": 4, "tough": 1, "models": 5}, "range_penalty_in": 0.0}]
	p["los"] = los
	var sol := AiPosition.solve(p)
	assert_bool(bool(sol.get("used", false))).is_true()
	assert_bool(bool(sol.get("shoot", false))).is_true()
	assert_bool(str(sol.get("action", "")) == "advance").is_true()
	# The chosen destination HAS line of sight AND range to a target — the whole point of Stage 1.
	var goal: Vector2 = sol["goal"]
	assert_bool(bool(los.call(goal, target))).is_true()
	assert_float(goal.distance_to(target) * IN_PER_M).is_less_equal(24.0)


## Dual channel: among equally-good shots, the LOCATION veto discards exposed spots when a covered spot
## with a comparable shot exists → the unit fires from cover (the "ignores cover" failure, fixed).
func test_quick_shot_keeps_the_volley_on_a_rush_distance_spot() -> void:
	# The firing spot needs a side-step beyond the (shrunk, 2") Advance band — the proven x > 3" LOS
	# geometry of the invariant test, but with Advance too short to reach it: a plain unit is demoted
	# to a dry Rush there; a Quick Shot unit keeps its volley after Rushing (army-book).
	var target := Vector2(0.0, -20.0 * IN)
	var los := func(a: Vector2, _b: Vector2) -> bool: return a.x > 3.0 * IN
	var p := _base_params()
	p["advance_m"] = 2.0 * IN
	p["toward"] = target
	p["targets"] = [{"centre": target, "def_ctx": {"defense": 4, "tough": 1, "models": 5}, "range_penalty_in": 0.0}]
	p["los"] = los
	var plain := AiPosition.solve(p)
	if bool(plain.get("used", false)):
		assert_bool(bool(plain.get("shoot", false))).is_false()   # beyond Advance = dry rush for a plain unit
	p["quick_shot"] = true
	var qs := AiPosition.solve(p)
	assert_bool(bool(qs.get("used", false))).is_true()
	assert_bool(bool(qs.get("shoot", false))).is_true()
	assert_str(str(qs.get("action", ""))).is_equal("rush")


func test_prefers_a_covered_firing_spot_over_an_exposed_one() -> void:
	var target := Vector2(0.0, -8.0 * IN)
	var cover := func(pt: Vector2) -> bool: return pt.x < -3.0 * IN   # a wood to the west
	var p := _base_params()
	p["toward"] = target
	p["our_profiles"] = [_rprof(100, 10)]     # long gun ⇒ every in-reach spot has an identical (plain) EV
	p["shoot_range_in"] = 100.0
	p["targets"] = [{"centre": target, "def_ctx": {"defense": 4, "tough": 1, "models": 5}, "range_penalty_in": 0.0}]
	p["threats"] = [{"centre": target, "range_in": 100.0}]   # the whole board is under threat ⇒ cover matters
	p["cover_at"] = cover
	var sol := AiPosition.solve(p)
	assert_bool(bool(sol.get("used", false))).is_true()
	assert_bool(bool(sol.get("shoot", false))).is_true()
	assert_bool(bool(cover.call(sol["goal"]))).is_true()          # the chosen firing spot is IN cover
	var filtered: Dictionary = sol.get("filtered", {})
	assert_int(int(filtered.get("open_no_cover", 0))).is_greater(0)   # exposed shots were named + discarded


## No target is reachable from anywhere in the move band ⇒ the solver does NOT override the tree's approach
## (a shooter with no shot should keep closing the gap; loc-fallback ranks but never forces a worse move).
func test_defers_when_no_shot_exists_anywhere_in_reach() -> void:
	var target := Vector2(0.0, -60.0 * IN)   # far beyond gun + move band
	var p := _base_params()
	p["toward"] = target
	p["targets"] = [{"centre": target, "def_ctx": {"defense": 4, "tough": 1, "models": 5}, "range_penalty_in": 0.0}]
	var sol := AiPosition.solve(p)
	assert_bool(bool(sol.get("used", false))).is_false()


## No geometry wired (headless / SoloSim path) ⇒ the solver is a no-op, so the caller's plan is untouched
## (the byte-identical determinism seam).
func test_no_op_without_injected_geometry() -> void:
	var p := _base_params()
	p["los"] = Callable()
	p["targets"] = [{"centre": Vector2(0.0, -10.0 * IN), "def_ctx": {"defense": 4, "tough": 1, "models": 5}, "range_penalty_in": 0.0}]
	assert_bool(bool(AiPosition.solve(p).get("used", false))).is_false()


## Determinism: identical inputs ⇒ bit-identical output (seeded replay). And Kriegsherr (band 0) is argmax
## (deviation 0), the sharp ceiling — the ev_noise band only widens the choice at weaker grades.
func test_deterministic_and_kriegsherr_is_argmax() -> void:
	var target := Vector2(0.0, -18.0 * IN)
	var los := func(a: Vector2, _b: Vector2) -> bool: return a.x > 3.0 * IN
	var p := _base_params()
	p["toward"] = target
	p["targets"] = [{"centre": target, "def_ctx": {"defense": 4, "tough": 1, "models": 5}, "range_penalty_in": 0.0}]
	p["los"] = los
	var a := AiPosition.solve(p)
	var b := AiPosition.solve(p)
	assert_bool(bool(a.get("used", false))).is_true()
	assert_bool((a["goal"] as Vector2).is_equal_approx(b["goal"] as Vector2)).is_true()
	assert_int(int(a.get("deviation", -1))).is_equal(0)   # band_frac 0 ⇒ argmax, no deviation


## OBJECTIVE PRESERVATION: an objective-bound unit is NOT pulled off its marker toward a richer enemy
## firing spot — it either takes a firing spot that ALSO holds the marker, or keeps its objective rush.
func test_objective_bound_unit_is_not_pulled_off_its_marker() -> void:
	var marker := Vector2(0.0, -5.0 * IN)          # 5" ahead — reachable this Advance
	var enemy := Vector2(30.0 * IN, 0.0)           # a juicy shot lies EAST, far from the marker
	var p := _base_params()
	p["toward"] = marker
	p["targets"] = [{"centre": enemy, "def_ctx": {"defense": 4, "tough": 1, "models": 5}, "range_penalty_in": 0.0}]
	p["objective"] = {"pos": marker, "seize_ring_m": 3.0 * IN, "to_objective": true, "final_round": true}
	var sol := AiPosition.solve(p)
	# The only shot is off-marker ⇒ the solver must NOT redirect toward the enemy; it keeps the objective push.
	assert_bool(str(sol.get("toward", "objective")) == "enemy" and bool(sol.get("used", false))).is_false()


## …but when a seize-ring spot ALSO keeps a shot, the objective-bound shooter takes it (holds + fires).
func test_objective_bound_unit_takes_a_seize_ring_firing_spot() -> void:
	var marker := Vector2(0.0, -5.0 * IN)
	var enemy := Vector2(0.0, -24.0 * IN)          # ahead — in range from the seize ring around the marker
	var p := _base_params()
	p["toward"] = marker
	p["shoot_range_in"] = 24.0
	p["targets"] = [{"centre": enemy, "def_ctx": {"defense": 4, "tough": 1, "models": 5}, "range_penalty_in": 0.0}]
	p["objective"] = {"pos": marker, "seize_ring_m": 3.0 * IN, "to_objective": true, "final_round": true}
	var sol := AiPosition.solve(p)
	assert_bool(bool(sol.get("used", false))).is_true()
	assert_bool(str(sol.get("toward", "")) == "objective").is_true()
	# The chosen spot is inside the seize ring (it holds the marker) AND it fired.
	assert_bool(bool(sol.get("shoot", false))).is_true()


## The ev_noise band gives the difficulty knob a real POSITION surface: a wide band + a seeded pick that
## deviates yields a DIFFERENT (still legal, still firing) spot than the argmax — deterministically.
func test_difficulty_band_deviates_to_a_second_best_firing_spot() -> void:
	var target := Vector2(0.0, -18.0 * IN)
	var los := func(a: Vector2, _b: Vector2) -> bool: return a.x > 3.0 * IN
	var sharp := _base_params()
	sharp["toward"] = target
	sharp["targets"] = [{"centre": target, "def_ctx": {"defense": 4, "tough": 1, "models": 5}, "range_penalty_in": 0.0}]
	sharp["los"] = los
	var wide := sharp.duplicate()
	wide["band_frac_pick"] = 0.4                       # rekrut-width band
	wide["pick"] = func(n: int) -> int: return 1 if n > 1 else 0   # force the 2nd-best in the band
	var argmax := AiPosition.solve(sharp)
	var noisy := AiPosition.solve(wide)
	assert_bool(bool(argmax.get("used", false))).is_true()
	assert_bool(bool(noisy.get("used", false))).is_true()
	# The noisy pick still fires (a legal firing spot), it is just not the argmax one.
	assert_bool(bool(noisy.get("shoot", false))).is_true()
	assert_bool(bool(los.call(noisy["goal"], target))).is_true()
	assert_int(int(noisy.get("deviation", 0))).is_greater_equal(0)


## NML-007 "Solver zu still": Fall (d) — ein MATERIELL reicherer Feuerplatz (absolute UND relative
## Marge) überstimmt den aktuellen Schussplatz; würfelrausch-große Gewinne brechen Move-Commitment nie.
func test_worth_overriding_ev_upgrade_needs_both_margins() -> void:
	var from := {"can_shoot": true, "cover": false, "threatened": false, "ev": 1.0, "obj_gap_in": 99.0}
	var big := {"can_shoot": true, "cover": false, "ev": 2.0, "obj_gap_in": 99.0}
	var small := {"can_shoot": true, "cover": false, "ev": 1.5, "obj_gap_in": 99.0}
	assert_bool(AiPosition._worth_overriding(big, from, true, {}, IN_PER_M)).is_true()
	assert_bool(AiPosition._worth_overriding(small, from, true, {}, IN_PER_M)).is_false()   # absolute Marge verfehlt
	var rel := {"can_shoot": true, "cover": false, "ev": 4.8, "obj_gap_in": 99.0}
	var from_rich := {"can_shoot": true, "cover": false, "threatened": false, "ev": 4.0, "obj_gap_in": 99.0}
	assert_bool(AiPosition._worth_overriding(rel, from_rich, true, {}, IN_PER_M)).is_false()   # relative Marge verfehlt

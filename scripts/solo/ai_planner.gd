class_name AiPlanner
extends RefCounted
## Phase-1 step 5, first half: candidate generation per plan D3 — tactical
## points, not a grid. For one un-activated unit: hold; hold + best-EV shoot;
## one rush per objective; a charge on the best hurtable target (scored by
## AiEv.charge_score, gated by the live futile-charge doctrine); one retreat
## point away from the nearest threat. Destinations are GOALS — resolve clamps
## them to the legal band, so unreachable points degrade to "move toward".


const RETREAT_GOAL_IN := 100.0   # far marker; the band clamp turns it into one move away
const SAFE_LINE_COVER_BONUS_IN := 6.0    # D22: a covered stop outbids 6" of open progress
const SAFE_LINE_OPEN_LINE_PENALTY_IN := 2.0   # D22: each open fire line beyond the first costs 2"


## The 1-ply pick (plan D5): roll every candidate of every un-activated unit
## of `player` through BattleSim.resolve, score the outcome in mission
## currency, and return the best (unit, action) pair — WHICH unit activates
## is part of the pick. Pure and deterministic: dict order is capture order,
## ties keep the first seen. A shaken unit only gets its recovery hold.
static func plan(state: Dictionary, player: int) -> Dictionary:
	var base := AiMissionEval.score(state, player, BattleSim.reply_threat(state, player))
	var best := {}
	var runner := {}
	for key in state["units"]:
		var su: Dictionary = state["units"][key]
		if int(su["player"]) != player or bool(su["activated"]) or int(su["alive"]) <= 0:
			continue
		var cands: Array = [{"unit": key, "kind": AiDecision.Action.HOLD}] \
			if bool(su.get("shaken", false)) else candidates(state, str(key))
		for action in cands:
			var next := BattleSim.resolve(state, action)
			var s := AiMissionEval.score(next, player, BattleSim.reply_threat(next, player))
			var cand := {"unit_key": str(key), "action": action, "score": s}
			if best.is_empty() or s > float(best["score"]):
				runner = best
				best = cand
			elif runner.is_empty() or s > float(runner["score"]):
				runner = cand
	if best.is_empty():
		return {"used": false}
	return {"used": true, "unit_key": best["unit_key"], "action": best["action"],
		"intent": _intent(state, best, runner, base),
		"expectation": {"before": base, "after": float(best["score"])},
		"runner_up": runner}


const ROLLOUT_TOP_K := 6   # rollout budget: only this many 1-ply-best openers get played out
static var _tk := 0   # research seam: NML_TOP_K overrides (lazy; <=0 = unread)


static func top_k_default() -> int:
	if _tk <= 0:
		var e := OS.get_environment("NML_TOP_K")
		_tk = clampi(int(e), 1, 32) if e != "" else ROLLOUT_TOP_K
	return _tk


## R2 (round-rollout search): rank every (unit, action) pair 1-ply with the
## rich leaf exactly like plan(), keep the TOP_K, play each survivor's round
## out and take the best END-OF-ROUND rich-leaf score. top_k <= 0 degrades to
## plan() byte-identically (the safety valve and the red-green seam).
## Deterministic: prefilter ties keep capture order (explicit index tiebreak).
## S-wave knobs (grill 15.08.): playout arbitration fires only when the
## blend sees the top-2 CLOSE; the playout verdict then decides outright.
static var playout_search := false   # set per pick from the difficulty preset
static var playout_net: Dictionary = {}   # net-guided playouts: the Feldherrenblick
	# steers every imagined activation ({} = heuristic playouts, byte-identical).
	# Set per pick by the controller (NML_PLAYOUT_NET research gate).
static var playout_arbitrations := 0  # test/diagnosis counter: how often playouts fired
static var _po_t0 := 0
## Continuation leaf for playouts: rich (reply-threat aware, 238ms/step on
## 8v8) vs cheap (31ms — 7.6x faster, same brain for BOTH branches so the
## comparison stays fair). Env seam NML_PLAYOUT_RICH=0 flips an arena arm.
static var _po_rich := -1
static func playout_rich() -> bool:
	if _po_rich == -1:
		_po_rich = 0 if OS.get_environment("NML_PLAYOUT_RICH") == "0" else 1
	return _po_rich == 1
static var playout_close_margin := 0.02   # blend-score gap that counts as "close" (knob)
static var _po_margin_env := -1.0
static func close_margin() -> float:
	if _po_margin_env == -1.0:
		var e := OS.get_environment("NML_PLAYOUT_MARGIN")
		_po_margin_env = float(e) if e.is_valid_float() else -2.0   # -2 = no env
	return _po_margin_env if _po_margin_env >= 0.0 else playout_close_margin
const PLAYOUT_DECIDE_MARGIN := 0.5   # mean marker-delta that settles it
const PLAYOUT_CAP := 7               # max playouts per branch


static func plan_with_rollout(state: Dictionary, player: int,
		top_k: int = -1) -> Dictionary:
	_last_leaf_state = {}
	if top_k == -1:
		top_k = top_k_default()   # research seam; default = the const
	if top_k <= 0:
		return plan(state, player)
	var base := AiMissionEval.score(state, player, BattleSim.reply_threat(state, player))
	var scored: Array = []
	for key in state["units"]:
		var su: Dictionary = state["units"][key]
		if int(su["player"]) != player or bool(su["activated"]) or int(su["alive"]) <= 0:
			continue
		var cands: Array = [{"unit": key, "kind": AiDecision.Action.HOLD}] \
			if bool(su.get("shaken", false)) else candidates(state, str(key))
		for action in cands:
			var next := BattleSim.resolve(state, action)
			scored.append({"unit_key": str(key), "action": action, "idx": scored.size(),
				"score": AiMissionEval.score(next, player, BattleSim.reply_threat(next, player))})
	if scored.is_empty():
		return {"used": false}
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["score"]) != float(b["score"]):
			return float(a["score"]) > float(b["score"])
		return int(a["idx"]) < int(b["idx"]))
	# Coverage guarantee (diagnosis 07.08.): WHICH unit opens is the whole
	# question, but bait moves rank low 1-ply and never survived a global
	# TOP_K cut. Every un-activated unit gets its best candidate rolled out;
	# the global TOP_K adds depth on the leaders.
	var pool: Array = []
	var covered := {}
	var patient_of := {}
	for cand in scored:
		if not covered.has(cand["unit_key"]):
			covered[cand["unit_key"]] = true
			pool.append(cand)
		if bool((cand["action"] as Dictionary).get("patient", false)) \
				and not patient_of.has(cand["unit_key"]):
			patient_of[cand["unit_key"]] = cand
	for cand in scored.slice(0, mini(top_k, scored.size())):
		if not pool.has(cand):
			pool.append(cand)
	# R8 pool guarantee (same lesson as the per-unit coverage): the PATIENT
	# advance ranks low 1-ply by construction (it forgoes the marker), so the
	# prefilter would starve it before it ever got played out — every unit's
	# patient candidate enters the pool and lets the blend judge it.
	for k in patient_of:
		if not pool.has(patient_of[k]):
			pool.append(patient_of[k])
	# D23 pool guarantee (same starving risk as the patient advance): every
	# unit's second-wave candidate reaches the rollout, ranked or not.
	for cand in scored:
		if str((cand["action"] as Dictionary).get("wave", "")) != "" \
				and not pool.has(cand):
			pool.append(cand)
	var best := {}
	var runner := {}
	for cand in pool:
		var ends := rollout_boundaries(state, cand["action"], player)
		var rs := _blend_score(ends, player)
		if OS.get_environment("NML_PLAN_DUMP") == "1":   # diagnosis-only; ladder silent without it
			printerr("[PLAN] R%d %s kind=%d 1ply=%.4f rolled=%.4f" % [int(state["round"]),
				str(cand["unit_key"]), int((cand["action"] as Dictionary).get("kind", -1)),
				float(cand["score"]), rs])
		var rolled := {"unit_key": cand["unit_key"], "action": cand["action"], "score": rs}
		if best.is_empty() or rs > float(best["score"]):
			runner = best
			best = rolled
			if not ends.is_empty():
				_last_leaf_state = ends[ends.size() - 1]
		elif runner.is_empty() or rs > float(runner["score"]):
			runner = rolled
	# S-wave PS2 (D17/D19): on a CLOSE top-2 the playout DECIDES — adaptive
	# escalation (3 playouts each, +2 while tied, hard cap), deterministic
	# prng per state+branch. playout_search=false = byte-identical pick.
	var playout_note := ""
	if OS.get_environment("NML_PLAN_DUMP") == "1" and not runner.is_empty():
		printerr("[GAP] R%d best=%s %.4f runner=%s %.4f gap=%.4f search=%s" % [
			int(state["round"]), str(best["unit_key"]), float(best["score"]),
			str(runner["unit_key"]), float(runner["score"]),
			absf(float(best["score"]) - float(runner["score"])), str(playout_search)])
	if playout_search and not runner.is_empty() \
			and absf(float(best["score"]) - float(runner["score"])) < close_margin():
		playout_arbitrations += 1
		_po_t0 = Time.get_ticks_msec()
		var sig := _playout_sig(state, player)
		var n := 3
		var sum_b := 0.0
		var sum_r := 0.0
		var done := 0
		while n <= PLAYOUT_CAP:
			for i in range(done, n):
				var rb := RandomNumberGenerator.new()
				rb.seed = sig * 31 + i * 2
				var pb := full_playout(state, best["action"], player, rb)
				sum_b += float(pb["p1"] - pb["p2"]) * (1.0 if player == 1 else -1.0)
				var rr := RandomNumberGenerator.new()
				rr.seed = sig * 31 + i * 2 + 1
				var pr := full_playout(state, runner["action"], player, rr)
				sum_r += float(pr["p1"] - pr["p2"]) * (1.0 if player == 1 else -1.0)
			done = n
			if absf(sum_b - sum_r) / float(n) >= PLAYOUT_DECIDE_MARGIN:
				break
			n += 2
		if OS.get_environment("NML_PLAN_DUMP") == "1":
			printerr("[PLAYOUT] fired n=%d/side dt_ms=%d sums %.1f vs %.1f swap=%s" % [
				done, Time.get_ticks_msec() - _po_t0, sum_b, sum_r, str(sum_r > sum_b)])
		if sum_r > sum_b:
			var tmp := best
			best = runner
			runner = tmp
		playout_note = " [playout %d/side: %.2f vs %.2f -> %s]" % [done,
			maxf(sum_b, sum_r) / done, minf(sum_b, sum_r) / done, str(best["unit_key"])]
	var waits := 0
	for key in state["units"]:
		var su: Dictionary = state["units"][key]
		if int(su["player"]) == player and not bool(su["activated"]) \
				and int(su["alive"]) > 0 and str(key) != str(best["unit_key"]):
			waits += 1
	return {"used": true, "unit_key": best["unit_key"], "action": best["action"],
		"intent": _intent(state, best, runner, base) + " (round played out; %d own kept back)" % waits + playout_note,
		"expectation": {"before": base, "after": float(best["score"])},
		"runner_up": runner, "waits": waits, "rolled_units": covered.keys()}


const ROLLOUT_HORIZON_ROUNDS := 2   # R6: a move's price only shows NEXT round — round 1 alone is a movement round
static var _hz := 0   # research seam: NML_HORIZON overrides (lazy; <=0 = unread)


static func horizon() -> int:
	if _hz <= 0:
		var e := OS.get_environment("NML_HORIZON")
		_hz = clampi(int(e), 1, 3) if e != "" else ROLLOUT_HORIZON_ROUNDS
	return _hz


## R1+R6 (round-rollout search): play the rest of the ROUND out after
## `first_action` by `me` — sides alternate as in the real rule, a dry side
## lets the other play its tail, every step is the cheap-policy greedy pick —
## and then keep playing INTO the following round(s) up to `horizon_rounds`
## (R6: the step-4 calibration proved the round-1 leaf is blind — imagined
## round 1 holds almost no combat, so every opener scored alike; the
## consequences land in round 2, which the mind must now watch). Returns the
## horizon-end state; the CALLER prices it with the rich leaf (eval +
## reply_threat). Pure and deterministic. horizon_rounds = 1 is the pre-R6
## single-round rollout, byte-identical (the safety valve and test seam).
static func rollout(state: Dictionary, first_action: Dictionary, me: int,
		horizon_rounds: int = -1) -> Dictionary:
	var ends := rollout_boundaries(state, first_action, me, horizon_rounds)
	return ends[ends.size() - 1]


## R7: the same playout, but returning the state AT EVERY round boundary of
## Leaf-row seam (glasses v4): the WINNING candidate's horizon-end state —
## the exact distribution the leaf eval judges. The controller logs it as a
## training row; reset per pick, {} when the rollout path did not run.
static var _last_leaf_state: Dictionary = {}


## the horizon (index 0 = end of the current round, last = horizon end) — the
## caller prices each boundary and blends. The boundary snapshot is taken
## BEFORE _cross_round mutates the walker, so every entry is a true round-end.
static var _tail_cap_env := {}   # SPEED L2 (NML-1024): lazy per-slot cache

## SPEED L2: cap on simulated activations per rollout. 0/absent = OFF —
## byte-identical to the uncapped path. Per-seat override so the SAME net can
## play capped vs uncapped against itself (improvement-operator A/B pattern);
## the truncated state simply becomes the last boundary the blend prices.
static func _tail_cap_for(me: int) -> int:
	if not _tail_cap_env.has(me):
		var e := OS.get_environment("NML_PLAYOUT_TAIL_CAP_P%d" % me)
		if e == "":
			e = OS.get_environment("NML_PLAYOUT_TAIL_CAP")
		_tail_cap_env[me] = maxi(int(e), 0) if e != "" else 0
	return int(_tail_cap_env[me])


static func rollout_boundaries(state: Dictionary, first_action: Dictionary, me: int,
		horizon_rounds: int = -1) -> Array:
	if horizon_rounds <= 0:
		horizon_rounds = horizon()   # research seam; default = R6's 2
	var out: Array = []
	var cur := BattleSim.resolve(state, first_action)
	var turn := _other_player(state, me)
	var rounds_left := maxi(horizon_rounds, 1)
	var guard: int = ((state["units"] as Dictionary).size() + 2) * rounds_left
	var tail_cap := _tail_cap_for(me)
	var steps := 0
	while guard > 0:
		guard -= 1
		if tail_cap > 0 and steps >= tail_cap:
			out.append(cur)   # truncated: the blend prices this state as-is
			return out
		steps += 1
		var a := _policy_step(cur, turn, turn == me)   # R9: own side steps danger-aware
		if a.is_empty():
			turn = _other_player(cur, turn)
			a = _policy_step(cur, turn, turn == me)
			if a.is_empty():
				out.append(cur)
				rounds_left -= 1
				if rounds_left <= 0 or int(cur["round"]) >= int(cur["rounds_total"]):
					return out
				cur = BattleSim.clone_state(cur)
				turn = _cross_round(cur)
				continue
		cur = BattleSim.resolve(cur, a)
		turn = _other_player(cur, turn)
	out.append(cur)   # guard backstop only — a logic error, never the rule path
	return out


const DEPTH_DISCOUNT := 0.5   # R7: each further imagined round carries half the previous one's vote


## D-wave: seat-aware leaf weighting. The A/B ledger proved the two depth
## modes own opposite seats — last-boundary voting (R6) was the best OPENER
## ever (12.5% seat) and the worst responder; the discount blend (R7) is the
## best RESPONDER (78%) and a weak opener. The controller sets this per pick:
## true = our side opened the current round.
static var opener_seat := false
static var _seat_env := -1   # research seam: NML_SEAT_DEPTH=off disables the opener mode (lazy env)


static func seat_depth_enabled() -> bool:
	if _seat_env < 0:
		_seat_env = 0 if OS.get_environment("NML_SEAT_DEPTH") == "off" else 1
	return _seat_env == 1


## R7/D: price a rollout's round boundaries as ONE number. Responder seat:
## geometric depth discount, normalized — the current round's certainty keeps
## the 2/3 majority, the imagined next round refines. Opener seat: the LAST
## boundary alone votes — an opener's move only shows its worth after the
## enemy's full reply, so the deep look must be allowed to outvote.
static func _blend_score(ends: Array, player: int) -> float:
	if opener_seat and seat_depth_enabled():
		var last: Dictionary = ends[ends.size() - 1]
		return AiMissionEval.score(last, player, BattleSim.reply_threat(last, player))
	var total := 0.0
	var weights := 0.0
	var w := 1.0
	for end in ends:
		total += w * AiMissionEval.score(end, player, BattleSim.reply_threat(end, player))
		weights += w
		w *= DEPTH_DISCOUNT
	return total / weights


## R6: cross the round boundary INSIDE the mental game — round counter up,
## everyone un-activated, fatigue gone (p.9: it lasts until the end of the
## round; Shaken persists — its recovery is the idle activation the policy
## already hands out). Returns the imagined new round's opener: under strict
## alternation the side with fewer alive units finished its activations first
## and opens the next round (GF v3.5.1 p.4); a tie opens with the lower slot
## (v0 approximation, deterministic). Mutates `cur` in place — it is the
## rollout's private clone chain, never a caller's state.
## W-P1 round-cycle (coverage table 20.08.): everything the game refreshes at
## a round start that the imagined rounds ran WITHOUT. Spell tokens refill
## (game_unit.add_round_caster_points — Caster Group resets to bearer count,
## plain casters accumulate to the cap) and Battleborn/Steadfast clears Shaken
## for free (main.gd round-start pass; deterministic playout grants the 4+ —
## binary state, and the idle-recovery path still serves everyone else).
static func _round_start_refresh(su: Dictionary) -> void:
	su["activated"] = false
	su["fatigued"] = false
	var gu: GameUnit = su["unit"]
	if gu == null:
		return
	if gu.has_special_rule("Caster Group"):
		su["casts"] = int(su["alive"])
	elif int(gu.casts_per_round) > 0:
		su["casts"] = mini(int(su.get("casts", 0)) + int(gu.casts_per_round),
			GameUnit.CASTER_POINTS_CAP)
	if bool(su.get("shaken", false)) and (RulesRegistry.unit_rule_active(gu, "Battleborn")
			or RulesRegistry.unit_rule_active(gu, "Steadfast")):
		su["shaken"] = false


static func _cross_round(cur: Dictionary) -> int:
	cur["round"] = int(cur["round"]) + 1
	var counts := {}
	for k in cur["units"]:
		var su: Dictionary = cur["units"][k]
		_round_start_refresh(su)
		if int(su["alive"]) > 0:
			counts[int(su["player"])] = int(counts.get(int(su["player"]), 0)) + 1
	var players: Array = counts.keys()
	players.sort()
	if players.size() == 2 and int(counts[players[0]]) != int(counts[players[1]]):
		return int(players[0]) if int(counts[players[0]]) < int(counts[players[1]]) \
			else int(players[1])
	return int(players[0]) if not players.is_empty() else 0


## Rollout policy, one step: the best restricted move of `player`'s un-activated
## units. The OPPONENT is imagined with the CHEAP leaf (mission eval WITHOUT
## reply pricing — greedy is a conservative enemy model); OUR OWN side steps
## with the RICH leaf (R9: the danger-blind cheap leaf marched the imagined
## own army into the same overextension on every line, so patience could
## never look better than rushing). {} when dry.
static func _policy_step(state: Dictionary, player: int, rich := false) -> Dictionary:
	if not playout_net.is_empty():
		return _policy_step_net(state, player, rich)
	var best := {}
	var best_s := -INF
	for key in state["units"]:
		var su: Dictionary = state["units"][key]
		if int(su["player"]) != player or bool(su["activated"]) or int(su["alive"]) <= 0:
			continue
		for action in _policy_candidates(state, str(key)):
			var next := BattleSim.resolve(state, action)
			var s := AiMissionEval.score(next, player, BattleSim.reply_threat(next, player)) \
				if rich else AiMissionEval.score(next, player)
			if s > best_s:
				best_s = s
				best = action
	return best


## Net-guided playout step: the Feldherrenblick chooses each unit's move WITHIN
## its menu — the exact per-menu distribution it was trained on (cross-menu
## logits are NOT calibrated, so the net never arbitrates between units).
## Mission currency then decides ACROSS units on the per-unit picks alone:
## one resolve per unit instead of units x candidates — smarter AND cheaper.
static func _policy_step_net(state: Dictionary, player: int, rich := false) -> Dictionary:
	var board: Array = BattleSim.board_rows(state)
	var terrain_at: Callable = state.get("terrain_at", Callable())
	# Review find (workflow 22.08.): without a real los_at the sight feature collapses
	# to a constant 0.5 across every candidate — erasing exactly the within-menu
	# discrimination the trained nets carry. The controller stamps its los_checker.
	var los_at: Callable = state.get("los_at", Callable())
	var picks: Array = []
	for key in state["units"]:
		var su: Dictionary = state["units"][key]
		if int(su["player"]) != player or bool(su["activated"]) or int(su["alive"]) <= 0:
			continue
		var cands := _policy_candidates(state, str(key))
		if cands.is_empty():
			continue
		var pick: Dictionary = cands[0]
		if cands.size() > 1:
			var menu := AiClone.menu_tuples(state, str(key), cands, terrain_at, los_at)
			var sc := AiClone.scores(playout_net, board, player, menu)
			if sc.size() == cands.size():
				var bi := 0
				for i in range(1, sc.size()):
					if float(sc[i]) > float(sc[bi]):
						bi = i
				pick = cands[bi]
		picks.append(pick)
	var best := {}
	var best_s := -INF
	for action in picks:
		var next := BattleSim.resolve(state, action)
		var s := AiMissionEval.score(next, player, BattleSim.reply_threat(next, player)) \
			if rich else AiMissionEval.score(next, player)
		if s > best_s:
			best_s = s
			best = action
	return best


## Restricted candidate set for rollout steps (cheap on purpose): hold with the
## best-EV shoot when one exists, plus one rush to the nearest objective. A
## shaken unit only gets its recovery hold — same rule plan() applies.
static func _policy_candidates(state: Dictionary, key: String) -> Array:
	var su: Dictionary = state["units"][key]
	if bool(su.get("shaken", false)):
		return [{"unit": key, "kind": AiDecision.Action.HOLD}]
	var hold := {"unit": key, "kind": AiDecision.Action.HOLD}
	var shoot := _best_shoot(state, key)
	if shoot != "":
		hold["shoot"] = shoot
	var out: Array = [hold]
	var best_d := INF
	var dest := Vector3.ZERO
	for o in state["objectives"]:
		var d := ((o as Dictionary)["pos"] as Vector3 - _centre(su)).length()
		if d < best_d:
			best_d = d
			dest = (o as Dictionary)["pos"]
	if best_d < INF:
		out.append({"unit": key, "kind": AiDecision.Action.RUSH, "dest": dest})
	# Counter-charges exist in the mental game too (diagnosis 07.08.: without
	# this, a committed unit could never be punished in the rollout, so early
	# commitment looked free). Same futility-gated pick plan() uses.
	var charge := _best_charge(state, key)
	if charge != "":
		out.append({"unit": key, "kind": AiDecision.Action.CHARGE,
			"dest": _centre(state["units"][charge]), "charge": charge})
	var patient := _safe_advance(state, key)
	if not patient.is_empty():
		out.append(patient)
	return out


## R8 (opener diagnosis 09.08., seed-1 capture): the PATIENT advance — toward
## the nearest objective, with the goal clamped to the strongest safety still
## available (tier 1: outside every gun's reach; tier 2: outside every charge
## reach). This makes the tree's opening (walk up, do NOT overextend)
## imaginable: before it, every future the rollout could picture rushed onto
## markers into unspent guns, so the search could only ever pick the least-bad
## overextension — the planner opened at 8% against a 25% structural par.
## {} when even charge safety is already lost (rush/retreat own that regime)
## or when there is nothing to walk toward.
static func _safe_advance(state: Dictionary, key: String) -> Dictionary:
	var su: Dictionary = state["units"][key]
	var centre := _centre(su)
	var best_d := INF
	var goal := Vector3.ZERO
	for o in state["objectives"]:
		var d := ((o as Dictionary)["pos"] as Vector3 - centre).length()
		if d < best_d:
			best_d = d
			goal = (o as Dictionary)["pos"]
	if best_d == INF or best_d < 0.001:
		return {}
	var dir := (goal - centre).normalized()
	var band_m := float(SoloController.sim_move_bands(su["unit"]).get("advance", 6)) \
		* BattleSim.IN2M
	# Two safety tiers: (1) outside EVERYTHING (range + advance, or rush) —
	# rarely available on a 72x48 board where front lines start ~24" apart;
	# (2) fallback: outside every CHARGE reach (rush band) — "midfield,
	# unbound": guns that already cover the whole board reach you anyway, but
	# nobody gets to charge you and you stand short of the marker scrum.
	# Distances are NEAREST MODEL to nearest model (charges and range checks
	# resolve that way — centre maths under-reads the danger by both units'
	# formation spread), and the charge reach carries the contact allowance.
	var full: Array = []
	var charge_only: Array = []
	for ek in _enemy_keys(state, key):
		var eu: Dictionary = state["units"][ek]
		if int(eu["alive"]) <= 0:
			continue
		var u: GameUnit = eu["unit"]
		var w: Array = []
		if u.source_type == "opr" and u.source_data is OPRApiClient.OPRUnit:
			w = (u.source_data as OPRApiClient.OPRUnit).weapons
		var bands := SoloController.sim_move_bands(u)
		var charge_in := float(bands.get("rush", 12)) + BattleSim.CONTACT_IN
		full.append({"positions": eu["positions"], "reach": maxf(
			float(AiArchetype.max_range_inches(w)) + float(bands.get("advance", 6)),
			charge_in) * BattleSim.IN2M})
		charge_only.append({"positions": eu["positions"], "reach": charge_in * BattleSim.IN2M})
	if full.is_empty():
		return {}
	var positions: Array = su["positions"]
	for threats in [full, charge_only]:
		var inside := false
		for e in threats:
			if _gap_m(positions, Vector3.ZERO, e["positions"]) <= float(e["reach"]):
				inside = true
				break
		if inside:
			continue   # this tier's safety is already lost — try the weaker tier
		# D22 (grill 15.08.): among SAFE points, progress is no longer the only
		# currency — cover earns a bonus and every OPEN enemy fire line beyond
		# the first costs (his four criteria; marker direction is inherent).
		# Safety stays a half-inch grid; scoring probes the safe frontier.
		var step := 0.5 * BattleSim.IN2M
		var safe_ts: Array = []
		var t := step
		while t <= band_m + 0.0001:
			var safe := true
			for e in threats:
				if _gap_m(positions, dir * t, e["positions"]) <= float(e["reach"]):
					safe = false
					break
			if safe:
				safe_ts.append(t)
			t += step
		if safe_ts.is_empty():
			continue
		var terrain_at: Callable = state.get("terrain_at", Callable())
		var los_blocked: Callable = state.get("los_blocked", Callable())
		var frontier: Array = safe_ts.slice(maxi(safe_ts.size() - 8, 0))
		var best_t := 0.0
		var best_sc := -INF
		for ft in frontier:
			var pnt: Vector3 = centre + dir * float(ft)
			var sc := float(ft) / BattleSim.IN2M
			if terrain_at.is_valid() \
					and TerrainRules.gives_cover(int(terrain_at.call(pnt))):
				sc += SAFE_LINE_COVER_BONUS_IN
			if los_blocked.is_valid():
				var open_lines := 0
				for ek2 in _enemy_keys(state, key):
					var eu2: Dictionary = state["units"][ek2]
					if int(eu2["alive"]) <= 0:
						continue
					if not bool(los_blocked.call(_centre(eu2), pnt)):
						open_lines += 1
					if open_lines >= 4:
						break
				sc -= SAFE_LINE_OPEN_LINE_PENALTY_IN * maxf(open_lines - 1, 0)
			if sc > best_sc:
				best_sc = sc
				best_t = float(ft)
		if best_t > 0.001:
			return {"unit": key, "kind": AiDecision.Action.ADVANCE,
				"dest": centre + dir * best_t, "patient": true}
	return {}


## Smallest model-to-model distance (metres) after shifting `a` by `offset`.
static func _gap_m(a: Array, offset: Vector3, b: Array) -> float:
	var best := INF
	for pa in a:
		for pb in b:
			best = minf(best, ((pa as Vector3) + offset - (pb as Vector3)).length())
	return best


## Opener-doctrine probe (research knob, NML-995): forces the OPENER's
## round-1 macro-plan so the seat's policy space can be MEASURED directly
## (4 arms x 50 farm games) instead of iterated blindly through the eval.
## Arms: "patient" (every unit safe-advances, hold when boxed), "rush"
## (nearest marker — the pathological control arm), "screen" (the cheapest
## unit rushes the center first, everyone else patient), "hold" (the full
## null-move: cede round 1 entirely, keep the army for the responder
## rounds). Returns a plan()-shaped pick; {} lets the caller fall through
## to the normal search. Only the controller's env gate ever calls this.
static func doctrine_pick(state: Dictionary, player: int, doctrine: String) -> Dictionary:
	var first_key := ""
	var cheapest := ""
	var cheapest_w := INF
	var any_own_acted := false
	for key in state["units"]:
		var su: Dictionary = state["units"][key]
		if int(su["player"]) != player or int(su["alive"]) <= 0:
			continue
		if bool(su["activated"]):
			any_own_acted = true
			continue
		if first_key == "":
			first_key = str(key)
		var wsum := 0.0
		for w in su["wounds"]:
			wsum += float(w)
		if wsum < cheapest_w:
			cheapest_w = wsum
			cheapest = str(key)
	if first_key == "":
		return {}
	var key := first_key
	var act := {}
	match doctrine:
		"rush":
			var best_d := INF
			var dest := Vector3.ZERO
			var su: Dictionary = state["units"][key]
			for o in state["objectives"]:
				var d := ((o as Dictionary)["pos"] as Vector3 - _centre(su)).length()
				if d < best_d:
					best_d = d
					dest = (o as Dictionary)["pos"]
			act = {"unit": key, "kind": AiDecision.Action.RUSH, "dest": dest}
		"hold":
			act = {"unit": key, "kind": AiDecision.Action.HOLD}
		"screen":
			if not any_own_acted:
				key = cheapest
				var mid := Vector3.ZERO
				for o in state["objectives"]:
					mid += (o as Dictionary)["pos"] as Vector3
				if not state["objectives"].is_empty():
					mid /= state["objectives"].size()
				act = {"unit": key, "kind": AiDecision.Action.RUSH, "dest": mid}
			else:
				act = _safe_advance(state, key)
				if act.is_empty():
					act = {"unit": key, "kind": AiDecision.Action.HOLD}
		"patient", _:
			act = _safe_advance(state, key)
			if act.is_empty():
				act = {"unit": key, "kind": AiDecision.Action.HOLD}
	if not act.has("unit"):
		act["unit"] = key
	var base := AiMissionEval.score(state, player, BattleSim.reply_threat(state, player))
	return {"used": true, "unit_key": str(act["unit"]), "action": act,
		"intent": "opener doctrine '%s' (research probe)" % doctrine,
		"expectation": {"before": base, "after": base}, "waits": 0, "rolled_units": []}


## The other side's player id, read from the units (any enemy of `player`).
static func _other_player(state: Dictionary, player: int) -> int:
	for key in state["units"]:
		var p := int((state["units"][key] as Dictionary)["player"])
		if p != player:
			return p
	return player


static func _intent(state: Dictionary, best: Dictionary, runner: Dictionary,
		base: float) -> String:
	var txt := "%s: %s — win %.2f → %.2f" % [_name_of(state, str(best["unit_key"])),
		_describe(state, best["action"]), base, float(best["score"])]
	if not runner.is_empty():
		txt += "; over %s: %s (%.2f)" % [_name_of(state, str(runner["unit_key"])),
			_describe(state, runner["action"]), float(runner["score"])]
	return txt


static func _describe(state: Dictionary, action: Dictionary) -> String:
	var kind := int(action.get("kind", AiDecision.Action.HOLD))
	if kind == AiDecision.Action.CHARGE:
		return "charge %s" % _name_of(state, str(action["charge"]))
	if kind == AiDecision.Action.RUSH:
		var obs: Array = state["objectives"]
		for i in range(obs.size()):
			if (obs[i] as Dictionary)["pos"] == action.get("dest"):
				return "rush objective %d" % (i + 1)
		return "rush"
	if kind == AiDecision.Action.ADVANCE:
		return "fall back"
	if action.has("shoot"):
		return "hold and shoot %s" % _name_of(state, str(action["shoot"]))
	return "hold"


static func _name_of(state: Dictionary, key: String) -> String:
	return ((state["units"][key] as Dictionary)["unit"] as GameUnit).get_name()


static func candidates(state: Dictionary, key: String) -> Array:
	var su: Dictionary = state["units"][key]
	var out: Array = [{"unit": key, "kind": AiDecision.Action.HOLD}]
	var shoot := _best_shoot(state, key)
	if shoot != "":
		out.append({"unit": key, "kind": AiDecision.Action.HOLD, "shoot": shoot})
	# NML-1020 lab half: Immobile/Artillery may only Hold (p.13/p.57) — the menu
	# for carriers ends here, so no playout can ever imagine them moving.
	if SoloController.forces_hold((su["unit"] as GameUnit).get_special_rules()):
		return out
	for o in state["objectives"]:
		out.append({"unit": key, "kind": AiDecision.Action.RUSH,
			"dest": (o as Dictionary)["pos"]})
	var charge := _best_charge(state, key)
	if charge != "":
		out.append({"unit": key, "kind": AiDecision.Action.CHARGE,
			"dest": _centre(state["units"][charge]), "charge": charge})
	var threat := _nearest_enemy(state, key)
	if threat != "":
		var away: Vector3 = _centre(su) - _centre(state["units"][threat])
		if away.length() > 0.001:
			out.append({"unit": key, "kind": AiDecision.Action.ADVANCE,
				"dest": _centre(su) + away.normalized() * RETREAT_GOAL_IN * BattleSim.IN2M})
	var patient := _safe_advance(state, key)
	if not patient.is_empty():
		out.append(patient)
	var wave := _second_wave(state, key)
	if not wave.is_empty():
		out.append(wave)
	return out


## The TEACHER menu (P0b, NML-1009). P0 measured where the narrow menu cannot
## express the tree: it offers exactly ONE shoot target (_best_shoot) and ONE
## charge victim (_best_charge, futile-gated), and the tree picks a different
## one in a third of its holds and nearly half of its charges — those
## activations could never carry an imitation label. So the teacher menu adds
## every OTHER target: one hold+shoot per enemy the unit can legally see, one
## charge per living enemy (no futile bar here — the clone learns what the
## teacher DOES; doctrine filters belong on top, not in the transcript).
## The LIVE planner keeps candidates() byte-identical: it pays a full rollout
## per candidate, while the clone scores one with a single net forward.
static func candidates_wide(state: Dictionary, key: String) -> Array:
	var out := candidates(state, key)
	var su: Dictionary = state["units"][key]
	# NML-1020 lab half: the base menu is already hold-only for Immobile/
	# Artillery — the wide builder must not append moves back.
	if SoloController.forces_hold((su["unit"] as GameUnit).get_special_rules()):
		return out
	var seen_shoot := {}
	var seen_charge := {}
	for c in out:
		var cd: Dictionary = c
		if cd.has("shoot"):
			seen_shoot[str(cd["shoot"])] = true
		if cd.has("charge"):
			seen_charge[str(cd["charge"])] = true
	var ours: Array = BattleSim._profiles_of(su, true)
	# Head wave 1 (review find): the TEACHER menu obeys the same charge legality as
	# _best_charge — before this, teacher rows could label a charge the adoption gate
	# then refused, so the book taught moves the body never plays.
	var illegal_cb: Callable = state.get("charge_illegal", Callable())
	# NML-1049: the advance band this unit would really cover, for the reach gate below.
	var advance_in := float(SoloController.sim_move_bands(su["unit"]).get("advance", 6))
	for ek in _enemy_keys(state, key):
		var tu: Dictionary = state["units"][ek]
		if int(tu["alive"]) <= 0:
			continue
		var gap_in := BattleSim.dist_in(su["positions"], tu["positions"])
		if not seen_shoot.has(str(ek)) and BattleSim.sees(su, str(ek)) \
				and _can_shoot_at(su, tu, gap_in):
			out.append({"unit": key, "kind": AiDecision.Action.HOLD, "shoot": str(ek)})
		if not seen_charge.has(str(ek)) and not ours.is_empty() \
				and not (illegal_cb.is_valid() and bool(illegal_cb.call(su["unit"], tu["unit"],
					maxf(BattleSim.dist_in(su["positions"], tu["positions"])
						- BattleSim.CONTACT_IN, 0.0),
					_centre(su), _centre(tu)))):
			out.append({"unit": key, "kind": AiDecision.Action.CHARGE,
				"dest": _centre(tu), "charge": str(ek)})
		# Movement toward the ENEMY — the whole narrow menu is marker-shaped, so
		# on a ONE-marker mission it collapsed: measured on the box, movement
		# coverage fell from 83.6% (three markers) to 36.4% (king_of_the_hill).
		# The tree's other destination has always been "at that unit over there".
		out.append({"unit": key, "kind": AiDecision.Action.RUSH,
			"dest": _centre(tu), "at": str(ek)})
		# ADVANCE **and** SHOOT — the action this menu could never express
		# (measured 16.08.): a shoot target only ever hung on HOLD, so the
		# learned policy could fire only by standing still. It stood still in
		# 3.5% of activations and rushed in 85%, and clone-vs-clone games ended
		# with a median 62 survivors against tree-vs-tree's 54 — it moved and
		# stopped fighting. Advance keeps the shot window open (Rush does not),
		# so this is the move the tree makes constantly and the clone never saw.
		# NML-1049: ...but only when the barrel reaches after that advance. The gap
		# is the OPTIMISTIC one (closing straight in at the full band), so the gate
		# never removes a shot the move could have set up.
		if BattleSim.sees(su, str(ek)) \
				and _can_shoot_at(su, tu, maxf(gap_in - advance_in, 0.0)):
			out.append({"unit": key, "kind": AiDecision.Action.ADVANCE,
				"dest": _centre(tu), "shoot": str(ek)})
	return out


## NML-1049 GHOST SHOTS: can `su` put a shot on `tu` from `d_in` inches? The wide
## menu asked BattleSim.sees() alone — line of sight — so it offered SHOOT to
## gunless units and to targets far past every barrel: on the 633-game c8 corpus
## 402 rows ordered a gunless unit to fire, 155 held and shot beyond range, 1328
## advanced and were still short. The amplifier cannot strip them (an impossible
## shot scores 0, so hold and hold+ghost-shot tie and the pick is arbitrary), so
## the menu must gate. The truth used is the one BattleSim.resolve() fires with —
## profiles_in_range — widened by the unit's range bonus (Royal Legion, spell
## tokens) so a shot the ENGINE allows never falls out of the teacher's menu, plus
## the caster's damage spells: for a gunless mage the spell IS the shot.
## Shooting candidates only — charge, rush and retreat legality are untouched.
static func _can_shoot_at(su: Dictionary, tu: Dictionary, d_in: float) -> bool:
	var reach_in := maxf(d_in - float(SoloController.shooting_range_bonus(su["unit"])), 0.0)
	if not BattleSim._profiles_of(su, false, reach_in).is_empty():
		return true
	return float(BattleSim.spell_ev_of(su, tu, d_in)["ev"]) > 0.0


## P0 MENU-COVERAGE PROBE (Plan B v2, 15.08.): can this menu even EXPRESS the
## move the TEACHER (the decision tree) just chose? Measurement only — nothing
## here decides anything. `move` is the tree's settled activation:
##   kind    : AiDecision.Action (KITE arrives normalised to ADVANCE)
##   goal    : the point it moved toward (movement kinds only)
##   band_m  : the reach it actually used — BOTH sides are clamped to it, so a
##             candidate's 100"-convention retreat goal compares as the step it
##             would really produce, not as a point off the table
##   shoot / charge : victim keys ("" = none)
## Hold and charge match on the VICTIM (picking the same target is part of
## expressing the move); movement matches on where the unit ends up: covered =
## within the 3" seize ring (same spot for mission purposes), loose = within
## one Advance. best_in = -1 when distance does not apply.
const MENU_COVER_IN := 3.0
const MENU_LOOSE_IN := 6.0

static func menu_covers(state: Dictionary, key: String, move: Dictionary,
		wide := false) -> Dictionary:
	return menu_covers_in(candidates_wide(state, key) if wide else candidates(state, key),
		state, key, move)


## Same answer against an ALREADY BUILT menu — P1 logs the menu itself next to
## the teacher's index, and building it twice per activation is pure cost.
## "idx" is WHICH candidate matched (-1 = none): that index IS the imitation
## label the clone trains on.
static func menu_covers_in(cands: Array, state: Dictionary, key: String,
		move: Dictionary) -> Dictionary:
	var kind := int(move.get("kind", AiDecision.Action.HOLD))
	if kind == AiDecision.Action.KITE:
		kind = AiDecision.Action.ADVANCE
	var out := {"menu": cands.size(), "covered": false, "loose": false,
		"best_in": -1.0, "class": "hold", "idx": -1}
	if kind == AiDecision.Action.CHARGE or kind == AiDecision.Action.HOLD:
		out["class"] = "charge" if kind == AiDecision.Action.CHARGE else "hold"
		var field := "charge" if kind == AiDecision.Action.CHARGE else "shoot"
		for i in range(cands.size()):
			var c: Dictionary = cands[i]
			if int(c["kind"]) == kind and str(c.get(field, "")) == str(move.get(field, "")):
				out["covered"] = true
				out["loose"] = true
				out["idx"] = i
				break
		return out
	out["class"] = "move"
	var centre := _centre(state["units"][key])
	var band := maxf(float(move.get("band_m", 0.0)), 0.0)
	var goal_pt := _clamp_to_band(centre, move.get("goal", centre), band)
	# A move that also FIRES is only truly expressed by a candidate that fires at
	# the SAME target. Matching on the destination alone silently dropped half of
	# the teacher's decision — that is how a corpus full of "advance and shoot"
	# taught a clone to advance and never shoot (measured 16.08.).
	var want_shoot := str(move.get("shoot", ""))
	var best := INF
	var best_i := -1
	var shot_best := INF
	var shot_i := -1
	for i in range(cands.size()):
		var cd: Dictionary = cands[i]
		if not cd.has("dest") or int(cd["kind"]) == AiDecision.Action.CHARGE:
			continue
		var d := (_clamp_to_band(centre, cd["dest"], band) - goal_pt).length() / BattleSim.IN2M
		if d < best:
			best = d
			best_i = i
		if want_shoot != "" and str(cd.get("shoot", "")) == want_shoot and d < shot_best:
			shot_best = d
			shot_i = i
	# Prefer the candidate that also carries the shot, but only when it really
	# lands where the teacher went — a matching target is not worth a wrong spot.
	if shot_i >= 0 and shot_best <= MENU_COVER_IN:
		best = shot_best
		best_i = shot_i
	# HONEST, not vacuous. This read `want_shoot == "" or shot_i == best_i`, which
	# short-circuits to TRUE exactly when the shot is being dropped — it reported
	# "100% kept" on a corpus that kept none of them, because production could
	# never set want_shoot at all (fixed 17.08. in SoloController.label_shoot_for).
	# An instrument built to make a loss visible must not be true when there is
	# nothing to lose: `had_shot` is the denominator, and without it the ratio
	# has no meaning.
	out["had_shot"] = want_shoot != ""
	out["shot_kept"] = shot_i >= 0 and shot_i == best_i
	if best < INF:
		out["best_in"] = best
		out["covered"] = best <= MENU_COVER_IN
		out["loose"] = best <= MENU_LOOSE_IN
		if bool(out["covered"]):
			out["idx"] = best_i
	return out


## The step a goal really produces: the band clamp BattleSim.resolve applies.
static func _clamp_to_band(centre: Vector3, goal: Vector3, band_m: float) -> Vector3:
	var away := goal - centre
	var d := away.length()
	if d <= band_m or d <= 0.001:
		return goal
	return centre + away / d * band_m


## D21/D23 (grill 15.08.) — the SECOND WAVE: a follow-up move toward where
## it is needed. Offered when a friendly unit CONTESTS a marker (enemy in
## the same 3" ring), when a friend is battered (below half or shaken),
## and ALWAYS for idle rear units (nearest far marker then). The stop
## point is support distance: NEXT round's rush reaches the goal — arrive
## ready, not spent. Timing (D6) weighs the VALUE downstream, never gates
## the offer (his explicit non-pick).
static func _second_wave(state: Dictionary, key: String) -> Dictionary:
	var su: Dictionary = state["units"][key]
	var centre := _centre(su)
	var me := int(su["player"])
	var goal := Vector3.INF
	var why := ""
	var best_d := INF
	for o in state["objectives"]:
		var op: Vector3 = (o as Dictionary)["pos"]
		var friend_in := false
		var enemy_in := false
		for fk in state["units"]:
			var fu: Dictionary = state["units"][fk]
			if int(fu["alive"]) <= 0 or str(fk) == key:
				continue
			var near := false
			for pp in fu["positions"]:
				if ((pp as Vector3) - op).length() <= 3.0 * BattleSim.IN2M:
					near = true
					break
			if near:
				if int(fu["player"]) == me:
					friend_in = true
				else:
					enemy_in = true
		if friend_in and enemy_in:
			var d := (op - centre).length()
			if d < best_d:
				best_d = d
				goal = op
				why = "contested marker"
	if goal == Vector3.INF:
		for fk in state["units"]:
			var fu: Dictionary = state["units"][fk]
			if str(fk) == key or int(fu["player"]) != me or int(fu["alive"]) <= 0:
				continue
			if bool(fu.get("shaken", false)) or _below_half(fu):
				var fc := _centre(fu)
				var d2 := (fc - centre).length()
				if d2 > 4.0 * BattleSim.IN2M and d2 < best_d:
					best_d = d2
					goal = fc
					why = "battered friend"
	if goal == Vector3.INF:
		for o in state["objectives"]:
			var d3 := ((o as Dictionary)["pos"] as Vector3 - centre).length()
			if d3 / BattleSim.IN2M > 9.0 and d3 < best_d:
				best_d = d3
				goal = (o as Dictionary)["pos"]
				why = "idle reserve moves up"
	if goal == Vector3.INF:
		return {}
	var rush_in := float(SoloController.sim_move_bands(su["unit"]).get("rush", 12))
	var dist_in := (goal - centre).length() / BattleSim.IN2M
	if dist_in <= 0.001:
		return {}
	var stop_in := maxf(dist_in - (rush_in + 2.0), 0.0)
	var dest: Vector3 = goal - (goal - centre).normalized() * stop_in * BattleSim.IN2M
	return {"unit": key, "kind": AiDecision.Action.ADVANCE, "dest": dest,
		"wave": why}


static func _below_half(su: Dictionary) -> bool:
	# v0: model count against the snapshot's position slots (conservative —
	# when slots track only the living, only 'shaken' triggers the wave).
	return int(su["alive"]) * 2 <= (su["positions"] as Array).size()


static func _centre(su: Dictionary) -> Vector3:
	var c := Vector3.ZERO
	var ps: Array = su["positions"]
	for p in ps:
		c += p as Vector3
	return c / maxi(ps.size(), 1)


static func _enemy_keys(state: Dictionary, key: String) -> Array:
	var player: int = int((state["units"][key] as Dictionary)["player"])
	var out: Array = []
	for k in state["units"]:
		var su: Dictionary = state["units"][k]
		if int(su["player"]) != player and int(su["alive"]) > 0:
			out.append(k)
	return out


static func _best_shoot(state: Dictionary, key: String) -> String:
	var su: Dictionary = state["units"][key]
	var best := ""
	var best_ev := 0.0
	for ek in _enemy_keys(state, key):
		if not BattleSim.sees(su, str(ek)):
			continue
		var tu: Dictionary = state["units"][ek]
		var d := BattleSim.dist_in(su["positions"], tu["positions"])
		var ev := AiEv.shoot_ev(BattleSim._profiles_of(su, false, d),
			BattleSim._ctx_of(su), BattleSim._ctx_of(tu), d)
		if ev > best_ev:
			best_ev = ev
			best = str(ek)
	return best


## Best hurtable melee target by charge_score; targets under the live
## futile-charge bar (SoloController.FUTILE_CHARGE_EV) are never candidates.
static func _best_charge(state: Dictionary, key: String) -> String:
	var su: Dictionary = state["units"][key]
	var ours: Array = BattleSim._profiles_of(su, true)
	if ours.is_empty():
		return ""
	# Head wave 1: the controller hands down its charge-legality truth (aircraft, band
	# incl. Melee Shrouding, difficult cap) — a victim the rules forbid never enters the
	# menu, so no rollout wastes budget on it. Absent key (lab tests, old snapshots) =
	# byte-identical menu.
	var illegal_cb: Callable = state.get("charge_illegal", Callable())
	var best := ""
	var best_score := -INF
	for ek in _enemy_keys(state, key):
		var tu: Dictionary = state["units"][ek]
		if illegal_cb.is_valid() and bool(illegal_cb.call(su["unit"], tu["unit"],
				maxf(BattleSim.dist_in(su["positions"], tu["positions"])
					- BattleSim.CONTACT_IN, 0.0),
				_centre(su), _centre(tu))):
			# Review find (workflow 22.08.): dist_in is centre-to-centre while the gate's
			# truth measures base-edge gap — the CONTACT_IN slack is exactly the sim's own
			# landing rule (post-move centre gap <= CONTACT_IN = melee), so the menu offers
			# precisely what the sim can execute, no less.
			continue
		var us := BattleSim._ctx_of(su)
		var them := BattleSim._ctx_of(tu)
		if AiEv.melee_ev(ours, us, them, true) < SoloController.FUTILE_CHARGE_EV:
			continue
		var s := AiEv.charge_score(ours, us, BattleSim._profiles_of(tu, true), them)
		if s > best_score:
			best_score = s
			best = str(ek)
	return best


static func _nearest_enemy(state: Dictionary, key: String) -> String:
	var su: Dictionary = state["units"][key]
	var best := ""
	var best_d := INF
	for ek in _enemy_keys(state, key):
		var d := BattleSim.dist_in(su["positions"], (state["units"][ek] as Dictionary)["positions"])
		if d < best_d:
			best_d = d
			best = str(ek)
	return best


# === S-wave: playout search (grill 15.08., D16-D19) ==========================
# The triple-chance finding: no static judge (planner eval 51.4%, fork-net
# 52.9%, maintainer 53%) reads clear fork outcomes from the position — but
# the cheap-policy playout REPRODUCES them (98.2% split-half). So on close
# calls the planner PLAYS ITS CANDIDATES OUT instead of judging: cheap
# policy for both sides (D18), playout verdict decides (D19). Local rng
# only — the game's dice stream is never touched.


## Deterministic per-state seed for playout prngs: same position + same
## player = same dice, so the pick is reproducible (A/B and replay safe).
static func _playout_sig(state: Dictionary, player: int) -> int:
	return hash("%d:%d:%s" % [int(state.get("round", 0)), player,
		str(BattleSim.board_rows(state))])


## Hard round cap — INSURANCE, not a rule. A playout that never returns does
## not fail the arena, it HANGS it, so a nonsense rounds_total (corrupt save,
## synthetic state, a future mission with a broken descriptor) is clamped
## here. Real missions run 4-6 rounds, so the cap only ever binds on a broken
## state — and it binds VISIBLY, through rounds_played.
const PLAYOUT_MAX_ROUNDS := 12


## Play ONE branch to game end under the cheap policy, reported in the ARENA's
## vocabulary so a played-out game and a real tools/arena_match.gd game are a
## DIRECT comparison (that comparison is the fidelity gate):
##   "p1" / "p2"     : mission-currency points — final markers for Face-Off's
##                     END scoring, cumulative VPs when the state carries
##                     scoring="round_vp" (unchanged; the search reads these)
##   "vp"            : {"p1","p2"} the full VP ledger incl. the book's end bonus
##   "objectives"    : {"p1","p2","neutral"} final marker owners
##   "survivors"     : {"p1","p2"} living models per side at game end
##   "rounds_played" : the round number the game ended in (arena_match reports
##                     army_manager.current_round — same meaning)
##   "winner"        : "p1" | "p2" | "draw" (arena_match's rule: points decide;
##                     a board with NO markers falls back to survivors)
## Twin of the factory's fork playout — same seize rule
## (BattleSim.playout_seize), so search verdicts and fork labels speak the same
## currency. `prng` is a LOCAL generator: a playout never reads or advances the
## game's dice stream (the global RNG), so replaying a game through it cannot
## change the game it is measuring.
static func full_playout(state0: Dictionary, action: Dictionary, player: int,
		prng: RandomNumberGenerator) -> Dictionary:
	var owners: Array = []
	for o in state0.get("objectives", []):
		owners.append(int((o as Dictionary).get("owner", 0)))
	var state := BattleSim.resolve_stochastic(state0, action, prng)
	var turn := 2 if player == 1 else 1
	# NML-1010 W2: the playout continues the LIVE ledger (a playout that
	# counts only remaining-round VP can call an already-won game lost) and
	# speaks the mission's flavour; empty flavour = the v1 end-majority rule.
	var vp := [0, 0]
	var vp_live: Variant = state0.get("vp")
	if vp_live is Array and (vp_live as Array).size() == 2:
		vp = [int(vp_live[0]), int(vp_live[1])]
	var vp_flavour: Dictionary = state0.get("vp_flavour", {}) as Dictionary
	var vp_memo: Dictionary = (state0.get("vp_memo", {}) as Dictionary).duplicate()
	var res := _playout_round_tail(state, turn, prng)
	state = res["state"]
	var opener: int = (2 if int(res["last"]) == 1 else 1) if int(res["last"]) != 0 else turn
	BattleSim.playout_seize(state, owners)
	if state.has("markers_meta"):
		BattleSim.apply_destroy_step(state["markers_meta"], owners, state["destroy_seq"])
	BattleSim.vp_score_round(owners, vp, vp_flavour, vp_memo, state.get("markers_meta", []))
	var round0 := int(state0.get("round", 1))
	var rounds_total: int = mini(int(state.get("rounds_total", 4)),
		round0 + PLAYOUT_MAX_ROUNDS - 1)
	for r in range(round0 + 1, rounds_total + 1):
		state["round"] = r
		for k in state["units"]:
			_round_start_refresh(state["units"][k])
		res = _playout_round_tail(state, opener, prng)
		state = res["state"]
		if int(res["last"]) != 0:
			opener = 2 if int(res["last"]) == 1 else 1
		BattleSim.playout_seize(state, owners)
		if state.has("markers_meta"):
			BattleSim.apply_destroy_step(state["markers_meta"], owners, state["destroy_seq"])
		BattleSim.vp_score_round(owners, vp, vp_flavour, vp_memo, state.get("markers_meta", []))
	# NML-1008 CORRECTED (record check 15.08. evening): our v1 missions are
	# FACE-OFF = END-scored per book AND per grill D4 (12.08.); the VP ledger
	# is always closed out (book: +1 for holding more markers at game end) and
	# stays armed for the PROGRESSIVE wave, but WHICH currency decides is the
	# mission's business. W2: the flavour now picks end/round/none majority.
	BattleSim.vp_score_end(owners, vp, vp_flavour)
	var p1 := 0
	var p2 := 0
	for o in owners:
		if int(o) == 1:
			p1 += 1
		elif int(o) == 2:
			p2 += 1
	var alive1 := 0
	var alive2 := 0
	for k in state["units"]:
		var su: Dictionary = state["units"][k]
		if int(su["player"]) == 1:
			alive1 += int(su["alive"])
		elif int(su["player"]) == 2:
			alive2 += int(su["alive"])
	var round_vp := str(state0.get("scoring", "end")) == "round_vp"
	var pts1: int = int(vp[0]) if round_vp else p1
	var pts2: int = int(vp[1]) if round_vp else p2
	if str(state0.get("scoring", "end")) == "sabotage":
		# W3: the playout speaks sabotage's own goal — destroy theirs, keep
		# yours — so the planner optimises the mission that is actually played.
		var sw := BattleSim.sabotage_winner(state.get("markers_meta", []))
		pts1 = 1 if sw == "p1" else 0
		pts2 = 1 if sw == "p2" else 0
	var winner := "draw"
	if pts1 != pts2:
		winner = "p1" if pts1 > pts2 else "p2"
	elif owners.is_empty() and alive1 != alive2:
		winner = "p1" if alive1 > alive2 else "p2"
	return {"p1": pts1, "p2": pts2,
		"vp": {"p1": int(vp[0]), "p2": int(vp[1])},
		"objectives": {"p1": p1, "p2": p2, "neutral": owners.size() - p1 - p2},
		"survivors": {"p1": alive1, "p2": alive2},
		"rounds_played": maxi(rounds_total, round0),
		"winner": winner}


## Seed-taking twin: the same playout with its LOCAL generator built here, so
## a caller only ever has to name a number. Same state + same seed = the same
## game, every time — the reproducibility the fidelity replay and every A/B
## rest on.
static func full_playout_seeded(state0: Dictionary, action: Dictionary,
		player: int, playout_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = playout_seed
	return full_playout(state0, action, player, rng)


## Cheap-policy alternation until the round runs dry (official one-for-one;
## a dry side passes the tail). Returns {"state", "last"}.
static func _playout_round_tail(state: Dictionary, turn: int,
		prng: RandomNumberGenerator) -> Dictionary:
	var last := 0
	var guard: int = (state["units"] as Dictionary).size() * 2 + 4
	while guard > 0:
		guard -= 1
		var a := _playout_pick(state, turn)
		if a.is_empty():
			var other := 2 if turn == 1 else 1
			a = _playout_pick(state, other)
			if a.is_empty():
				break
			turn = other
		state = BattleSim.resolve_stochastic(state, a, prng)
		last = turn
		turn = 2 if turn == 1 else 1
	return {"state": state, "last": last}


static func _playout_pick(state: Dictionary, player: int) -> Dictionary:
	for k in state["units"]:
		var su: Dictionary = state["units"][k]
		if int(su["player"]) == player and not bool(su["activated"]) \
				and int(su["alive"]) > 0:
			return _policy_step(state, player, playout_rich())
	return {}

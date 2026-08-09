class_name AiPlanner
extends RefCounted
## Phase-1 step 5, first half: candidate generation per plan D3 — tactical
## points, not a grid. For one un-activated unit: hold; hold + best-EV shoot;
## one rush per objective; a charge on the best hurtable target (scored by
## AiEv.charge_score, gated by the live futile-charge doctrine); one retreat
## point away from the nearest threat. Destinations are GOALS — resolve clamps
## them to the legal band, so unreachable points degrade to "move toward".


const RETREAT_GOAL_IN := 100.0   # far marker; the band clamp turns it into one move away


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


## R2 (round-rollout search): rank every (unit, action) pair 1-ply with the
## rich leaf exactly like plan(), keep the TOP_K, play each survivor's round
## out and take the best END-OF-ROUND rich-leaf score. top_k <= 0 degrades to
## plan() byte-identically (the safety valve and the red-green seam).
## Deterministic: prefilter ties keep capture order (explicit index tiebreak).
static func plan_with_rollout(state: Dictionary, player: int,
		top_k: int = ROLLOUT_TOP_K) -> Dictionary:
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
	var best := {}
	var runner := {}
	for cand in pool:
		var rs := _blend_score(rollout_boundaries(state, cand["action"], player), player)
		if OS.get_environment("NML_PLAN_DUMP") == "1":   # diagnosis-only; ladder silent without it
			printerr("[PLAN] R%d %s kind=%d 1ply=%.4f rolled=%.4f" % [int(state["round"]),
				str(cand["unit_key"]), int((cand["action"] as Dictionary).get("kind", -1)),
				float(cand["score"]), rs])
		var rolled := {"unit_key": cand["unit_key"], "action": cand["action"], "score": rs}
		if best.is_empty() or rs > float(best["score"]):
			runner = best
			best = rolled
		elif runner.is_empty() or rs > float(runner["score"]):
			runner = rolled
	var waits := 0
	for key in state["units"]:
		var su: Dictionary = state["units"][key]
		if int(su["player"]) == player and not bool(su["activated"]) \
				and int(su["alive"]) > 0 and str(key) != str(best["unit_key"]):
			waits += 1
	return {"used": true, "unit_key": best["unit_key"], "action": best["action"],
		"intent": _intent(state, best, runner, base) + " (round played out; %d own kept back)" % waits,
		"expectation": {"before": base, "after": float(best["score"])},
		"runner_up": runner, "waits": waits, "rolled_units": covered.keys()}


const ROLLOUT_HORIZON_ROUNDS := 2   # R6: a move's price only shows NEXT round — round 1 alone is a movement round


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
		horizon_rounds: int = ROLLOUT_HORIZON_ROUNDS) -> Dictionary:
	var ends := rollout_boundaries(state, first_action, me, horizon_rounds)
	return ends[ends.size() - 1]


## R7: the same playout, but returning the state AT EVERY round boundary of
## the horizon (index 0 = end of the current round, last = horizon end) — the
## caller prices each boundary and blends. The boundary snapshot is taken
## BEFORE _cross_round mutates the walker, so every entry is a true round-end.
static func rollout_boundaries(state: Dictionary, first_action: Dictionary, me: int,
		horizon_rounds: int = ROLLOUT_HORIZON_ROUNDS) -> Array:
	var out: Array = []
	var cur := BattleSim.resolve(state, first_action)
	var turn := _other_player(state, me)
	var rounds_left := maxi(horizon_rounds, 1)
	var guard: int = ((state["units"] as Dictionary).size() + 2) * rounds_left
	while guard > 0:
		guard -= 1
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


## R7/D: price a rollout's round boundaries as ONE number. Responder seat:
## geometric depth discount, normalized — the current round's certainty keeps
## the 2/3 majority, the imagined next round refines. Opener seat: the LAST
## boundary alone votes — an opener's move only shows its worth after the
## enemy's full reply, so the deep look must be allowed to outvote.
static func _blend_score(ends: Array, player: int) -> float:
	if opener_seat:
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
static func _cross_round(cur: Dictionary) -> int:
	cur["round"] = int(cur["round"]) + 1
	var counts := {}
	for k in cur["units"]:
		var su: Dictionary = cur["units"][k]
		su["activated"] = false
		su["fatigued"] = false
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
	var band_m := float(SoloController.move_bands_for_unit(su["unit"], null).get("advance", 6)) \
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
		var bands := SoloController.move_bands_for_unit(u, null)
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
		# Farthest point along the line that stays safe — half-inch grid, deterministic.
		var step := 0.5 * BattleSim.IN2M
		var best_t := 0.0
		var t := step
		while t <= band_m + 0.0001:
			var safe := true
			for e in threats:
				if _gap_m(positions, dir * t, e["positions"]) <= float(e["reach"]):
					safe = false
					break
			if safe:
				best_t = t
			t += step
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
	return out


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
	var best := ""
	var best_score := -INF
	for ek in _enemy_keys(state, key):
		var tu: Dictionary = state["units"][ek]
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

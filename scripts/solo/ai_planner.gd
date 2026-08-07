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


## R1 (round-rollout search): play the rest of the ROUND out after `first_action`
## by `me` — sides alternate as in the real rule, a dry side lets the other play
## its tail, every step is the cheap-policy greedy pick. Returns the end-of-round
## state; the CALLER prices it with the rich leaf (eval + reply_threat). Pure and
## deterministic. The guard only backstops a logic error, it never binds: one
## round has at most units-many activations.
static func rollout(state: Dictionary, first_action: Dictionary, me: int) -> Dictionary:
	var cur := BattleSim.resolve(state, first_action)
	var turn := _other_player(state, me)
	var guard: int = (state["units"] as Dictionary).size() + 2
	while guard > 0:
		guard -= 1
		var a := _policy_step(cur, turn)
		if a.is_empty():
			turn = _other_player(cur, turn)
			a = _policy_step(cur, turn)
			if a.is_empty():
				break
		cur = BattleSim.resolve(cur, a)
		turn = _other_player(cur, turn)
	return cur


## Rollout policy, one step: the best restricted move of `player`'s un-activated
## units by the CHEAP leaf (mission eval WITHOUT reply pricing). {} when dry.
static func _policy_step(state: Dictionary, player: int) -> Dictionary:
	var best := {}
	var best_s := -INF
	for key in state["units"]:
		var su: Dictionary = state["units"][key]
		if int(su["player"]) != player or bool(su["activated"]) or int(su["alive"]) <= 0:
			continue
		for action in _policy_candidates(state, str(key)):
			var s := AiMissionEval.score(BattleSim.resolve(state, action), player)
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
	return out


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

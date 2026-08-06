class_name AiPlanner
extends RefCounted
## Phase-1 step 5, first half: candidate generation per plan D3 — tactical
## points, not a grid. For one un-activated unit: hold; hold + best-EV shoot;
## one rush per objective; a charge on the best hurtable target (scored by
## AiEv.charge_score, gated by the live futile-charge doctrine); one retreat
## point away from the nearest threat. Destinations are GOALS — resolve clamps
## them to the legal band, so unreachable points degrade to "move toward".


const RETREAT_GOAL_IN := 100.0   # far marker; the band clamp turns it into one move away


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

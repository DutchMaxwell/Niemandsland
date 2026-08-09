class_name AiMissionEval
extends RefCounted
## Planner phase-1 step 4: a P(win) proxy in [0,1] over a BattleSim state.
## Per objective, both sides project CONTROL over the remaining rounds — band
## reachability times surviving strength — and the objective's probability is
## the soft ratio of the projections; the state score is the mean over all
## objectives. Wounds enter ONLY via the strength projection (plan decision).
## Weights are hand-tuned v0; the arena A/B is the judge, not intuition.


const DISCOUNT := 0.5   # presence halves per future round still needed to arrive


## `incoming` (danger term): my_unit_key -> expected reply wounds
## (BattleSim.reply_threat); each mapped unit projects with that strength
## already shot off. Empty map = pre-danger behaviour, byte-identical.
static func score(state: Dictionary, player: int, incoming: Dictionary = {}) -> float:
	var objectives: Array = state["objectives"]
	if objectives.is_empty():
		return 0.5
	var total := 0.0
	for o in objectives:
		total += _objective_p(state, o as Dictionary, player, incoming)
	return total / objectives.size()


static func _objective_p(state: Dictionary, obj: Dictionary, player: int,
		incoming: Dictionary = {}) -> float:
	var mine := 0.0
	var theirs := 0.0
	for key in state["units"]:
		var su: Dictionary = state["units"][key]
		var presence := _presence(state, su, obj["pos"] as Vector3,
			float(incoming.get(str(key), 0.0)))
		if int(su["player"]) == player:
			mine += presence
		else:
			theirs += presence
	if mine + theirs <= 0.0:
		# Nobody can ever get there — ownership persists (seize_objectives rule).
		var owner := int(obj.get("owner", 0))
		return 0.5 if owner == 0 else (1.0 if owner == player else 0.0)
	return mine / (mine + theirs)


## E1 (eval-tuning wave): the eval's RAW FEATURE VECTOR for a state, from
## `player`'s perspective — the offline fit's input, logged per planner round
## boundary by the arena. Flat name->float, all cheap, all explainable. The
## tail_* counts are the material of the proven seat effect (who can still
## act near a marker decides its seize); the eval itself cannot see them yet.
static func features(state: Dictionary, player: int, incoming: Dictionary = {}) -> Dictionary:
	var f := {"round_frac": float(state["round"]) / maxf(float(state["rounds_total"]), 1.0),
		"my_wounds": 0.0, "their_wounds": 0.0, "my_units": 0.0, "their_units": 0.0,
		"my_unactivated": 0.0, "their_unactivated": 0.0, "my_incoming": 0.0,
		"presence_mine": 0.0, "presence_theirs": 0.0, "tail_mine": 0.0, "tail_theirs": 0.0,
		"obj_owned_mine": 0.0, "obj_owned_theirs": 0.0}
	for v in incoming.values():
		f["my_incoming"] += float(v)
	for key in state["units"]:
		var su: Dictionary = state["units"][key]
		if int(su["alive"]) <= 0:
			continue
		var mine := int(su["player"]) == player
		var wounds := 0.0
		for w in su["wounds"]:
			wounds += float(w)
		f["my_wounds" if mine else "their_wounds"] += wounds
		f["my_units" if mine else "their_units"] += 1.0
		if not bool(su.get("activated", false)):
			f["my_unactivated" if mine else "their_unactivated"] += 1.0
		var rush := float(SoloController.move_bands_for_unit(su["unit"], null).get("rush", 12))
		for o in state["objectives"]:
			var d := INF
			for p in su["positions"]:
				d = minf(d, ((p as Vector3) - ((o as Dictionary)["pos"] as Vector3)).length())
			d /= BattleSim.IN2M
			f["presence_mine" if mine else "presence_theirs"] += _presence(state, su,
				(o as Dictionary)["pos"] as Vector3, float(incoming.get(str(key), 0.0)))
			if not bool(su.get("activated", false)) and not bool(su.get("shaken", false)) \
					and d <= SoloController.OBJECTIVE_CONTROL_IN + rush:
				f["tail_mine" if mine else "tail_theirs"] += 1.0
	for o in state["objectives"]:
		var owner := int((o as Dictionary).get("owner", 0))
		if owner == player:
			f["obj_owned_mine"] += 1.0
		elif owner != 0:
			f["obj_owned_theirs"] += 1.0
	return f


## Projected hold strength of ONE unit at ONE objective: its remaining wounds,
## discounted per future activation it still needs to reach the control ring.
## Dead units project nothing; a shaken unit pays one recovery activation
## first (it can neither seize nor contest until it idles — same rule the
## seize verdict applies today, read as a projection).
static func _presence(state: Dictionary, su: Dictionary, obj_pos: Vector3,
		threat := 0.0) -> float:
	if int(su["alive"]) <= 0:
		return 0.0
	var d := INF
	for p in su["positions"]:
		d = minf(d, ((p as Vector3) - obj_pos).length())
	d /= BattleSim.IN2M
	var rush := float(SoloController.move_bands_for_unit(su["unit"], null).get("rush", 12))
	var needed := 0
	if d > SoloController.OBJECTIVE_CONTROL_IN:
		needed = int(ceil((d - SoloController.OBJECTIVE_CONTROL_IN) / maxf(rush, 1.0)))
	if bool(su.get("shaken", false)):
		needed += 1
	var moves_left: int = int(state["rounds_total"]) - int(state["round"]) \
		+ (0 if bool(su.get("activated", false)) else 1)
	if needed > moves_left:
		return 0.0
	var strength := 0.0
	for w in su["wounds"]:
		strength += float(w)
	return maxf(strength - threat, 0.0) * pow(DISCOUNT, needed)

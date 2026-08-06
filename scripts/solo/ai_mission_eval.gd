class_name AiMissionEval
extends RefCounted
## Planner phase-1 step 4: a P(win) proxy in [0,1] over a BattleSim state.
## Per objective, both sides project CONTROL over the remaining rounds — band
## reachability times surviving strength — and the objective's probability is
## the soft ratio of the projections; the state score is the mean over all
## objectives. Wounds enter ONLY via the strength projection (plan decision).
## Weights are hand-tuned v0; the arena A/B is the judge, not intuition.


const DISCOUNT := 0.5   # presence halves per future round still needed to arrive


static func score(state: Dictionary, player: int) -> float:
	var objectives: Array = state["objectives"]
	if objectives.is_empty():
		return 0.5
	var total := 0.0
	for o in objectives:
		total += _objective_p(state, o as Dictionary, player)
	return total / objectives.size()


static func _objective_p(state: Dictionary, obj: Dictionary, player: int) -> float:
	var mine := 0.0
	var theirs := 0.0
	for key in state["units"]:
		var su: Dictionary = state["units"][key]
		var presence := _presence(state, su, obj["pos"] as Vector3)
		if int(su["player"]) == player:
			mine += presence
		else:
			theirs += presence
	if mine + theirs <= 0.0:
		# Nobody can ever get there — ownership persists (seize_objectives rule).
		var owner := int(obj.get("owner", 0))
		return 0.5 if owner == 0 else (1.0 if owner == player else 0.0)
	return mine / (mine + theirs)


## Projected hold strength of ONE unit at ONE objective: its remaining wounds,
## discounted per future activation it still needs to reach the control ring.
## Dead units project nothing; a shaken unit pays one recovery activation
## first (it can neither seize nor contest until it idles — same rule the
## seize verdict applies today, read as a projection).
static func _presence(state: Dictionary, su: Dictionary, obj_pos: Vector3) -> float:
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
	return strength * pow(DISCOUNT, needed)

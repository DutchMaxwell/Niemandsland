class_name AiMissionEval
extends RefCounted
## Planner phase-1 step 4: a P(win) proxy in [0,1] over a BattleSim state.
## Per objective, both sides project CONTROL over the remaining rounds — band
## reachability times surviving strength — and the objective's probability is
## the soft ratio of the projections; the state score is the mean over all
## objectives. Wounds enter ONLY via the strength projection (plan decision).
## Weights are hand-tuned v0; the arena A/B is the judge, not intuition.


const DISCOUNT := 0.5   # presence halves per future round still needed to arrive


# === E4 (eval-tuning wave): the FITTED eval ===
## Provenance: eval_fit.py --gd over selfplay_out/eval_data_v1 — 300 farm
## games (planner_v0 vs albtraum, both orders, seeds 1-75), 1180 labeled
## round-start positions; holdout test AUC 0.929, round-1-only AUC 0.907.
## Raw-space logistic weights (standardization folded in). Re-fit = re-run
## the tool and replace this block; never hand-edit numbers.
const FIT_W := {
	"my_incoming": 0.097222, "my_unactivated": 0.738885, "my_units": -0.549964,
	"my_wounds": 0.016974, "obj_owned_mine": 0.384703, "obj_owned_theirs": -0.111727,
	"presence_mine": 0.070416, "presence_theirs": -0.063847, "round_frac": -0.550355,
	"tail_mine": 0.162490, "tail_theirs": -0.255218, "their_unactivated": -1.288218,
	"their_units": 0.578704, "their_wounds": -0.011167,
}
const FIT_B := 2.507512

## Routes every score() call through the fitted eval — set per planner pick by
## the controller from the difficulty preset (planner_v1). Static on purpose:
## the planner's whole static call tree (blend, policy, prefilter) switches
## without threading a parameter. CAVEAT: process-global — two PLANNER presets
## with different eval modes in ONE game would fight over it (the arena pairs
## a planner side against a tree side, so this never binds today).
static var fit_mode := false


## `incoming` (danger term): my_unit_key -> expected reply wounds
## (BattleSim.reply_threat); each mapped unit projects with that strength
## already shot off. Empty map = pre-danger behaviour, byte-identical.
static func score(state: Dictionary, player: int, incoming: Dictionary = {}) -> float:
	if fit_mode:
		return _score_fit(state, player, incoming)
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


## E4: logistic P(win) over the raw features. A FINISHED round is scored as
## the NEXT round's fresh start (flags cleared, round+1) — that is the
## distribution the fit was trained on, and it restores the tail/seat signal
## a spent round hides (rollout leaves are exactly round ends).
static func _score_fit(state: Dictionary, player: int, incoming: Dictionary) -> float:
	var view := state
	if int(state["round"]) < int(state["rounds_total"]) and _all_activated(state):
		view = BattleSim.clone_state(state)
		view["round"] = int(view["round"]) + 1
		for k in view["units"]:
			(view["units"][k] as Dictionary)["activated"] = false
	var f := features(view, player, incoming)
	var z := float(FIT_B)
	for k in FIT_W:
		z += float(FIT_W[k]) * float(f.get(k, 0.0))
	return 1.0 / (1.0 + exp(-clampf(z, -30.0, 30.0)))


static func _all_activated(state: Dictionary) -> bool:
	for k in state["units"]:
		var su: Dictionary = state["units"][k]
		if int(su["alive"]) > 0 and not bool(su.get("activated", false)):
			return false
	return true


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

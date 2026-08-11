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
## Provenance (v8, SIZE-NORMALISED): ratio features (force-relative — the
## ladder-v3 size collapse showed absolutes leave their trained range on
## 1500/2000pt armies) fitted per-activation TD (LAM .7, sign priors) over
## the FULL pooled fair corpus (1100 games incl. mixed sizes, 11575 rows).
## Every controllable carries doctrine-signed weight as a fraction of the
## own force. Prior (v5): per-activation TD (LAM 0.7, sign priors) over
## eval_data_fair — the first weights learned from UNCONTAMINATED games
## (NML-1002/1003 fixed, symmetric varied maps; 200 games, 2191 rows,
## outcome-AUC 0.768 — fair games are honestly harder to predict). Every
## controllable feature carries doctrine-signed weight (cover +/-, exposure -,
## focus load -). Prior note (v4, per-activation TD): eval_fit TD pass over eval_data_v3
## (300 games, 2826 PER-PICK rows, chained per side by seq; LAM=0.7,
## doctrine sign priors). FIRST fit where the move-controllable features
## carry real, correctly-signed weight: my_charge_exposed -0.29 std,
## their_charge_exposed +0.26, cover_mine +0.07 — round-level labels never
## could (credit too coarse). Outcome-AUC 0.891 (TD trades a little pure
## prediction for controllability). Prior note (v2 RESTORED 10.08.): v3
## (sign-constrained refit on
## eval_data_v2) measured 40.0% vs v2's 43.0% — same-structure refits
## oscillate within noise; v2 stays until a structure-level change (per-
## activation TD) earns its A/B. Original v3 note follows for the record.
## (v3, self-play round 3): SIGN-CONSTRAINED fit over eval_data_v2
## (300 games of the v2 stack, 1188 rows, 19 logged features); holdout test
## AUC 0.941. Doctrine signs enforced by projected gradient — under the
## constraint the data pushed ALL four E5 controllable features to ~zero
## (cover, charge exposure, focus load): observational outcomes carry no
## causal-direction signal for them, exactly the predictor!=controller trap.
## Their value needs consequence-aware training targets (TD) — next rung.
## Re-fit = re-run the tool and replace this block; never hand-edit numbers.
const FIT_W := {
	"presence_mine/my_wounds": 0.878619, "presence_theirs/their_wounds": -0.866414,
	"tail_mine/my_units": 0.009734, "tail_theirs/their_units": -0.019579,
	"my_unactivated/my_units": 1.569704, "their_unactivated/their_units": -1.862250,
	"my_incoming/my_wounds": -1.048846, "cover_mine/my_units": 0.285064,
	"cover_theirs/their_units": -0.714390, "my_charge_exposed/my_units": -0.672654,
	"their_charge_exposed/their_units": 0.227429, "obj_owned_mine": 0.483178,
	"obj_owned_theirs": -0.459405, "round_frac": 0.838045,
}
const FIT_B := 0.144714
## Research seam: the PREVIOUS weight set (v2, outcome-labels) selectable via
## NML_FIT_WEIGHTS=v2 — both sets were tuned on CONTAMINATED games, the clean
## ladder re-ranks them.
const FIT_W_V2 := {
	"my_unactivated": 0.708979, "obj_owned_mine": 0.327349,
	"obj_owned_theirs": -0.290469, "presence_mine": 0.062309,
	"presence_theirs": -0.041864, "round_frac": 0.763686,
	"tail_mine": 0.134124, "tail_theirs": -0.336638,
	"their_unactivated": -0.564309,
}
const FIT_B_V2 := -0.472502
static var _wsel := ""   # lazy env cache


static func _weights() -> Array:
	if _wsel == "":
		_wsel = "v2" if OS.get_environment("NML_FIT_WEIGHTS") == "v2" else "v4"
	return [FIT_W_V2, FIT_B_V2] if _wsel == "v2" else [FIT_W, FIT_B]

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
const FIT_BLEND_DEFAULT := 0.5   # E4.2: fitted share; the hand eval keeps the move gradient

## Measurement seam: NML_FIT_BLEND overrides the fitted share for sweep runs
## (read once per process; the ladder without the env is byte-identical to
## the committed default). Cache -1 = unread.
static var _blend := -1.0

static func fit_blend() -> float:
	if _blend < 0.0:
		var e := OS.get_environment("NML_FIT_BLEND")
		_blend = clampf(float(e), 0.0, 1.0) if e != "" else FIT_BLEND_DEFAULT
	return _blend


static func score(state: Dictionary, player: int, incoming: Dictionary = {}) -> float:
	if fit_mode:
		# E4.2 blend: pure fit played WORSE than the hand eval (v1.1 A/B 37%
		# vs 40.5%) — a strong outcome PREDICTOR was a weak move CONTROLLER
		# (its dominant signals are not move-controllable). The blend keeps
		# the hand eval's sensitivity to material/position and adds the
		# fit's seat/tempo context (tail counts at the next-round view).
		var fb := fit_blend()
		return (1.0 - fb) * _score_hand(state, player, incoming) 			+ fb * _score_fit(state, player, incoming)
	return _score_hand(state, player, incoming)


static func _score_hand(state: Dictionary, player: int, incoming: Dictionary = {}) -> float:
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
	var wb := _weights()
	var z := float(wb[1])
	for k in wb[0]:
		z += float((wb[0] as Dictionary)[k]) * _feature_value(f, str(k))
	return 1.0 / (1.0 + exp(-clampf(z, -30.0, 30.0)))


## E7/E8: a weight key may be a PRODUCT "a*b" or a RATIO "a/b" (size
## normalisation — absolute sums break across 1000/1500/2000-point armies;
## fractions of the own force do not). Denominator floors at 1.
static func _feature_value(f: Dictionary, key: String) -> float:
	if key.contains("*"):
		var parts := key.split("*")
		return float(f.get(parts[0], 0.0)) * float(f.get(parts[1], 0.0))
	if key.contains("/"):
		var parts := key.split("/")
		return float(f.get(parts[0], 0.0)) / maxf(float(f.get(parts[1], 0.0)), 1.0)
	return float(f.get(key, 0.0))


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
## `rich` gates the feature-wave signals that cost real work (mirror
## reply_threat + melee magnitudes): true at the two LOGGING sites (training
## data), false in the eval hot path. A/B probes measured no regression from
## the wave, but the gate keeps eval cost independent of future signal growth;
## flip to live (with pair-EV memoisation) when the net eval needs them.
static func features(state: Dictionary, player: int, incoming: Dictionary = {},
		rich := false) -> Dictionary:
	var f := {"round_frac": float(state["round"]) / maxf(float(state["rounds_total"]), 1.0),
		"my_wounds": 0.0, "their_wounds": 0.0, "my_units": 0.0, "their_units": 0.0,
		"my_unactivated": 0.0, "their_unactivated": 0.0, "my_incoming": 0.0,
		"presence_mine": 0.0, "presence_theirs": 0.0, "tail_mine": 0.0, "tail_theirs": 0.0,
		"obj_owned_mine": 0.0, "obj_owned_theirs": 0.0,
		# E5 — move-CONTROLLABLE structure (the earlier fits were dominated by
		# uncontrollable context; a controller needs gradients its move can move):
		"cover_mine": 0.0, "cover_theirs": 0.0,
		"my_charge_exposed": 0.0, "their_charge_exposed": 0.0,
		"my_incoming_max": 0.0,
		# Feature wave (net stage): raw signals a nonlinear eval will need —
		# what is never logged can never be learned.
		"their_incoming": 0.0,               # MY projected fire onto them (mirror)
		"my_melee_in": 0.0, "their_melee_in": 0.0,   # expected charge damage, magnitude
		"my_near_half": 0.0, "their_near_half": 0.0, # units close to the morale half-line
		"my_shaken": 0.0, "their_shaken": 0.0,
		"my_fatigued": 0.0, "their_fatigued": 0.0,
		# Deploy state (reserves/ambushers still off-table): read from an optional
		# state key the controller stamps; the rollout never changes it.
		"my_reserve": float((state.get("reserves", {}) as Dictionary).get(player, 0)),
		"their_reserve": float((state.get("reserves", {}) as Dictionary).get(3 - player, 0))}
	for v in incoming.values():
		f["my_incoming"] += float(v)
		f["my_incoming_max"] = maxf(float(f["my_incoming_max"]), float(v))
	if rich:
		for v in BattleSim.reply_threat(state, 3 - player).values():
			f["their_incoming"] += float(v)
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
		if bool(su.get("in_cover", false)):
			f["cover_mine" if mine else "cover_theirs"] += 1.0
		if bool(su.get("shaken", false)):
			f["my_shaken" if mine else "their_shaken"] += 1.0
		if bool(su.get("fatigued", false)):
			f["my_fatigued" if mine else "their_fatigued"] += 1.0
		# Morale proximity: a unit just ABOVE half strength flips to testing
		# range with the next casualty wave — the eval should see the cliff.
		var wounds_max := 0.0
		for m in (su["unit"] as GameUnit).models:
			wounds_max += float(m.wounds_max)
		if wounds_max > 0.0 and wounds > wounds_max * 0.5 and wounds <= wounds_max * 0.7:
			f["my_near_half" if mine else "their_near_half"] += 1.0
		# Charge exposure: any hostile unit's nearest model within rush+contact
		# of this unit's nearest model — the R8 safety geometry as a feature.
		# Feature wave: additionally the MAGNITUDE (worst single charger's
		# expected melee damage), because a grot mob and an ogre block are
		# not the same threat.
		var exposed := false
		var worst_melee := 0.0
		for ok in state["units"]:
			var ou: Dictionary = state["units"][ok]
			if int(ou["player"]) == int(su["player"]) or int(ou["alive"]) <= 0:
				continue
			var oreach := float(SoloController.move_bands_for_unit(ou["unit"], null).get("rush", 12)) 				+ BattleSim.CONTACT_IN
			if BattleSim.dist_in(su["positions"], ou["positions"]) <= oreach:
				exposed = true
				if rich:
					worst_melee = maxf(worst_melee, BattleSim.melee_threat(ou, su))
				else:
					break   # pre-wave behaviour: the binary flag is enough
		if exposed:
			f["my_charge_exposed" if mine else "their_charge_exposed"] += 1.0
			f["my_melee_in" if mine else "their_melee_in"] += worst_melee
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

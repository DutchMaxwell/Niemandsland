class_name AiPosition
extends RefCounted
## AI PLAUSIBILITY stage 1 — the dedicated POSITION-PICKING solver (joint move×target enumeration).
##
## Industry finding (Niemandsland_AI_Plausibility_Plan.md §3 LAYER 3 / §4 stage 1): "rule-correct but
## implausible" — a unit that "parks without line of sight / range" or "ignores cover" — is NOT cured by
## deeper search. It is cured by a dedicated position solver that evaluates the move JOINTLY with the
## attack it enables (Into the Breach's exhaustive move×target enumeration; Crytek Crysis-2 Tactical
## Position Selection; Killzone-3 position picking). This module is that solver, distilled to a single
## deterministic pure function so it stays byte-reproducible and headless-testable.
##
## PIPELINE (all four industry pieces, in order):
##   1. JOINT ENUMERATION — sample the reachable region (rings at fractions of the legal move band × a
##      bearing fan, plus the CURRENT spot and, when heading to a marker, the seize ring) and, for each
##      candidate destination, enumerate the targets shootable FROM there. Positioning is never scored
##      blind of the shot it buys (the fix for "parks with no LOS/range").
##   2. HARD FILTERS (conditions, not blended weights — Crytek "conditions + fallbacks") — a candidate is
##      discarded, with the failed condition NAMED (Bulletstorm precedent → our reasoning records), when:
##        • it ends in the open facing a threat while a covered candidate with a comparable shot exists;
##        • it ends inside a friendly's line of fire (injected `blocks_friend`);
##        • it is not a legal rest spot (injected `legal_at`: off-table / forbidden terrain / congested —
##          Wave-1's large-base congestion, now extended to ALL classes).
##   3. DUAL-CHANNEL SCORING (never one monolithic EV): a TARGET score (the existing AiEv expected wounds)
##      and a separate LOCATION score. The location score is a HARD VETO (net-negative location ⇒ discard)
##      and the FALLBACK ranking when no candidate can attack (so a unit with nothing to shoot still moves
##      toward cover / its objective / the approach lane intelligently). 1–2 blunt weights per context.
##   4. ARGMAX WITHIN A DIFFICULTY BAND — high grades take the argmax; lower grades may take the 2nd/3rd
##      best inside an EV-epsilon band, via the injected seeded `pick` (this is the surface the otherwise
##      dead ev_noise knob finally acts on — POSITION choice, seeded for bit-identical replay).
##
## PURE + DETERMINISTIC: every board query (line of sight, cover, legality, friendly lanes) is an injected
## Callable; the EV is AiEv (pure). Positions are table-plane Vector2 in WORLD METRES (matching the game's
## x/z); distances are converted to inches with `in_per_m` for the range/EV gates. The SoloController is
## the only adapter — it builds `p` from live units and maps the result back. SoloSim never constructs it.

# ---- Location-channel weights (few + blunt, plan §3: "1–2 weights per context"). Kept on a wounds-like
# scale so the veto threshold (0) reads naturally: exposure and cover cancel, objective/approach add. ----
const EXPOSURE_PENALTY := 2.0      # ending in the open within a live enemy threat range
const COVER_BONUS := 2.0           # resting in cover (worth more when actually threatened)
const OBJECTIVE_PULL := 3.0        # per-context pull toward an uncontrolled marker (strong in the last round)
const APPROACH_WEIGHT := 1.0       # fallback ranking: progress toward the intended goal (per inch closed)
const THREAT_APPROACH_IN := 6.0    # an enemy this much beyond its own range can still reach us next turn
const COVER_TIE_EV_FRAC := 0.75    # a covered shot within this fraction of the best EV beats an exposed one
const EV_EPS := 0.05               # EVs within this are a genuine tie (float noise floor)


## Solve one activation's position. `p` keys (all optional unless noted; missing ⇒ neutral):
##   from            : Vector2  — the acting unit's centre (world metres, table plane). REQUIRED.
##   toward          : Vector2  — the naive goal the tree picked (enemy/objective) — bearing bias + the
##                                fallback approach target. REQUIRED.
##   advance_m       : float    — the Advance band in metres (a shot needs travel ≤ this to fire this turn).
##   rush_m          : float    — the Rush band in metres (the outer reachable radius).
##   bearings        : int      — bearing-fan samples per ring (default 12).
##   band_fracs      : Array    — ring radii as fractions of rush (default [0.4, 0.7, 1.0]).
##   our_profiles    : Array    — our in-range-at-0 ranged AiShooting profiles (Sergeant-stamped, limited-filtered).
##   our_ctx         : Dictionary — AiEv attacker context (ctx_for(us)).
##   shoot_range_in  : float    — our longest weapon range (+bonuses) in inches.
##   targets         : Array of {centre: Vector2, def_ctx: Dictionary, range_penalty_in: float} — live enemies.
##   objective       : Dictionary {pos: Vector2, seize_ring_m: float, to_objective: bool, final_round: bool}
##                                 or empty when this activation is not objective-bound.
##   threats         : Array of {centre: Vector2, range_in: float} — enemies whose fire we want to avoid.
##   in_per_m        : float    — inches per metre (1 / INCHES_TO_METERS).
##   is_shooter      : bool     — the unit has ranged weapons and its job is shooting/hybrid.
##   los             : Callable(Vector2 from, Vector2 to) -> bool     — terrain line of sight (world metres).
##   cover_at        : Callable(Vector2 p) -> bool                    — does p rest in cover.
##   legal_at        : Callable(Vector2 p) -> bool                    — on-table, clear of forbidden terrain + spacing.
##   blocks_friend   : Callable(Vector2 p) -> bool                    — p sits in a friendly's firing lane (optional).
##   band_frac_pick  : float    — EV-band width for the difficulty grade (0 ⇒ argmax; ~0.15 ⇒ rekrut).
##   pick            : Callable(int n) -> int                         — seeded index in [0,n) (difficulty band).
##
## Returns {used, goal:Vector2, target_index:int, action:"advance"|"rush", shoot:bool, toward:"enemy"|"objective",
##          why:String, considered:int, shooters:int, filtered:Dictionary, chosen_ev:float, chosen_loc:float,
##          deviation:int}. `used=false` ⇒ the caller keeps its existing (Wave-1) plan byte-identically.
static func solve(p: Dictionary) -> Dictionary:
	var none := {"used": false}
	var from: Vector2 = p.get("from", Vector2.ZERO)
	var toward: Vector2 = p.get("toward", from)
	var los: Callable = p.get("los", Callable())
	var legal_at: Callable = p.get("legal_at", Callable())
	if not los.is_valid() or not legal_at.is_valid():
		return none   # no geometry wired (headless unit tests, sim path) ⇒ leave the plan untouched
	var in_per_m: float = float(p.get("in_per_m", 1.0 / 0.0254))
	var advance_m: float = float(p.get("advance_m", 0.0))
	var rush_m: float = float(p.get("rush_m", 0.0))
	if rush_m <= 0.0:
		return none
	var bearings: int = int(p.get("bearings", 12))
	var band_fracs: Array = p.get("band_fracs", [0.4, 0.7, 1.0])
	var targets: Array = p.get("targets", [])
	var our_profiles: Array = p.get("our_profiles", [])
	var our_ctx: Dictionary = p.get("our_ctx", {})
	var shoot_range_in: float = float(p.get("shoot_range_in", 0.0))
	var is_shooter: bool = bool(p.get("is_shooter", false)) and shoot_range_in > 0.0 and not our_profiles.is_empty()
	var threats: Array = p.get("threats", [])
	var cover_at: Callable = p.get("cover_at", Callable())
	var blocks_friend: Callable = p.get("blocks_friend", Callable())
	var objective: Dictionary = p.get("objective", {})
	var band_frac_pick: float = float(p.get("band_frac_pick", 0.0))
	var pick: Callable = p.get("pick", Callable())

	# --- 1. JOINT ENUMERATION: build the candidate destination set (deterministic order) ---
	var raw: Array = _candidate_points(from, toward, rush_m, bearings, band_fracs, objective, in_per_m)
	var cands: Array = []
	for pt: Vector2 in raw:
		if not bool(legal_at.call(pt)):
			continue
		cands.append(_evaluate(pt, from, toward, in_per_m, advance_m, is_shooter, our_profiles, our_ctx,
			shoot_range_in, targets, threats, objective, los, cover_at, blocks_friend))
	if cands.is_empty():
		return none

	var filtered := {"open_no_cover": 0, "friendly_lane": 0, "location_veto": 0}
	var considered := cands.size()
	var shooters: Array = []
	for c in cands:
		if bool((c as Dictionary)["can_shoot"]):
			shooters.append(c)

	# --- 2. HARD FILTERS + 3. DUAL CHANNEL, on the shooting candidates first (the joint choice) ---
	var chosen: Dictionary = {}
	var deviation := 0
	var toward_kind := "enemy"
	var did_shoot := false
	var to_objective: bool = bool(objective.get("to_objective", false))
	var seize_in := _seize_in(objective, in_per_m)
	if is_shooter and not shooters.is_empty():
		# Best raw EV present anywhere — the reference for "a comparable shot" (cover-vs-open filter).
		var best_ev := 0.0
		for c in shooters:
			best_ev = maxf(best_ev, float((c as Dictionary)["ev"]))
		var kept: Array = []
		for c in shooters:
			var cd := c as Dictionary
			# Filter: friendly line of fire (named).
			if blocks_friend.is_valid() and bool(cd["blocks_friend"]):
				filtered["friendly_lane"] += 1
				continue
			# Filter: ends in the open under threat while a COVERED comparable shot exists (named).
			if bool(cd["threatened"]) and not bool(cd["cover"]) \
					and _covered_shot_exists(shooters, best_ev):
				filtered["open_no_cover"] += 1
				continue
			# Veto: any net-negative LOCATION score discards the candidate (plan §3 hard veto).
			if float(cd["loc"]) < 0.0 and _positive_loc_exists(shooters):
				filtered["location_veto"] += 1
				continue
			kept.append(cd)
		if kept.is_empty():
			kept = shooters   # every shot was filtered — keep them rather than idle (all-exposed board)
		# OBJECTIVE PRESERVATION: an objective-bound unit (the tree / final-round urgency sent it to a marker)
		# only takes a firing spot that ALSO holds that marker — a spot inside the seize ring. Never let a
		# richer enemy-ward shot pull it OFF the objective push (that regressed objective_urgency). If no
		# seize-ring shot exists it keeps its objective rush (used=false via the empty-pool fall-through).
		if to_objective:
			kept = kept.filter(func(c): return float((c as Dictionary)["obj_gap_in"]) <= seize_in)
		if not kept.is_empty():
			# Prefer shots we can take THIS turn (travel ≤ advance) — firing now is the whole point.
			var now_shots: Array = kept.filter(func(c): return float((c as Dictionary)["travel_in"]) <= advance_m * in_per_m + 0.01)
			var pool: Array = now_shots if not now_shots.is_empty() else kept
			did_shoot = not now_shots.is_empty()
			# --- 4. ARGMAX WITHIN THE DIFFICULTY BAND (rank EV, then location, then deterministic index) ---
			var picked := _band_pick(pool, "ev", band_frac_pick, pick)
			chosen = picked["chosen"]
			deviation = int(picked["deviation"])
			toward_kind = "objective" if to_objective else "enemy"
	if chosen.is_empty():
		# --- FALLBACK: nothing to shoot from anywhere in reach — rank by the LOCATION channel so the unit
		# still moves toward cover / its marker / the approach lane instead of parking blindly. (This ranking
		# does not override the caller's tree approach; see _worth_overriding — it defers when no shot.) ---
		var kept2: Array = []
		for c in cands:
			var cd := c as Dictionary
			if float(cd["loc_fallback"]) > -1e17:
				kept2.append(cd)
		if kept2.is_empty():
			return none
		var picked2 := _band_pick(kept2, "loc_fallback", band_frac_pick, pick)
		chosen = picked2["chosen"]
		deviation = int(picked2["deviation"])
		toward_kind = "objective" if to_objective else "enemy"

	# --- Decide whether this beats the caller's naive plan enough to override it (bounded change) ---
	var from_eval := _evaluate(from, from, toward, in_per_m, advance_m, is_shooter, our_profiles, our_ctx,
		shoot_range_in, targets, threats, objective, los, cover_at, blocks_friend)
	var used := _worth_overriding(chosen, from_eval, did_shoot, objective, in_per_m)
	if not used:
		return {"used": false, "considered": considered, "shooters": shooters.size(), "filtered": filtered}

	var travel_in := float(chosen["travel_in"])
	var action := "advance" if (did_shoot and travel_in <= advance_m * in_per_m + 0.01) else "rush"
	var shoot := did_shoot and action == "advance"
	return {
		"used": true,
		"goal": chosen["pos"],
		"target_index": int(chosen["target_index"]),
		"action": action,
		"shoot": shoot,
		"toward": toward_kind,
		"why": _why(chosen, shoot, toward_kind),
		"considered": considered,
		"shooters": shooters.size(),
		"filtered": filtered,
		"chosen_ev": float(chosen["ev"]),
		"chosen_loc": float(chosen["loc"]),
		"deviation": deviation,
	}


# ---- Candidate generation: rings × bearing fan + current spot + (objective) seize ring. Fixed order. ----
static func _candidate_points(from: Vector2, toward: Vector2, rush_m: float, bearings: int,
		band_fracs: Array, objective: Dictionary, in_per_m: float) -> Array:
	var pts: Array = [from]   # the "hold here and shoot / re-evaluate current spot" candidate — always first
	var base_ang := 0.0
	var to_dir := toward - from
	if to_dir.length() > 0.0001:
		base_ang = to_dir.angle()   # bearing 0 points straight at the naive goal (a stable, meaningful anchor)
	var b := maxi(bearings, 1)
	for frac in band_fracs:
		var r: float = rush_m * float(frac)
		if r <= 0.0001:
			continue
		for k in range(b):
			var ang := base_ang + TAU * float(k) / float(b)
			pts.append(from + Vector2.from_angle(ang) * r)
	# Objective seize ring: points just inside the seize bubble, so an objective-bound unit can be scored
	# for a spot that both HOLDS the marker and keeps a shot (generalises Wave-1's objective_fire_anchor).
	if objective.get("to_objective", false) and objective.has("pos"):
		var op: Vector2 = objective["pos"]
		if from.distance_to(op) <= rush_m + 0.001:
			var ring_m: float = maxf(0.0, _seize_in(objective, in_per_m) / in_per_m - 0.5 / in_per_m)
			pts.append(op)
			for k in range(b):
				var ang := TAU * float(k) / float(b)
				pts.append(op + Vector2.from_angle(ang) * ring_m)
	return pts


# ---- Evaluate ONE candidate: its best shot (target channel) + its location score (location channel). ----
static func _evaluate(pt: Vector2, from: Vector2, toward: Vector2, in_per_m: float, advance_m: float,
		is_shooter: bool, our_profiles: Array, our_ctx: Dictionary, shoot_range_in: float, targets: Array,
		threats: Array, objective: Dictionary, los: Callable, cover_at: Callable, blocks_friend: Callable) -> Dictionary:
	var travel_in := from.distance_to(pt) * in_per_m
	# Target channel — the best expected-wounds shot available FROM this spot (joint with the position).
	var best_ev := 0.0
	var best_t := -1
	if is_shooter:
		for i in range(targets.size()):
			var t := targets[i] as Dictionary
			var tc: Vector2 = t["centre"]
			var d_in := pt.distance_to(tc) * in_per_m + float(t.get("range_penalty_in", 0.0))
			if d_in > shoot_range_in:
				continue
			if not bool(los.call(pt, tc)):
				continue
			var ev := AiEv.shoot_ev(our_profiles, our_ctx, t.get("def_ctx", {}), d_in)
			if ev > best_ev + EV_EPS:
				best_ev = ev
				best_t = i
	var can_shoot := best_t >= 0 and best_ev > 0.0
	# Location channel.
	var cover := cover_at.is_valid() and bool(cover_at.call(pt))
	var threatened := _threatened(pt, threats, los, in_per_m)
	var blocks := blocks_friend.is_valid() and bool(blocks_friend.call(pt))
	var loc := 0.0
	if threatened and not cover:
		loc -= EXPOSURE_PENALTY
	if cover:
		loc += COVER_BONUS if threatened else COVER_BONUS * 0.4
	var obj_gap_in := INF
	if objective.has("pos"):
		obj_gap_in = pt.distance_to(objective["pos"]) * in_per_m
		if bool(objective.get("to_objective", false)):
			var seize_in := _seize_in(objective, in_per_m)
			var pull := clampf(1.0 - obj_gap_in / maxf(seize_in * 6.0, 1.0), 0.0, 1.0)
			loc += OBJECTIVE_PULL * pull * (1.5 if bool(objective.get("final_round", false)) else 1.0)
	# Fallback ranking key (used only when NOTHING can shoot): approach toward the intended goal + cover,
	# minus exposure. Progress is the dominant term so a shot-less unit still advances sensibly.
	var goal_gap_in := pt.distance_to(toward) * in_per_m
	var loc_fallback := loc - APPROACH_WEIGHT * goal_gap_in
	return {
		"pos": pt, "travel_in": travel_in, "ev": best_ev, "target_index": best_t, "can_shoot": can_shoot,
		"cover": cover, "threatened": threatened, "blocks_friend": blocks, "loc": loc,
		"obj_gap_in": obj_gap_in, "loc_fallback": loc_fallback,
	}


static func _threatened(pt: Vector2, threats: Array, los: Callable, in_per_m: float) -> bool:
	for th in threats:
		var t := th as Dictionary
		var tc: Vector2 = t["centre"]
		if pt.distance_to(tc) * in_per_m <= float(t.get("range_in", 0.0)) + THREAT_APPROACH_IN \
				and bool(los.call(pt, tc)):
			return true
	return false


static func _covered_shot_exists(shooters: Array, best_ev: float) -> bool:
	for c in shooters:
		var cd := c as Dictionary
		if bool(cd["cover"]) and float(cd["ev"]) >= best_ev * COVER_TIE_EV_FRAC:
			return true
	return false


static func _positive_loc_exists(shooters: Array) -> bool:
	for c in shooters:
		if float((c as Dictionary)["loc"]) >= 0.0:
			return true
	return false


## Argmax within the difficulty band: sort by `key` (desc), then location, then a stable index; then let
## the seeded `pick` deviate to a 2nd/3rd-best candidate that lies within an EV-epsilon band of the best.
static func _band_pick(pool: Array, key: String, band_frac: float, pick: Callable) -> Dictionary:
	var idx: Array = []
	for i in range(pool.size()):
		idx.append(i)
	idx.sort_custom(func(a, b) -> bool:
		var ca := pool[a] as Dictionary
		var cb := pool[b] as Dictionary
		var ka := float(ca[key])
		var kb := float(cb[key])
		if absf(ka - kb) > EV_EPS:
			return ka > kb
		var la := float(ca["loc"])
		var lb := float(cb["loc"])
		if absf(la - lb) > EV_EPS:
			return la > lb
		return a < b)   # deterministic final tie-break on the fixed candidate index
	var ordered: Array = []
	for i in idx:
		ordered.append(pool[i])
	var best_key := float((ordered[0] as Dictionary)[key])
	# The band = candidates within band_frac of the best key (an absolute EV-epsilon floor for tiny/zero keys).
	var band: Array = [ordered[0]]
	for i in range(1, ordered.size()):
		var k := float((ordered[i] as Dictionary)[key])
		if best_key > 0.0:
			if k >= best_key * (1.0 - band_frac) - EV_EPS:
				band.append(ordered[i])
		elif absf(best_key - k) <= EV_EPS + band_frac:
			band.append(ordered[i])
	var deviation := 0
	if band.size() > 1 and pick.is_valid() and band_frac > 0.0:
		deviation = clampi(int(pick.call(band.size())), 0, band.size() - 1)
	return {"chosen": band[deviation], "deviation": deviation}


## Whether the solved candidate beats the caller's current-spot plan enough to override it — a BOUNDED
## change so the many already-good moves stay on the Wave-1 path (protects determinism + move-commitment).
## Override when: (a) we found a shot we can take now but the current spot has none (the idle-shooter fix);
## (b) our chosen shot is covered while the current spot's shot is exposed (a cover upgrade); or
## (c) an objective-bound shooter reaches the seize ring while keeping a shot (anchor generalisation).
## The no-shot case defers to the caller's tree approach (loc_fallback ranks it but does not override — a
## shooter with no shot should close the gap toward range, which the tree's rush already does).
static func _worth_overriding(chosen: Dictionary, from_eval: Dictionary, did_shoot: bool,
		objective: Dictionary, in_per_m: float) -> bool:
	if chosen.is_empty() or not did_shoot:
		return false
	if not bool(chosen["can_shoot"]):
		return false
	if not bool(from_eval["can_shoot"]):
		return true   # (a) current spot cannot fire; the chosen spot can — convert an idle shooter to a shot
	if bool(chosen["cover"]) and not bool(from_eval["cover"]) and bool(from_eval["threatened"]):
		return true   # (b) upgrade an exposed shot to a covered one
	if bool(objective.get("to_objective", false)) \
			and float(chosen["obj_gap_in"]) <= _seize_in(objective, in_per_m) \
			and float(from_eval["obj_gap_in"]) > _seize_in(objective, in_per_m):
		return true   # (c) reach the seize ring AND keep the shot
	return false


static func _seize_in(objective: Dictionary, in_per_m: float) -> float:
	return float(objective.get("seize_ring_m", 3.0 / in_per_m)) * in_per_m


static func _why(chosen: Dictionary, shoot: bool, toward_kind: String) -> String:
	if shoot and toward_kind == "objective":
		return "seize-ring firing spot: holds the marker and keeps the shot"
	if shoot and bool(chosen["cover"]):
		return "firing position in cover with range and line of sight"
	if shoot:
		return "firing position with range and line of sight"
	if toward_kind == "objective":
		return "approach toward the marker"
	return "approach toward a firing lane"

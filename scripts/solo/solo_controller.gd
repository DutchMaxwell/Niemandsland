class_name SoloController
extends Node
## Solo/AI controller — the in-game brain of the AI army (goal 001 + goal 003 P3). Each activation runs
## the OFFICIAL OPR Solo & Co-Op v3.5.0 flow through the SAME pure modules the headless self-play sim
## proved: the D6-section unit pick (Shaken last), AiArchetype + the objective-driven AiDecision.decide_solo
## tree, terrain-aware movement (TerrainRules Difficult/Dangerous on real overlay data; MovementPlanner
## steering around real walls for loose units), and a report main.gd resolves with REAL tray dice
## (split fire / overlays / melee). Deployment + ambush arrival follow the official rules (AiDeployment).
##
## It REUSES: MoveIntent (rigid-move planning), MovementRangeController (move bands), TurnManager
## (alternating-activation engine), GameUnit / OPRArmyManager (state), and NetworkManager
## broadcast_move_batch / broadcast_unit_activation (MP sync).

signal ai_unit_activated(unit: GameUnit)   # emitted after the AI moves + activates a unit (for UI/log)

const BOUNDS_MARGIN_M := 0.02   # keep models a hair inside the table edge
const INCHES_TO_METERS := 0.0254
const OBJECTIVE_CONTROL_IN := 3.0   # OPR objective seize/hold radius (Solo & Co-Op v3.5.0 p.6)
const CONTACT_IN := 2.0             # centre-to-centre "in melee" distance a charge closes to
const MELEE_REACH_IN := 2.0         # OPR "Who Can Strike" (GF Advanced Rules v3.5.1 p.9): only models within 2" strike
const BASE_CONTACT_IN := 1.0        # nominal centre-to-centre gap of two standard ~25 mm bases at contact (~1")
const IN_THE_WAY_IN := 6.0          # OPR: an enemy within 6" of the unit→objective line is "in the way" (p.58)
const NO_OBJECTIVE := Vector3(INF, INF, INF)   # _nearest_uncontrolled_objective sentinel: no uncontrolled objective
## Difficult-terrain move cap (GF Advanced Rules v3.5.1 p.11): "If any model in a unit moves in or
## through difficult terrain at any point of its move, then all models in the unit may not move more
## than 6” for that movement." — a 6" CAP on the whole move, NOT a halving.
const DIFFICULT_MOVE_CAP_IN := 6.0
## Unit spacing (GF/AoF Advanced Rules v3.5.1 p.7 "General Movement": "Models may never be within 1” of
## models from OTHER UNITS, unless they are taking a Charge action, and may never move through other
## models or units (friendly or enemy), even if they are taking a Charge action.") — applies to ALL
## other units, FRIENDLY included; only the moving unit's own models (and its attached heroes) are
## exempt. Edge-to-edge, so planner zones are inflated by both bases' radii
## (== SeparationChecker.SEPARATION_DISTANCE_INCHES, the shared distance module).
const UNIT_SPACING_IN := 1.0
## Post-melee separation (GF Advanced Rules v3.5.1 p.9 "Consolidation Moves"): "If neither of the units
## was destroyed, then the charging unit must move back by 1” (if possible), to keep the separation
## between units clear."
const MELEE_SEPARATION_IN := 1.0
## Safety margin added to the moving base's radius when inflating obstacles (inches) — guards float
## shaving at wall corners; not a rule value.
const CLEARANCE_EPS_IN := 0.1
## Target candidates within the same 1" distance band count as "equally near" — tabletop measuring
## precision for the official nearest-target key. A GENUINE tie is where the official rules would roll a
## die; the hybrid policy (docs/SOLO_AI_PLAN.md) ranks it by the EV metric instead. A documented
## convention, not an official value.
const TARGET_TIE_BAND_IN := 1.0

var army_manager: OPRArmyManager = null
var network_manager: Node = null
var movement_range: MovementRangeController = null
var human_slot: int = 1
var ai_slot: int = 2
## Units held back by their Ambush rule during deploy_army — they arrive at the start of round 2
## following the same deployment rules (goal 003 P1: arrive_ambush_reserve wires the arrival).
var ambush_reserve: Array = []
## Deploy context stashed by deploy_army so the round-2 ambush arrival reuses the same objectives +
## terrain classification (goal 003 P1).
var _deploy_objectives: Array = []
var _deploy_blocked_normal: Callable = Callable()
var _deploy_blocked_flying: Callable = Callable()
## What the last activate_next_ai_unit did: {unit, target, action, can_shoot, dist_in} — main reads it
## to resolve shooting (P3) and the charge melee (P4).
var last_report: Dictionary = {}
## Per-model routes of the last AI move: Array of {model: ModelInstance, path: Array[Vector3] (world
## waypoints, start … final), radius_m: float (the model's base radius — the swept-corridor half-width)}.
## The presentation layer replays them as glide animation + base-width corridors; purely observational —
## positions are applied/broadcast before this is read.
var last_move_paths: Array = []
## Move budget (inches) actually granted to the last AI move (band, difficult-capped when the route
## entered difficult terrain) — the denominator of the corridor's distance label.
var last_move_budget_in: float = 0.0
## Structured AI decision records (the developer-mode lane + the foundation for future introspection-
## driven AI). Each record is a typed Dictionary built AT DECISION TIME — cheap fields only, no string
## formatting (rendering happens in render_decision, and only when the dev toggle is on):
##   kind       : String — "deploy" | "pick" | "action" | "target" | "move" | "separate"
##   unit       : String — acting unit's name
##   rule       : String — the official tree node / rule that fired, with its citation (a literal)
##   candidates : Array of {name: String, ev: float, key: Array} — the option list with EV scores
##   chosen     : String — the picked option
##   why        : String — decisive key / tie-break reason (a literal, no formatting)
##   data       : Dictionary — kind-specific numbers (distances, bands, rolls)
## Ring-buffered at DECISION_LOG_CAP (drop-oldest) so an undrained log never grows unbounded.
var decision_log: Array = []
const DECISION_LOG_CAP := 200
## Injected by main: Callable(from: Vector3, to: Vector3) -> bool for terrain line of sight.
var los_checker: Callable = Callable()
## Injected by main (goal 003 P3 — real terrain feeds the shared pure modules):
##   terrain_type_at    : Callable(world: Vector3) -> int   (TerrainRules/overlay TerrainType at a point)
##   walls_provider     : Callable() -> Array               (world-space [Vector2 a, Vector2 b] wall segments, metres)
##   objectives_provider: Callable() -> Array               (objective world positions, Array[Vector3])
##   objective_owner_of : Callable(index: int) -> int       (owner player_id, 0 = neutral)
## All optional; an invalid Callable degrades gracefully (no terrain / no walls / no objectives).
var terrain_type_at: Callable = Callable()
var walls_provider: Callable = Callable()
var objectives_provider: Callable = Callable()
var objective_owner_of: Callable = Callable()

var turn_manager: TurnManager = null
var _rng := RandomNumberGenerator.new()


func setup(p_army_manager: OPRArmyManager, p_network_manager: Node, p_movement_range: MovementRangeController,
		p_human_slot: int = 1, p_ai_slot: int = 2) -> void:
	army_manager = p_army_manager
	network_manager = p_network_manager
	movement_range = p_movement_range
	human_slot = p_human_slot
	ai_slot = p_ai_slot
	turn_manager = TurnManager.new()
	add_child(turn_manager)
	turn_manager.configure(human_slot, ai_slot, self)
	if not turn_manager.activation_required.is_connected(_on_activation_required):
		turn_manager.activation_required.connect(_on_activation_required)


func _on_activation_required(side: int) -> void:
	if side == TurnManager.Side.AI:
		activate_next_ai_unit()


# === TurnManager delegate contract ===

func units() -> Array:
	return army_manager.get_all_game_units() if army_manager != null else []


func slot_of(unit) -> int:
	return int((unit as GameUnit).unit_properties.get("player_id", 0)) if unit != null else 0


## Eligible = alive, not yet activated, and NOT an attached hero: a joined hero deploys, activates and
## moves WITH its host unit (GF Advanced Rules v3.5.1 "Hero": "may deploy as part of one multi-model
## unit" — one unit, one activation; GameUnit.activate() already cascades to attached heroes). Letting
## the hero count as its own activation made the AI's D6 pick move him SOLO out of his unit
## (maintainer field-test bug) and made the round-over check wait for a phantom second activation.
func is_eligible(unit) -> bool:
	var u := unit as GameUnit
	if u == null or u.is_activated or u.is_destroyed():
		return false
	return not (u.has_method("is_attached") and u.is_attached())


func mark_activated(unit) -> void:
	var u := unit as GameUnit
	if u != null:
		u.activate(army_manager.current_round if army_manager != null else 1)


func reset_round() -> void:
	pass   # OPRArmyManager.advance_round() already clears activation flags for the whole table


# === AI turn ===

## Activates every eligible AI unit in sequence — the visible M1 "AI advances its army" turn. Returns
## the number of units moved. (One-unit-per-press is activate_next_ai_unit(); alternating flow is driven
## by TurnManager for when the human side is also wired.)
func run_ai_turn() -> int:
	var moved := 0
	while activate_next_ai_unit() != null:
		moved += 1
	return moved


## Move + activate the next eligible AI unit. Selection is the official OPR Solo & Co-Op v3.5.0 pick:
## D6 → table section (1–3 = west half, 4–6 = east half; empty section → the other), a random eligible
## unit within it — with SHAKEN units always LAST (they activate last and stay idle to recover, p.2).
## A Shaken unit's activation is an IDLE (no move/attack) reported as {"idle_shaken": true}; the caller
## clears the Shaken state through its marker/broadcast seam. Returns the unit, or null when none left.
func activate_next_ai_unit() -> GameUnit:
	var eligible := eligible_ai_units()
	if eligible.is_empty():
		return null
	var unit := _select_ai_unit(eligible)
	if unit == null:
		return null
	last_move_paths = []   # cleared per activation — HOLD / Shaken idle replays nothing
	if unit.is_shaken:
		# OPR (p.10): a Shaken unit spends its activation idle, which lets it recover.
		last_report = {"unit": unit, "target": null, "action": AiDecision.Action.HOLD,
			"toward": AiDecision.Toward.ENEMY, "shoot": false, "can_shoot": false,
			"dist_in": INF, "dangerous_models": 0, "idle_shaken": true}
	else:
		last_report = _act(unit)
	mark_activated(unit)
	if network_manager != null and network_manager.has_method("broadcast_unit_activation"):
		network_manager.broadcast_unit_activation(unit)
	if turn_manager != null:
		turn_manager.notify_activated(unit)
	ai_unit_activated.emit(unit)
	return unit


func eligible_ai_units() -> Array:
	return eligible_units_for(ai_slot)


## Eligible (alive, not-yet-activated) units of any player slot — the round-over check reads both sides.
func eligible_units_for(slot: int) -> Array:
	var out: Array = []
	if army_manager == null:
		return out
	for u in army_manager.get_game_units_for_player(slot):
		if is_eligible(u):
			out.append(u)
	return out


## The official unit pick: Shaken last; then D6 → 2 table sections split along the AI's deployment edge
## (west/east half by centre X), rotating to the other section when the rolled one has no eligible unit;
## then a random eligible unit in that section (seeded _rng → reproducible), with the section's Counter
## units activated only after its non-Counter units (the official Counter overlay).
func _select_ai_unit(eligible: Array) -> GameUnit:
	var fresh: Array = []
	var shaken: Array = []
	for u in eligible:
		if (u as GameUnit).is_shaken:
			shaken.append(u)
		else:
			fresh.append(u)
	var pool: Array = fresh if not fresh.is_empty() else shaken
	if pool.size() == 1:
		return pool[0]
	var west: Array = []
	var east: Array = []
	for u in pool:
		if unit_centre(u).x < 0.0:
			west.append(u)
		else:
			east.append(u)
	var roll_west: bool = _rng.randi_range(1, 6) <= 3
	var section: Array = west if roll_west else east
	if section.is_empty():
		section = east if roll_west else west   # rotate to the other section (rule: no eligible unit there)
	# Counter overlay (GF/AoF v3.5.1 solo rules p.57: "AI units with Counter are always activated after all
	# other friendly non-Counter units in their section have been activated") — pick among the section's
	# non-Counter units first; Counter units only when none remain.
	var non_counter: Array = []
	for u in section:
		if not has_counter(AiShooting.melee_profiles(_unit_weapons(u)), (u as GameUnit).get_special_rules()):
			non_counter.append(u)
	var counter_deferred: bool = not non_counter.is_empty() and non_counter.size() < section.size()
	if not non_counter.is_empty():
		section = non_counter
	var picked: GameUnit = section[_rng.randi_range(0, section.size() - 1)]
	record_decision({"kind": "pick", "unit": picked.get_name(),
		"rule": "Solo v3.5.0: D6 section roll, random eligible; Shaken last; Counter last in section (p.57)",
		"candidates": [], "chosen": picked.get_name(),
		"why": ("counter units deferred" if counter_deferred else ("shaken pool" if fresh.is_empty() else "section roll")),
		"data": {"west": west.size(), "east": east.size(), "rolled_west": roll_west, "eligible": eligible.size()}})
	return picked


## The move/charge target for an AI unit — the OPR Solo & Co-Op v3.5.0 targeting rule (p.2 / p.57):
## the NEAREST valid enemy, preferring not-yet-activated targets. Distances are compared in 1" bands
## (TARGET_TIE_BAND_IN); a GENUINE tie — where the official rules would roll a die — is ranked by the EV
## metric instead (hybrid policy): the charge matchup score for a unit with melee weapons (Furious /
## Thrust / Impact in; the defender's Counter reduces it; our Fearless raises risk tolerance), else the
## shooting EV at that distance. Deterministic; the decision is recorded for the dev-mode lane.
func nearest_human_unit(ai_unit: GameUnit) -> GameUnit:
	if army_manager == null:
		return null
	var from := unit_centre(ai_unit)
	var cands: Array = []
	for h in army_manager.get_game_units_for_player(human_slot):
		var hu := h as GameUnit
		if hu == null or hu.is_destroyed():
			continue
		if hu.has_method("is_attached") and hu.is_attached():
			continue   # a joined hero is PART of its host unit — you target the unit, never the hero alone
		var d := MoveIntent.distance_inches(from, unit_centre(hu))
		cands.append({"unit": hu, "d": d, "band": int(floorf(d / TARGET_TIE_BAND_IN)),
			"activated": hu.is_activated, "ev": 0.0})
	if cands.is_empty():
		return null
	# Official key: not-yet-activated first, then nearest (banded).
	var tied: Array = [cands[0]]
	for i in range(1, cands.size()):
		var cmp := _target_key_compare(cands[i], tied[0])
		if cmp < 0:
			tied = [cands[i]]
		elif cmp == 0:
			tied.append(cands[i])
	var why := "official: nearest, not-activated first"
	var chosen: Dictionary = tied[0]
	if tied.size() > 1:
		# A genuine tie: rank by EV (utility instead of the rules' die roll — hybrid policy).
		var our_weapons := _unit_weapons(ai_unit)
		var our_melee := AiShooting.melee_profiles(our_weapons)
		var us := AiEv.ctx_for(ai_unit, false, counter_models_of(ai_unit))
		for t in tied:
			var td := t as Dictionary
			var hu := td["unit"] as GameUnit
			var them := AiEv.ctx_for(hu, false, counter_models_of(hu))
			if our_melee.is_empty():
				td["ev"] = AiEv.shoot_ev(AiShooting.profiles_in_range(our_weapons, 0.0), us, them, float(td["d"]))
			else:
				td["ev"] = AiEv.charge_score(our_melee, us, AiShooting.melee_profiles(_unit_weapons(hu)), them)
		for t in tied:
			if float((t as Dictionary)["ev"]) > float(chosen["ev"]):
				chosen = t
		why = "ev tie-break"
	var rec_cands: Array = []
	for t in tied:
		var td := t as Dictionary
		rec_cands.append({"name": (td["unit"] as GameUnit).get_name(), "ev": float(td["ev"]),
			"key": [td["activated"], td["band"]]})
	record_decision({"kind": "target", "unit": ai_unit.get_name(),
		"rule": "Solo v3.5.0 p.2: nearest valid target, not-activated first",
		"candidates": rec_cands, "chosen": (chosen["unit"] as GameUnit).get_name(), "why": why,
		"data": {"considered": cands.size(), "dist_in": float(chosen["d"])}})
	return chosen["unit"] as GameUnit


## Official target ordering: not-yet-activated before activated, then the nearer 1" distance band.
## Returns <0 when `a` outranks `b`, 0 on a genuine tie, >0 otherwise.
static func _target_key_compare(a: Dictionary, b: Dictionary) -> int:
	var aa := 1 if bool(a.get("activated", false)) else 0
	var bb := 1 if bool(b.get("activated", false)) else 0
	if aa != bb:
		return aa - bb
	return int(a.get("band", 0)) - int(b.get("band", 0))


## One activation by the FULL official OPR Solo & Co-Op v3.5.0 decision tree (goal 003 P3 — the sim's brain
## wired into the real game). Classify the archetype, pick the nearest un-activated enemy AND the nearest
## objective this side does not control, build the tree context, resolve the action toward the objective or
## the enemy, and execute a terrain-aware move (Difficult halves, walls are steered around, Dangerous is
## surfaced for main to roll on the real dice tray). Reports {unit, target, action, toward, shoot, can_shoot,
## dist_in, dangerous_models} so main resolves shooting / the charge melee / the Dangerous test with real dice.
func _act(unit: GameUnit) -> Dictionary:
	var report := {"unit": unit, "target": null, "action": AiDecision.Action.HOLD,
		"toward": AiDecision.Toward.ENEMY, "shoot": false, "can_shoot": false, "dist_in": INF, "dangerous_models": 0}
	var target_unit := nearest_human_unit(unit)
	if target_unit == null or alive_positions(unit).is_empty():
		return report
	report["target"] = target_unit
	var weapons := _unit_weapons(unit)
	var bands: Dictionary = {"advance": 6, "rush": 12}
	if movement_range != null:
		bands = movement_range.move_bands_for_props(unit.unit_properties)
	var advance := float(bands.get("advance", 6))
	var rush := float(bands.get("rush", 12))
	var centre := unit_centre(unit)
	var tcentre := unit_centre(target_unit)
	var enemy_dist := MoveIntent.distance_inches(centre, tcentre)
	var shoot_range := AiArchetype.max_range_inches(weapons)
	# The archetype's "better than" (Solo & Co-Op v3.5.0 p.1) is filled with the EV metric in the REAL
	# game (AiEv.classify — Furious/Thrust/Impact weigh the melee side); the sim keeps the frozen
	# AiArchetype.classify heuristic, so its fairness oracle is untouched.
	var archetype := AiEv.classify(weapons, AiEv.ctx_for(unit, false, 0))
	# Nearest objective NOT controlled by this AI side — the official trees pivot on it.
	var obj_pos := _nearest_uncontrolled_objective(centre)
	var has_obj: bool = obj_pos != NO_OBJECTIVE
	var obj_dist: float = MoveIntent.distance_inches(centre, obj_pos) if has_obj else INF
	var ctx := {
		"arch": archetype, "objective": has_obj, "in_way": has_obj and _enemy_in_way(centre, obj_pos),
		"obj_in_advance": obj_dist <= advance + OBJECTIVE_CONTROL_IN,
		"obj_in_rush": obj_dist <= rush + OBJECTIVE_CONTROL_IN,
		"enemy_in_charge": enemy_dist <= rush,
		"shoot_after_advance": shoot_range > 0 and (enemy_dist - advance) <= float(shoot_range),
	}
	var dec := AiDecision.decide_solo(ctx)
	var action: int = int(dec["action"])
	var do_shoot: bool = bool(dec["shoot"])
	var action_why := "decision tree"
	# Relentless overlay (Solo & Co-Op Rules v3.5.0 p.2): a Relentless ranged weapon in range → Hold and shoot.
	if _forces_hold_and_shoot(weapons, shoot_range > 0 and enemy_dist <= float(shoot_range)):
		action = AiDecision.Action.HOLD
		do_shoot = true
		action_why = "Relentless hold-and-shoot overlay"
	# Immobile / Artillery (GF/AoF v3.5.1 p.13): "may only use Hold actions" — the tree's move is overridden
	# to HOLD unconditionally; the unit still shoots when a target is in range (Artillery solo overlay p.57:
	# "If they are in range of enemies, they always use Hold and shoot"; can_shoot re-gates on range + LOS).
	if forces_hold(unit.get_special_rules()):
		action = AiDecision.Action.HOLD
		do_shoot = shoot_range > 0
		action_why = "Immobile/Artillery hold-only"
	record_decision({"kind": "action", "unit": unit.get_name(),
		"rule": "Solo v3.5.0 decision tree (archetype branch; EV fills the p.1 'better than')",
		"candidates": [], "chosen": AiDecision.action_name(action), "why": action_why,
		"data": {"arch": archetype, "objective": bool(ctx["objective"]), "in_way": bool(ctx["in_way"]),
			"enemy_in_charge": bool(ctx["enemy_in_charge"]), "shoot_after_advance": bool(ctx["shoot_after_advance"]),
			"enemy_dist_in": enemy_dist, "toward_objective": int(dec["toward"]) == AiDecision.Toward.OBJECTIVE}})
	report["action"] = action
	report["shoot"] = do_shoot
	report["toward"] = int(dec["toward"])
	var to_obj: bool = int(dec["toward"]) == AiDecision.Toward.OBJECTIVE and has_obj
	var goal: Vector3 = obj_pos if to_obj else tcentre
	var goal_dist := MoveIntent.distance_inches(centre, goal)
	var dang := 0
	match action:
		AiDecision.Action.RUSH:
			dang = _move_toward(unit, goal, (minf(rush, goal_dist) if to_obj else rush), false)
		AiDecision.Action.CHARGE:
			# Close toward the enemy (lands on/near contact; the real melee gate confirms reach). Charge is
			# the one action exempt from steering easing — allow_contact skips the coherency slack.
			dang = _move_toward(unit, tcentre, rush, true, target_unit)
		AiDecision.Action.ADVANCE:
			if to_obj:
				dang = _move_toward(unit, goal, minf(advance, goal_dist), false)
			elif enemy_dist <= float(shoot_range):
				# "Advancing" (p.58): a shooter already in range steps BACK to the range edge, still shooting.
				dang = _move_away(unit, tcentre, minf(advance, float(shoot_range) - enemy_dist))
			else:
				dang = _move_toward(unit, tcentre, advance, false)
		_:
			pass   # HOLD
	report["dangerous_models"] = dang
	# Shooting eligibility is measured AFTER the move; only actions the tree marked shoot=true actually fire.
	var d2 := MoveIntent.distance_inches(unit_centre(unit), unit_centre(target_unit))
	report["dist_in"] = d2
	report["can_shoot"] = do_shoot and shoot_range > 0 and d2 <= float(shoot_range) and _has_los(unit, target_unit)
	return report


## Rigid move toward `goal_world`, capped at `inches`, table-clamped; Difficult terrain on the straight path
## halves it. Loose units steer around walls via MovementPlanner (regiments keep the rigid block slide).
## Returns the number of alive models whose path crossed Dangerous terrain (main rolls the real tests).
func _move_toward(unit: GameUnit, goal_world: Vector3, inches: float, allow_contact: bool,
		charge_target: GameUnit = null) -> int:
	if is_zero_approx(inches):
		return 0
	return _execute_move(unit, _clamp_to_bounds(goal_world), inches, allow_contact, charge_target)


## Post-melee separation move (GF Advanced Rules v3.5.1 p.9 "Consolidation Moves": "If neither of the
## units was destroyed, then the charging unit must move back by 1” (if possible)"): back the charger
## straight away from the defender by MELEE_SEPARATION_IN. Returns the Dangerous-crossing model count;
## publishes last_move_paths so the separation replays as a visible corridor.
func separate_from_melee(charger: GameUnit, defender_centre: Vector3) -> int:
	return _move_away(charger, defender_centre, MELEE_SEPARATION_IN)


## Rigid move directly AWAY from `from_world` by `inches` (the shooter "stay at range edge" step), clamped.
func _move_away(unit: GameUnit, from_world: Vector3, inches: float) -> int:
	if is_zero_approx(inches):
		return 0
	var centre := unit_centre(unit)
	var goal := centre + (centre - _clamp_to_bounds(from_world))
	return _execute_move(unit, _clamp_to_bounds(goal), inches, false)


## Shared move executor — rule-true, glass-clear movement:
##   • Difficult terrain (GF Advanced Rules v3.5.1 p.11: "If any model in a unit moves in or through
##     difficult terrain at any point of its move, then all models in the unit may not move more than 6”
##     for that movement."): the planner first tries to go AROUND difficult terrain at the FULL band
##     (solo overlay p.57: AI units "must always move around it" unless the destination lies inside);
##     only when the actual planned route still crosses difficult terrain does the 6" CAP apply and the
##     move is re-planned through it. This replaces the former ×0.5 halving, which matched the rule only
##     for a 12" band. Strider/Flying are exempt (p.14/p.13, wave 3).
##   • Distance truth (p.7: "no part of their bases move further than the total movement distance"):
##     every model's ACTUAL polyline is measured and trimmed to the granted budget — the drawn corridor
##     length always equals the distance moved.
##   • Dangerous tests count the models whose actual route crossed dangerous cells (Flying ignores, p.13).
## Moves the host's models AND its attached heroes' as ONE formation (GF v3.5.1 "Hero"). Publishes
## last_move_paths ({model, path, radius_m}) + last_move_budget_in for the corridor presentation.
## Returns the Dangerous-crossing model count (main rolls the real tests).
func _execute_move(unit: GameUnit, goal: Vector3, inches: float, allow_contact: bool,
		charge_target: GameUnit = null) -> int:
	var models := _moving_models(unit)
	var positions := _positions_of(models)
	if positions.is_empty():
		return 0
	var flying: bool = unit.has_special_rule("Flying")
	var ignores_difficult: bool = flying or unit.has_special_rule("Strider")
	var reach := inches
	# Pass 1: full band, going AROUND difficult terrain — unless the unit ignores it or its destination
	# lies inside difficult terrain (objective/charge into a forest — the p.57 overlay exceptions).
	var avoid: bool = not ignores_difficult and not _targets_in_difficult(positions, goal, reach)
	var trails: Array = []
	var new_positions := _plan_move(unit, models, positions, goal, reach, allow_contact, avoid, trails, charge_target)
	if not ignores_difficult and _trails_cross_difficult(trails):
		# The actual route enters difficult terrain → the 6" cap applies (p.11); re-plan through it so the
		# budget math and the drawn corridor agree.
		reach = minf(inches, DIFFICULT_MOVE_CAP_IN)
		trails = []
		new_positions = _plan_move(unit, models, positions, goal, reach, allow_contact, false, trails, charge_target)
	# Distance truth (p.7): no model's polyline may exceed the granted budget — the coherency easing is
	# best-effort and may not stretch a route past its legal length.
	var budget_m := reach * INCHES_TO_METERS
	for i in range(mini(trails.size(), new_positions.size())):
		var t := trails[i] as Array
		if MovementPlanner.polyline_length(t) > budget_m + 0.0005:
			var cut := MovementPlanner.trim_polyline(t, budget_m)
			trails[i] = cut
			if not cut.is_empty():
				var fin := cut.back() as Vector3
				new_positions[i] = Vector3(fin.x, (new_positions[i] as Vector3).y, fin.z)
	# Nothing actually moved (clamped to zero) → keep the old early-out (no state write, no broadcast).
	var moved := false
	for i in range(mini(positions.size(), new_positions.size())):
		if ((new_positions[i] as Vector3) - (positions[i] as Vector3)).length() > 0.0005:
			moved = true
			break
	if not moved:
		last_move_paths = []
		return 0
	# Flying ignores terrain effects whilst moving (p.13) — no Dangerous tests for its crossings.
	var dang := 0 if flying else _count_dangerous_trails(trails)
	_apply_model_positions(models, new_positions)
	# Publish the per-model routes + base radii for the presentation layer (glide + swept corridor +
	# distance label) — the STATE is already final (applied + broadcast above); the replay is local.
	last_move_budget_in = reach
	var radii := _model_radius_map(models)
	last_move_paths = []
	var longest_arc_m := 0.0
	for i in range(mini(models.size(), trails.size())):
		longest_arc_m = maxf(longest_arc_m, MovementPlanner.polyline_length(trails[i] as Array))
		last_move_paths.append({"model": models[i], "path": trails[i],
			"radius_m": float(radii.get(models[i], SeparationChecker.DEFAULT_BASE_RADIUS_M))})
	record_decision({"kind": "move", "unit": unit.get_name(),
		"rule": "GF v3.5.1 p.7 move bands; p.11 difficult 6\" cap; p.57 move around difficult",
		"candidates": [], "chosen": "",
		"why": ("difficult cap" if reach < inches else ("around difficult" if avoid else "direct")),
		"data": {"band_in": inches, "budget_in": reach, "arc_in": longest_arc_m / INCHES_TO_METERS,
			"dangerous_models": dang}})
	return dang


## One planning pass: rigid clamp to the table, then obstacle-aware per-model planning. Returns the new
## positions; `trails` receives one world polyline per model.
func _plan_move(unit: GameUnit, models: Array, positions: Array, goal: Vector3, reach_in: float,
		allow_contact: bool, avoid_difficult: bool, trails: Array, charge_target: GameUnit) -> Array:
	var delta := MoveIntent.plan_unit_move(positions, goal, reach_in)
	delta = _clamp_delta_to_bounds(positions, delta)
	if delta == Vector3.ZERO:
		_fill_straight_trails(trails, positions, positions)
		return positions.duplicate()
	return _plan_positions(unit, models, positions, delta, allow_contact, trails, avoid_difficult, charge_target)


## Would the rigid move's per-model TARGETS land inside difficult terrain? (Objective or charge target
## inside a forest — then going around is impossible and the 6" cap path is taken directly.)
func _targets_in_difficult(positions: Array, goal: Vector3, reach_in: float) -> bool:
	if not terrain_type_at.is_valid():
		return false
	var delta := _clamp_delta_to_bounds(positions, MoveIntent.plan_unit_move(positions, goal, reach_in))
	for p in positions:
		if TerrainRules.is_difficult(int(terrain_type_at.call((p as Vector3) + delta))):
			return true
	return false


## Whether any model's ACTUAL planned route crosses difficult terrain (the p.11 cap trigger — checked on
## the real polyline, not the straight line, so the budget math always matches the drawn corridor).
func _trails_cross_difficult(trails: Array) -> bool:
	for t in trails:
		var leg := t as Array
		for i in range(1, leg.size()):
			if _path_crosses_terrain(leg[i - 1], leg[i], TerrainRules.PathCheck.DIFFICULT):
				return true
	return false


## A model's base bounding radius (metres) via the SHARED distance module (one radius truth:
## SeparationChecker.shape_for_model — round exact, oval/rect circumscribed), with the module's 32 mm
## fallback when the shape cannot be built.
static func model_base_radius_m(model: ModelInstance) -> float:
	var shape := SeparationChecker.shape_for_model(model)
	if shape == null:
		return SeparationChecker.DEFAULT_BASE_RADIUS_M
	return shape.bounding_radius()


## The largest base radius among the moving models (unit + attached heroes) — the planner clearance.
func _move_base_radius_m(models: Array) -> float:
	var r := SeparationChecker.DEFAULT_BASE_RADIUS_M
	for m in models:
		r = maxf(r, model_base_radius_m(m as ModelInstance))
	return r


## Per-model base radius (metres) keyed by ModelInstance — each corridor is exactly one base-width wide.
func _model_radius_map(models: Array) -> Dictionary:
	var map := {}
	for m in models:
		map[m] = model_base_radius_m(m as ModelInstance)
	return map


## Unit-spacing no-go zones for an AI move (GF/AoF v3.5.1 p.7 — see UNIT_SPACING_IN): one circle per
## alive model of EVERY other unit, friendly or enemy (only the moving unit + its attached heroes are
## exempt), radius = that base's bounding radius + 1" + the mover's radius (world metres; the caller
## converts to the planner's inch frame). On a Charge, `charge_target` (and its attached heroes) instead
## get BODY-ONLY zones (both radii, no 1" buffer): the charge may end at base contact with its target
## but may never move THROUGH it — and every other unit keeps its full 1" zone (the amendment ruling:
## the Charge exception applies only toward the charge target). Radii come from the shared
## SeparationChecker shapes (circles: exact for round bases, circumscribed for oval/rect trays).
func _spacing_zones_world(unit: GameUnit, own_radius_m: float, charge_target: GameUnit) -> Array:
	var zones: Array = []
	if army_manager == null:
		return zones
	var own := {}
	var own_members: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		own_members = own_members + unit.get_attached_heroes()
	for m in own_members:
		if m != null:
			own[m] = true
	var target_members := {}
	if charge_target != null:
		target_members[charge_target] = true
		if charge_target.has_method("get_attached_heroes"):
			for h in charge_target.get_attached_heroes():
				if h != null:
					target_members[h] = true
	for g in army_manager.get_all_game_units():
		var gu := g as GameUnit
		if gu == null or own.has(gu):
			continue
		var buffer_m: float = 0.0 if target_members.has(gu) else UNIT_SPACING_IN * INCHES_TO_METERS
		for model in gu.get_alive_models():
			var shape := SeparationChecker.shape_for_model(model as ModelInstance)
			if shape == null:
				continue
			zones.append({"c": shape.center, "r": shape.bounding_radius() + buffer_m + own_radius_m})
	return zones


## Sample the REAL overlay into the planner's typed 3" cell grid (inch frame). Returns
## {"grid": {Vector2i: TerrainType}, "avoid": {Vector2i: true}} — Impassable cells are always avoided;
## Difficult cells only when the route should go around them (solo overlay p.57).
func _terrain_grid_in(board_in: float, off: Vector2, avoid_difficult: bool) -> Dictionary:
	var grid := {}
	var avoid := {}
	if not terrain_type_at.is_valid():
		return {"grid": grid, "avoid": avoid}
	var n := maxi(1, int(ceil(board_in / TerrainRules.CELL_IN)))
	for cy in range(n):
		for cx in range(n):
			var centre_in := Vector2((float(cx) + 0.5) * TerrainRules.CELL_IN, (float(cy) + 0.5) * TerrainRules.CELL_IN)
			var world := centre_in * INCHES_TO_METERS - off
			var t: int = int(terrain_type_at.call(Vector3(world.x, 0.0, world.y)))
			if t == TerrainRules.TerrainType.NONE:
				continue
			var cell := Vector2i(cx, cy)
			grid[cell] = t
			if TerrainRules.is_impassable(t) or (avoid_difficult and TerrainRules.is_difficult(t)):
				avoid[cell] = true
	return {"grid": grid, "avoid": avoid}


## The models an AI move displaces: the unit's own alive models PLUS its attached heroes' (one unit,
## one move — coherency). Filtered to models with a live node so the list aligns 1:1 with the
## position arrays the planner produces (no index drift on a freed node).
func _moving_models(unit: GameUnit) -> Array:
	var raw: Array = unit.get_alive_models_with_attached() if unit.has_method("get_alive_models_with_attached") \
		else unit.get_alive_models()
	var out: Array = []
	for m in raw:
		var node := (m as ModelInstance).node
		if node != null and is_instance_valid(node):
			out.append(m)
	return out


## World positions of an already node-filtered ModelInstance list (1:1, order preserved).
func _positions_of(models: Array) -> Array:
	var out: Array = []
	for m in models:
		out.append(((m as ModelInstance).node as Node3D).global_position)
	return out


## The unit's OPR weapons (empty when it has no OPR source — counts as melee-only).
func _unit_weapons(unit: GameUnit) -> Array:
	if unit.source_type == "opr" and unit.source_data is OPRApiClient.OPRUnit:
		return (unit.source_data as OPRApiClient.OPRUnit).weapons
	return []


## Line of sight between two units via the injected checker (main wires terrain LOS); no checker = clear.
func _has_los(unit: GameUnit, target_unit: GameUnit) -> bool:
	if not los_checker.is_valid():
		return true
	return bool(los_checker.call(unit_centre(unit), unit_centre(target_unit)))


## Set each model node to its planned world position (Y preserved) + broadcast the batch. `models` is the
## node-filtered list the positions were planned from (_moving_models), so indices align 1:1.
func _apply_model_positions(models: Array, new_positions: Array) -> void:
	var batch: Array = []
	for i in range(mini(models.size(), new_positions.size())):
		var node := (models[i] as ModelInstance).node
		if node == null or not is_instance_valid(node):
			continue
		var np: Vector3 = new_positions[i]
		node.global_position = Vector3(np.x, node.global_position.y, np.z)
		if node.has_meta("network_id"):
			batch.append(node.get_meta("network_id"))
			batch.append(node.global_position.x)
			batch.append(node.global_position.y)
			batch.append(node.global_position.z)
	if network_manager != null and not batch.is_empty() and network_manager.has_method("broadcast_move_batch"):
		network_manager.broadcast_move_batch(batch)


## Plan the per-model destination positions for a move by rigid `delta`. A regiment keeps the rigid tray
## slide (documented gap: its block is not obstacle-planned). A LOOSE unit plans base-aware: walls are
## inflated by the moving base's radius (no clipping, no edge-shaving), every OTHER unit's models —
## friendly or enemy — carry a 1" no-go zone (GF/AoF v3.5.1 p.7; on a Charge the target's models are
## body-only so the charge ends at base contact but never passes through, and all other units keep the
## full zone), and difficult/impassable cells are routed around (solo overlay p.57) via the shared
## MovementPlanner in its 0-origin inch frame. The fast path (nothing in the way) stays the exact rigid
## slide. `world_trails` (optional out): one WORLD-space waypoint list per model — the real route taken.
func _plan_positions(unit: GameUnit, models: Array, positions: Array, delta: Vector3, allow_contact: bool,
		world_trails: Array = [], avoid_difficult: bool = true, charge_target: GameUnit = null) -> Array:
	var rigid: Array = []
	for p in positions:
		rigid.append((p as Vector3) + delta)
	if _is_regiment(unit):
		_fill_straight_trails(world_trails, positions, rigid)
		return rigid   # a regiment moves as its rigid tray block — no individual steering
	# Map world XZ (metres, centred at 0) into the planner's non-negative inch frame: shift by the table
	# half-extents, then divide by the inch scale. board_in is the larger table extent in inches.
	var walls_world: Array = _walls_world()
	var half := _table_half_extents()
	var off := Vector2(half.x, half.y)
	var board_in: float = (maxf(half.x, half.y) * 2.0) / INCHES_TO_METERS
	var mpos: Array = []
	for p in positions:
		mpos.append((Vector2((p as Vector3).x, (p as Vector3).z) + off) / INCHES_TO_METERS)
	var mdelta := Vector2(delta.x, delta.z) / INCHES_TO_METERS
	var walls_in: Array = []
	for w in walls_world:
		var wa: Vector2 = w[0]
		var wb: Vector2 = w[1]
		walls_in.append([(wa + off) / INCHES_TO_METERS, (wb + off) / INCHES_TO_METERS])
	# Base-aware planner opts: wall clearance = the moving base's radius + epsilon; unit-spacing zones
	# for EVERY other unit (p.7; on a Charge the target is body-only); difficult/impassable cells to
	# route around (p.57 overlay).
	var own_r_m := _move_base_radius_m(models)
	var opts := {"clearance": own_r_m / INCHES_TO_METERS + CLEARANCE_EPS_IN}
	var zones_in: Array = []
	for z in _spacing_zones_world(unit, own_r_m, charge_target if allow_contact else null):
		var zd := z as Dictionary
		zones_in.append({"c": ((zd["c"] as Vector2) + off) / INCHES_TO_METERS,
			"r": float(zd["r"]) / INCHES_TO_METERS})
	if not zones_in.is_empty():
		opts["zones"] = zones_in
	var sampled := _terrain_grid_in(board_in, off, avoid_difficult)
	opts["avoid_cells"] = sampled["avoid"]
	if not MovementPlanner.rigid_blocked(mpos, mdelta, walls_in, opts):
		_fill_straight_trails(world_trails, positions, rigid)
		return rigid
	var plan_trails: Array = []
	var planned: Array = MovementPlanner.plan_unit_step(mpos, mdelta, walls_in, sampled["grid"],
		allow_contact, board_in, plan_trails, opts)
	var out: Array = []
	if world_trails != null:
		world_trails.clear()
	for i in range(positions.size()):
		var pi: Vector2 = mpos[i]
		if i < planned.size():
			pi = planned[i]
		var world := (pi * INCHES_TO_METERS) - off
		var src: Vector3 = positions[i]
		out.append(Vector3(world.x, src.y, world.y))
		if world_trails != null:
			var leg: Array = []
			if i < plan_trails.size():
				for wp in plan_trails[i]:
					var wv := ((wp as Vector2) * INCHES_TO_METERS) - off
					leg.append(Vector3(wv.x, src.y, wv.y))
			if leg.size() < 2:
				leg = [src, out[i]]
			world_trails.append(leg)
	return out


## Straight one-leg trails for a rigid slide (start → end per model).
static func _fill_straight_trails(world_trails: Array, from_pos: Array, to_pos: Array) -> void:
	if world_trails == null:
		return
	world_trails.clear()
	for i in range(from_pos.size()):
		world_trails.append([from_pos[i], to_pos[i]])


## Count models whose ACTUAL planned route (polyline legs, not the straight line) crossed Dangerous
## terrain — one test per model (GF Advanced Rules v3.5.1 p.12); main rolls the real tray dice.
func _count_dangerous_trails(trails: Array) -> int:
	var n := 0
	for t in trails:
		var leg := t as Array
		for i in range(1, leg.size()):
			if _path_crosses_terrain(leg[i - 1], leg[i], TerrainRules.PathCheck.DANGEROUS):
				n += 1
				break
	return n


## True when the straight world path a→b crosses a terrain cell matching `check` (TerrainRules.PathCheck),
## sampled against the REAL overlay via the injected terrain_type_at, with TerrainRules as the predicate.
func _path_crosses_terrain(a: Vector3, b: Vector3, check: int) -> bool:
	if not terrain_type_at.is_valid():
		return false
	var span := Vector2(b.x - a.x, b.z - a.z).length()
	var cell_m := TerrainRules.CELL_IN * INCHES_TO_METERS
	var steps := maxi(1, int(ceil(span / (cell_m * 0.5))))
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		if _terrain_matches(int(terrain_type_at.call(p)), check):
			return true
	return false


static func _terrain_matches(t: int, check: int) -> bool:
	match check:
		TerrainRules.PathCheck.DIFFICULT:
			return TerrainRules.is_difficult(t)
		TerrainRules.PathCheck.DANGEROUS:
			return TerrainRules.is_dangerous(t)
		TerrainRules.PathCheck.IMPASSABLE:
			return TerrainRules.is_impassable(t)
	return false


## Whether the unit is a regiment (rigid tray) — those keep the block slide, not individual steering.
func _is_regiment(unit: GameUnit) -> bool:
	return army_manager != null and army_manager.regiments is Dictionary and army_manager.regiments.has(unit.unit_id)


## World-space wall segments ([Vector2 a, Vector2 b], metres) from the injected provider, or empty.
func _walls_world() -> Array:
	if not walls_provider.is_valid():
		return []
	var w: Variant = walls_provider.call()
	if w is Array:
		var arr: Array = w
		return arr
	return []


## Nearest objective this AI side does NOT control (owner != ai_slot). NO_OBJECTIVE when none / no provider.
func _nearest_uncontrolled_objective(from: Vector3) -> Vector3:
	if not objectives_provider.is_valid():
		return NO_OBJECTIVE
	var objs: Variant = objectives_provider.call()
	if not (objs is Array):
		return NO_OBJECTIVE
	var arr: Array = objs
	var best := NO_OBJECTIVE
	var best_d := INF
	for i in range(arr.size()):
		var owner: int = int(objective_owner_of.call(i)) if objective_owner_of.is_valid() else 0
		if owner == ai_slot:
			continue   # already ours → controlled
		var o: Vector3 = arr[i]
		var d := MoveIntent.distance_inches(from, o)
		if d < best_d:
			best_d = d
			best = o
	return best


## Any living enemy within 6" of the straight unit→objective line ("in the way", p.58). Inch-space segment test.
func _enemy_in_way(from: Vector3, obj: Vector3) -> bool:
	if army_manager == null:
		return false
	var a := Vector2(from.x, from.z)
	var b := Vector2(obj.x, obj.z)
	var reach_m := IN_THE_WAY_IN * INCHES_TO_METERS
	for h in army_manager.get_game_units_for_player(human_slot):
		var hu := h as GameUnit
		if hu == null or hu.is_destroyed():
			continue
		var c := unit_centre(hu)
		if _seg_dist(a, b, Vector2(c.x, c.z)) <= reach_m:
			return true
	return false


## Distance (metres) from point p to segment a→b in the table plane. Pure.
static func _seg_dist(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Relentless "Hold and shoot" overlay (Solo & Co-Op Rules v3.5.0 p.2): a ranged weapon with Relentless and
## an enemy in range forces a Hold-and-shoot activation instead of manoeuvring.
static func _forces_hold_and_shoot(weapons: Array, enemy_in_range: bool) -> bool:
	if not enemy_in_range:
		return false
	for w in weapons:
		var rng_in: int = int((w as Object).range_value) if (w is Object and (w as Object).get("range_value") != null) else 0
		if rng_in <= 0:
			continue
		var rules: Array = (w as Object).special_rules if (w is Object and (w as Object).get("special_rules") != null) else []
		for r in rules:
			if str(r).strip_edges().begins_with("Relentless"):
				return true
	return false


## Hold-only unit rules (GF/AoF Advanced Rules v3.5.1 p.13): Immobile — "may only use Hold actions";
## Artillery — "May only use Hold actions." (its solo overlay p.57 adds "If they are in range of enemies,
## they always use Hold and shoot", which the caller honours by keeping the shoot flag). Pure predicate on
## the unit's special-rule strings.
static func forces_hold(unit_rules: Array) -> bool:
	for r in unit_rules:
		var s := str(r).strip_edges()
		if s.begins_with("Immobile") or s.begins_with("Artillery"):
			return true
	return false


## Whether a unit fights with Counter (GF/AoF v3.5.1 p.13) — a Counter melee weapon among `melee_profiles`
## (AiShooting.melee_profiles output), or the rule granted unit-wide in `unit_rules`. Input to the official
## Counter activation-order overlay (solo rules p.57: Counter units activate after all other friendly
## non-Counter units in their section) and to the strike-first melee phase.
static func has_counter(melee_profiles: Array, unit_rules: Array) -> bool:
	for r in unit_rules:
		if str(r).strip_edges().begins_with("Counter"):
			return true
	for p in melee_profiles:
		if bool((p as Dictionary).get("counter", false)):
			return true
	return false


## Alive models of a unit (incl. attached heroes) that fight with Counter — the Impact-reduction /
## charge-EV input (GF/AoF v3.5.1 p.13: "-1 total Impact rolls per model with Counter"). A unit-wide
## Counter rule counts every alive model; otherwise the count of Counter melee-weapon copies, capped at
## the member's alive models (dead models' weapons no longer counter).
static func counter_models_of(unit: GameUnit) -> int:
	if unit == null:
		return 0
	var members: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		members = members + unit.get_attached_heroes()
	var total := 0
	for m in members:
		var member := m as GameUnit
		if member == null:
			continue
		var alive: int = member.get_alive_count()
		if alive <= 0:
			continue
		if member.has_special_rule("Counter"):
			total += alive
			continue
		var weapons: Array = []
		if member.source_type == "opr" and member.source_data is OPRApiClient.OPRUnit:
			weapons = (member.source_data as OPRApiClient.OPRUnit).weapons
		var bearers := 0
		for w in weapons:
			if not (w is Object) or (w as Object).get("range_value") == null or int((w as Object).range_value) > 0:
				continue   # Counter strikes "with this weapon" — a melee-weapon rule
			var rules: Array = (w as Object).special_rules if (w as Object).get("special_rules") != null else []
			for r in rules:
				if str(r).strip_edges().begins_with("Counter"):
					bearers += maxi(int((w as Object).count) if (w as Object).get("count") != null else 1, 1)
					break
		total += mini(bearers, alive)
	return total


# ===== AI decision records (developer mode — introspection first, then intelligence) =====

## Append one structured decision record (see decision_log). Ring-buffered: the oldest record is
## dropped past DECISION_LOG_CAP, so an undrained buffer stays bounded in long games.
func record_decision(rec: Dictionary) -> void:
	decision_log.append(rec)
	if decision_log.size() > DECISION_LOG_CAP:
		decision_log.pop_front()


## Hand the pending records to the renderer and clear the buffer. The caller (main) renders them into
## the battle log when the dev toggle is ON, or discards them (records stay cheap either way).
func drain_decisions() -> Array:
	var out := decision_log
	decision_log = []
	return out


## Render one decision record as a battle-log line — the ONLY place record fields become formatted
## strings (zero formatting cost while the dev toggle is off). Pure + static (testable).
static func render_decision(rec: Dictionary) -> String:
	var parts: PackedStringArray = ["AI [%s] %s" % [str(rec.get("kind", "?")), str(rec.get("unit", "?"))]]
	var rule := str(rec.get("rule", ""))
	if not rule.is_empty():
		parts.append("rule: %s" % rule)
	var cands: Array = rec.get("candidates", [])
	if not cands.is_empty():
		var listed: PackedStringArray = []
		for c in cands:
			var cd := c as Dictionary
			listed.append("%s EV %.2f" % [str(cd.get("name", "?")), float(cd.get("ev", 0.0))])
		parts.append("options: " + ", ".join(listed))
	var chosen := str(rec.get("chosen", ""))
	if not chosen.is_empty():
		parts.append("chose %s" % chosen)
	var why := str(rec.get("why", ""))
	if not why.is_empty():
		parts.append("(%s)" % why)
	var data: Dictionary = rec.get("data", {})
	if not data.is_empty():
		var kv: PackedStringArray = []
		for k in data:
			var v: Variant = data[k]
			kv.append("%s=%s" % [str(k), ("%.1f" % float(v)) if (v is float) else str(v)])
		parts.append("[" + ", ".join(kv) + "]")
	return " — ".join(parts)


# ===== Army rule inventory (the AI-handoff transparency scan) =====

## Classify an army's special-rule occurrences into the three transparency classes the maintainer asked
## for: "resolved" (mechanically implemented — the caller passes main's SOLO_MODELED_RULES, no second
## hand-maintained list), of which the "decision" subset ALSO steers behaviour choices (targeting
## overlays / EV inputs / activation order / movement), and "unknown" (kept in the once-per-session
## un-automated battle-log flow). `rule_names` may repeat (one entry per bearing unit/weapon) — the
## values are occurrence counts. Matching is prefix-based, mirroring _solo_log_unmodeled_rules.
static func classify_rule_inventory(rule_names: Array, modeled: Array, decision_relevant: Array) -> Dictionary:
	var resolved := {}
	var decision := {}
	var unknown := {}
	for r in rule_names:
		var name := str(r).strip_edges().get_slice("(", 0)
		if name.is_empty():
			continue
		var is_modeled := false
		for known in modeled:
			if name.begins_with(str(known)):
				is_modeled = true
				break
		if not is_modeled:
			unknown[name] = int(unknown.get(name, 0)) + 1
			continue
		resolved[name] = int(resolved.get(name, 0)) + 1
		for d in decision_relevant:
			if name.begins_with(str(d)):
				decision[name] = int(decision.get(name, 0)) + 1
				break
	return {"resolved": resolved, "decision": decision, "unknown": unknown}


## OPR "Determine Attacks" (mirrors SoloSim._effective_attacks): only living models' weapons count, so scale
## a weapon group's attacks by alive/max. Pure — used by the real combat path to stop dead models attacking.
static func effective_attacks(base_attacks: int, alive: int, max_models: int) -> int:
	if max_models <= 0:
		return base_attacks
	return maxi(0, int(round(float(base_attacks) * float(alive) / float(max_models))))


## OPR "Who Can Shoot" (GF Advanced Rules v3.5.1 p.8): "All models in a unit with line of sight to the
## target, and that have a weapon that is within range of it, may fire at it." — shooting is PER MODEL:
## count the shooter models that have BOTH range and LOS to at least one target model (the rulebook's
## Dynasty Warriors example: 3 of 5 in range+LOS → 3 attacks). `los` is injected (terrain_overlay in the
## game, a TerrainRules grid in tests) so this stays pure. Nearest-target-model first + early-out keeps
## the check cheap; range gates before the LOS call (the expensive half).
static func sighted_models(shooter_positions: Array, target_positions: Array, range_m: float, los: Callable) -> int:
	if shooter_positions.is_empty() or target_positions.is_empty():
		return 0
	var range2 := range_m * range_m
	var n := 0
	for s in shooter_positions:
		var sp := s as Vector3
		# Nearest target model first: it is the most likely to be visible AND the cheapest to confirm.
		var order: Array = target_positions.duplicate()
		order.sort_custom(func(a, b) -> bool:
			return sp.distance_squared_to(a) < sp.distance_squared_to(b))
		for t in order:
			var tp := t as Vector3
			if Vector2(tp.x - sp.x, tp.z - sp.z).length_squared() > range2:
				break   # sorted by distance — everything after is farther still
			if not los.is_valid() or bool(los.call(sp, tp)):
				n += 1
				break
	return n


## The alternating-activation pump's next step (pure state machine — goal 003 P2 + the auto-tail fix).
## OPR alternation: each human activation is answered by ONE AI activation (REPLY, queued in `pending`);
## once the human side is exhausted the AI plays out its remaining units AUTOMATICALLY (TAIL — the rule's
## "the other side keeps activating"; the maintainer previously had to press F11); both sides exhausted
## ends the round (END_ROUND); otherwise the AI waits for the human (WAIT).
enum AltStep { WAIT, REPLY, TAIL, END_ROUND }


static func alternation_next(pending_replies: int, human_eligible: int, ai_eligible: int) -> AltStep:
	if ai_eligible <= 0:
		return AltStep.END_ROUND if human_eligible <= 0 else AltStep.WAIT
	if pending_replies > 0:
		return AltStep.REPLY
	if human_eligible <= 0:
		return AltStep.TAIL
	return AltStep.WAIT


## Apply `wounds` whole-wounds to a unit's models back-rank-first (Tough models absorb damage before
## dying — GF v3.5.1 p.9 casualty removal, defender-optimal). The TESTABLE core of the solo damage
## application (maintainer field-test: an AI Tough hero soaked wounds with no visible tick — main's seams
## do the marker/broadcast/park work through the callbacks):
##   on_changed : Callable(model)         — wounds_current changed and the model is STILL ALIVE
##   on_died    : Callable(model)         — the model just died
## Returns the wounds left over (spill into an attached hero is the caller's job).
static func apply_wounds_to_models(unit: GameUnit, wounds: int, on_changed: Callable, on_died: Callable) -> int:
	var remaining := wounds
	for i in range(unit.models.size() - 1, -1, -1):
		if remaining <= 0:
			break
		var m: ModelInstance = unit.models[i]
		if m == null or not m.is_alive:
			continue
		var touched := false
		var died := false
		while remaining > 0 and m.is_alive:
			died = m.apply_damage(1)
			touched = true
			remaining -= 1
		if died and on_died.is_valid():
			on_died.call(m)
		elif touched and on_changed.is_valid():
			on_changed.call(m)
	return remaining


## What the P8 targeting mode does with one input event (pure, testable — the event→action resolution).
## The mode owns the MOUSE while active: LMB picks the hovered enemy, RMB/ESC cancels, motion tracks the
## live LOS line. A click over an interactive HUD control is IGNOREd so the GUI keeps working underneath.
## REGRESSION GUARD (maintainer field-test bug): the original P8 wiring fed the handler only from
## _unhandled_key_input, which never receives mouse events in Godot 4 — the enemy click landed nowhere
## (object_manager defers the mouse while targeting). Mouse events MUST be first-class targeting input;
## main._input forwards them through this router.
enum TargetingRoute { IGNORE, CANCEL, PICK, TRACK }


static func targeting_route(event: InputEvent, over_blocking_ui: bool) -> TargetingRoute:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and k.keycode == KEY_ESCAPE:
			return TargetingRoute.CANCEL
		return TargetingRoute.IGNORE
	if event is InputEventMouseMotion:
		return TargetingRoute.TRACK
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return TargetingRoute.IGNORE
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			return TargetingRoute.CANCEL
		if mb.button_index == MOUSE_BUTTON_LEFT:
			return TargetingRoute.IGNORE if over_blocking_ui else TargetingRoute.PICK
	return TargetingRoute.IGNORE


## The AI-action presentation pacing (goal 003 game-feel): every AI action steps through
## ANNOUNCE (who acts on whom — highlights + banner hold) → EXECUTE (animated movement / dice thrown) →
## RESOLVE (event-gated: the tray's roll_finnished fires only after every die has been physically calm
## for its SETTLE_HOLD, plus a readable buffer here) → OUTCOME (the result summary holds on screen) →
## DONE. Pure + testable; main drives the awaits. Fast-forward scales the fixed holds down for veterans.
enum Pace { ANNOUNCE, EXECUTE, RESOLVE, OUTCOME, DONE }

const PACE_ANNOUNCE_S := 1.0            # attribution hold before anything happens
const PACE_OUTCOME_S := 1.8             # result summary hold after a combat resolves
const PACE_DICE_SETTLE_BUFFER_S := 0.6  # extra beat after the tray reports physical rest
const PACE_MOVE_SPEED_M_S := 0.20       # animated model speed (~8"/s — readable, not sluggish)
const PACE_TRAIL_FADE_S := 2.0          # movement trail ribbons fade out over this long
const PACE_FAST_SCALE := 0.15           # fast-forward multiplier on every fixed hold


static func pace_next(phase: int) -> Pace:
	match phase:
		Pace.ANNOUNCE: return Pace.EXECUTE
		Pace.EXECUTE: return Pace.RESOLVE
		Pace.RESOLVE: return Pace.OUTCOME
		_: return Pace.DONE


## The FIXED hold of a phase in seconds (0 for the event-gated phases — EXECUTE ends when the animation
## or dice throw ends, RESOLVE when the tray settles; their buffers/durations come from their own events).
static func pace_seconds(phase: int, fast: bool) -> float:
	var base := 0.0
	match phase:
		Pace.ANNOUNCE: base = PACE_ANNOUNCE_S
		Pace.OUTCOME: base = PACE_OUTCOME_S
		Pace.RESOLVE: base = PACE_DICE_SETTLE_BUFFER_S
		_: base = 0.0
	return base * (PACE_FAST_SCALE if fast else 1.0)


## OPR objective control at ROUND END (Solo & Co-Op v3.5.0 p.6, mirrors SoloSim._seize_objectives): a marker
## is seized by the ONE player with a non-Shaken unit model within 3"; models of two (or more) players within
## 3" contest it → neutral (0); nobody near → the owner PERSISTS. Shaken units can neither seize nor contest.
## Pure + deterministic (goal 003 P2 — the auto-seize the manual radial pick can still override).
##   unit_infos : Array of {player: int, shaken: bool, positions: Array[Vector3] (alive models, metres)}
##   objectives : Array[Vector3] marker world positions
##   owners     : Array[int] current owner player ids (0 = neutral), same length as objectives
## Returns {"owners": Array[int], "changes": Array of {index: int, owner: int}} (changes only where the
## owner actually flipped — the caller logs + broadcasts exactly those).
static func seize_objectives(unit_infos: Array, objectives: Array, owners: Array) -> Dictionary:
	var new_owners: Array = []
	var changes: Array = []
	for i in range(objectives.size()):
		var current: int = int(owners[i]) if i < owners.size() else 0
		var near_players := {}
		for info in unit_infos:
			var d := info as Dictionary
			if bool(d.get("shaken", false)):
				continue   # Shaken units can neither seize nor contest
			var pid: int = int(d.get("player", 0))
			if near_players.has(pid):
				continue
			for p in d.get("positions", []):
				# Inclusive 3" with a hair of float tolerance (~0.025 mm) so a model measured EXACTLY on the
				# ring still counts — the metre→inch conversion is one ulp off at the boundary otherwise.
				if MoveIntent.distance_inches(p, objectives[i]) <= OBJECTIVE_CONTROL_IN + 0.001:
					near_players[pid] = true
					break
		var next: int = current
		if near_players.size() == 1:
			next = int(near_players.keys()[0])   # seized (or held) by the only side near
		elif near_players.size() > 1:
			next = 0                             # contested → neutral
		# nobody near → owner persists
		new_owners.append(next)
		if next != current:
			changes.append({"index": i, "owner": next})
	return {"owners": new_owners, "changes": changes}


## OPR "Who Can Strike" (GF Advanced Rules v3.5.1 p.9, mirrors SoloSim._striking_models): count the striker's
## alive models within 2" (base contact folded in) of ANY enemy model. World positions in METRES. Falls back
## to the whole living set when either side has no positions (a focused test).
static func striking_models(striker_positions: Array, enemy_positions: Array) -> int:
	if striker_positions.is_empty() or enemy_positions.is_empty():
		return striker_positions.size()
	var reach := (BASE_CONTACT_IN + MELEE_REACH_IN) * INCHES_TO_METERS
	var reach2 := reach * reach
	var n := 0
	for s in striker_positions:
		var sp := Vector2((s as Vector3).x, (s as Vector3).z)
		for e in enemy_positions:
			if sp.distance_squared_to(Vector2((e as Vector3).x, (e as Vector3).z)) <= reach2:
				n += 1
				break
	return n


# === Geometry helpers (pure where possible) ===

func unit_centre(unit: GameUnit) -> Vector3:
	return MoveIntent.anchor_of(alive_positions(unit))


func alive_positions(unit: GameUnit) -> Array:
	var out: Array = []
	for m in unit.get_alive_models():
		var node := (m as ModelInstance).node
		if node != null and is_instance_valid(node):
			out.append(node.global_position)
	return out


## Index of the nearest point in `candidates` to `from` (table-plane distance), or -1 if empty. Pure.
static func nearest_index(from: Vector3, candidates: Array) -> int:
	var best := -1
	var best_d := INF
	for i in candidates.size():
		var d := MoveIntent.distance_inches(from, candidates[i])
		if d < best_d:
			best_d = d
			best = i
	return best


## Table half-extents (metres) from the "table" node, or a 4×4 ft default if absent. Pure given a tree.
func _table_half_extents() -> Vector2:
	var t := get_tree().get_first_node_in_group("table") if is_inside_tree() else null
	var feet := Vector2(4, 4)
	if t != null and "table_size" in t:
		feet = t.table_size
	var m := feet * 0.3048
	return m * 0.5


func _clamp_to_bounds(p: Vector3) -> Vector3:
	var h := _table_half_extents()
	return Vector3(clampf(p.x, -h.x + BOUNDS_MARGIN_M, h.x - BOUNDS_MARGIN_M), p.y,
		clampf(p.z, -h.y + BOUNDS_MARGIN_M, h.y - BOUNDS_MARGIN_M))


## Shrink the move delta so no model leaves the table (crude M1 bounds — terrain avoidance is deferred).
func _clamp_delta_to_bounds(positions: Array, delta: Vector3) -> Vector3:
	var h := _table_half_extents()
	var scale := 1.0
	for p in positions:
		var dest: Vector3 = p + delta
		scale = min(scale, _axis_scale(p.x, delta.x, h.x - BOUNDS_MARGIN_M))
		scale = min(scale, _axis_scale(p.z, delta.z, h.y - BOUNDS_MARGIN_M))
	return delta * clampf(scale, 0.0, 1.0)


static func _axis_scale(start: float, d: float, limit: float) -> float:
	var dest := start + d
	if absf(dest) <= limit or is_zero_approx(d):
		return 1.0
	var bound := limit if dest > 0.0 else -limit
	return clampf((bound - start) / d, 0.0, 1.0)


# === AI deployment (goal 001 P2 — OPR Solo & Co-Op v3.5.0) ===

## Deploy the whole AI army by the official rules via the pure AiDeployment core: random 3-way group
## split, D3 section per group (all-same re-roll), then one random unit at a time placed in its section
## as close as possible to the nearest objective — Scouts last, Ambush units into ambush_reserve.
## `zone` = the AI deployment zone in table XZ; `objectives` = XZ points; `blocked_normal` /
## `blocked_flying` classify terrain for ground vs Strider/Flying units. Seeded → reproducible.
## Returns {deployed, reserved, seed}.
func deploy_army(zone: Rect2, objectives: Array, blocked_normal: Callable, blocked_flying: Callable, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Stash the context so the round-2 ambush arrival reuses the same objectives + terrain rules.
	_deploy_objectives = objectives
	_deploy_blocked_normal = blocked_normal
	_deploy_blocked_flying = blocked_flying
	var all_units: Array = []
	for u in army_manager.get_game_units_for_player(ai_slot):
		# Attached heroes deploy WITH their host unit (coherency!), never as their own drop.
		if u != null and u.get_alive_count() > 0 and not (u.has_method("is_attached") and u.is_attached()):
			all_units.append(u)
	if all_units.is_empty():
		return {"deployed": 0, "reserved": 0, "seed": seed_value}
	var groups := AiDeployment.split_into_groups(all_units.size(), rng)
	var sections := AiDeployment.assign_sections(groups.size(), rng)
	var section_of := {}
	for g in range(groups.size()):
		for i in groups[g]:
			section_of[int(i)] = int(sections[g])
	var flags: Array = []
	ambush_reserve.clear()
	for i in range(all_units.size()):
		var u: GameUnit = all_units[i]
		var is_ambush: bool = u.has_special_rule("Ambush")
		flags.append({"id": i, "scout": u.has_special_rule("Scout"), "ambush": is_ambush})
		if is_ambush:
			ambush_reserve.append(u)
	var order := AiDeployment.placement_order(flags, rng)
	var occupied: Array = []
	var deployed := 0
	for id in order:
		var unit: GameUnit = all_units[int(id)]
		var sec := AiDeployment.section_rect(zone, int(section_of.get(int(id), 2)))
		# Deployment REFORMS the unit into a compact grid at its spot — measuring the staging import
		# rows made wide units never fit their section and they were skipped silently (field test:
		# "only a few miniatures deploy"). The footprint is the grid the unit WILL take.
		var radius := _deploy_footprint_radius(unit)
		var ignores_terrain: bool = unit.has_special_rule("Strider") or unit.has_special_rule("Flying")
		var blocked := blocked_flying if ignores_terrain else blocked_normal
		var spot := AiDeployment.best_spot(sec, objectives, occupied, radius, blocked, 0.025, radius)
		var spot_why := "best legal spot toward nearest objective (section)"
		if spot == Vector2.INF:
			spot = AiDeployment.best_spot(zone, objectives, occupied, radius, blocked, 0.025, radius)
			spot_why = "section full — whole-zone fallback"
		if spot == Vector2.INF:
			# The army MUST deploy (rule) — worst case the unit forms up at its section centre even if
			# that crowds neighbours; never silently skip a unit again.
			spot = sec.get_center()
			spot_why = "zone full — section centre (must deploy)"
		_place_unit_at(unit, spot)
		record_decision({"kind": "deploy", "unit": unit.get_name(),
			"rule": "Solo v3.5.0 AI deployment: objective-near spot in the unit's section; Scout/Ambush overlays",
			"candidates": [], "chosen": "", "why": spot_why,
			"data": {"section": int(section_of.get(int(id), 2)), "x_m": spot.x, "z_m": spot.y}})
		occupied.append({"pos": spot, "radius": radius})
		deployed += 1
	return {"deployed": deployed, "reserved": ambush_reserve.size(), "seed": seed_value}


const AMBUSH_MIN_ENEMY_DIST_M := 0.2286   # OPR: Ambush arrivals deploy MORE THAN 9" from enemy units


## OPR Ambush (goal 003 P1): reserved units arrive at the start of round 2, placed by the same deploy
## rules (near the nearest objective, avoiding blocked terrain, reusing the context stashed by
## deploy_army) but strictly MORE THAN 9" from any enemy. `arrival_zone` is the whole table (ambush may
## arrive anywhere); `enemy_positions` are enemy unit centres in table XZ. A unit with no legal spot on a
## crowded table stays in reserve for a later round. Returns {arrived, still_reserved}.
func arrive_ambush_reserve(arrival_zone: Rect2, enemy_positions: Array) -> Dictionary:
	if ambush_reserve.is_empty():
		return {"arrived": 0, "still_reserved": 0}
	var no_block := func(_p: Vector2) -> bool: return false
	var occupied: Array = []
	for e in enemy_positions:
		occupied.append({"pos": e, "radius": AMBUSH_MIN_ENEMY_DIST_M})
	var arrived := 0
	var still: Array = []
	for u in ambush_reserve:
		var unit: GameUnit = u
		if unit == null or unit.get_alive_count() <= 0:
			continue   # a reserve unit destroyed before arrival is simply gone
		var ignores_terrain: bool = unit.has_special_rule("Strider") or unit.has_special_rule("Flying")
		var blocked: Callable = _deploy_blocked_flying if ignores_terrain else _deploy_blocked_normal
		if not blocked.is_valid():
			blocked = no_block
		var radius := _deploy_footprint_radius(unit)
		var spot := AiDeployment.best_spot(arrival_zone, _deploy_objectives, occupied, radius, blocked, 0.025, radius)
		if spot == Vector2.INF:
			still.append(unit)
			continue
		_place_unit_at(unit, spot)
		occupied.append({"pos": spot, "radius": radius})
		arrived += 1
	ambush_reserve = still
	return {"arrived": arrived, "still_reserved": still.size()}


const DEPLOY_SPACING_M := 0.04   # compact deployment grid: model-centre spacing (~1.6", coherent)
const DEPLOY_COLS := 5           # models per rank in the deployment grid


## The models a deployment drop places: the unit's own alive models PLUS its attached heroes' — heroes
## deploy with their unit, in the same grid (coherency).
func _deploy_models(unit: GameUnit) -> Array:
	var out: Array = unit.get_alive_models()
	if unit.has_method("get_attached_heroes"):
		for h in unit.get_attached_heroes():
			if h != null:
				out = out + h.get_alive_models()
	return out


## Footprint radius of the COMPACT grid the unit takes at deployment (not its staging formation).
func _deploy_footprint_radius(unit: GameUnit) -> float:
	var n: int = maxi(_deploy_models(unit).size(), 1)
	var cols: int = mini(n, DEPLOY_COLS)
	var rows: int = int(ceil(float(n) / float(DEPLOY_COLS)))
	var half_w: float = float(cols - 1) * DEPLOY_SPACING_M * 0.5
	var half_d: float = float(rows - 1) * DEPLOY_SPACING_M * 0.5
	return sqrt(half_w * half_w + half_d * half_d) + 0.03


## Put the unit AT the spot: a regiment moves as its tray and reforms its block there; a loose unit's
## models form a compact grid (ranks of DEPLOY_COLS). Positions broadcast so MP mirrors stay in sync.
func _place_unit_at(unit: GameUnit, spot: Vector2) -> void:
	if army_manager != null and army_manager.regiments is Dictionary and army_manager.regiments.has(unit.unit_id):
		var reg = army_manager.regiments[unit.unit_id]
		if reg != null and is_instance_valid(reg.tray):
			reg.tray.global_position = Vector3(spot.x, reg.tray.global_position.y, spot.y)
			reg.tray.reform_from_unit(unit)
			# Heroes attached to the regiment stand directly behind the block (coherency).
			var back := 0.08 if spot.y > 0.0 else -0.08
			var hi := 0
			if unit.has_method("get_attached_heroes"):
				for h in unit.get_attached_heroes():
					if h == null:
						continue
					for m in h.get_alive_models():
						var hnode: Node3D = (m as ModelInstance).node
						if hnode != null and is_instance_valid(hnode):
							hnode.global_position = Vector3(spot.x + float(hi) * DEPLOY_SPACING_M, hnode.global_position.y, spot.y + back)
							hi += 1
			_broadcast_positions(unit)
			return
	var alive: Array = _deploy_models(unit)   # incl. attached heroes — they drop with their unit
	var n: int = alive.size()
	if n == 0:
		return
	var cols: int = mini(n, DEPLOY_COLS)
	var rows: int = int(ceil(float(n) / float(DEPLOY_COLS)))
	for i in range(n):
		var node: Node3D = (alive[i] as ModelInstance).node
		if node == null or not is_instance_valid(node):
			continue
		var col: int = i % DEPLOY_COLS
		var row: int = i / DEPLOY_COLS
		node.global_position = Vector3(
			spot.x + (float(col) - float(cols - 1) * 0.5) * DEPLOY_SPACING_M,
			node.global_position.y,
			spot.y + (float(row) - float(rows - 1) * 0.5) * DEPLOY_SPACING_M)
	_broadcast_positions(unit)


## Broadcast the unit's CURRENT model positions (incl. attached heroes) as one move batch (MP mirror).
func _broadcast_positions(unit: GameUnit) -> void:
	if network_manager == null or not network_manager.has_method("broadcast_move_batch"):
		return
	var batch: Array = []
	for m in _deploy_models(unit):
		var node: Node3D = (m as ModelInstance).node
		if node != null and is_instance_valid(node) and node.has_meta("network_id"):
			batch.append(node.get_meta("network_id"))
			batch.append(node.global_position.x)
			batch.append(node.global_position.y)
			batch.append(node.global_position.z)
	if not batch.is_empty():
		network_manager.broadcast_move_batch(batch)

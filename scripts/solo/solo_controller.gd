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
## A charge closes the REAL base-to-base gap plus this hair so the nearest models land firmly in contact
## (the target's body-only planner zone clamps them to exact contact; snap_charge clears any residual).
## Not a rule value — a contact epsilon (field-test finding 3: a charge within band fell short of contact).
const CHARGE_CONTACT_MARGIN_IN := 0.25
## Kite margin: the "Advancing" step-back stops this hair INSIDE max range instead of exactly ON the
## edge — a move ending at 24.000…1" of a 24" gun lost its shot to float noise (AI plausibility wave 1).
## A measuring margin in the CHARGE_CONTACT_MARGIN_IN spirit, not a rule value.
const KITE_RANGE_MARGIN_IN := 0.25
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
## Winner consolidation (GF Advanced Rules v3.5.1 p.9 "Consolidation Moves"): "If one of the two units was
## destroyed (by removing all models as casualties, or by routing due to a failed morale test), then the
## other unit may move by up to 3”." — verified identical across GF / AoF / AoFS / GFF / AoFR v3.5.1, so one
## shared constant (no system scoping needed; re-check on errata).
const CONSOLIDATION_WIN_IN := 3.0
## Safety margin added to the moving base's radius when inflating obstacles (inches) — guards float
## shaving at wall corners; not a rule value.
const CLEARANCE_EPS_IN := 0.1
## A planned move achieving less than this fraction of its budget counts as STALLED and is re-planned
## straight through the terrain it tried to route around (round 7, finding 2 — mirrors the planner's
## STUCK_FRACTION). A convention, not a rule value.
const STALL_REPLAN_FRACTION := 0.25
## Target candidates within the same 1" distance band count as "equally near" — tabletop measuring
## precision for the official nearest-target key. A GENUINE tie is where the official rules would roll a
## die; the hybrid policy (docs/SOLO_AI_PLAN.md) ranks it by the EV metric instead. A documented
## convention, not an official value.
const TARGET_TIE_BAND_IN := 1.0

# --- Aircraft (GF Advanced Rules v3.5.1 special rule; AI plausibility wave 1) ---
## Fallback values for the RulesRegistry "Aircraft" params (the committed gf mechanics map carries the
## same numbers; these keep headless tests without assets byte-identical). Per the rulebook: Advance-only,
## straight line, the move is mandatory and at least this long (a table edge may not shorten it below),
## and enemies targeting the aircraft get the range penalty. The solo-AI section fixes the AI's aircraft
## move at exactly 30".
const AIRCRAFT_MOVE_IN := 30.0
const AIRCRAFT_TARGET_RANGE_PENALTY_IN := 12.0
## Compass headings sampled when no enemy-directed aircraft lane is legal/scoring (evenly spread, fixed
## order ⇒ deterministic tie behaviour).
const AIRCRAFT_HEADINGS := 16

# --- Big-base maneuvering (AI plausibility wave 1) ---
## A model whose base bounding radius reaches this counts as LARGE (Carnivo-Rex class, ≥ ~75 mm across):
## it gets the boxed-reposition fallback and, at high coordination grades, activates before smaller
## friends fill the lanes. A planning convention, not a rule value.
const LARGE_BASE_RADIUS_IN := 1.5
## A completed move that displaced the unit less than this counts as BOXED for the reposition fallback
## and the plausibility metric ("no large model idles >2 activations unless surrounded").
const BOXED_ACHIEVED_IN := 1.0
## Lateral goal rotations (degrees, tried in order) of the boxed-reposition fallback: when even the
## gate-collapse ladder left a LARGE base at a token step, re-aim the same band sideways to find an open
## lane instead of grinding into the jam. Both signs of each magnitude are tried (+ then -); the fan
## reaches all the way to a pure BACK-OUT (180°) — a deployment-crowd-boxed monster that waddles free
## backward beats one twitching half an inch into the jam (rekrut showcase: Carnivo-Rex R1).
const BOXED_REPOSITION_DEGREES: Array[float] = [35.0, 70.0, 110.0, 145.0, 180.0]

# --- Fast-unit flanking doctrine (AI plausibility wave 1) ---
## A ranged unit whose Advance band reaches this (Fast bikes and similar) prefers a FLANKING firing
## position over walking straight at its target: stand-off points on the target's flanks that keep
## range + LOS score an EV bonus. Conventions, not rule values (movement placement is officially open).
const FLANK_MIN_ADVANCE_IN := 7.0
## Flank candidate bearings (degrees off the straight approach line, tried symmetrically ±).
const FLANK_ANGLES: Array[float] = [0.0, 35.0, 70.0, 100.0]
## Stand-off gap kept inside max weapon range at the flank anchor (measuring slack + a step of kite room).
const FLANK_RANGE_SLACK_IN := 2.0
## Tie-break EV bonus per 90° of flank offset — enough to prefer a flank among near-equal shots, never
## enough to override a materially better straight-line volley.
const FLANK_EV_BONUS_PER_90 := 0.15

# --- Hard final placement gate (field-test findings 3 + 6; real-game loose-unit path only) ---
const OVERLAP_GATE_PASSES := 4        # Gauss-Seidel passes of the per-model absolute overlap resolution
const COH_SHORTEN_BISECT := 16        # bisection depth of the coherency move-shorten (2^-16 ≈ 0.0015%)
const TERRAIN_OUT_STEP_M := 0.01      # radial search granularity when projecting a model OUT of impassable
const TERRAIN_OUT_MAX_M := 0.20       # max radial reach of the impassable-out projection (~8")
const TERRAIN_OUT_DIRS := 16          # compass directions sampled for the impassable-out projection
const OVERLAP_EPS_M := 0.0005         # sub-0.5 mm world moves are noise (matches the animation snap tolerance)

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
## Flow order (MODEL indices, nearest-to-destination first) of the last loose AI move — the sequential
## per-model flow (field-test round 6, finding 7). last_move_paths is reordered into this order so the
## presentation glides each model individually in the order it filed to its slot. Empty for a regiment / a
## move that produced no plan.
var last_flow_order: Array = []
## Move budget (inches) actually granted to the last AI move (band, difficult-capped when the route
## entered difficult terrain) — the denominator of the corridor's distance label.
var last_move_budget_in: float = 0.0
## Limited weapons already fired this game (wave 5, core v3.5.1: "may only be used once per game").
## Key: "<unit_id>::<weapon name>" (limited_key). Tracked for EVERY unit — AI and human — since both
## resolve through the shared profile paths; lives with the controller (one game = one controller).
var limited_used: Dictionary = {}
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

# === COMMANDER LAYER (AI plausibility Stage 3, Part B) ===============================================
## A thin per-round commander (research §3 SCHICHT 1; Killzone full-assignment): EVERY graded AI unit gets
## a weighted ROLE + a standing order so nothing structurally idles. The load-bearing effect is a PERSISTENT
## close-and-fight target for melee/monster roles: a unit keeps closing on ONE enemy across rounds instead of
## re-chasing whoever is momentarily "nearest, not-yet-activated" — the Carnivo-Rex flip-chase (enemy gap
## 34→22→34→31 over four rounds) that left a 295-pt monster idle at the board edge. Orders PERSIST and are
## re-validated each activation (Killzone continue-task: keep unless the target died or a certain charge on a
## nearer enemy appears). Difficulty scales the SCOPE via the (previously dead) coordination knob:
##   FULL  (kriegsherr/albtraum, coord ≥ 0.9): every close-role unit is driven with a standing target.
##   BASIC (veteran, coord ≥ COORD_THRESHOLD): every close-role unit is driven.
##   MINIMAL (rekrut, coord < COORD_THRESHOLD): ONLY big monsters get a standing order — the rest act
##           locally (re-pick nearest each round = rekrut's characteristic idle-prone weakness).
## Only consulted under a difficulty (arena / graded human-vs-AI); the default null-AI and the SoloSim oracle
## never enter it, so their planned decisions stay byte-identical. Every assignment is a reasoning record.
enum CmdRole { CLOSE_AND_FIGHT, RANGED_LINE, FLANK, CASTER, AIRCRAFT }
const CMD_ROLE_NAMES := ["close-and-fight", "ranged line", "flanker", "caster", "aircraft"]
const COMMANDER_FULL_COORD := 0.9   # coordination at/above which the commander drives EVERY close-role unit
## Standing orders keyed by unit_id → {role:int, target_id:String, round:int, driven:bool}. One game = one
## controller, so this persists for the whole match; re-validated on each activation of the unit.
var commander_orders: Dictionary = {}
## Optional mirror of EVERY decision record (Callable(rec: Dictionary) -> void), invoked at record time
## BEFORE ring-buffer eviction — the rating-ladder harness captures the full stream for its per-game
## result JSON without touching the dev-toggle drain path. Invalid (default) ⇒ zero cost, no behaviour change.
var decision_sink: Callable = Callable()
## Injected by main: Callable() -> int returning the CURRENT round number, plus the match length —
## the final-round objective urgency (AI plausibility wave 1) pivots on "is this the last round?".
## Invalid/0 ⇒ the urgency never fires (headless tests, endless sandbox play).
var round_provider: Callable = Callable()
var game_rounds: int = 0
## Kind-specific extras merged into the NEXT move decision record (_execute_move) — the acting layer
## (_act) knows the enemy gap / objective intent the executor doesn't; cleared after each merge.
var _move_extra: Dictionary = {}
## Injected by main: Callable(from: Vector3, to: Vector3) -> bool for terrain line of sight.
var los_checker: Callable = Callable()
## Injected by main: Callable(shooter: GameUnit, target: GameUnit) -> bool — the GEOMETRIC PER-MODEL line
## of sight (terrain + walls + other units' bases, GF/AoF v3.5.1 p.5/p.8). When wired it OVERRIDES the
## coarse unit-centre los_checker so the AI's shoot decision matches the resolution's per-model gate
## (field-test finding 6: a shooter with a clear per-model line, but a blocked centre-to-centre line, was
## wrongly held from firing; finding 2 is the reverse — a blocked line must never fire).
var unit_los_checker: Callable = Callable()
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

# === AI ARENA difficulty (policy knobs; see SoloDifficulty) ===
## Per-side difficulty presets: player-slot → SoloDifficulty. Empty ⇒ the DEFAULT AI (the human-vs-AI flow
## is byte-identical to before — no knob code runs when active_difficulty() returns null). Set per side so a
## both-AI arena match can pit e.g. Rekrut (P1) vs Kriegsherr (P2). The knobs shape only the discretionary
## hybrid-policy zones; legality is never affected (SoloDifficulty).
var difficulty_by_slot: Dictionary = {}
## Game-level base seed folded into every knob draw, so a whole match's "mistakes" replay identically.
var difficulty_seed: int = 0
## Monotonic activation counter (never reset) — the per-activation seed part that makes each decision's
## deterministic draw unique while staying fully reproducible for a fixed seed.
var _activation_seq: int = 0


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


## Assign a difficulty preset to one player slot (the arena's per-side grading). `diff == null` clears it
## (that slot reverts to the DEFAULT sharp AI). The base seed is stamped onto every assigned preset so all
## sides draw from the same reproducible game seed.
func set_difficulty(slot: int, diff: SoloDifficulty) -> void:
	if diff == null:
		difficulty_by_slot.erase(slot)
		return
	diff.base_seed = difficulty_seed
	difficulty_by_slot[slot] = diff


## The difficulty steering the CURRENTLY-acting AI side (ai_slot), or null when none is configured — in
## which case every knob site falls through to the original, byte-identical decision path.
func active_difficulty() -> SoloDifficulty:
	return difficulty_by_slot.get(ai_slot, null)


## The deterministic seed parts for a knob draw on `unit` this activation: the game seed is folded in by
## SoloDifficulty; here we add the acting side, the monotonic activation index and the unit's name hash so
## two units (or two sides) in the same activation slot never share a draw.
func _knob_seed_parts(unit: GameUnit) -> Array:
	return [ai_slot, _activation_seq, str(unit.get_name()).hash()]


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
	# A unit still HELD in Ambush reserve is off the table and cannot be activated until it arrives
	# (GF/AoF Advanced Rules v3.5.1 p.13: "May be set aside before deployment. At the start of any round
	# after the first, may be deployed…"). Field-test finding 5: reserve units were eligible in round 1
	# (the AI activated a not-yet-arrived unit); arrival then read as if it had already spent its turn.
	if unit_in_reserve(u):
		return false
	return not (u.has_method("is_attached") and u.is_attached())


## Whether a unit is still HELD in Ambush reserve (off-table, not yet arrived — GF/AoF v3.5.1 p.13). The
## single truth used everywhere a reserve unit must be invisible to the game: activation eligibility,
## movement/LOS obstacles, and target validity. Field-test finding 3: a reserve unit leaked into play.
static func unit_in_reserve(u: GameUnit) -> bool:
	return u != null and bool(u.unit_properties.get("ambush_reserve", false))


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
	_activation_seq += 1   # monotonic per-activation index for the deterministic difficulty draws
	last_move_paths = []   # cleared per activation — HOLD / Shaken idle replays nothing
	if unit.is_shaken:
		# OPR (p.10): a Shaken unit spends its activation idle, which lets it recover. An AIRCRAFT still
		# makes its MANDATORY straight move first (GF v3.5.1: the move happens even Shaken, and it does
		# not break the staying-idle requirement) — _act_aircraft skips targeting/shooting while Shaken.
		if is_aircraft(unit):
			last_report = _act(unit)
			last_report["idle_shaken"] = true
			last_report["shoot"] = false
			last_report["can_shoot"] = false
		else:
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
	# LARGE-BASES-FIRST (AI plausibility wave 1, big-model maneuvering): the official pick draws a RANDOM
	# eligible unit from the section — a die roll the hybrid policy may fill with judgment. At high
	# coordination grades the section's LARGE bases (Carnivo-Rex class) activate before small friends
	# fill the lanes, so the big model still has room to plan its move. The pick stays random WITHIN the
	# preferred pool (same seeded stream); the Shaken/Counter overlays keep their precedence above.
	var diff := active_difficulty()
	var large_first := false
	if diff != null and diff.focus_fires() and section.size() > 1:
		var large: Array = []
		for u in section:
			if _move_base_radius_m(_moving_models(u as GameUnit)) >= LARGE_BASE_RADIUS_IN * INCHES_TO_METERS:
				large.append(u)
		if not large.is_empty() and large.size() < section.size():
			section = large
			large_first = true
	var picked: GameUnit = section[_rng.randi_range(0, section.size() - 1)]
	record_decision({"kind": "pick", "unit": picked.get_name(),
		"rule": "Solo v3.5.0: D6 section roll, random eligible; Shaken last; Counter last in section (p.57)",
		"candidates": [], "chosen": picked.get_name(),
		"why": ("large bases first" if large_first else ("counter units deferred" if counter_deferred
			else ("shaken pool" if fresh.is_empty() else "section roll"))),
		"data": {"west": west.size(), "east": east.size(), "rolled_west": roll_west,
			"eligible": eligible.size(), "large_first": large_first}})
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
	# An Aircraft can't be charged (GF v3.5.1) — for a unit with NO ranged weapons it is no valid
	# target at all (it can never attack it), so the nearest-target key skips it.
	var melee_only: bool = AiShooting.profiles_in_range(_unit_weapons(ai_unit), 0.0).is_empty()
	var cands: Array = []
	for h in army_manager.get_game_units_for_player(human_slot):
		var hu := h as GameUnit
		if hu == null or hu.is_destroyed() or unit_in_reserve(hu):
			continue   # skip destroyed units and any still off-table in Ambush reserve (findings 3/4)
		if hu.has_method("is_attached") and hu.is_attached():
			continue   # a joined hero is PART of its host unit — you target the unit, never the hero alone
		if melee_only and is_aircraft(hu):
			continue   # unchargeable and out of reach for a pure melee unit — never "the nearest valid target"
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
		# A genuine tie: rank by EV (utility instead of the rules' die roll — hybrid policy). Wave 5:
		# expended Limited profiles are filtered out and the Sergeant facet is stamped on BOTH sides,
		# so the score sees the same weapon state the dice would roll.
		var our_weapons := _unit_weapons(ai_unit)
		var our_melee := AiEv.stamp_sergeant(filter_limited(ai_unit, AiShooting.melee_profiles(our_weapons)), ai_unit)
		var us := AiEv.ctx_for(ai_unit, majority_in_cover(ai_unit), counter_models_of(ai_unit))
		for t in tied:
			var td := t as Dictionary
			var hu := td["unit"] as GameUnit
			# Real terrain cover feeds the EV (field-test finding 6): a defender whose majority sits in
			# woods/ruins is worth less to shoot — the EV must see it, not a hardcoded false.
			var them := AiEv.ctx_for(hu, majority_in_cover(hu), counter_models_of(hu))
			if our_melee.is_empty():
				# Targeting an Aircraft costs -12" of range — fold it into the EV distance so the
				# range gates inside shoot_ev see the effective reach (system-scoped; 0 otherwise).
				td["ev"] = AiEv.shoot_ev(AiEv.stamp_sergeant(
					filter_limited(ai_unit, AiShooting.profiles_in_range(our_weapons, 0.0)), ai_unit), us, them,
					float(td["d"]) + target_range_penalty_in(hu))
			else:
				td["ev"] = AiEv.charge_score(our_melee, us,
					AiEv.stamp_sergeant(filter_limited(hu, AiShooting.melee_profiles(_unit_weapons(hu))), hu), them)
		var diff := active_difficulty()
		if diff == null:
			# DEFAULT AI (and human-vs-AI): the sharp pick — the earliest maximum-EV tied target. Byte-identical.
			for t in tied:
				if float((t as Dictionary)["ev"]) > float(chosen["ev"]):
					chosen = t
			why = "ev tie-break"
		else:
			# ARENA: the difficulty knobs shape which of the (equally legal) tied targets is taken.
			chosen = _difficulty_target_pick(ai_unit, tied, diff)
			why = "ev tie-break (%s)" % diff.grade_name
	var rec_cands: Array = []
	for t in tied:
		var td := t as Dictionary
		# Report a NON-NEGATIVE target EV (field-test finding 2): the charge tie-break score is a NET
		# dealt-minus-taken utility that can go below zero for an unfavourable matchup, but it is only ever a
		# ranking key — surfacing a negative "expected wounds" in the dev log is misleading, so the recorded
		# value is floored at 0. The raw score still drives the ranking above (selection is unchanged).
		rec_cands.append({"name": (td["unit"] as GameUnit).get_name(), "ev": maxf(0.0, float(td["ev"])),
			"key": [td["activated"], td["band"]]})
	record_decision({"kind": "target", "unit": ai_unit.get_name(),
		"rule": "Solo v3.5.0 p.2: nearest valid target, not-activated first",
		"candidates": rec_cands, "chosen": (chosen["unit"] as GameUnit).get_name(), "why": why,
		"data": {"considered": cands.size(), "dist_in": float(chosen["d"])}})
	return chosen["unit"] as GameUnit


## ARENA — pick the taken target from a set of GENUINELY TIED candidates (same official key; EV already
## filled) under a difficulty. Every candidate here is an equally-legal choice, so the knobs shape only
## CLEVERNESS: rule_exploitation narrows by the weapon overlay (Deadly→Tough…), coordination orders for
## focus-fire vs spread, ev_noise deviates to the 2nd/3rd-best. Deterministic; each application is recorded.
func _difficulty_target_pick(ai_unit: GameUnit, tied: Array, diff: SoloDifficulty) -> Dictionary:
	var pool: Array = tied.duplicate()
	# rule_exploitation: press the weapon overlay to narrow the tie (Solo & Co-Op v3.5.0 p.2 targeting keys).
	# Lower grades skip it — they leave the Deadly-onto-Tough / AP-onto-armour optimisation unused.
	var exploited := false
	if diff.exploits_rules() and pool.size() > 1:
		var overlay: int = AiTargeting.weapon_overlay(_all_weapon_rules(ai_unit))
		if overlay != AiTargeting.Overlay.NONE:
			var descs: Array = []
			for t in pool:
				descs.append(_overlay_descriptor(t as Dictionary))
			var keep: Array = AiTargeting.tied_with_best(descs, overlay, AiTargeting.best_index(descs, overlay))
			if not keep.is_empty() and keep.size() < pool.size():
				var narrowed: Array = []
				for i in keep:
					narrowed.append(pool[i])
				pool = narrowed
				exploited = true
	# coordination: order best-first for FOCUS FIRE (highest EV first) or worst-first to SPREAD onto another
	# tied target. A total order (EV, then original tie index) keeps it deterministic regardless of sort stability.
	var focus := diff.focus_fires()
	for i in range(pool.size()):
		(pool[i] as Dictionary)["_i"] = i
	pool.sort_custom(func(a, b) -> bool:
		var ea := float((a as Dictionary)["ev"])
		var eb := float((b as Dictionary)["ev"])
		if ea != eb:
			return (ea > eb) if focus else (ea < eb)
		return int((a as Dictionary)["_i"]) < int((b as Dictionary)["_i"]))
	# ev_noise: deviate to the 2nd/3rd-best of the coordination ordering with the seeded probability.
	var idx: int = diff.noisy_pick(pool.size(), _knob_seed_parts(ai_unit))
	var chosen: Dictionary = pool[idx]
	record_decision({"kind": "difficulty", "unit": ai_unit.get_name(),
		"rule": "ARENA target knobs (%s): overlay/coordination/ev_noise on a genuine tie — always legal" % diff.grade_name,
		"candidates": [], "chosen": (chosen["unit"] as GameUnit).get_name(),
		"why": ("focus-fire" if focus else "spread") + (" +noise" if idx > 0 else ""),
		"data": {"grade": diff.grade_name, "exploited": exploited, "spread": not focus,
			"deviation": idx, "tied": tied.size(), "pool": pool.size()}})
	return chosen


## Every special-rule string carried by the unit's weapons — the input to the dominant targeting overlay.
func _all_weapon_rules(unit: GameUnit) -> Array:
	var out: Array = []
	for w in _unit_weapons(unit):
		var rules: Array = []
		if w is Object and (w as Object).get("special_rules") != null:
			rules = (w as Object).special_rules
		elif w is Dictionary:
			rules = (w as Dictionary).get("special_rules", [])
		for r in rules:
			out.append(r)
	return out


## Build the AiTargeting candidate descriptor for one tied enemy (for the overlay narrowing). Upgrade-cost
## tiers are not representable in this data (flagged in docs/SOLO_AI_RULES_COVERAGE.md) → defaults.
func _overlay_descriptor(td: Dictionary) -> Dictionary:
	var hu := td["unit"] as GameUnit
	var tough: int = maxi(AiEv.unit_rating(hu, "Tough"), 1)
	var alive: int = maxi(hu.get_alive_count(), 1)
	return {"dist": float(td["d"]), "activated": bool(td.get("activated", false)),
		"in_cover": majority_in_cover(hu), "defense": hu.get_defense(),
		"is_hero": hu.has_special_rule("Hero"), "has_upgrade": false, "upgrade_cost": 0,
		"single_tough": alive == 1 and tough > 1, "has_tough": tough > 1,
		"remaining_tough": tough * alive}


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
	if alive_positions(unit).is_empty():
		return report
	# Aircraft (GF v3.5.1, system-scoped): mandatory straight Advance on an EV-picked strafing lane —
	# a completely separate action shape (no decision tree, no objectives, no charge).
	if is_aircraft(unit):
		return _act_aircraft(unit, report)
	var target_unit := nearest_human_unit(unit)
	if target_unit == null:
		return report
	# COMMANDER (Stage 3, Part B): a graded standing order. For a close-and-fight role it PERSISTS the target
	# across rounds so the unit keeps closing on ONE enemy instead of re-chasing the momentary nearest (the
	# idle monster). Returns the default target unchanged for the null-AI / non-driven roles (byte-identical).
	target_unit = _commander_apply(unit, target_unit)
	report["target"] = target_unit
	var weapons := _unit_weapons(unit)
	var bands: Dictionary = move_bands_for_unit(unit, movement_range)
	var advance := float(bands.get("advance", 6))
	var rush := float(bands.get("rush", 12))
	# Musician (wave 5, system-scoped via RulesRegistry — the full games grant the bearer's unit +1" on
	# move actions; GFF/AoFS scope it to the bearer + up to 3 picked units, of which the automation
	# applies the bearer facet): +1" on every move band (Advance AND Rush/Charge are move actions).
	var musician_in := musician_move_bonus_in(unit)
	if musician_in > 0.0:
		advance += musician_in
		rush += musician_in
	var centre := unit_centre(unit)
	var tcentre := unit_centre(target_unit)
	var enemy_dist := MoveIntent.distance_inches(centre, tcentre)
	var shoot_range := AiArchetype.max_range_inches(weapons) + shooting_range_bonus(unit)   # +Royal Legion (wave 4)
	# Targeting an Aircraft costs -12" of range (GF v3.5.1, system-scoped) — every range gate below
	# measures against THIS target, so the penalty folds into the working range once, here.
	var target_is_aircraft := is_aircraft(target_unit)
	if target_is_aircraft and shoot_range > 0:
		shoot_range = maxi(shoot_range - int(target_range_penalty_in(target_unit)), 0)
	# The archetype's "better than" (Solo & Co-Op v3.5.0 p.1) is filled with the EV metric in the REAL
	# game (AiEv.classify — Furious/Thrust/Impact weigh the melee side); the sim keeps the frozen
	# AiArchetype.classify heuristic, so its fairness oracle is untouched.
	var archetype := AiEv.classify(weapons, AiEv.ctx_for(unit, false, 0))
	# Nearest objective NOT controlled by this AI side — the official trees pivot on it. Control follows the
	# official "Controlling Objectives" rule (Solo & Co-Op v3.5.0 p.2), and among the un-held ones the tree
	# prefers a HOLDABLE marker over a contested one so units peel off to open flanks (field-test finding 1).
	var obj_pos := _nearest_uncontrolled_objective(centre, unit)
	var has_obj: bool = obj_pos != NO_OBJECTIVE
	# ARENA mission_focus knob: a lower grade may deliberately IGNORE an uncontrolled objective and just fight
	# the enemy (always a legal play). Deterministic + reproducible; at full focus (Kriegsherr/Albtraum, or the
	# default null AI) this never fires, so the official tree is untouched. Every application is explainable.
	var diff := active_difficulty()
	if diff != null and has_obj and diff.skips_objective(_knob_seed_parts(unit)):
		has_obj = false
		record_decision({"kind": "difficulty", "unit": unit.get_name(),
			"rule": "ARENA mission_focus (%s): weaker grades fight instead of holding — legal, never forced" % diff.grade_name,
			"candidates": [], "chosen": "ignore objective, engage enemy", "why": "mission_focus knob",
			"data": {"grade": diff.grade_name, "mission_focus": diff.mission_focus}})
	var obj_dist: float = MoveIntent.distance_inches(centre, obj_pos) if has_obj else INF
	# The charge gate measures the REAL base-to-base gap, not the coarse centre-to-centre distance (finding
	# 3): a wide/offset unit whose centres are >12" apart can still have bases inside the 12" charge band —
	# and must never DECLARE a charge whose true gap exceeds the band (GF/AoF v3.5.1 p.8).
	var charge_gap := nearest_melee_gap_in(unit, target_unit)
	var ctx := {
		"arch": archetype, "objective": has_obj, "in_way": has_obj and _enemy_in_way(centre, obj_pos),
		"obj_in_advance": obj_dist <= advance + OBJECTIVE_CONTROL_IN,
		"obj_in_rush": obj_dist <= rush + OBJECTIVE_CONTROL_IN,
		# An Aircraft can't be charged (GF v3.5.1) — the tree must never see it "in charge range".
		"enemy_in_charge": charge_gap <= rush and not target_is_aircraft,
		"shoot_after_advance": shoot_range > 0 and (enemy_dist - advance) <= float(shoot_range),
	}
	var dec := AiDecision.decide_solo(ctx)
	var action: int = int(dec["action"])
	var do_shoot: bool = bool(dec["shoot"])
	var action_why := "decision tree"
	# FINAL-ROUND OBJECTIVE URGENCY (AI plausibility wave 1): in the match's LAST round, a full-focus
	# grade (kriegsherr/albtraum — and the default AI) that can still REACH seize range of an
	# uncontrolled marker goes for it instead of a marginal fight: after this activation there is no
	# later turn where the fight pays off, only the markers score. Never fires when the unit is already
	# in seize range, when the charge target itself contests that marker (fighting there IS holding it),
	# or mid-match. Overlays below (Relentless/Immobile hold) keep their precedence.
	var diff2 := active_difficulty()
	if _is_final_round() and has_obj and (diff2 == null or diff2.mission_focus >= 1.0) \
			and int(dec["toward"]) == AiDecision.Toward.ENEMY \
			and obj_dist <= rush + OBJECTIVE_CONTROL_IN \
			and _nearest_model_gap_to_in(unit, obj_pos) > OBJECTIVE_CONTROL_IN \
			and not (bool(ctx["enemy_in_charge"]) \
				and MoveIntent.distance_inches(tcentre, obj_pos) <= OBJECTIVE_CONTROL_IN + CONTACT_IN):
		action = AiDecision.Action.RUSH
		do_shoot = false
		if obj_dist <= advance + OBJECTIVE_CONTROL_IN and bool(ctx["shoot_after_advance"]):
			action = AiDecision.Action.ADVANCE   # the marker is close enough to seize AND still shoot
			do_shoot = true
		dec["toward"] = AiDecision.Toward.OBJECTIVE
		action_why = "final-round urgency: seize range beats a marginal fight"
		record_decision({"kind": "urgency", "unit": unit.get_name(),
			"rule": "Final round: only held markers score — a reachable uncontrolled marker outranks a fight that cannot pay off later",
			"candidates": [], "chosen": AiDecision.action_name(action) + " toward objective",
			"why": "final-round urgency",
			"data": {"round": _current_round(), "obj_dist_in": obj_dist, "rush_in": rush}})
	# Relentless / Indirect overlay (Solo & Co-Op AI overlays; Indirect is wave 5): a Relentless or
	# Indirect ranged weapon with an enemy in range → Hold and shoot. The record names the trigger.
	var hold_rule := hold_and_shoot_rule(weapons, shoot_range > 0 and enemy_dist <= float(shoot_range))
	if not hold_rule.is_empty():
		action = AiDecision.Action.HOLD
		do_shoot = true
		action_why = "%s hold-and-shoot overlay" % hold_rule
	# Immobile / Artillery (GF/AoF v3.5.1 p.13): "may only use Hold actions" — the tree's move is overridden
	# to HOLD unconditionally; the unit still shoots when a target is in range (Artillery solo overlay p.57:
	# "If they are in range of enemies, they always use Hold and shoot"; can_shoot re-gates on range + LOS).
	if forces_hold(unit.get_special_rules()):
		action = AiDecision.Action.HOLD
		do_shoot = shoot_range > 0
		action_why = "Immobile/Artillery hold-only"
	# STAGE 1 POSITION SOLVER (AI plausibility): the dedicated joint move×target position pipeline replaces
	# the naive single-destination pick for GRADED games (arena + graded human-vs-AI). It generalises the
	# Wave-1 flank/anchor/yield single-hooks to EVERY archetype and BOTH channels (enemy + objective); when
	# it overrides the plan the Wave-1 single-hooks below are skipped (their behaviour is subsumed). The
	# default null-AI path and the SoloSim oracle never enter it (byte-identical). Charges/holds untouched.
	var solver_goal := NO_OBJECTIVE
	var solver_used := false
	if (action == AiDecision.Action.RUSH or action == AiDecision.Action.ADVANCE) and _position_solver_active():
		var sol := _solve_position(unit, target_unit, weapons, archetype, advance, rush, obj_pos, has_obj, int(dec["toward"]), do_shoot)
		if bool(sol.get("used", false)):
			solver_used = true
			action = int(sol["action"])
			do_shoot = bool(sol["shoot"])
			dec["toward"] = int(sol["toward"])
			action_why = str(sol["why"])
			var new_target := sol.get("target", target_unit) as GameUnit
			if new_target != null and new_target != target_unit:
				target_unit = new_target
				report["target"] = target_unit
				tcentre = unit_centre(target_unit)
				enemy_dist = MoveIntent.distance_inches(centre, tcentre)
			solver_goal = sol["goal"]
	# FAST-UNIT FLANKING DOCTRINE (AI plausibility wave 1): a fast ranged unit that would walk toward an
	# enemy it can't shoot THIS activation (out of range, or range without line of sight) instead heads
	# for a FLANK firing anchor — a stand-off point on the target's flank with range + LOS. Reachable
	# with an Advance → advance there and SHOOT; further → rush the approach lane (the deferred shot).
	# Placement of a legal move is officially the player's open choice, so this is pure doctrine — the
	# hold overlays below keep their precedence, charges and objective moves are untouched. Skipped when
	# the general position solver already chose a position (it subsumes this single-hook).
	var flank_goal := NO_OBJECTIVE
	if not solver_used and (action == AiDecision.Action.RUSH or action == AiDecision.Action.ADVANCE) \
			and int(dec["toward"]) == AiDecision.Toward.ENEMY and not bool(ctx["enemy_in_charge"]) \
			and shoot_range > 0 and (advance >= FLANK_MIN_ADVANCE_IN or unit.has_special_rule("Fast")) \
			and (enemy_dist > float(shoot_range) or not _has_los(unit, target_unit)):
		var fl := _flank_goal(unit, target_unit, float(shoot_range), advance)
		if bool(fl.get("found", false)):
			flank_goal = fl["goal"] as Vector3
			if bool(fl.get("within_advance", false)):
				action = AiDecision.Action.ADVANCE
				do_shoot = true
				action_why = "flank: firing position with range and line of sight"
			else:
				action = AiDecision.Action.RUSH
				do_shoot = false
				action_why = "flank: approach run toward a firing lane"
			record_decision({"kind": "flank", "unit": unit.get_name(),
				"rule": "Fast-unit doctrine: move placement is the player's choice — a flank anchor with range+LOS beats walking blind at the target",
				"candidates": [], "chosen": AiDecision.action_name(action) + " to flank",
				"why": ("reaches firing position" if bool(fl.get("within_advance", false)) else "approach toward firing lane"),
				"data": {"angle_deg": float(fl.get("angle_deg", 0.0)), "anchor_dist_in": float(fl.get("dist_in", 0.0)),
					"ring_in": float(fl.get("ring_in", 0.0)), "ev": float(fl.get("ev", 0.0))}})
	var action_data := {"arch": archetype, "role": archetype_role_label(archetype),
		"objective": bool(ctx["objective"]), "in_way": bool(ctx["in_way"]),
		"enemy_in_charge": bool(ctx["enemy_in_charge"]), "shoot_after_advance": bool(ctx["shoot_after_advance"]),
		"enemy_dist_in": enemy_dist, "charge_gap_in": charge_gap, "obj_dist_in": obj_dist,
		"toward_objective": int(dec["toward"]) == AiDecision.Toward.OBJECTIVE}
	if musician_in > 0.0:
		# Dev-mode visibility (wave 5): the Musician bonus changed this unit's move reach.
		action_data["musician_bonus_in"] = musician_in
	record_decision({"kind": "action", "unit": unit.get_name(),
		"rule": "Solo v3.5.0 decision tree (archetype branch; EV fills the p.1 'better than')",
		"candidates": [], "chosen": AiDecision.action_name(action), "why": action_why, "data": action_data})
	report["action"] = action
	report["shoot"] = do_shoot
	report["toward"] = int(dec["toward"])
	var to_obj: bool = int(dec["toward"]) == AiDecision.Toward.OBJECTIVE and has_obj
	report["to_objective"] = to_obj   # main narrates "→ objective" instead of the enemy name (finding 1 label)
	# The general position solver (when it fired) already chose a filtered, dual-channel-scored destination
	# that subsumes the flank anchor; otherwise fall back to the Wave-1 goal (objective / flank / enemy).
	var to_flank: bool = (solver_used or flank_goal != NO_OBJECTIVE) and not to_obj
	var goal: Vector3 = solver_goal if solver_used else (obj_pos if to_obj else (flank_goal if to_flank else tcentre))
	# OBJECTIVE FIRING ANCHOR (AI plausibility wave 1): an objective-bound SHOOTER whose tree promised a
	# shot (Advance toward marker + shoot) stops at a spot INSIDE the seize ring that keeps range + line
	# of sight to its target — the marker CENTRE is only a placement convention, and walking onto it
	# regularly broke the post-move shot (kriegsherr showcase: the bikers held markers but never fired).
	# Skipped when the general solver already placed the unit (its seize-ring candidates cover this).
	if not solver_used and to_obj and do_shoot and shoot_range > 0 and action == AiDecision.Action.ADVANCE:
		var fire_anchor := _objective_fire_anchor(unit, target_unit, goal, float(shoot_range))
		if fire_anchor != NO_OBJECTIVE:
			goal = fire_anchor
			record_decision({"kind": "flank", "unit": unit.get_name(),
				"rule": "Objective firing anchor: any spot within 3\" seizes — prefer one that keeps range and line of sight to the target",
				"candidates": [], "chosen": "seize-ring firing spot", "why": "keeps the promised shot while seizing",
				"data": {"anchor_dist_in": MoveIntent.distance_inches(centre, fire_anchor)}})
	# Coordination first slice (round 7, finding 6): a RUSH/ADVANCE mover that would PARK in a bigger,
	# not-yet-activated friendly shooter's line of fire side-steps to an equivalent position (equal
	# progress, small/cheap units defer). Charges are exempt (they must reach their target), and so is a
	# move that reaches seize range of its objective (holding the marker beats keeping a lane clear).
	# Skipped when the general solver already ran — its blocks_friend hard filter covers the same lane.
	if not solver_used and (action == AiDecision.Action.RUSH or action == AiDecision.Action.ADVANCE) \
			and not (to_obj and (bool(ctx["obj_in_rush"]) or bool(ctx["obj_in_advance"]))):
		var corridors := _friendly_fire_corridors(unit)
		if not corridors.is_empty():
			var band_m: float = (rush if action == AiDecision.Action.RUSH else advance) * INCHES_TO_METERS
			var clear_m: float = _deploy_footprint_radius(unit) + LANE_CLEAR_MARGIN_IN * INCHES_TO_METERS
			var offsets_m: Array = []
			for o in LANE_OFFSET_STEPS_IN:
				offsets_m.append(float(o) * INCHES_TO_METERS)
			var yg := yielded_goal_2d(Vector2(centre.x, centre.z), Vector2(goal.x, goal.z), band_m,
				corridors, clear_m, offsets_m, LANE_PROGRESS_TOL_IN * INCHES_TO_METERS)
			if bool(yg["yielded"]):
				var g2: Vector2 = yg["goal"]
				goal = Vector3(g2.x, goal.y, g2.y)
				record_decision({"kind": "yield_lof", "unit": unit.get_name(),
					"rule": "Coordination: don't end a move in a bigger friendly shooter's line of fire when an equivalent spot exists (small/cheap units defer)",
					"candidates": [], "chosen": "side-step %.1f\"" % (float(yg["offset"]) / INCHES_TO_METERS),
					"why": "clears %s's line of fire" % str(yg["friend"]),
					"data": {"friend": str(yg["friend"]),
						"offset_in": float(yg["offset"]) / INCHES_TO_METERS, "role": archetype_role_label(archetype)}})
	var goal_dist := MoveIntent.distance_inches(centre, goal)
	# Extras for the MOVE decision record (_execute_move merges + clears them): the plausibility metrics
	# need the acting context the executor doesn't know — how boxed-in by enemies the unit was, whether
	# the move was mission play, and whether the base counts as LARGE (big-model maneuver acceptance).
	_move_extra = {"enemy_gap_in": charge_gap, "to_objective": to_obj, "flank": to_flank,
		"large": _move_base_radius_m(_moving_models(unit)) >= LARGE_BASE_RADIUS_IN * INCHES_TO_METERS}
	var dang := 0
	match action:
		AiDecision.Action.RUSH:
			dang = _move_toward(unit, goal, (minf(rush, goal_dist) if (to_obj or to_flank) else rush), false)
		AiDecision.Action.CHARGE:
			# Close the REAL base-to-base gap to base contact, capped at the band (field-test finding 3): the
			# former "move toward the enemy centre, capped at rush" under-shot for wide/offset units and the
			# charge fell short within band. Charge is the one action exempt from steering easing.
			dang = _charge_move(unit, target_unit, rush)
		AiDecision.Action.ADVANCE:
			if to_obj or to_flank:
				dang = _move_toward(unit, goal, minf(advance, goal_dist), false)
			elif enemy_dist <= float(shoot_range):
				# "Advancing" (p.58): a shooter already in range steps BACK toward the range edge, still
				# shooting — held a measuring hair INSIDE range so the post-move gate never flips on floats.
				dang = _move_away(unit, tcentre,
					minf(advance, maxf(float(shoot_range) - enemy_dist - KITE_RANGE_MARGIN_IN, 0.0)))
			else:
				dang = _move_toward(unit, goal, advance, false)
		_:
			pass   # HOLD
	_move_extra = {}
	report["dangerous_models"] = dang
	# Instrument the objective outcome (field-test finding 1: the harness logged enemy distance but NEVER the
	# model-to-marker distance, so "did the AI actually contest?" was unmeasurable). Record the post-move gap
	# from the unit's NEAREST model to its NEAREST marker and whether it now sits in seize range (≤3", p.2).
	if objectives_provider.is_valid():
		var obj_gap_after := _nearest_objective_model_gap_in(unit)
		if obj_gap_after < INF:
			report["obj_gap_after_in"] = obj_gap_after
			record_decision({"kind": "seize_check", "unit": unit.get_name(),
				"rule": "Solo & Co-Op v3.5.0 p.2: a marker is held by non-Shaken models within 3\"",
				"candidates": [], "chosen": ("in seize range" if obj_gap_after <= OBJECTIVE_CONTROL_IN else "short of marker"),
				"why": ("toward objective" if to_obj else "toward enemy"),
				"data": {"obj_gap_after_in": obj_gap_after, "toward_objective": to_obj,
					"in_seize_range": obj_gap_after <= OBJECTIVE_CONTROL_IN}})
	# Shooting eligibility is measured AFTER the move; only actions the tree marked shoot=true actually
	# fire. Indirect (wave 5) may target enemies out of line of sight, so an Indirect ranged weapon
	# waives the LOS gate here (the volley's per-model sighting then counts range-only for it).
	var d2 := MoveIntent.distance_inches(unit_centre(unit), unit_centre(target_unit))
	report["dist_in"] = d2
	report["moved"] = action != AiDecision.Action.HOLD   # Indirect's -1 to hit fires when shooting after moving
	report["can_shoot"] = do_shoot and shoot_range > 0 and d2 <= float(shoot_range) \
		and (_has_los(unit, target_unit) or has_indirect_ranged(weapons))
	# Wave 6 — Caster(X): the official Solo v3.5.0 procedure casts AFTER moving, BEFORE attacking, so
	# the cast plan is drawn from the post-move geometry here; main resolves the cast rolls on the real
	# dice tray before the shooting/melee it already resolves (spells are ADDITIONAL to the attack).
	var casts := _plan_casts(unit)
	if not casts.is_empty():
		report["casts"] = casts
	return report


# ===== Aircraft activation (GF Advanced Rules v3.5.1 "Aircraft"; AI plausibility wave 1) =====

## One aircraft activation: the ONLY legal action is an Advance along a STRAIGHT line whose full length
## (the AI-section 30") must fit on the table — the aircraft may not use an edge to move less. It ignores
## every unit and all terrain while moving and stopping, can never seize or contest a marker, and shoots
## after the move like any advancing unit (targets get their range against IT reduced, not the reverse).
## The open choice — WHICH straight lane — is filled by the EV metric: the heading whose endpoint offers
## the best expected volley (a strafing run), with "stay away from the edges" as the no-shot fallback.
func _act_aircraft(unit: GameUnit, report: Dictionary) -> Dictionary:
	var weapons := _unit_weapons(unit)
	var move_in := aircraft_move_in(unit)
	var centre := unit_centre(unit)
	var pick := _aircraft_heading(unit, centre, move_in, weapons)
	var dir2: Vector2 = pick.get("dir", Vector2(0, 1))
	record_decision({"kind": "action", "unit": unit.get_name(),
		"rule": "GF v3.5.1 Aircraft: straight Advance-only, mandatory length, ignores units/terrain, no seizing, uncharged",
		"candidates": [], "chosen": "flies a strafing run",
		"why": str(pick.get("why", "best strafing lane")),
		"data": {"move_in": move_in, "heading_deg": rad_to_deg(dir2.angle()),
			"strafe_ev": float(pick.get("ev", 0.0)), "legal_headings": int(pick.get("legal", 0))}})
	_move_extra = {"aircraft": true, "large": true}
	_aircraft_move(unit, dir2, move_in)
	_move_extra = {}
	report["action"] = AiDecision.Action.ADVANCE
	report["aircraft"] = true   # main narrates "flies" and skips ground-move framing
	report["moved"] = true
	# Post-move targeting/shooting exactly like a ground advance: nearest valid target from the NEW
	# position; the aircraft's own shooting suffers no penalty (the -12" applies only AGAINST it).
	if unit.is_shaken:
		return report   # the mandatory move happened; a Shaken aircraft still spends the turn recovering
	var target_unit := nearest_human_unit(unit)
	if target_unit == null:
		return report
	report["target"] = target_unit
	var shoot_range := AiArchetype.max_range_inches(weapons) + shooting_range_bonus(unit)
	if is_aircraft(target_unit) and shoot_range > 0:
		shoot_range = maxi(shoot_range - int(target_range_penalty_in(target_unit)), 0)
	var d2 := MoveIntent.distance_inches(unit_centre(unit), unit_centre(target_unit))
	report["dist_in"] = d2
	report["shoot"] = shoot_range > 0
	report["can_shoot"] = shoot_range > 0 and d2 <= float(shoot_range) \
		and (_has_los(unit, target_unit) or has_indirect_ranged(weapons))
	var casts := _plan_casts(unit)
	if not casts.is_empty():
		report["casts"] = casts
	return report


## Pick the aircraft's straight lane: candidate headings toward every living enemy centre plus a fixed
## compass fan; a heading is LEGAL when the whole straight move keeps every model of the aircraft on the
## table (the rulebook forbids shortening the mandatory move into an edge). Among legal headings the best
## expected post-move volley wins; with no shot anywhere, the endpoint furthest from the edges (keeps
## every next-turn lane open). Returns {dir, ev, why, legal}.
func _aircraft_heading(unit: GameUnit, centre: Vector3, move_in: float, weapons: Array) -> Dictionary:
	var half := _table_half_extents()
	var own_r := _deploy_footprint_radius(unit)
	var move_m := move_in * INCHES_TO_METERS
	var candidates: Array = []   # Vector2 headings, enemy-directed first (deterministic order)
	var enemies: Array = []
	if army_manager != null:
		for h in army_manager.get_game_units_for_player(human_slot):
			var hu := h as GameUnit
			if hu == null or hu.is_destroyed() or unit_in_reserve(hu):
				continue
			if hu.has_method("is_attached") and hu.is_attached():
				continue
			enemies.append(hu)
			var to_enemy := Vector2(unit_centre(hu).x - centre.x, unit_centre(hu).z - centre.z)
			if to_enemy.length() > 0.001:
				candidates.append(to_enemy.normalized())
	for i in range(AIRCRAFT_HEADINGS):
		candidates.append(Vector2.from_angle(TAU * float(i) / float(AIRCRAFT_HEADINGS)))
	var us := AiEv.ctx_for(unit, false, 0)
	var profiles := AiEv.stamp_sergeant(filter_limited(unit, AiShooting.profiles_in_range(weapons, 0.0)), unit)
	var best_dir := Vector2.ZERO
	var best_ev := -1.0
	var best_margin := -INF
	var legal := 0
	for c in candidates:
		var dir := c as Vector2
		var endpoint := centre + Vector3(dir.x, 0.0, dir.y) * move_m
		# Legality: the FULL straight move stays on the table (endpoint in bounds ⇒ the whole straight
		# segment is, by convexity), measured to the base's bounding radius like every bounds clamp.
		var lim_x := half.x - BOUNDS_MARGIN_M - own_r
		var lim_z := half.y - BOUNDS_MARGIN_M - own_r
		if absf(endpoint.x) > lim_x or absf(endpoint.z) > lim_z:
			continue
		legal += 1
		var ev := 0.0
		for e in enemies:
			var them := AiEv.ctx_for(e as GameUnit, majority_in_cover(e as GameUnit), 0)
			var dist := MoveIntent.distance_inches(endpoint, unit_centre(e as GameUnit))
			var e_los: bool = not los_checker.is_valid() \
				or bool(los_checker.call(Vector3(endpoint.x, centre.y, endpoint.z), unit_centre(e as GameUnit)))
			if e_los:
				ev = maxf(ev, AiEv.shoot_ev(profiles, us, them, dist))
		var margin := minf(lim_x - absf(endpoint.x), lim_z - absf(endpoint.z))
		if ev > best_ev + 0.0001 or (absf(ev - best_ev) <= 0.0001 and margin > best_margin):
			best_ev = ev
			best_dir = dir
			best_margin = margin
	if best_dir == Vector2.ZERO:
		# Degenerate board (no legal full-length lane — impossible on a standard table): fly toward the
		# centre, the direction with the longest clear run; the bounds clamp keeps it on the table.
		best_dir = Vector2(-centre.x, -centre.z).normalized() if Vector2(centre.x, centre.z).length() > 0.001 else Vector2(0, 1)
		return {"dir": best_dir, "ev": 0.0, "why": "no legal full-length lane — inward fallback", "legal": 0}
	return {"dir": best_dir, "ev": maxf(best_ev, 0.0),
		"why": ("strafing run (best expected volley)" if best_ev > 0.0 else "no shot anywhere — keep lanes open"),
		"legal": legal}


## Execute the aircraft's straight move: every model shifts by the same delta — no planner, no spacing
## zones, no terrain gates, no dangerous tests (the rule ignores units and terrain while moving and
## stopping; only the actual model counts, bases block nothing). State is applied + broadcast like any
## AI move and the trails feed the same glide presentation.
func _aircraft_move(unit: GameUnit, dir: Vector2, move_in: float) -> void:
	var models := _moving_models(unit)
	var positions := _positions_of(models)
	if positions.is_empty():
		return
	var delta := Vector3(dir.x, 0.0, dir.y) * move_in * INCHES_TO_METERS
	# Defensive clamp only (the heading pick already guarantees the full length fits).
	delta = _clamp_delta_to_bounds(positions, delta)
	var new_positions: Array = []
	for p in positions:
		new_positions.append((p as Vector3) + delta)
	var trails: Array = []
	_fill_straight_trails(trails, positions, new_positions)
	_apply_model_positions(models, new_positions)
	last_move_budget_in = move_in
	last_flow_order = []
	var radii := _model_radius_map(models)
	last_move_paths = []
	for i in range(mini(models.size(), trails.size())):
		last_move_paths.append({"model": models[i], "path": trails[i],
			"radius_m": float(radii.get(models[i], SeparationChecker.DEFAULT_BASE_RADIUS_M))})
	var achieved_m := _achieved_m(positions, new_positions)
	var rec_data := {"band_in": move_in, "budget_in": move_in,
		"arc_in": achieved_m / INCHES_TO_METERS, "achieved_in": achieved_m / INCHES_TO_METERS,
		"dangerous_models": 0, "straight": true}
	for k in _move_extra:
		rec_data[k] = _move_extra[k]
	record_decision({"kind": "move", "unit": unit.get_name(),
		"rule": "GF v3.5.1 Aircraft: mandatory straight move, ignores all units and terrain while moving and stopping",
		"candidates": [], "chosen": "", "why": "aircraft lane", "data": rec_data})


## Final-round helpers (objective urgency): round data is injected by main (round_provider +
## game_rounds); without it the urgency never fires (sandbox play, headless tests).
func _current_round() -> int:
	return int(round_provider.call()) if round_provider.is_valid() else 0


func _is_final_round() -> bool:
	return game_rounds > 0 and _current_round() >= game_rounds


# === Commander layer (Stage 3, Part B) ==============================================================

## The commander's decision for `unit` this activation: classify a weighted ROLE, and for a DRIVEN
## close-and-fight role return a PERSISTENT target (kept across rounds) in place of the momentary nearest,
## so a melee/monster keeps closing on ONE enemy instead of flip-chasing. Records the order (every unit is
## assigned — Killzone: no structural idle). Returns `default_target` unchanged when no difficulty is
## configured (null-AI / SoloSim — byte-identical) or when the role is not driven at this grade's scope.
func _commander_apply(unit: GameUnit, default_target: GameUnit) -> GameUnit:
	var diff := active_difficulty()
	if diff == null:
		return default_target
	var role := _commander_role(unit)
	var scope := _commander_scope(diff)
	var is_big: bool = _move_base_radius_m(_moving_models(unit)) >= LARGE_BASE_RADIUS_IN * INCHES_TO_METERS
	# Driven = a close-combat role the commander steers with a standing target. FULL/BASIC drive every close
	# role; MINIMAL (rekrut) drives ONLY big monsters (the anti-idle floor) — small melee act locally, which
	# is rekrut's characteristic idle-prone weakness.
	var driven: bool = role == CmdRole.CLOSE_AND_FIGHT and (scope >= 1 or is_big)
	var chosen := default_target
	var why := "role assigned; acts on the local nearest target"
	if driven:
		chosen = _commander_persist_target(unit, default_target, diff)
		why = "standing close-and-fight order — keep closing on one enemy across rounds"
	var persisted: bool = driven and chosen != default_target
	commander_orders[unit.unit_id] = {"role": role, "target_id": (chosen.unit_id if chosen != null else ""),
		"round": _current_round(), "driven": driven}
	record_decision({"kind": "commander", "unit": unit.get_name(),
		"rule": "Commander (%s): weighted role for EVERY unit; melee/monster hold a standing close order (Killzone full-assignment)" % diff.grade_name,
		"candidates": [], "chosen": _cmd_role_name(role) + ((" → " + chosen.get_name()) if (driven and chosen != null) else ""),
		"why": why, "data": {"grade": diff.grade_name, "scope": scope, "role": _cmd_role_name(role),
			"driven": driven, "big_monster": is_big, "persisted": persisted}})
	return chosen if chosen != null else default_target


## Commander scope from the (previously dead) coordination knob: 2=FULL (kriegsherr/albtraum, coord ≥ 0.9),
## 1=BASIC (veteran, coord ≥ COORD_THRESHOLD), 0=MINIMAL (rekrut — only big monsters driven).
func _commander_scope(diff: SoloDifficulty) -> int:
	if diff.coordination >= COMMANDER_FULL_COORD:
		return 2
	if diff.coordination >= SoloDifficulty.COORD_THRESHOLD:
		return 1
	return 0


## Classify the unit's commander ROLE (research §3 role packages; Days-Gone pattern — a role slots onto the
## existing decision tree without rewriting it). Aircraft and casters are their own packages; a melee-only or
## MELEE-archetype unit closes-and-fights; a Fast ranged unit flanks; everything else holds the ranged line.
func _commander_role(unit: GameUnit) -> int:
	if is_aircraft(unit):
		return CmdRole.AIRCRAFT
	if _unit_has_caster(unit):
		return CmdRole.CASTER
	var weapons := _unit_weapons(unit)
	if AiShooting.profiles_in_range(weapons, 0.0).is_empty():
		return CmdRole.CLOSE_AND_FIGHT   # no ranged weapon at all → pure melee
	if AiEv.classify(weapons, AiEv.ctx_for(unit, false, 0)) == AiArchetype.Type.MELEE:
		return CmdRole.CLOSE_AND_FIGHT
	if unit.has_special_rule("Fast"):
		return CmdRole.FLANK
	return CmdRole.RANGED_LINE


## The persistent close-and-fight target: keep the SAME enemy the unit was closing on (Killzone continue-task)
## while it is alive and on the table, so the monster stops flip-chasing the momentary nearest. Two legal
## overrides: the standing target died / left the table, or a NEARER enemy is now in charge range while the
## standing one is not (a certain charge THIS turn is the strictly better plan).
func _commander_persist_target(unit: GameUnit, default_target: GameUnit, _diff: SoloDifficulty) -> GameUnit:
	var prev: Dictionary = commander_orders.get(unit.unit_id, {})
	var prev_id: String = str(prev.get("target_id", ""))
	if prev_id == "":
		return default_target   # first assignment: adopt the nearest as the standing target
	var pu := _unit_by_id(prev_id)
	if pu == null or pu.is_destroyed() or unit_in_reserve(pu) \
			or (pu.has_method("is_attached") and pu.is_attached()):
		return default_target   # standing target gone → re-adopt the nearest
	if default_target != null and default_target != pu:
		var rush: float = float(move_bands_for_unit(unit, movement_range).get("rush", 12))
		if nearest_melee_gap_in(unit, default_target) <= rush and nearest_melee_gap_in(unit, pu) > rush:
			return default_target   # a certain charge on a nearer enemy beats continuing to close on the far one
	return pu


## Whether ANY member of the unit (itself or an attached hero) is a Caster — the caster role package.
func _unit_has_caster(unit: GameUnit) -> bool:
	if RulesRegistry.unit_rule_active(unit, "Caster"):
		return true
	if unit.has_method("get_attached_heroes"):
		for h in unit.get_attached_heroes():
			if h != null and RulesRegistry.unit_rule_active(h, "Caster"):
				return true
	return false


## Look up a live GameUnit by its unit_id (any slot), or null — re-resolves a standing target each round.
func _unit_by_id(id: String) -> GameUnit:
	if army_manager == null or id == "":
		return null
	for g in army_manager.get_all_game_units():
		var gu := g as GameUnit
		if gu != null and gu.unit_id == id:
			return gu
	return null


func _cmd_role_name(role: int) -> String:
	return CMD_ROLE_NAMES[role] if role >= 0 and role < CMD_ROLE_NAMES.size() else "?"


## Nearest alive-model distance (inches) from `unit` to a world position.
func _nearest_model_gap_to_in(unit: GameUnit, pos: Vector3) -> float:
	var best := INF
	for p in alive_positions(unit):
		best = minf(best, MoveIntent.distance_inches(p as Vector3, pos))
	return best


## OBJECTIVE FIRING ANCHOR: a stop INSIDE the marker's seize ring (2" of 3" — a measuring margin) that
## keeps range + LOS to `target`. Candidates: the marker centre plus 8 ring bearings; each must be on
## the table, out of impassable rest terrain, clear of other units' spacing zones, within
## `range_in − KITE_RANGE_MARGIN_IN` of the target and sighted. The nearest-travel candidate wins
## (deterministic bearing order breaks ties). NO_OBJECTIVE when nothing qualifies (keep the centre).
func _objective_fire_anchor(unit: GameUnit, target: GameUnit, obj_pos: Vector3, range_in: float) -> Vector3:
	if target == null or range_in <= 0.0:
		return NO_OBJECTIVE
	var centre := unit_centre(unit)
	var tcentre := unit_centre(target)
	var own_r := _deploy_footprint_radius(unit)
	var zones := _spacing_zones_world(unit, own_r, null)
	var ring_m: float = (OBJECTIVE_CONTROL_IN - 1.0) * INCHES_TO_METERS   # 2" of the 3" seize bubble
	var candidates: Array = [obj_pos]
	for i in range(8):
		var ang := TAU * float(i) / 8.0
		candidates.append(obj_pos + Vector3(cos(ang), 0.0, sin(ang)) * ring_m)
	var best := NO_OBJECTIVE
	var best_travel := INF
	for c in candidates:
		var anchor := c as Vector3
		if _clamp_to_bounds(anchor).distance_to(anchor) > 0.0005:
			continue
		if _world_forbidden(anchor, own_r):
			continue
		var blocked := false
		var a2 := Vector2(anchor.x, anchor.z)
		for z in zones:
			if ((z as Dictionary)["c"] as Vector2).distance_to(a2) < float((z as Dictionary)["r"]):
				blocked = true
				break
		if blocked:
			continue
		if MoveIntent.distance_inches(anchor, tcentre) > range_in - KITE_RANGE_MARGIN_IN:
			continue
		if los_checker.is_valid() and not bool(los_checker.call(anchor, tcentre)):
			continue
		var travel := MoveIntent.distance_inches(centre, anchor)
		if travel < best_travel - 0.001:
			best_travel = travel
			best = anchor
	return best


## FLANK ANCHOR search (fast-unit doctrine): stand-off points on a ring just inside max weapon range
## around the target, at bearings fanned off the straight approach line — each must be ON the table,
## outside impassable rest terrain, clear of every other unit's spacing zone, and have line of sight to
## the target. Scored by the shared volley EV at ring distance, discounted when only reachable as an
## approach run, plus a small bonus per degree of flank offset (the doctrine's tie-break). Returns
## {found, goal, within_advance, angle_deg, dist_in, ring_in, ev} or {found: false}.
func _flank_goal(unit: GameUnit, target: GameUnit, range_in: float, advance_in: float) -> Dictionary:
	var none := {"found": false}
	if range_in <= 0.0 or target == null:
		return none
	var centre := unit_centre(unit)
	var tcentre := unit_centre(target)
	var approach := Vector2(centre.x - tcentre.x, centre.z - tcentre.z)   # target → us
	if approach.length() < 0.001:
		return none
	var profiles := AiEv.stamp_sergeant(filter_limited(unit, AiShooting.profiles_in_range(_unit_weapons(unit), 0.0)), unit)
	if profiles.is_empty():
		return none
	var ring_in: float = maxf(range_in - FLANK_RANGE_SLACK_IN, minf(range_in, 6.0))
	var us := AiEv.ctx_for(unit, false, 0)
	var them := AiEv.ctx_for(target, majority_in_cover(target), counter_models_of(target))
	var ring_ev := AiEv.shoot_ev(profiles, us, them, ring_in + target_range_penalty_in(target))
	if ring_ev <= 0.0:
		return none
	var base_ang := approach.angle()
	var own_r := _deploy_footprint_radius(unit)
	var zones := _spacing_zones_world(unit, own_r, null)
	var t2 := Vector2(tcentre.x, tcentre.z)
	var best := none
	var best_score := 0.0
	for mag in FLANK_ANGLES:
		var sides: Array = [1.0] if is_zero_approx(float(mag)) else [1.0, -1.0]
		for side in sides:
			var ang := base_ang + deg_to_rad(float(mag) * float(side))
			var p2 := t2 + Vector2.from_angle(ang) * (ring_in * INCHES_TO_METERS)
			var anchor := Vector3(p2.x, centre.y, p2.y)
			if _clamp_to_bounds(anchor).distance_to(anchor) > 0.0005:
				continue   # off the table
			if _world_forbidden(anchor, own_r):
				continue   # would rest in impassable terrain
			var blocked := false
			for z in zones:
				if ((z as Dictionary)["c"] as Vector2).distance_to(p2) < float((z as Dictionary)["r"]):
					blocked = true
					break
			if blocked:
				continue   # inside another unit's 1" spacing zone — not a legal rest spot
			if los_checker.is_valid() and not bool(los_checker.call(anchor, tcentre)):
				continue   # no line of sight from the anchor — pointless as a firing position
			var dist_to := MoveIntent.distance_inches(centre, anchor)
			var reach_now := dist_to <= advance_in
			var score := ring_ev * (1.0 if reach_now else 0.5) \
				+ ring_ev * FLANK_EV_BONUS_PER_90 * (float(mag) / 90.0)
			if score > best_score + 0.0001:
				best_score = score
				best = {"found": true, "goal": anchor, "within_advance": reach_now,
					"angle_deg": float(mag) * float(side), "dist_in": dist_to, "ring_in": ring_in, "ev": ring_ev}
	return best


# ===== AI plausibility stage 1 — the dedicated POSITION SOLVER adapter (AiPosition) =====

## Whether the joint move×target position pipeline is live for THIS activation: only when a difficulty is
## configured (arena / a graded human-vs-AI solo game) AND the geometry callables are wired. The default
## null-AI path and the SoloSim fairness oracle never enter here, so both stay byte-identical (§ the
## opts-pattern discipline). Headless unit tests without injected LOS also fall through untouched.
func _position_solver_active() -> bool:
	return active_difficulty() != null and (los_checker.is_valid() or unit_los_checker.is_valid())


## Difficulty → position-band width: the ev_noise knob finally gets a real surface (POSITION choice). A
## wide band at Rekrut (2nd/3rd-best firing spot allowed), narrowing to argmax at Kriegsherr/Albtraum.
func _position_band_frac(diff: SoloDifficulty) -> float:
	return diff.ev_noise if diff != null else 0.0


## Build the AiPosition params from live units and run the solver. Returns {} (no override) when the
## solver is inactive or finds nothing worth changing; otherwise the mapped result the caller applies:
## {used, action:int(AiDecision.Action), shoot:bool, toward:int(AiDecision.Toward), target:GameUnit,
##  goal:Vector3, why:String}. Pure of side effects apart from the one explainability record it emits.
func _solve_position(unit: GameUnit, primary_target: GameUnit, weapons: Array, archetype: int,
		advance: float, rush: float, obj_pos: Vector3, has_obj: bool, dec_toward: int, do_shoot: bool) -> Dictionary:
	var diff := active_difficulty()
	if diff == null or unit == null or primary_target == null:
		return {}
	var centre := unit_centre(unit)
	var yy := centre.y
	var in_per_m := 1.0 / INCHES_TO_METERS
	var own_pid: int = int(unit.unit_properties.get("player_id", 0))
	var to_obj: bool = dec_toward == AiDecision.Toward.OBJECTIVE and has_obj
	var is_shooter: bool = (archetype == AiArchetype.Type.SHOOTING or archetype == AiArchetype.Type.HYBRID) \
		and not AiShooting.profiles_in_range(weapons, 0.0).is_empty()

	# Attacker channel: OUR ranged volley (Sergeant-stamped, expended-Limited filtered) + context.
	var our_profiles: Array = AiEv.stamp_sergeant(filter_limited(unit, AiShooting.profiles_in_range(weapons, 0.0)), unit)
	var our_ctx: Dictionary = AiEv.ctx_for(unit, false, 0)
	var base_range_in: float = float(AiArchetype.max_range_inches(weapons)) + shooting_range_bonus(unit)

	# Target + threat lists — every LIVE enemy of THIS unit's side (side-agnostic: both-AI arena defenders
	# target their own enemies). Aircraft are unshootable-for-free targets but valid firing targets.
	var targets: Array = []
	var threats: Array = []
	if army_manager != null:
		for g in army_manager.get_all_game_units():
			var gu := g as GameUnit
			if gu == null or gu.is_destroyed() or unit_in_reserve(gu):
				continue
			if int(gu.unit_properties.get("player_id", 0)) == own_pid:
				continue
			if gu.has_method("is_attached") and gu.is_attached():
				continue
			var gc := unit_centre(gu)
			var g2 := Vector2(gc.x, gc.z)
			var pen: float = target_range_penalty_in(gu) if is_aircraft(gu) else 0.0
			targets.append({"centre": g2,
				"def_ctx": AiEv.ctx_for(gu, majority_in_cover(gu), counter_models_of(gu)),
				"range_penalty_in": pen})
			threats.append({"centre": g2, "range_in": float(AiArchetype.max_range_inches(_unit_weapons(gu)))})
	if is_shooter and targets.is_empty():
		return {}

	# Legality + geometry closures (capture the acting unit's footprint + the live spacing zones once).
	var own_r := _deploy_footprint_radius(unit)
	var zones := _spacing_zones_world(unit, own_r, null)
	# The coarse centre-to-centre terrain LOS is the hypothetical-spot gate (per-model LOS needs real units
	# placed at the candidate — the same gate Wave-1's flank/anchor already validate candidates with).
	var los_at := func(a: Vector2, b: Vector2) -> bool:
		if los_checker.is_valid():
			return bool(los_checker.call(Vector3(a.x, yy, a.y), Vector3(b.x, yy, b.y)))
		return true
	var cover_at := func(pt: Vector2) -> bool:
		if not terrain_type_at.is_valid():
			return false
		return TerrainRules.gives_cover(int(terrain_type_at.call(Vector3(pt.x, yy, pt.y))))
	var legal_at := func(pt: Vector2) -> bool:
		var w := Vector3(pt.x, yy, pt.y)
		if _clamp_to_bounds(w).distance_to(w) > 0.0005:
			return false
		if _world_forbidden(w, own_r):
			return false
		for z in zones:
			if ((z as Dictionary)["c"] as Vector2).distance_to(pt) < float((z as Dictionary)["r"]):
				return false
		return true
	# Friendly firing lanes to yield (Wave-1 coordination, extended to the whole candidate set).
	var corridors := _friendly_fire_corridors(unit)
	var lane_clear_m: float = _deploy_footprint_radius(unit) + LANE_CLEAR_MARGIN_IN * INCHES_TO_METERS
	var blocks_friend := func(pt: Vector2) -> bool:
		for c in corridors:
			var cd := c as Dictionary
			if MovementPlanner.point_seg_distance(pt, cd["a"], cd["b"]) < lane_clear_m:
				return true
		return false

	var naive_goal := obj_pos if to_obj else unit_centre(primary_target)
	var params := {
		"from": Vector2(centre.x, centre.z),
		"toward": Vector2(naive_goal.x, naive_goal.z),
		"advance_m": advance * INCHES_TO_METERS,
		"rush_m": rush * INCHES_TO_METERS,
		"our_profiles": our_profiles, "our_ctx": our_ctx, "shoot_range_in": base_range_in,
		"targets": targets, "threats": threats, "in_per_m": in_per_m, "is_shooter": is_shooter,
		"objective": ({"pos": Vector2(obj_pos.x, obj_pos.z),
			"seize_ring_m": OBJECTIVE_CONTROL_IN * INCHES_TO_METERS,
			"to_objective": to_obj, "final_round": _is_final_round()} if has_obj else {}),
		"los": los_at, "cover_at": cover_at, "legal_at": legal_at, "blocks_friend": blocks_friend,
		"band_frac_pick": _position_band_frac(diff),
		# A distinct seed part (7331) decorrelates the POSITION band draw from the target-tie draw, which
		# also runs noisy_pick on the same activation seed — same reproducibility, independent deviations.
		"pick": func(n: int) -> int: return diff.noisy_pick(n, _knob_seed_parts(unit) + [7331]),
	}
	var sol := AiPosition.solve(params)
	if not bool(sol.get("used", false)):
		return {}

	var ti: int = int(sol.get("target_index", -1))
	var chosen_target: GameUnit = primary_target
	if ti >= 0 and ti < targets.size() and army_manager != null:
		# Map the winning target descriptor back to its GameUnit (re-walk in the same order it was built).
		chosen_target = _enemy_by_centre(unit, (targets[ti] as Dictionary)["centre"])
		if chosen_target == null:
			chosen_target = primary_target
	var goal2: Vector2 = sol["goal"]
	var goal := Vector3(goal2.x, yy, goal2.y)
	var act: int = AiDecision.Action.ADVANCE if str(sol["action"]) == "advance" else AiDecision.Action.RUSH
	var toward: int = AiDecision.Toward.OBJECTIVE if str(sol["toward"]) == "objective" else AiDecision.Toward.ENEMY
	record_decision({"kind": "position", "unit": unit.get_name(),
		"rule": "Stage 1 position solver: joint move×target enumeration → hard filters (LOS/range/cover/lane) → dual-channel (EV + location veto) → argmax within the %s band" % diff.grade_name,
		"candidates": [], "chosen": AiDecision.action_name(act) + (" and shoots" if bool(sol["shoot"]) else ""),
		"why": str(sol.get("why", "")),
		"data": {"considered": int(sol.get("considered", 0)), "shooters": int(sol.get("shooters", 0)),
			"filtered": sol.get("filtered", {}), "chosen_ev": float(sol.get("chosen_ev", 0.0)),
			"chosen_loc": float(sol.get("chosen_loc", 0.0)), "deviation": int(sol.get("deviation", 0)),
			"grade": diff.grade_name}})
	return {"used": true, "action": act, "shoot": bool(sol["shoot"]), "toward": toward,
		"target": chosen_target, "goal": goal, "why": str(sol.get("why", ""))}


## Map a target descriptor's world-plane centre back to its live GameUnit (nearest enemy centre match). The
## descriptor list is built from live units in one pass, so an exact-centre match recovers the unit.
func _enemy_by_centre(unit: GameUnit, centre2: Vector2) -> GameUnit:
	if army_manager == null:
		return null
	var own_pid: int = int(unit.unit_properties.get("player_id", 0))
	var best: GameUnit = null
	var best_d := INF
	for g in army_manager.get_all_game_units():
		var gu := g as GameUnit
		if gu == null or gu.is_destroyed() or unit_in_reserve(gu):
			continue
		if int(gu.unit_properties.get("player_id", 0)) == own_pid:
			continue
		if gu.has_method("is_attached") and gu.is_attached():
			continue
		var gc := unit_centre(gu)
		var d := Vector2(gc.x, gc.z).distance_to(centre2)
		if d < best_d:
			best_d = d
			best = gu
	return best


# ===== Wave 6 — the Caster(X) cast phase (official Solo & Co-Op v3.5.0 "Caster" procedure) =====

## Whether the OTHER side's interference tokens are auto-planned (native both-AI mode: the defending
## AI decides + spends deterministically at plan time — no dialogs). In human-vs-AI games this stays
## false and main.gd offers the human a resist prompt at resolution time instead.
var auto_interference: bool = false

## Plan the activation's casts for every Caster member of `unit` (the unit itself + attached heroes
## — each is its own caster with its own tokens and D3+X pick). Follows the official procedure
## verbatim: one selection cycle per caster, first valid spell or nothing; the EV metric fills ONLY
## the officially-open choices (which target, boost/interference tokens). Spell tokens are SPENT here
## (the official cost is paid on the ATTEMPT, before rolling); main rolls the 4+ cast die on the real
## tray and applies the effect. Every decision is recorded (kind "cast" / "cast_skip").
func _plan_casts(unit: GameUnit) -> Array:
	var casts: Array = []
	if army_manager == null:
		return casts
	var members: Array = [unit]
	if unit.has_method("get_attached_heroes"):
		members = members + unit.get_attached_heroes()
	for m in members:
		var member := m as GameUnit
		if member == null or member.get_alive_count() == 0 or not member.is_caster():
			continue
		if not RulesRegistry.unit_rule_active(member, "Caster"):
			continue   # system-scoped gate: the rule only fires where the book fields it
		var plan := _plan_member_cast(unit, member)
		if not plan.is_empty():
			casts.append(plan)
	return casts


## The one cast attempt of a single caster member: D3+X over the faction's BOOK-ORDERED spell list,
## cycle to the first valid spell (official); target + token economy filled by EV. Returns {} when
## the caster holds (no valid spell / no spell data), with the decision recorded either way.
func _plan_member_cast(unit: GameUnit, member: GameUnit) -> Dictionary:
	var tokens: int = member.casts_current
	if tokens <= 0:
		return {}
	var spells := SpellsRegistry.spells_for_unit(member)
	if spells.is_empty():
		# No committed spell data for this (system, faction): casting stays fully manual (the honest
		# pre-wave-6 behaviour) — recorded once per activation so the gap is visible in dev mode.
		record_decision({"kind": "cast_skip", "unit": member.get_name(),
			"rule": "Solo v3.5.0 'Caster' — no spell data for this faction/system; casting stays manual",
			"candidates": [], "chosen": "hold tokens", "why": "no spell map",
			"data": {"tokens": tokens, "system": RulesRegistry.system_of_unit(member),
				"faction": RulesRegistry.faction_of_unit(member)}})
		return {}
	var caster_x: int = member.get_caster_value()
	var d3: int = _rng.randi_range(1, 3)
	var order: Array = AiSpell.official_pick_order(spells.size(), d3, caster_x)
	var diff := active_difficulty()
	# Difficulty ladder (design table): Rekrut/default follow the official D3+X die exactly; Veteran
	# cycles past valid-but-worthless (0-EV) spells; Kriegsherr/Albtraum replace the die with the
	# EV-best castable spell (the same die-replacement licence as the targeting tie-break).
	var skip_zero_ev: bool = diff != null and diff.rule_exploitation > 0.0 and not diff.exploits_rules()
	var ev_best_pick: bool = diff != null and diff.exploits_rules()
	var candidates_rec: Array = []
	var chosen: Dictionary = {}
	var chosen_targets: Array = []
	var chosen_ev := 0.0
	var fallback: Dictionary = {}      # first officially-valid spell (kept when better filters find nothing)
	var fallback_targets: Array = []
	var fallback_ev := 0.0
	for idx in order:
		var entry: Dictionary = spells[idx]
		var threshold := int(entry.get("threshold", 0))
		var status := str(entry.get("status", "unmodeled"))
		var valid := true
		var why := ""
		var targets: Array = []
		var ev := 0.0
		if status == "unmodeled":
			valid = false
			why = "unmodeled"
		elif threshold > tokens:
			valid = false
			why = "not enough tokens"
		else:
			targets = _spell_targets(unit, member, entry)
			if targets.is_empty():
				valid = false
				why = "no valid target"
			else:
				ev = _targets_ev(targets)
		candidates_rec.append({"name": str(entry.get("name", "?")), "ev": ev,
			"key": [threshold, valid, why]})
		if not valid:
			continue
		if fallback.is_empty():
			fallback = entry
			fallback_targets = targets
			fallback_ev = ev
			if not skip_zero_ev and not ev_best_pick:
				break   # official: the FIRST valid spell in cycle order is cast
		if skip_zero_ev and ev > 0.0 and chosen.is_empty():
			chosen = entry
			chosen_targets = targets
			chosen_ev = ev
			break   # Veteran: first valid spell with a real payoff
		if ev_best_pick and ev > chosen_ev:
			chosen = entry
			chosen_targets = targets
			chosen_ev = ev
	if chosen.is_empty():
		chosen = fallback
		chosen_targets = fallback_targets
		chosen_ev = fallback_ev
	if chosen.is_empty():
		record_decision({"kind": "cast_skip", "unit": member.get_name(),
			"rule": "Solo v3.5.0 'Caster': D3+X pick, cycle-to-valid — no valid spell, don't cast",
			"candidates": candidates_rec, "chosen": "hold tokens", "why": "no castable spell",
			"data": {"d3": d3, "caster_x": caster_x, "tokens": tokens}})
		return {}
	# — Token economy (officially open — the EV heuristics fill it): boost from OTHER friendly casters
	#   within 18" LoS (+1 each), gated by the difficulty's spend_boosts (default sharp AI spends). —
	var threshold := int(chosen.get("threshold", 0))
	var base_target := int(RulesRegistry.unit_param(member, "Caster", "cast_target", AiSpell.CAST_BASE_TARGET))
	var boost := 0
	var boost_sources: Array = []
	var spend_boosts: bool = diff == null or diff.spend_boosts()
	var helpers := _aura_casters(ai_slot, unit, member)
	if spend_boosts and not helpers.is_empty():
		var pool := 0
		for h in helpers:
			pool += int((h as Dictionary)["tokens"])
		boost = AiSpell.plan_boost(chosen_ev, pool)
		boost_sources = _draw_aura_tokens(helpers, boost)
	# — Interference (the enemy's officially-open counter-choice): auto-planned ONLY in both-AI mode
	#   (the defending AI spends deterministically); in human-vs-AI main prompts the human instead. —
	var interference := 0
	var interference_sources: Array = []
	var enemy_helpers := _aura_casters(human_slot, unit, null)
	if auto_interference and not enemy_helpers.is_empty():
		var ediff: SoloDifficulty = difficulty_by_slot.get(human_slot)
		if ediff == null or ediff.spend_boosts():
			var epool := 0
			for h in enemy_helpers:
				epool += int((h as Dictionary)["tokens"])
			interference = AiSpell.plan_interference(chosen_ev, epool, boost)
			interference_sources = _draw_aura_tokens(enemy_helpers, interference)
	# — SPEND (the attempt's cost is paid before the roll — v3.5.1; one try per spell): the caster's
	#   threshold, the helpers' boost tokens, the enemy's interference tokens. —
	var tokens_before := member.casts_current
	member.spend_caster_points(threshold)
	_broadcast_casts(member)
	for src in boost_sources + interference_sources:
		var su := (src as Dictionary)["unit"] as GameUnit
		su.spend_caster_points(int((src as Dictionary)["tokens"]))
		_broadcast_casts(su)
	var p_cast := AiSpell.cast_success_chance(boost, interference, base_target)
	var target_names: Array = []
	for t in chosen_targets:
		target_names.append(((t as Dictionary)["unit"] as GameUnit).get_name())
	record_decision({"kind": "cast", "unit": member.get_name(),
		"rule": "Solo v3.5.0 'Caster' (D3+X, cycle-to-valid) + Caster(X) v3.5.1 (4+, boost/interference 18\" LoS)",
		"candidates": candidates_rec, "chosen": str(chosen.get("name", "?")),
		"why": ("ev-best pick" if ev_best_pick else ("skip 0-EV" if skip_zero_ev and chosen_ev > 0.0 else "official D3+X cycle")),
		"data": {"d3": d3, "caster_x": caster_x, "targets": ", ".join(PackedStringArray(target_names)),
			"ev": chosen_ev, "boost": boost, "interference": interference, "p_cast": p_cast,
			"tokens_before": tokens_before, "tokens_after": member.casts_current}})
	var target_units: Array = []
	for t in chosen_targets:
		target_units.append((t as Dictionary)["unit"])
	return {"caster": member, "caster_unit": unit, "spell": chosen,
		"name": str(chosen.get("name", "?")), "threshold": threshold,
		"targets": target_units, "ev": chosen_ev, "boost": boost, "interference": interference,
		"target_num": AiSpell.cast_target(boost, interference, base_target), "base_target": base_target,
		"interference_open": not auto_interference and not enemy_helpers.is_empty(),
		"tokens_before": tokens_before, "tokens_after": member.casts_current}


## The legal targets of one spell for this caster, EV-ranked best-first: side/count/range from the
## committed entry, distances from the CASTER UNIT's centre (the spell projects from the unit), line
## of sight through the same seam the shoot decision uses (v3.5.1: "a target in line of sight").
## Returns up to target.count entries {unit, ev} (multi-target spells hit the N best). The EV per
## kind fills the officially-open target choice: damage → P2 expected wounds; buff → P3 delta on the
## candidate's own attack; debuff → P3 delta for our attacks against it (or the reduction of ITS
## attack when the penalty lands on the target itself); "castable"-status spells value 0 (still
## legally castable — the official procedure needs only a valid target, not a payoff).
func _spell_targets(unit: GameUnit, member: GameUnit, entry: Dictionary) -> Array:
	var target_spec: Dictionary = entry.get("target", {})
	var side := str(target_spec.get("side", "enemy"))
	var count := maxi(int(target_spec.get("count", 1)), 1)
	var range_in := float(entry.get("range_in", 0))
	var pool_slot: int = ai_slot if side == "friendly" else human_slot
	var from := unit_centre(unit)
	var cands: Array = []
	for c in army_manager.get_game_units_for_player(pool_slot):
		var cu := c as GameUnit
		if cu == null or cu.is_destroyed() or unit_in_reserve(cu):
			continue
		if cu.has_method("is_attached") and cu.is_attached():
			continue   # a joined hero is part of its host unit — the unit is the target
		if MoveIntent.distance_inches(from, unit_centre(cu)) > range_in:
			continue
		if cu != unit and not _has_los(unit, cu):
			continue   # LoS from the caster's unit (own unit is trivially in sight)
		cands.append({"unit": cu, "ev": _spell_ev_for(unit, member, entry, cu)})
	if cands.is_empty():
		return []
	cands.sort_custom(func(a, b) -> bool:
		return float((a as Dictionary)["ev"]) > float((b as Dictionary)["ev"]))
	return cands.slice(0, count)


## The EV of one spell against/for ONE candidate unit (the metric that ranks the open target choice).
func _spell_ev_for(unit: GameUnit, _member: GameUnit, entry: Dictionary, cand: GameUnit) -> float:
	var effect: Dictionary = entry.get("effect", {})
	var kind := str(effect.get("kind", ""))
	if str(entry.get("status", "")) != "modeled":
		return 0.0
	if kind == "damage":
		var facets := AiSpell.spell_facets(effect.get("weapon_rules", []))
		var def_ctx := AiEv.ctx_for(cand, false, 0)   # cover irrelevant: spells ignore Cover AND Shielded
		if str((entry.get("target", {}) as Dictionary).get("kind", "unit")) == "model":
			def_ctx["models"] = 1   # "resolved as if the target was a unit of [1]" — no Blast fan-out
		return AiSpell.spell_damage_ev(int(effect.get("hits", 0)), def_ctx, facets)
	if kind == "buff":
		# Buff value = expected delta on the buffed unit's OWN next attack (design §4): the better of
		# its shooting (at its current enemy gap) and its melee swing.
		return _modifier_value_on_attack(cand, effect, false)
	if kind == "debuff":
		if str(effect.get("beneficiary", "")) == "attackers":
			# Our attackers gain the effect against the target: proxy = the ACTIVATING unit's own
			# attack into that target (the nearest attacker the AI controls this activation).
			return _modifier_delta(unit, cand, effect)
		# The penalty lands on the target's own attacks: value = how much WORSE its attack gets.
		return -_modifier_value_on_attack(cand, effect, true)
	return 0.0


## P3 wrapper: the EV delta `effect` causes on `attacker`'s attack into `defender` (shooting at the
## current gap when it has ranged reach, else its melee swing).
func _modifier_delta(attacker: GameUnit, defender: GameUnit, effect: Dictionary) -> float:
	var weapons := _unit_weapons(attacker)
	var att := AiEv.ctx_for(attacker, false, 0)
	var def_ctx := AiEv.ctx_for(defender, majority_in_cover(defender), 0)
	var dist := MoveIntent.distance_inches(unit_centre(attacker), unit_centre(defender))
	var ranged := AiEv.stamp_sergeant(filter_limited(attacker, AiShooting.profiles_in_range(weapons, dist)), attacker)
	if not ranged.is_empty():
		return AiSpell.spell_modifier_delta(ranged, att, def_ctx, effect, true, dist, false)
	var melee := AiEv.stamp_sergeant(filter_limited(attacker, AiShooting.melee_profiles(weapons)), attacker)
	return AiSpell.spell_modifier_delta(melee, att, def_ctx, effect, false, 0.0, true)


## The value of a modifier/grant on `cand`'s OWN attack (vs its nearest enemy): max of the shooting
## delta (when in reach) and the melee delta. `flip_sides` evaluates the effect on an ENEMY unit's
## attack (debuffs on the target itself) — the enemy of that unit is then OUR side's nearest unit.
func _modifier_value_on_attack(cand: GameUnit, effect: Dictionary, flip_sides: bool) -> float:
	var enemy_slot: int = human_slot if not flip_sides else ai_slot
	var nearest: GameUnit = null
	var best := INF
	for e in army_manager.get_game_units_for_player(enemy_slot):
		var eu := e as GameUnit
		if eu == null or eu.is_destroyed() or unit_in_reserve(eu):
			continue
		if eu.has_method("is_attached") and eu.is_attached():
			continue
		var d := MoveIntent.distance_inches(unit_centre(cand), unit_centre(eu))
		if d < best:
			best = d
			nearest = eu
	if nearest == null:
		return 0.0
	var weapons := _unit_weapons(cand)
	var att := AiEv.ctx_for(cand, false, 0)
	var def_ctx := AiEv.ctx_for(nearest, majority_in_cover(nearest), 0)
	var ranged := AiEv.stamp_sergeant(filter_limited(cand, AiShooting.profiles_in_range(weapons, best)), cand)
	var shoot_delta := AiSpell.spell_modifier_delta(ranged, att, def_ctx, effect, true, best, false) \
		if not ranged.is_empty() else 0.0
	var melee := AiEv.stamp_sergeant(filter_limited(cand, AiShooting.melee_profiles(weapons)), cand)
	var melee_delta := AiSpell.spell_modifier_delta(melee, att, def_ctx, effect, false, 0.0, true) \
		if not melee.is_empty() else 0.0
	return maxf(shoot_delta, melee_delta)


## The caster units of `slot` holding spell tokens within the 18" boost/interference aura of
## `caster_unit`, in line of sight (v3.5.1: "Models within 18\" in line of sight of the caster's
## unit may spend any number of spell tokens"). `exclude` drops the casting member itself (the ±1
## comes from OTHER models). Returns [{unit, tokens}] nearest-first (a deterministic draw order).
func _aura_casters(slot: int, caster_unit: GameUnit, exclude: GameUnit) -> Array:
	var aura_in := float(RulesRegistry.unit_param(caster_unit, "Caster", "aura_in", AiSpell.AURA_RANGE_IN))
	var from := unit_centre(caster_unit)
	var out: Array = []
	for c in army_manager.get_game_units_for_player(slot):
		var cu := c as GameUnit
		if cu == null or cu.is_destroyed() or unit_in_reserve(cu):
			continue
		var members: Array = [cu]
		if cu.has_method("get_attached_heroes"):
			members = members + cu.get_attached_heroes()
		for m in members:
			var member := m as GameUnit
			if member == null or member == exclude or member.get_alive_count() == 0:
				continue
			if not member.is_caster() or member.casts_current <= 0:
				continue
			var d := MoveIntent.distance_inches(from, unit_centre(member if member.models.size() > 0 else cu))
			if d > aura_in:
				continue
			if cu != caster_unit and not _has_los(caster_unit, cu):
				continue
			out.append({"unit": member, "tokens": member.casts_current, "d": d})
	out.sort_custom(func(a, b) -> bool:
		return float((a as Dictionary)["d"]) < float((b as Dictionary)["d"]))
	return out


## Distribute a total token spend across the aura helpers nearest-first. Returns [{unit, tokens}]
## for the units that actually pay (deterministic; the caller spends them).
static func _draw_aura_tokens(helpers: Array, total: int) -> Array:
	var out: Array = []
	var left := total
	for h in helpers:
		if left <= 0:
			break
		var hd := h as Dictionary
		var take: int = mini(int(hd["tokens"]), left)
		if take > 0:
			out.append({"unit": hd["unit"], "tokens": take})
			left -= take
	return out


## Sum of the ranked targets' EVs (multi-target spells add up — each picked unit takes the effect).
static func _targets_ev(targets: Array) -> float:
	var total := 0.0
	for t in targets:
		total += float((t as Dictionary)["ev"])
	return total


## Broadcast a unit's token count to MP peers (the same seam the manual casts dialog uses).
func _broadcast_casts(member: GameUnit) -> void:
	if network_manager != null and network_manager.has_method("broadcast_unit_casts"):
		network_manager.broadcast_unit_casts(member)


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


## Winner consolidation (GF Advanced Rules v3.5.1 p.9: the enemy unit was destroyed in melee → the survivor
## "may move by up to 3”") — round 7, finding 4. A MAY, so the AI takes it when it helps: EV-aware goal =
## the nearest objective this side doesn't control (seize-range progress wins games), else the nearest
## living enemy (sets up the next charge/volley). No goal → the unit stays (the honest "may"). Slot-aware
## (reads the unit's OWN player_id), so the arena's defender consolidates toward ITS enemy, never its own
## side. Returns the Dangerous-crossing model count; last_move_paths carries the replay corridor.
func consolidate_after_melee_win(unit: GameUnit) -> int:
	if unit == null or unit.get_alive_count() <= 0:
		return 0
	# The consolidating unit may be the DEFENDER — the side the controller currently calls human_slot
	# (both-AI arena) — while the objective seam (_nearest_uncontrolled_objective) is ai/human oriented.
	# Flip the orientation to the unit's OWN side for the goal choice, restore after (non-destructive,
	# the same probe pattern as _solo_side_has_eligible).
	var prev_ai := ai_slot
	var prev_human := human_slot
	var own_pid: int = int(unit.unit_properties.get("player_id", ai_slot))
	if own_pid != ai_slot:
		ai_slot = own_pid
		human_slot = prev_ai
	var centre := unit_centre(unit)
	var goal := _nearest_uncontrolled_objective(centre, unit)
	var why := "toward objective"
	if goal == NO_OBJECTIVE:
		var enemy := _nearest_enemy_of(unit)
		if enemy == null:
			ai_slot = prev_ai
			human_slot = prev_human
			last_move_paths = []
			return 0
		goal = unit_centre(enemy)
		why = "toward next target"
	var dang := _move_toward(unit, goal, CONSOLIDATION_WIN_IN, false)
	ai_slot = prev_ai
	human_slot = prev_human
	record_decision({"kind": "consolidate", "unit": unit.get_name(),
		"rule": "GF v3.5.1 p.9 consolidation: enemy destroyed in melee — the survivor may move up to 3\"",
		"candidates": [], "chosen": why, "why": "melee winner consolidation",
		"data": {"band_in": CONSOLIDATION_WIN_IN}})
	return dang


# === AI coordination — friendly line-of-fire yielding (round 7, finding 6, FIRST SLICE) =============
# "Small units yield space to bigger ones": a cheap mover side-steps rather than PARKING in a bigger,
# not-yet-activated friendly shooter's line of fire — when an equally-good position exists. Deliberately
# narrow: end-position awareness only (the route itself may still cross a lane — models keep moving),
# nearest-enemy proxy for the friend's intended target, centre-line corridors. The wider role-aware
# coordination (screening, focus-fire lanes, terrain-anchored roles) is documented as future work in
# docs/SOLO_AI_RULES_COVERAGE.md.

const LANE_CLEAR_MARGIN_IN := 1.0            # clearance beyond the mover's footprint radius
const LANE_OFFSET_STEPS_IN: Array[float] = [2.0, 4.0]   # lateral side-step magnitudes tried, small first
const LANE_PROGRESS_TOL_IN := 1.0            # a side-step may cost at most this much goal progress
const LANE_TARGET_SLACK_IN := 2.0            # corridor counts while the friend's target is near its range


## PURE lane-yield decision (unit-agnostic: pass metres or inches consistently). `corridors` =
## [{a: Vector2, b: Vector2, friend: String}] — friendly shooter centre → its intended target centre.
## The mover's END anchor (centre advanced toward `goal`, capped at `band`) must keep `clear` distance
## from every corridor segment; when it doesn't, lateral offsets of the GOAL are tried (smallest first,
## +perp then -perp — deterministic) and the first candidate that clears every corridor while losing at
## most `progress_tol` of forward progress wins. Returns {goal, yielded, offset, friend}.
static func yielded_goal_2d(centre: Vector2, goal: Vector2, band: float, corridors: Array,
		clear: float, offsets: Array, progress_tol: float) -> Dictionary:
	var to_goal := goal - centre
	if to_goal.length() < 0.0001 or corridors.is_empty():
		return {"goal": goal, "yielded": false, "offset": 0.0, "friend": ""}
	var dirn := to_goal.normalized()
	var end := centre + dirn * minf(band, to_goal.length())
	var blocked_idx := _nearest_corridor(end, corridors)
	if blocked_idx < 0 or _corridor_distance(end, corridors[blocked_idx]) >= clear:
		return {"goal": goal, "yielded": false, "offset": 0.0, "friend": ""}
	var base_progress := (end - centre).dot(dirn)
	var perp := Vector2(-dirn.y, dirn.x)
	for mag in offsets:
		for side in [1.0, -1.0]:
			var g2: Vector2 = goal + perp * (float(mag) * side)
			var to2 := g2 - centre
			if to2.length() < 0.0001:
				continue
			var end2 := centre + to2.normalized() * minf(band, to2.length())
			var ok := true
			for c in corridors:
				if _corridor_distance(end2, c as Dictionary) < clear:
					ok = false
					break
			if not ok:
				continue
			if (end2 - centre).dot(dirn) < base_progress - progress_tol:
				continue   # the side-step gives up too much progress — not an "equivalent position"
			return {"goal": g2, "yielded": true, "offset": float(mag) * side,
				"friend": str((corridors[blocked_idx] as Dictionary).get("friend", ""))}
	return {"goal": goal, "yielded": false, "offset": 0.0, "friend": ""}


static func _corridor_distance(p: Vector2, corridor: Dictionary) -> float:
	return MovementPlanner.point_seg_distance(p, corridor.get("a", Vector2.ZERO), corridor.get("b", Vector2.ZERO))


static func _nearest_corridor(p: Vector2, corridors: Array) -> int:
	var best := -1
	var best_d := INF
	for i in range(corridors.size()):
		var d := _corridor_distance(p, corridors[i] as Dictionary)
		if d < best_d:
			best_d = d
			best = i
	return best


## The fire corridors this mover must respect (world XZ metres): one segment per friendly unit that
## (a) has NOT yet activated (its shot is still to come), (b) has ranged weapons with its nearest enemy
## around range, and (c) represents an EQUAL-OR-BIGGER investment than the mover (points; alive-model
## count when points are absent) — the "small/cheap units defer" rule. The friend's intended target is
## approximated by its nearest enemy (the official solo targeting default).
func _friendly_fire_corridors(mover: GameUnit) -> Array:
	var out: Array = []
	if army_manager == null or mover == null:
		return out
	var own_pid: int = int(mover.unit_properties.get("player_id", 0))
	var mover_weight: int = mover.get_cost() if mover.get_cost() > 0 else mover.get_alive_count()
	for g in army_manager.get_all_game_units():
		var gu := g as GameUnit
		if gu == null or gu == mover or gu.is_destroyed() or gu.is_shaken or unit_in_reserve(gu):
			continue
		if int(gu.unit_properties.get("player_id", 0)) != own_pid or gu.is_activated:
			continue
		if gu.has_method("is_attached") and gu.is_attached():
			continue
		var rng_in: int = AiArchetype.max_range_inches(_unit_weapons(gu))
		if rng_in <= 0:
			continue
		var friend_weight: int = gu.get_cost() if gu.get_cost() > 0 else gu.get_alive_count()
		if friend_weight < mover_weight:
			continue   # the mover outweighs this friend — the smaller unit defers, not us
		var target := _nearest_enemy_of(gu)
		if target == null:
			continue
		var fc := unit_centre(gu)
		var tc := unit_centre(target)
		if MoveIntent.distance_inches(fc, tc) > float(rng_in) + LANE_TARGET_SLACK_IN:
			continue   # its target is way out of range — no live lane to protect
		out.append({"a": Vector2(fc.x, fc.z), "b": Vector2(tc.x, tc.z), "friend": gu.get_name()})
	return out


## The nearest living enemy unit measured from `unit`'s OWN side (player_id), not from the controller's
## current ai/human orientation — consolidation runs for defenders too (both-AI arena), where the acting
## side and `unit`'s side differ. Reserve units are off-table; attached heroes are part of their host.
func _nearest_enemy_of(unit: GameUnit) -> GameUnit:
	if army_manager == null or unit == null:
		return null
	var own_pid: int = int(unit.unit_properties.get("player_id", 0))
	var from := unit_centre(unit)
	var best: GameUnit = null
	var best_d := INF
	for g in army_manager.get_all_game_units():
		var gu := g as GameUnit
		if gu == null or gu.is_destroyed() or unit_in_reserve(gu):
			continue
		if int(gu.unit_properties.get("player_id", 0)) == own_pid:
			continue
		if gu.has_method("is_attached") and gu.is_attached():
			continue
		var d := MoveIntent.distance_inches(from, unit_centre(gu))
		if d < best_d:
			best_d = d
			best = gu
	return best


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
	var own_r_m := _move_base_radius_m(models)   # base radius for the EDGE-AWARE destination-terrain tests (finding 6)
	# Pass 1: full band, going AROUND difficult terrain — unless the unit ignores it or its destination
	# lies inside difficult terrain (objective/charge into a forest — the p.57 overlay exceptions).
	var avoid: bool = not ignores_difficult and not _targets_in_difficult(positions, goal, reach, own_r_m)
	# DANGEROUS terrain is also routed AROUND when a clear path exists (field-test finding 4). Only Flying
	# ignores it (Strider ignores Difficult but NOT Dangerous — GF/AoF v3.5.1 p.13/p.14); if the destination
	# itself is dangerous, going around is impossible, so the model routes in and takes its dangerous test.
	var avoid_dangerous: bool = not flying and not _targets_in_dangerous(positions, goal, reach, own_r_m)
	var trails: Array = []
	var new_positions := _plan_move(unit, models, positions, goal, reach, allow_contact, avoid, avoid_dangerous, trails, charge_target)
	if not ignores_difficult and _trails_cross_difficult(trails):
		# The actual route enters difficult terrain → the 6" cap applies (p.11); re-plan through it so the
		# budget math and the drawn corridor agree. Dangerous is STILL routed around on this pass.
		reach = minf(inches, DIFFICULT_MOVE_CAP_IN)
		trails = []
		new_positions = _plan_move(unit, models, positions, goal, reach, allow_contact, false, avoid_dangerous, trails, charge_target)
	elif not allow_contact and (avoid or avoid_dangerous) \
			and _achieved_m(positions, new_positions) < reach * INCHES_TO_METERS * STALL_REPLAN_FRACTION:
		# STALL ESCALATION (round 7, finding 2): routing AROUND difficult/dangerous terrain hemmed the unit
		# in (avoided cells walling its start) and the whole move collapsed to a token step — the maintainer's
		# "half an inch toward something". Going THROUGH is always legal — difficult costs the 6" cap (p.11),
		# dangerous costs the tests (p.12) — and a unit that decided to advance must actually cover distance
		# unless genuinely blocked. Keep the through-plan only when it really gets further.
		var t2: Array = []
		var p2 := _plan_move(unit, models, positions, goal, reach, allow_contact, false, false, t2, charge_target)
		var r2 := reach
		if not ignores_difficult and _trails_cross_difficult(t2):
			r2 = minf(inches, DIFFICULT_MOVE_CAP_IN)
			t2 = []
			p2 = _plan_move(unit, models, positions, goal, r2, allow_contact, false, false, t2, charge_target)
		if _achieved_m(positions, p2) > _achieved_m(positions, new_positions) + 0.01:
			reach = r2
			new_positions = p2
			trails = t2
			avoid = false   # the move goes through — the decision record's label follows suit
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
	# HARD FINAL PLACEMENT GATE (field-test findings 3 + 6), applied HERE — AFTER the distance-truth trim — so
	# the trim can never cut a gate-corrected (coherency-shortened) endpoint off its trail (the trim runs on the
	# pre-gate route). Resolves impassable-terrain rest → base overlap → coherency to a bounded fixed point.
	# Skipped for a REGIMENT: its rigid tray slide preserves coherency + internal spacing by construction, and
	# the per-model overlap push would break the block (regiments plan as a rigid body, not individual models).
	var gate_shortened := false
	if not _is_regiment(unit):
		var planned_m := _achieved_m(positions, new_positions)   # pre-gate displacement, post-trim
		new_positions = _finalize_placement(unit, models, positions, new_positions, allow_contact, charge_target)
		# GATE-COLLAPSE LADDER (round 7, finding 2 — "a constraint gate truncates the whole move"): the gate
		# legalizes by shortening the WHOLE move toward its start, so a full-length plan with no nearby legal
		# end state can collapse to ~zero even though the route itself was fine (self-play: arc_in 6.0,
		# achieved_in 0.0). A SHORTER advance along the same line usually has a legal end state — re-plan at
		# half, then a quarter of the reach, gate each, and keep the best POST-GATE displacement. Bounded
		# (two retries, collapsed moves only); a charge is exempt (its contact snap owns the endpoint).
		if not allow_contact and planned_m > 0.01 \
				and _achieved_m(positions, new_positions) < planned_m * STALL_REPLAN_FRACTION:
			var best_pos := new_positions
			var best_trails := trails
			var best_ach := _achieved_m(positions, new_positions)
			var best_reach := reach
			for frac in [0.5, 0.25]:
				var r3: float = reach * float(frac)
				var t3: Array = []
				var p3 := _plan_move(unit, models, positions, goal, r3, allow_contact, avoid, avoid_dangerous, t3, charge_target)
				var b3 := r3 * INCHES_TO_METERS
				for i in range(mini(t3.size(), p3.size())):
					var leg3 := t3[i] as Array
					if MovementPlanner.polyline_length(leg3) > b3 + 0.0005:
						var cut3 := MovementPlanner.trim_polyline(leg3, b3)
						t3[i] = cut3
						if not cut3.is_empty():
							var fin3 := cut3.back() as Vector3
							p3[i] = Vector3(fin3.x, (p3[i] as Vector3).y, fin3.z)
				p3 = _finalize_placement(unit, models, positions, p3, allow_contact, charge_target)
				var a3 := _achieved_m(positions, p3)
				if a3 > best_ach + 0.005:
					best_pos = p3
					best_trails = t3
					best_ach = a3
					best_reach = r3
					gate_shortened = true
				if a3 >= b3 * 0.75:
					break   # a committed shorter move — good enough, stop retrying
			new_positions = best_pos
			trails = best_trails
			reach = best_reach
	# BOXED REPOSITION (AI plausibility wave 1, big-base maneuvering): even the gate-collapse ladder can
	# leave a LARGE base (Carnivo-Rex class) at a token step when small units filled every straight lane —
	# the maintainer's "big models had no room to maneuver". A boxed large model re-aims its SAME band
	# sideways (rotated goals, both signs, small first) and keeps the best post-gate displacement: getting
	# OUT of the jam this activation buys the room the next activation needs. Bounded, large bases only,
	# never a charge (its contact snap owns the endpoint).
	var boxed_repositioned := false
	if not _is_regiment(unit) and not allow_contact \
			and _move_base_radius_m(models) >= LARGE_BASE_RADIUS_IN * INCHES_TO_METERS \
			and reach >= 2.0 \
			and _achieved_m(positions, new_positions) < BOXED_ACHIEVED_IN * INCHES_TO_METERS:
		var anchor := MoveIntent.anchor_of(positions)
		var to_goal := Vector2(goal.x - anchor.x, goal.z - anchor.z)
		if to_goal.length() > 0.001:
			var best_pos2 := new_positions
			var best_trails2 := trails
			var best_ach2 := _achieved_m(positions, new_positions)
			for mag in BOXED_REPOSITION_DEGREES:
				for side in [1.0, -1.0]:
					var rotated := to_goal.rotated(deg_to_rad(float(mag) * float(side)))
					var goal4 := Vector3(anchor.x + rotated.x, goal.y, anchor.z + rotated.y)
					var t4: Array = []
					var p4 := _plan_move(unit, models, positions, _clamp_to_bounds(goal4), reach,
						allow_contact, avoid, avoid_dangerous, t4, charge_target)
					var b4 := reach * INCHES_TO_METERS
					for i in range(mini(t4.size(), p4.size())):
						var leg4 := t4[i] as Array
						if MovementPlanner.polyline_length(leg4) > b4 + 0.0005:
							var cut4 := MovementPlanner.trim_polyline(leg4, b4)
							t4[i] = cut4
							if not cut4.is_empty():
								var fin4 := cut4.back() as Vector3
								p4[i] = Vector3(fin4.x, (p4[i] as Vector3).y, fin4.z)
					p4 = _finalize_placement(unit, models, positions, p4, allow_contact, charge_target)
					var a4 := _achieved_m(positions, p4)
					if a4 > best_ach2 + 0.005:
						best_pos2 = p4
						best_trails2 = t4
						best_ach2 = a4
						boxed_repositioned = true
				if best_ach2 >= BOXED_ACHIEVED_IN * INCHES_TO_METERS * 2.0:
					break   # clearly out of the box — smaller rotation preferred, stop widening
			if boxed_repositioned:
				new_positions = best_pos2
				trails = best_trails2
	# Flying ignores terrain effects whilst moving (p.13) — no Dangerous tests for its crossings. Counted on
	# the ROUTE (pre-gate endpoints of the CHOSEN plan): the model still traversed those cells even if the
	# gate nudges its rest spot.
	var dang := 0 if flying else _count_dangerous_trails(trails)
	# The decision-log / label arc is the PLANNED within-budget move (pre-gate route), so the move-band audit
	# and the "X / Y" label stay truthful; the gate's physical un-stack nudge is not counted as extra distance.
	var longest_arc_m := 0.0
	for t in trails:
		longest_arc_m = maxf(longest_arc_m, MovementPlanner.polyline_length(t as Array))
	if not _is_regiment(unit):
		# Retrace each animation trail to its GATED endpoint so the glide ends exactly where the state now is.
		for i in range(mini(trails.size(), new_positions.size())):
			trails[i] = _retrace_to(trails[i] as Array, positions[i] as Vector3, new_positions[i] as Vector3)
	_apply_model_positions(models, new_positions)
	# Publish the per-model routes + base radii for the presentation layer (glide + swept corridor +
	# distance label) — the STATE is already final (applied + broadcast above); the replay is local.
	last_move_budget_in = reach
	var radii := _model_radius_map(models)
	last_move_paths = []
	for i in range(mini(models.size(), trails.size())):
		last_move_paths.append({"model": models[i], "path": trails[i],
			"radius_m": float(radii.get(models[i], SeparationChecker.DEFAULT_BASE_RADIUS_M))})
	# Present the models in the SEQUENTIAL FLOW ORDER (finding 7): each glides individually, nearest-to-
	# destination first, so the step-by-step flow the planner produced is visible (main glides them in
	# last_move_paths order). Only reorder when the order is a valid 1:1 permutation of the built paths.
	if last_flow_order.size() == last_move_paths.size():
		var reordered: Array = []
		var seen := {}
		for oi in last_flow_order:
			var k := int(oi)
			if k >= 0 and k < last_move_paths.size() and not seen.has(k):
				reordered.append(last_move_paths[k])
				seen[k] = true
		if reordered.size() == last_move_paths.size():
			last_move_paths = reordered
	# Achieved-distance truth (round 7, finding 2 regression metric): the unit's POST-GATE centroid
	# displacement in inches — "how far did the unit actually go" — logged with every move record so a
	# seeded self-play run can assert that open-field advances achieve close to their band (the half-inch
	# token moves of the flow-collapse bug show up here as achieved_in << budget_in).
	var achieved_m := _achieved_m(positions, new_positions)
	var why := "difficult cap" if reach < inches else ("around difficult" if avoid else "direct")
	if gate_shortened:
		why = "gate-legal shorten"   # the collapse ladder chose a shorter move with a LEGAL end state
	if boxed_repositioned:
		why = "boxed reposition"     # the straight lane was jammed — the band re-aimed to an open one
	# goal_gap_in (plausibility metric): how far the intended goal was — an "arrival" (goal within reach)
	# legitimately uses less than its band, an open-field move toward a distant goal must not.
	var move_data := {"band_in": inches, "budget_in": reach, "arc_in": longest_arc_m / INCHES_TO_METERS,
		"achieved_in": achieved_m / INCHES_TO_METERS, "dangerous_models": dang,
		"goal_gap_in": MoveIntent.distance_inches(MoveIntent.anchor_of(positions), goal)}
	for k in _move_extra:
		move_data[k] = _move_extra[k]
	_move_extra = {}
	record_decision({"kind": "move", "unit": unit.get_name(),
		"rule": "GF v3.5.1 p.7 move bands; p.11 difficult 6\" cap; p.57 move around difficult",
		"candidates": [], "chosen": "", "why": why,
		"data": move_data})
	return dang


## Centroid displacement (metres) between two same-length position sets — the "how far did the unit
## actually go" measure behind the stall re-plan and the achieved_in metric (round 7, finding 2).
static func _achieved_m(before: Array, after: Array) -> float:
	return (MoveIntent.anchor_of(after) - MoveIntent.anchor_of(before)).length()


## One planning pass: rigid clamp to the table, then obstacle-aware per-model planning. Returns the new
## positions; `trails` receives one world polyline per model.
func _plan_move(unit: GameUnit, models: Array, positions: Array, goal: Vector3, reach_in: float,
		allow_contact: bool, avoid_difficult: bool, avoid_dangerous: bool, trails: Array, charge_target: GameUnit) -> Array:
	var delta := MoveIntent.plan_unit_move(positions, goal, reach_in)
	delta = _clamp_delta_to_bounds(positions, delta)
	if delta == Vector3.ZERO:
		_fill_straight_trails(trails, positions, positions)
		return positions.duplicate()
	return _plan_positions(unit, models, positions, delta, allow_contact, trails, avoid_difficult, avoid_dangerous, charge_target, reach_in)


## Would the rigid move's per-model TARGETS land inside difficult terrain? (Objective or charge target
## inside a forest — then going around is impossible and the 6" cap path is taken directly.)
func _targets_in_difficult(positions: Array, goal: Vector3, reach_in: float, radius_m: float = 0.0) -> bool:
	if not terrain_type_at.is_valid():
		return false
	var delta := _clamp_delta_to_bounds(positions, MoveIntent.plan_unit_move(positions, goal, reach_in))
	for p in positions:
		# Edge-aware via the single containment predicate: a base whose EDGE lands in difficult terrain by any
		# amount is IN it (finding 6; the effect trigger keys on the base edge, not the centre).
		if TerrainRules.base_in_terrain((p as Vector3) + delta, radius_m, terrain_type_at, TerrainRules.is_difficult):
			return true
	return false


## Would the rigid move's per-model TARGETS land inside DANGEROUS terrain? Then going around is impossible
## (the destination itself is dangerous — e.g. an objective sitting in a lava pool), so the planner routes
## straight in and the model simply takes its dangerous test. Otherwise dangerous cells are routed AROUND
## (field-test finding 4: the AI walked through dangerous terrain when a clear route existed).
func _targets_in_dangerous(positions: Array, goal: Vector3, reach_in: float, radius_m: float = 0.0) -> bool:
	if not terrain_type_at.is_valid():
		return false
	var delta := _clamp_delta_to_bounds(positions, MoveIntent.plan_unit_move(positions, goal, reach_in))
	for p in positions:
		# Edge-aware via the single containment predicate (finding 6): a base whose EDGE lands in dangerous
		# terrain by any amount is IN it, so the dangerous-terrain routing/test triggers.
		if TerrainRules.base_in_terrain((p as Vector3) + delta, radius_m, terrain_type_at, TerrainRules.is_dangerous):
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
		if gu == null or own.has(gu) or unit_in_reserve(gu):
			continue   # a reserve unit is off-table — never a movement obstacle (field-test findings 3/4)
		if is_aircraft(gu):
			continue   # an Aircraft flies high — units may move under it; its base blocks no movement (GF v3.5.1)
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
func _terrain_grid_in(board_in: float, off: Vector2, avoid_difficult: bool, avoid_dangerous: bool = false) -> Dictionary:
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
			# Impassable is always avoided; Difficult and Dangerous are routed AROUND when the caller asks
			# (a clear route exists — solo overlay p.57 for Difficult, field-test finding 4 for Dangerous).
			if TerrainRules.is_impassable(t) \
					or (avoid_difficult and TerrainRules.is_difficult(t)) \
					or (avoid_dangerous and TerrainRules.is_dangerous(t)):
				avoid[cell] = true
	return {"grid": grid, "avoid": avoid}


## Fine (MovementPlanner.PLAN_CELL_IN, ~1") set of cells NO model may REST in — CONTAINER/RUINS (the
## self-play geometry audit's "impassable" class) and DANGEROUS — sampled from the REAL overlay only over the
## move's local AABB (start + target + margin) so it stays cheap, in the planner's 0-origin inch frame. The
## unified solver projects any model resting in one of these cells back out (GF/AoF v3.5.1 p.7 movement).
## Keyed by TerrainRules.cell_of(centre, PLAN_CELL_IN) so it matches the solver's lookup exactly. Empty when
## no terrain provider is wired (headless unit tests).
func _forbid_cells_in(mpos: Array, mdelta: Vector2, board_in: float, off: Vector2, own_r_m: float) -> Dictionary:
	var forbid := {}
	if not terrain_type_at.is_valid() or mpos.is_empty():
		return forbid
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in mpos:
		var v := p as Vector2
		for q in [v, v + mdelta]:
			var w := q as Vector2
			lo.x = minf(lo.x, w.x)
			lo.y = minf(lo.y, w.y)
			hi.x = maxf(hi.x, w.x)
			hi.y = maxf(hi.y, w.y)
	var margin: float = own_r_m / INCHES_TO_METERS + TerrainRules.CELL_IN   # base radius + one coarse cell
	lo -= Vector2(margin, margin)
	hi += Vector2(margin, margin)
	var cell: float = MovementPlanner.PLAN_CELL_IN
	var n := maxi(1, int(ceil(board_in / cell)))
	var cx0 := clampi(int(floor(lo.x / cell)), 0, n - 1)
	var cx1 := clampi(int(floor(hi.x / cell)), 0, n - 1)
	var cy0 := clampi(int(floor(lo.y / cell)), 0, n - 1)
	var cy1 := clampi(int(floor(hi.y / cell)), 0, n - 1)
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var centre_in := Vector2((float(cx) + 0.5) * cell, (float(cy) + 0.5) * cell)
			var world := centre_in * INCHES_TO_METERS - off
			var t: int = int(terrain_type_at.call(Vector3(world.x, 0.0, world.y)))
			if t == TerrainRules.TerrainType.CONTAINER or t == TerrainRules.TerrainType.RUINS \
					or t == TerrainRules.TerrainType.DANGEROUS:
				forbid[Vector2i(cx, cy)] = true
	return forbid


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


## The unit's Advance/Rush move bands from the SAME source as the human player's reach rings
## (Fast/Slow/Swift + aura- and base-upgrade-aware — GF/AoF Advanced Rules v3.5.1 p.13 Fast +2"/+4",
## Slow -2"/-4"). With a MovementRangeController wired, use its per-model resolution (bands_for_model —
## picks up aura-granted movement rules and per-model base upgrades, exactly the human's rings); without
## one, fall back to the STATIC pure band computation on the unit's own props. NEVER a hardcoded 6"/12":
## the old fallback silently dropped Slow when no controller was injected (field-test finding 1 — a
## Robot Legions Slow unit advanced the full 6"). Static so it is unit-testable without a scene.
static func move_bands_for_unit(unit: GameUnit, mrc: MovementRangeController) -> Dictionary:
	if unit == null:
		return {"advance": 6, "rush": 12}
	if mrc != null:
		for m in unit.get_alive_models():
			var node := (m as ModelInstance).node
			if node != null and is_instance_valid(node):
				return mrc.bands_for_model(node)
	return MovementRangeController.move_bands_for_props(unit.unit_properties)


## Shooting-range bonus (inches) a unit's special rules grant its ranged weapons — the wave-4 army-book
## "Royal Legion" (Mummified Undead; official Army Forge text: "This model gets +4" range when shooting and
## moves +2" when using Charge actions." — the +2" Charge flows through move_bands_for_props). Applied to
## the AI's shoot decision + reach AND the human's target validity/preview, so both directions honour it.
## Static + pure (unit-testable). Wave 5: the inch value is DATA (RulesRegistry "Royal Legion"
## .range_bonus_in for the unit's system/faction); this constant is the byte-identical fallback.
const ROYAL_LEGION_RANGE_BONUS_IN := 4
static func shooting_range_bonus(unit: GameUnit) -> int:
	if unit == null or not unit.has_special_rule("Royal Legion"):
		return 0
	return int(RulesRegistry.unit_param(unit, "Royal Legion", "range_bonus_in", ROYAL_LEGION_RANGE_BONUS_IN))


## Musician move-action bonus (inches) for a unit (wave 5, system-scoped): +1" on move actions when the
## unit carries Musician AND its book fields the rule (RulesRegistry gate — the GFF/AoFS picked-units
## variant still grants the bearer's own move; the pick facet is manual). 0.0 otherwise.
static func musician_move_bonus_in(unit: GameUnit) -> float:
	if unit == null or not RulesRegistry.unit_rule_active(unit, "Musician"):
		return 0.0
	return float(RulesRegistry.unit_param(unit, "Musician", "move_bonus_in", AiCombatMath.MUSICIAN_MOVE_BONUS_IN))


# ===== Aircraft (GF Advanced Rules v3.5.1; system-scoped via RulesRegistry — AI plausibility wave 1) =====

## Whether the unit flies as an Aircraft — system-scoped: the rule only fires where the unit's book
## fields it (the committed mechanics maps automate it for GF v3.5.1 only; AoF/AoFS/AoFR/GFF v3.5.1
## print no such rule, verified against the official PDFs).
static func is_aircraft(unit: GameUnit) -> bool:
	return unit != null and RulesRegistry.unit_rule_active(unit, "Aircraft")


## Range penalty (inches) a shooter suffers when targeting `target` — the Aircraft rule reduces every
## enemy's range against it (system-scoped data; 0 for anything that is not an aircraft).
static func target_range_penalty_in(target: GameUnit) -> float:
	if not is_aircraft(target):
		return 0.0
	return float(RulesRegistry.unit_param(target, "Aircraft", "target_range_penalty_in", AIRCRAFT_TARGET_RANGE_PENALTY_IN))


## The AI's fixed aircraft move length (inches) — the solo-AI section pins aircraft at a straight 30"
## every activation (which also satisfies the core rule's mandatory minimum).
static func aircraft_move_in(unit: GameUnit) -> float:
	return float(RulesRegistry.unit_param(unit, "Aircraft", "solo_move_in", AIRCRAFT_MOVE_IN))


## Alive models of a unit INCLUDING its attached heroes — a unit with a joined hero is destroyed only
## when BOTH are gone (GF/AoF v3.5.1 "Heroes": the hero is part of the unit). The shared truth behind
## the battle log's destroyed-check and main's wound summaries.
static func combined_alive(unit: GameUnit) -> int:
	if unit == null:
		return 0
	var n: int = unit.get_alive_count()
	if unit.has_method("get_attached_heroes"):
		for h in unit.get_attached_heroes():
			if h != null:
				n += (h as GameUnit).get_alive_count()
	return n


## Total model count of a unit INCLUDING its attached heroes (the denominator shown next to
## combined_alive in log lines — "(alive/total)" must count the same pool on both sides).
static func combined_total(unit: GameUnit) -> int:
	if unit == null:
		return 0
	var n: int = unit.models.size()
	if unit.has_method("get_attached_heroes"):
		for h in unit.get_attached_heroes():
			if h != null:
				n += (h as GameUnit).models.size()
	return n


## Line of sight between two units via the injected checker (main wires terrain LOS); no checker = clear.
func _has_los(unit: GameUnit, target_unit: GameUnit) -> bool:
	# Prefer the geometric per-model check (matches the shooting resolution's per-model gate); fall back to
	# the coarse unit-centre terrain callable only when no per-model checker is wired (headless tests).
	if unit_los_checker.is_valid():
		return bool(unit_los_checker.call(unit, target_unit))
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
		world_trails: Array = [], avoid_difficult: bool = true, avoid_dangerous: bool = false,
		charge_target: GameUnit = null, charge_arc_in: float = 0.0) -> Array:
	last_flow_order = []
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
	var sampled := _terrain_grid_in(board_in, off, avoid_difficult, avoid_dangerous)
	opts["avoid_cells"] = sampled["avoid"]
	# Unified-solver inputs (real-game path only): the presence of "radii" selects the C-space / Theta* /
	# funnel + unified-constraint-solver pipeline inside plan_unit_step. SoloSim never sets it, so its
	# steer+A* path and the mirror-fairness oracle stay byte-identical. radii = per-model base radius (inches)
	# for the anti-overlap constraint; forbid_cells = the fine (1") no-rest terrain set (Impassable +
	# Dangerous) the solver keeps every model out of. Every move runs the solver (no rigid fast-return here)
	# so even a straight slide can never park a model inside forbidden terrain.
	var radii_in: Array = []
	for m in models:
		radii_in.append(model_base_radius_m(m as ModelInstance) / INCHES_TO_METERS)
	opts["radii"] = radii_in
	opts["forbid_cells"] = _forbid_cells_in(mpos, mdelta, board_in, off, own_r_m)
	# CHARGE arc budget (field-test finding 3, charge-reach fix): a charge whose nearest models must DETOUR
	# around obstacles or a LARGE enemy base needs more ARC than the straight-line gap; the delta (aimed at
	# contact) is short, so we hand the planner the FULL charge band as the per-model arc allowance. The
	# target's body-only zone (built above) still clamps the stop AT base contact — the extra budget only
	# lets the route bend around, never overshoot. Non-charge moves pass 0 ⇒ the delta-length allowance.
	if allow_contact and charge_target != null and charge_arc_in > 0.0:
		opts["charge_allowance"] = charge_arc_in   # inches (the planner's frame) — the full charge band
		# The enemy BODY as the reach goal (planner inch frame): a charging model routes toward the target
		# centre and, blocked by its body-only zone, stops at base contact — bending around obstacles to the
		# nearest open face rather than stalling on the along-the-line point (charge-reach fix).
		var tc := unit_centre(charge_target)
		opts["charge_goal"] = (Vector2(tc.x, tc.z) + off) / INCHES_TO_METERS
	var plan_trails: Array = []
	var planned: Array = MovementPlanner.plan_unit_step(mpos, mdelta, walls_in, sampled["grid"],
		allow_contact, board_in, plan_trails, opts)
	# The sequential per-model flow (finding 7) writes back the order its models filed to their slots, so the
	# presentation glides each model individually in that order (main._solo_animate_move).
	last_flow_order = (opts.get("flow_order", []) as Array).duplicate()
	# The unified solver (solve_formation, inside plan_unit_step) resolves unit-spacing, own-base separation,
	# coherency and terrain-avoidance TOGETHER — but its least-violating fallback can still KEEP a residual
	# violation. The HARD final gate (findings 3 + 6) that guarantees them is applied by the CALLER
	# (_execute_move) AFTER the distance-truth trim, so the trim can never cut a gate-corrected (pulled-back)
	# endpoint off its trail. Here we only convert the solver's inch positions to world + build the route trail.
	var out: Array = []
	if world_trails != null:
		world_trails.clear()
	for i in range(positions.size()):
		var pi: Vector2 = planned[i] if i < planned.size() else mpos[i]
		var world := (pi * INCHES_TO_METERS) - off
		var src: Vector3 = positions[i]
		out.append(Vector3(world.x, src.y, world.y))
		if world_trails != null:
			var leg: Array = []
			if i < plan_trails.size():
				for wp in plan_trails[i]:
					var wv := ((wp as Vector2) * INCHES_TO_METERS) - off
					leg.append(Vector3(wv.x, src.y, wv.y))
			if leg.is_empty() or (leg.back() as Vector3).distance_to(out[i]) > OVERLAP_EPS_M:
				leg.append(out[i])
			if leg.size() < 2:
				leg = [src, out[i]]
			world_trails.append(leg)
	return out


# === HARD final placement gate (field-test findings 3 + 6 — real-game loose-unit path only) ==========
# The formation solver only APPROXIMATES the placement rules; its least-violating fallback can keep a
# residual violation the self-play audit still flags. This gate ENFORCES three invariants after every loose
# AI move, in the order the maintainer specified — terrain → overlap → coherency-shorten — iterated to a
# bounded fixed point, using the SAME base geometry (SeparationChecker) and coherency thresholds
# (CoherencyChecker) the audit measures, so the numbers actually drop:
#   (3a) NO model rests in impassable terrain (CONTAINER/RUINS — GF/AoF v3.5.1 p.7 "may never move through");
#   (3b) NO base overlaps ANY other base — same unit, other units, enemies (p.7; ported
#        SeparationResolver.resolve_overlaps, escape-scan-guaranteed to reach edge ≥ 0);
#   (6)  the unit ENDS in coherency (p.7; shorten the whole move back along its taut line toward the
#        coherent START until coherency holds — the unit began coherent, so a coherent result always exists).
# A CHARGE (allow_contact) must reach base contact with its target, so it skips the coherency + terrain
# shorten but STILL resolves overlap to CONTACT (edge ≥ 0): it touches, never moves through (p.7/p.8).
# The sim never calls this (it plans through MovementPlanner directly), so the fairness oracle is untouched.

## Resolve the placement invariants for one loose move. `start_world` = the coherent, overlap-free pre-move
## positions (a legal fallback the coherency-shorten can always retreat to); `planned_world` = the solver's
## output. Returns NEW world positions. Reads live obstacle node positions; mutates nothing on the scene.
func _finalize_placement(unit: GameUnit, models: Array, start_world: Array, planned_world: Array,
		allow_contact: bool, _charge_target: GameUnit) -> Array:
	var cfg: Array = planned_world.duplicate()
	var n := models.size()
	if n == 0:
		return cfg
	var obstacles := _external_obstacle_shapes(unit)
	# (terrain) Project every model out of forbidden terrain (impassable CONTAINER/RUINS + DANGEROUS — a model
	# should not REST in either). A charge may end wherever base contact demands, so it skips the terrain step.
	if not allow_contact:
		for i in range(n):
			cfg[i] = _project_out_forbidden_world(cfg[i], model_base_radius_m(models[i] as ModelInstance))
	# (overlap) Push every base off every other base — own unit, other units, enemies (SeparationResolver,
	# escape-scan-guaranteed to edge ≥ 0). On a charge this pushes exactly to CONTACT with the target, never through.
	_resolve_overlaps_world(models, cfg, obstacles)
	if allow_contact or n == 1:
		return cfg   # charge: contact reached; single model: no coherency notion — both are done
	# (coherency) If the unit is coherent AND overlap-free, keep the full move. Otherwise shorten the whole
	# move back along its taut line toward the coherent, overlap-free START until BOTH hold — the unit began
	# legal, so a legal factor always exists (t = 0), and the search takes the largest one (GF/AoF v3.5.1 p.7:
	# "or as close as possible"). Making the shorten OVERLAP-AWARE stops the coherency pull-back from dragging a
	# model back INTO a friendly unit near its start (self-play: the residual inter/intra overlap after v1).
	var max_chain: float = CoherencyChecker.SKIRMISH_CHAIN_DISTANCE_INCHES \
		if CoherencyChecker.is_skirmish_system(unit) else CoherencyChecker.MAX_CHAIN_DISTANCE_INCHES
	if _config_coherent_world(models, cfg, max_chain) and _config_overlap_free(models, cfg, obstacles) \
			and _config_terrain_clear(models, cfg):
		return cfg
	# MINIMAL per-model coherency repair FIRST (field-test round 6 findings 2/3): pull only the stragglers into
	# the coherent set, leaving the models that advanced correctly at their FULL move. The whole-unit shorten
	# below blends the ENTIRE unit back toward the start, which systematically under-moved the advance (and so
	# left the unit short of shooting range — finding 3). With finding 7's sequential flow the unit usually
	# arrives coherent, so this rarely fires; when it does it is a nudge, not a retreat. Fall back to the
	# whole-unit shorten only if the minimal repair can't restore a legal config (guarantees coherency: t=0 is
	# the coherent start).
	_pull_stragglers_coherent_world(models, cfg, obstacles, max_chain)
	if _config_coherent_world(models, cfg, max_chain) and _config_overlap_free(models, cfg, obstacles) \
			and _config_terrain_clear(models, cfg):
		return cfg
	return _shorten_world_to_legal(start_world, cfg, models, obstacles, max_chain)


## The indices of the LARGEST 1"-edge-link component among `shapes` (CoherencyChecker's link graph, BFS).
func _largest_link_component_world(shapes: Array) -> Array:
	var n := shapes.size()
	var best: Array = []
	var seen: Array[bool] = []
	seen.resize(n)
	seen.fill(false)
	for start in range(n):
		if seen[start]:
			continue
		var comp: Array = [start]
		var queue: Array = [start]
		seen[start] = true
		while not queue.is_empty():
			var cur: int = queue.pop_back()
			for other in range(n):
				if seen[other]:
					continue
				if SeparationChecker.edge_distance(shapes[cur], shapes[other]) <= CoherencyChecker.COHERENCY_DISTANCE_INCHES:
					seen[other] = true
					queue.append(other)
					comp.append(other)
		if comp.size() > best.size():
			best = comp
	return best


const COH_REPAIR_PASSES := 12   # bounded per-model coherency-repair sweeps (finding 2 minimal-shorten)

## Pull only the STRAGGLERS into coherency (field-test round 6 findings 2/3): each model outside the unit's
## largest 1"-link component is stepped toward its nearest in-component neighbour (stopping at a 1" edge link
## so no overlap is created), and the single model furthest from the centroid is pulled in when the unit
## over-spreads. Every nudge is table-clamped and projected out of forbidden terrain; a final overlap pass
## clears any residual stack. A MINIMAL correction — the models that advanced correctly keep their full move
## (unlike the whole-unit shorten). Mutates `cfg`; returns true when it ends coherent.
func _pull_stragglers_coherent_world(models: Array, cfg: Array, obstacles: Array, max_chain: float) -> bool:
	var n := models.size()
	if n <= 1:
		return true
	var link_step: float = CoherencyChecker.COHERENCY_DISTANCE_INCHES * INCHES_TO_METERS
	for _pass in range(COH_REPAIR_PASSES):
		if _config_coherent_world(models, cfg, max_chain):
			return true
		var shapes := _moving_shapes_at(models, cfg)
		var main := _largest_link_component_world(shapes)
		var in_main := {}
		for k in main:
			in_main[k] = true
		var moved := false
		# (a) Reconnect: each out-of-component model steps toward its nearest in-component neighbour, capped so
		# it stops at ~a 1" edge link (never overshoots into an overlap).
		for i in range(n):
			if in_main.has(i):
				continue
			var nearest := -1
			var nd := INF
			for m in main:
				var d: float = SeparationChecker.edge_distance(shapes[i], shapes[m])
				if d < nd:
					nd = d
					nearest = m
			if nearest < 0:
				continue
			var pi := Vector2((cfg[i] as Vector3).x, (cfg[i] as Vector3).z)
			var pn := Vector2((cfg[nearest] as Vector3).x, (cfg[nearest] as Vector3).z)
			var to_n := pn - pi
			var dist := to_n.length()
			if dist < OVERLAP_EPS_M:
				continue
			# Close the edge gap to the 1" link, capped at one link_step per pass (bounded, monotonic-inward).
			var close: float = minf(minf(nd - CoherencyChecker.COHERENCY_DISTANCE_INCHES * INCHES_TO_METERS, dist), link_step)
			if close <= OVERLAP_EPS_M:
				continue
			var cand := _clamp_to_bounds(Vector3((cfg[i] as Vector3).x + to_n.x / dist * close,
				(cfg[i] as Vector3).y, (cfg[i] as Vector3).z + to_n.y / dist * close))
			cfg[i] = _project_out_forbidden_world(cand, model_base_radius_m(models[i] as ModelInstance))
			moved = true
		# (b) Over-spread: pull the model furthest from the centroid inward.
		if _config_overspread_world(shapes, max_chain):
			var c := _config_centroid_world(cfg)
			var far := _furthest_from_world(cfg, c)
			if far >= 0:
				var pf := Vector2((cfg[far] as Vector3).x, (cfg[far] as Vector3).z)
				var to_c := Vector2(c.x, c.z) - pf
				var dc := to_c.length()
				if dc > OVERLAP_EPS_M:
					var stepc: float = minf(link_step, dc)
					var cand := _clamp_to_bounds(Vector3((cfg[far] as Vector3).x + to_c.x / dc * stepc,
						(cfg[far] as Vector3).y, (cfg[far] as Vector3).z + to_c.y / dc * stepc))
					cfg[far] = _project_out_forbidden_world(cand, model_base_radius_m(models[far] as ModelInstance))
					moved = true
		if not moved:
			break
	# Clear any residual overlap the inward pulls introduced, then report the final coherency.
	_resolve_overlaps_world(models, cfg, obstacles)
	return _config_coherent_world(models, cfg, max_chain)


## True when the widest edge-to-edge spread of `shapes` exceeds `max_chain` (the unit over-spreads, p.7).
func _config_overspread_world(shapes: Array, max_chain: float) -> bool:
	for i in range(shapes.size()):
		for j in range(i + 1, shapes.size()):
			if SeparationChecker.edge_distance(shapes[i], shapes[j]) > max_chain:
				return true
	return false


## Centroid (world) of a config's XZ positions (Y from the first entry).
func _config_centroid_world(cfg: Array) -> Vector3:
	if cfg.is_empty():
		return Vector3.ZERO
	var s := Vector2.ZERO
	for p in cfg:
		s += Vector2((p as Vector3).x, (p as Vector3).z)
	s /= float(cfg.size())
	return Vector3(s.x, (cfg[0] as Vector3).y, s.y)


## Index of the config model furthest (centre distance) from `c`.
func _furthest_from_world(cfg: Array, c: Vector3) -> int:
	var far := -1
	var fd := -1.0
	for i in range(cfg.size()):
		var d: float = Vector2((cfg[i] as Vector3).x, (cfg[i] as Vector3).z).distance_to(Vector2(c.x, c.z))
		if d > fd:
			fd = d
			far = i
	return far


## Every OTHER on-table unit's alive-model BaseShapes (at their live positions) — the obstacle set the
## moving unit's bases may never overlap. Excludes the moving unit + its attached heroes (coherency owns
## their internal spacing) and any Ambush-reserve unit (off-table — GF/AoF v3.5.1 p.13). Enemies AND
## friendlies both count: the no-through rule binds against any base (p.7).
func _external_obstacle_shapes(unit: GameUnit) -> Array:
	var out: Array = []
	if army_manager == null:
		return out
	var own := {unit: true}
	if unit.has_method("get_attached_heroes"):
		for h in unit.get_attached_heroes():
			if h != null:
				own[h] = true
	for g in army_manager.get_all_game_units():
		var gu := g as GameUnit
		if gu == null or own.has(gu) or unit_in_reserve(gu):
			continue
		if is_aircraft(gu):
			continue   # an Aircraft's base blocks nothing on the ground (GF v3.5.1 — only the model counts)
		for m in gu.get_alive_models():
			var sh := SeparationChecker.shape_for_model(m as ModelInstance)
			if sh != null:
				out.append(sh)
	return out


## BaseShapes for the moving models re-centred at the config positions `cfg` (world). The shape kind /
## extents / yaw come from each live model (round exact, oval/rect circumscribed); only the centre is
## overridden to the planned XZ, so the overlap + coherency math runs on the REAL base footprints.
func _moving_shapes_at(models: Array, cfg: Array) -> Array:
	var out: Array = []
	for i in range(models.size()):
		var sh := SeparationChecker.shape_for_model(models[i] as ModelInstance)
		if sh == null:
			sh = SeparationChecker.BaseShape.make_round(Vector2.ZERO, SeparationChecker.DEFAULT_BASE_RADIUS_M)
		sh.center = Vector2((cfg[i] as Vector3).x, (cfg[i] as Vector3).z)
		out.append(sh)
	return out


## Push every moving model out until NO base overlaps another (own unit, other units, enemies) — the
## ported SeparationResolver.resolve_overlaps applied per model (Gauss-Seidel: each model treated as the
## item, all OTHER bases as obstacles), a few passes so mutual pushes converge. Writes the cleared centres
## back into `cfg`. resolve_overlaps' escape-scan guarantees a finite obstacle set is always cleared.
func _resolve_overlaps_world(models: Array, cfg: Array, external_obstacles: Array) -> void:
	var n := models.size()
	if n == 0:
		return
	var shapes := _moving_shapes_at(models, cfg)
	for _pass in range(OVERLAP_GATE_PASSES):
		var moved := false
		for i in range(n):
			var obstacles: Array = external_obstacles.duplicate()
			for j in range(n):
				if j != i:
					obstacles.append(shapes[j])
			var delta := SeparationResolver.resolve_overlaps([shapes[i]], obstacles)
			if delta.length_squared() > 0.0:
				moved = true
		if not moved:
			break
	for i in range(n):
		cfg[i] = Vector3(shapes[i].center.x, (cfg[i] as Vector3).y, shapes[i].center.y)


## True when a model's BASE (radius `radius_m`) OVERLAPS forbidden-to-rest terrain it must not END on:
## impassable CONTAINER, RUINS (impassable internal walls) or DANGEROUS (the route planner routes around it; a
## model should not stand in it). Edge-aware via the SINGLE containment predicate (field-test round 6, finding
## 6; GF/AoF Advanced Rules v3.5.1 terrain guidelines — any part of the base in the terrain counts as in it):
## a base whose outer edge dips into the terrain by any amount is forbidden even when its centre sits outside.
## The move-through of Dangerous mid-route still triggers its test (counted from the route), independently of
## where the model finally rests.
func _world_forbidden(pos: Vector3, radius_m: float = 0.0) -> bool:
	return TerrainRules.base_in_terrain(pos, radius_m, terrain_type_at, TerrainRules.is_forbidden_rest)


## Project a model (base radius `radius_m`) resting in / OVERLAPPING forbidden terrain out to the nearest spot
## whose whole BASE is clear (16 compass directions × expanding 1 cm rings; edge-aware — finding 6), world-frame
## tie-break within a ring for determinism. A model with no clear point in range is left where it is (the
## overlap pass + coherency-shorten still act on it). No-op when the base is already clear.
func _project_out_forbidden_world(pos: Vector3, radius_m: float = 0.0) -> Vector3:
	if not _world_forbidden(pos, radius_m):
		return pos
	var dist := TERRAIN_OUT_STEP_M
	while dist <= TERRAIN_OUT_MAX_M + OVERLAP_EPS_M:
		var best := pos
		var found := false
		for k in range(TERRAIN_OUT_DIRS):
			var ang := TAU * float(k) / float(TERRAIN_OUT_DIRS)
			var c := _clamp_to_bounds(pos + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist))
			if _world_forbidden(c, radius_m):
				continue
			if not found or (c.x < best.x - OVERLAP_EPS_M or (absf(c.x - best.x) <= OVERLAP_EPS_M and c.z < best.z - OVERLAP_EPS_M)):
				best = c
				found = true
		if found:
			return best
		dist += TERRAIN_OUT_STEP_M
	return pos


## OPR coherency of a config (GF/AoF v3.5.1 p.7), measured on REAL base geometry exactly as the audit's
## CoherencyChecker does: models LINK when their bases are within COHERENCY_DISTANCE (1") edge-to-edge, the
## link graph must be a SINGLE connected chain, and the widest edge-to-edge spread must be ≤ `max_chain`
## (9", or 6" Skirmish). A unit of ≤1 model is trivially coherent.
func _config_coherent_world(models: Array, cfg: Array, max_chain: float) -> bool:
	var n := models.size()
	if n <= 1:
		return true
	var shapes := _moving_shapes_at(models, cfg)
	# Single connected 1"-link component (BFS).
	var visited: Array[bool] = []
	visited.resize(n)
	visited.fill(false)
	var queue: Array = [0]
	visited[0] = true
	var seen := 1
	while not queue.is_empty():
		var cur: int = queue.pop_back()
		for other in range(n):
			if visited[other]:
				continue
			if SeparationChecker.edge_distance(shapes[cur], shapes[other]) <= CoherencyChecker.COHERENCY_DISTANCE_INCHES:
				visited[other] = true
				seen += 1
				queue.append(other)
	if seen < n:
		return false
	# Widest edge-to-edge spread within max_chain.
	for i in range(n):
		for j in range(i + 1, n):
			if SeparationChecker.edge_distance(shapes[i], shapes[j]) > max_chain:
				return false
	return true


## True when NO model in the config has its BASE in forbidden terrain (impassable + dangerous), edge-aware:
## each model is tested at its real base radius (finding 6), so a base whose edge overlaps a container counts.
func _config_terrain_clear(models: Array, cfg: Array) -> bool:
	for i in range(cfg.size()):
		var r: float = model_base_radius_m(models[i] as ModelInstance) if i < models.size() else 0.0
		if _world_forbidden(cfg[i] as Vector3, r):
			return false
	return true


## True when NO moving base overlaps another moving base or any external obstacle base (edge ≥ 0, within a
## tiny epsilon so base CONTACT is allowed). The audit's no-stack invariant (GF/AoF v3.5.1 p.7), shape-exact.
func _config_overlap_free(models: Array, cfg: Array, obstacles: Array) -> bool:
	var n := models.size()
	var shapes := _moving_shapes_at(models, cfg)
	var tol := -SeparationResolver.RESOLVE_EPSILON_INCHES
	for i in range(n):
		for j in range(i + 1, n):
			if SeparationChecker.edge_distance(shapes[i], shapes[j]) < tol:
				return false
		for o in obstacles:
			if SeparationChecker.edge_distance(shapes[i], o as SeparationChecker.BaseShape) < tol:
				return false
	return true


## Shorten a move back along its taut line toward the legal START until the unit is BOTH coherent AND
## overlap-free (findings 3 + 6). Bisects the whole-unit blend factor: t = 0 is the start (coherent and
## overlap-free by the move invariant), t = 1 the planned config (illegal here), so the search always returns
## a legal placement, as far forward as the rules allow and no further ("or as close as possible" — GF/AoF
## v3.5.1 p.7). Retreating toward the start also moves the unit AWAY from whatever it overlapped, so making
## the predicate overlap-aware stops the pull-back from dragging a model back into a friendly unit.
func _shorten_world_to_legal(start_world: Array, cfg: Array, models: Array, obstacles: Array, max_chain: float) -> Array:
	if _config_coherent_world(models, cfg, max_chain) and _config_overlap_free(models, cfg, obstacles) \
			and _config_terrain_clear(models, cfg):
		return cfg.duplicate()
	var lo := 0.0
	var hi := 1.0
	for _b in range(COH_SHORTEN_BISECT):
		var mid := (lo + hi) * 0.5
		var blended := _blend_world(start_world, cfg, mid)
		if _config_coherent_world(models, blended, max_chain) and _config_overlap_free(models, blended, obstacles) \
				and _config_terrain_clear(models, blended):
			lo = mid
		else:
			hi = mid
	return _blend_world(start_world, cfg, lo)


## Per-model linear blend of two same-length world-position arrays at t (0 = a, 1 = b); Y from `a`.
func _blend_world(a: Array, b: Array, t: float) -> Array:
	var out: Array = []
	for i in range(a.size()):
		var pa: Vector3 = a[i]
		var pb: Vector3 = b[i]
		out.append(Vector3(lerpf(pa.x, pb.x, t), pa.y, lerpf(pa.z, pb.z, t)))
	return out


## Retrace a model's route trail so it ENDS at the gate-corrected endpoint (findings 3/6). The route is the
## taut path the model walked; the gate then adjusted its rest position (coherency pull-back / overlap push /
## terrain-out). Trimming the route to the straight start→gated distance keeps the path monotonic and within
## the arc it actually needs (a pull-back is shorter than the route arc), then the exact gated point is
## snapped on — so the glide follows the route's shape and lands precisely on the applied state. Pure.
func _retrace_to(route: Array, start: Vector3, gated: Vector3) -> Array:
	var straight := Vector2(gated.x - start.x, gated.z - start.z).length()
	if straight < OVERLAP_EPS_M:
		return [start]   # ended at (or pulled fully back to) the start — no visible glide
	if route.size() < 2:
		return [start, gated]
	var trimmed := MovementPlanner.trim_polyline(route, straight)
	if trimmed.is_empty():
		trimmed = [start]
	if (trimmed.back() as Vector3).distance_to(gated) > OVERLAP_EPS_M:
		trimmed.append(gated)
	return trimmed


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


## The objective the activating unit should head for — the nearest marker this AI side does NOT control,
## with a HOLDABLE marker (no enemy contesting it) preferred over a contested one. NO_OBJECTIVE when none.
##
## Control follows the official "Controlling Objectives" rule (Solo & Co-Op v3.5.0 p.2): an objective counts
## as under the AI's control if the AI already OWNS it (persistent round-end owner) OR more non-shaken AI
## units than enemy units are within 3" of it. Crucially we EXCLUDE the activating unit from that AI count,
## so a lone holder does not read itself as "controlling" and wander off — but the moment a SECOND AI unit
## is on the marker, a third treats it as held and peels off to an open one.
##
## Among the markers the AI does not control the tree prefers a HOLDABLE one — no enemy unit within 3", so a
## unit sent there can seize and keep it — over a contested one, then the nearest. This is the round-5 field
## finding: both armies piled onto the contested centre marker and no unit ever peeled off to hold an open
## flank, so every game stalled 0-0-3. Nearest-uncontrolled alone (the letter of the tree) never distributes;
## the holdable-first ordering is the documented refinement that makes the AI actually contest the mission.
func _nearest_uncontrolled_objective(from: Vector3, activating_unit: GameUnit = null) -> Vector3:
	if not objectives_provider.is_valid():
		return NO_OBJECTIVE
	var objs: Variant = objectives_provider.call()
	if not (objs is Array):
		return NO_OBJECTIVE
	var arr: Array = objs
	var best := NO_OBJECTIVE
	var best_holdable := false
	var best_d := INF
	for i in range(arr.size()):
		var o: Vector3 = arr[i]
		var owner: int = int(objective_owner_of.call(i)) if objective_owner_of.is_valid() else 0
		var enemy_near: int = _units_controlling(o, human_slot, null)
		# The AI controls it (skip) when it already owns it, or has a strict non-shaken majority within 3"
		# (excluding the unit deciding right now, so it never abandons a marker only it is holding).
		if owner == ai_slot or _units_controlling(o, ai_slot, activating_unit) > enemy_near:
			continue
		var holdable: bool = enemy_near == 0   # no enemy contesting → a unit here can seize and keep it
		var d := MoveIntent.distance_inches(from, o)
		# Holdable markers rank ahead of contested ones; within a tier the nearer marker wins.
		if best == NO_OBJECTIVE or (holdable and not best_holdable) or (holdable == best_holdable and d < best_d):
			best = o
			best_holdable = holdable
			best_d = d
	return best


## Count of a side's non-shaken, on-table units with at least one alive model within 3" of `obj` (the
## official "Controlling Objectives" presence, Solo & Co-Op v3.5.0 p.2 — counted per UNIT, not per model).
## `exclude` drops one unit from the tally (the unit currently deciding its own move). Reserve/attached
## units never count (they are not free-standing on the table).
func _units_controlling(obj: Vector3, slot: int, exclude: GameUnit) -> int:
	if army_manager == null:
		return 0
	var n := 0
	for u in army_manager.get_game_units_for_player(slot):
		var gu := u as GameUnit
		if gu == null or gu == exclude or gu.is_destroyed() or gu.is_shaken or unit_in_reserve(gu):
			continue
		if gu.has_method("is_attached") and gu.is_attached():
			continue
		if is_aircraft(gu):
			continue   # an Aircraft can neither seize nor contest objectives (GF v3.5.1)
		for p in alive_positions(gu):
			if MoveIntent.distance_inches(p, obj) <= OBJECTIVE_CONTROL_IN + 0.001:
				n += 1
				break
	return n


## Smallest distance (inches) from any alive model of `unit` to its nearest objective marker — the
## measurable "did the unit reach seize range?" number for the decision log (field-test finding 1). INF
## when there are no markers or no live models.
func _nearest_objective_model_gap_in(unit: GameUnit) -> float:
	if not objectives_provider.is_valid():
		return INF
	var objs: Variant = objectives_provider.call()
	if not (objs is Array):
		return INF
	var arr: Array = objs
	var best := INF
	for p in alive_positions(unit):
		for o in arr:
			best = minf(best, MoveIntent.distance_inches(p, o as Vector3))
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
		if hu == null or hu.is_destroyed() or unit_in_reserve(hu):
			continue   # an Ambush-reserve unit is off-table — it blocks no path (findings 4/5)
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


## Relentless / Indirect "Hold and shoot" overlay (Solo & Co-Op AI overlays: an AI unit whose Relentless —
## or, wave 5, Indirect — ranged weapon has an enemy in range always uses Hold and shoots instead of
## manoeuvring). Returns the triggering rule name ("" when none) so the decision record names WHICH rule
## overrode the tree.
static func hold_and_shoot_rule(weapons: Array, enemy_in_range: bool) -> String:
	if not enemy_in_range:
		return ""
	for w in weapons:
		var rng_in: int = int((w as Object).range_value) if (w is Object and (w as Object).get("range_value") != null) else 0
		if rng_in <= 0:
			continue
		var rules: Array = (w as Object).special_rules if (w is Object and (w as Object).get("special_rules") != null) else []
		for r in rules:
			var s := str(r).strip_edges()
			if s.begins_with("Relentless"):
				return "Relentless"
			if s.begins_with("Indirect"):
				return "Indirect"
	return ""


## Boolean form of hold_and_shoot_rule (the pre-wave-5 predicate, kept for the tests/callers).
static func _forces_hold_and_shoot(weapons: Array, enemy_in_range: bool) -> bool:
	return not hold_and_shoot_rule(weapons, enemy_in_range).is_empty()


## Whether any RANGED weapon carries Indirect (wave 5: "may target enemies that are not in line of
## sight") — the LOS waiver for the post-move can_shoot gate. Accepts OPRWeapon objects.
static func has_indirect_ranged(weapons: Array) -> bool:
	for w in weapons:
		var rng_in: int = int((w as Object).range_value) if (w is Object and (w as Object).get("range_value") != null) else 0
		if rng_in <= 0:
			continue
		var rules: Array = (w as Object).special_rules if (w is Object and (w as Object).get("special_rules") != null) else []
		for r in rules:
			if str(r).strip_edges().begins_with("Indirect"):
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
## dropped past DECISION_LOG_CAP, so an undrained buffer stays bounded in long games. A configured
## decision_sink sees every record first (lossless — the harness capture is not subject to eviction).
func record_decision(rec: Dictionary) -> void:
	if decision_sink.is_valid():
		decision_sink.call(rec)
	decision_log.append(rec)
	if decision_log.size() > DECISION_LOG_CAP:
		decision_log.pop_front()


## Official ROLL-OFF procedure (core rules): each player rolls a die, the higher result wins, and tied
## results are rolled again until someone wins. Returns the winning player slot (1 or 2). `roller` is an
## optional Callable() -> int producing one die result per call (tests script it); the default draws d6s
## from the controller's seeded _rng, so a fixed seed reproduces the roll-off. The rulebook couples this
## to match start: the roll-off winner deploys first AND opens round 1 — the both-AI driver passes the
## winner through as `first_opener`. A defensive cap guards against a degenerate roller that ties forever.
func roll_off(roller: Callable = Callable()) -> int:
	const ROLL_OFF_CAP := 100
	for _attempt in range(ROLL_OFF_CAP):
		var d1: int = int(roller.call()) if roller.is_valid() else _rng.randi_range(1, 6)
		var d2: int = int(roller.call()) if roller.is_valid() else _rng.randi_range(1, 6)
		record_decision({"kind": "roll_off", "unit": "-",
			"rule": "roll-off (core rules): higher die wins, tied dice roll again",
			"candidates": [], "chosen": ("P1" if d1 > d2 else ("P2" if d2 > d1 else "tie — re-roll")),
			"why": "deployment/first-turn roll-off", "data": {"p1": d1, "p2": d2}})
		if d1 != d2:
			return 1 if d1 > d2 else 2
	return 1   # unreachable with fair dice; deterministic fallback for a broken scripted roller


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
			# EV is expected wounds — never render it negative (finding 2): a net charge score below zero is a
			# ranking artefact, not a real "negative expected damage". Floored here as the final display guard.
			listed.append("%s EV %.2f" % [str(cd.get("name", "?")), maxf(0.0, float(cd.get("ev", 0.0)))])
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


## The expenditure key of a Limited weapon profile for a unit (wave 5): unit identity + weapon name —
## a unit's Limited weapon fires once per GAME, whatever target it picked.
static func limited_key(unit: GameUnit, profile: Dictionary) -> String:
	return "%s::%s" % [unit.unit_id if unit != null else "?", str(profile.get("name", "?"))]


## Whether this unit's Limited profile is already spent.
func is_limited_used(unit: GameUnit, profile: Dictionary) -> bool:
	return limited_used.has(limited_key(unit, profile))


## Mark a Limited profile spent (called after its dice actually rolled) + a dev-mode decision record —
## the once-per-game state is a DECISION input (an expended weapon stops shaping targeting/EV).
func mark_limited_used(unit: GameUnit, profile: Dictionary) -> void:
	limited_used[limited_key(unit, profile)] = true
	record_decision({"kind": "action", "unit": unit.get_name() if unit != null else "?",
		"rule": "Limited (core v3.5.1): may only be used once per game",
		"candidates": [], "chosen": str(profile.get("name", "?")), "why": "limited weapon expended",
		"data": {"weapon": str(profile.get("name", "?"))}})


## Drop the Limited profiles a unit has already fired (wave 5) — the shared pre-filter of BOTH the dice
## resolution and the EV metric, so an expended weapon neither rolls nor sways targeting. Non-Limited
## profiles pass through untouched; with no expenditure this is the identity (byte-identical seam).
func filter_limited(unit: GameUnit, profiles: Array) -> Array:
	var out: Array = []
	for p in profiles:
		var profile := p as Dictionary
		if bool(profile.get("limited", false)) and is_limited_used(unit, profile):
			continue
		out.append(p)
	return out


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


## Human-readable role of an AiArchetype.Type — the decision records carry it so the dev lane shows the
## ROLE reasoning behind an action, not just the branch index (round 7, finding 6b).
static func archetype_role_label(archetype: int) -> String:
	match archetype:
		AiArchetype.Type.MELEE:
			return "melee"
		AiArchetype.Type.HYBRID:
			return "hybrid"
		_:
			return "shooting"


static func alternation_next(pending_replies: int, human_eligible: int, ai_eligible: int) -> AltStep:
	if ai_eligible <= 0:
		return AltStep.END_ROUND if human_eligible <= 0 else AltStep.WAIT
	if pending_replies > 0:
		return AltStep.REPLY
	if human_eligible <= 0:
		return AltStep.TAIL
	return AltStep.WAIT


## OPR round-opener rule (GF/AoF Advanced Rules v3.5.1, "Rounds, Turns & Activations": "On each new round
## the player that finished activating first on the last round gets to activate first."). The side that
## took the LAST activation of a round is precisely the one that finished LAST, so the OTHER side opens the
## next round — which forbids the same side taking a round's last activation AND the next round's first
## (field-test finding 7: the AI activated back-to-back across the round boundary). The former round-parity
## opener ignored who actually went last. If the designated opener has been wiped, the side that still has
## units opens instead. Returns true when the AI should take the FIRST activation of the next round.
static func ai_opens_next_round(ai_took_last_activation: bool, human_has_units: bool, ai_has_units: bool) -> bool:
	if ai_took_last_activation:
		# The human finished first → the human opens; but if the human is wiped, the AI opens.
		return (not human_has_units) and ai_has_units
	# The AI finished first → the AI opens, provided it still has units.
	return ai_has_units


## The owed-AI-reply count at the START of a fresh round (field-test finding 7). Pending replies are a
## PER-ROUND quantity: a new round begins owing ZERO, plus exactly one grant if the AI opens it. The former
## code INCREMENTED a member that could still carry an undeliverable reply from the previous round (the
## human took a round's last activation while the AI was already exhausted), so the opener's grant stacked
## and the AI activated twice back-to-back. Deriving the fresh count from scratch makes that impossible —
## strict one-for-one alternation (GF/AoF v3.5.1 "Rounds, Turns & Activations"). Returns 1 iff the AI opens.
static func pending_replies_at_round_start(ai_opens: bool) -> int:
	return 1 if ai_opens else 0


## Whether a human unit destroyed DURING its own activation must AUTO-COMPLETE that activation (field-test
## round 6, finding 5). A unit wiped by a melee strike-back (or a dangerous-terrain test) while it is the
## currently-activating unit can never be marked activated via the radial toggle — the trigger the alternation
## depends on never fires — so if it was not ALREADY marked, its activation is consumed here and the AI
## receives its one alternating reply. Guarded on `already_activated` so a unit the player pre-toggled (the AI
## already replied) is never double-counted. Pure + unit-testable.
static func human_activation_autocompletes(destroyed: bool, already_activated: bool) -> bool:
	return destroyed and not already_activated


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
## Activation-choreography attention beat (maintainer's explicit staging, field-test finding 7): the fixed
## pause held between each stage of an AI activation — camera focus → (beat) → movement corridors appear →
## (beat) → models glide → (beat) → attacks/abilities resolve. Fast-AI compresses it by PACE_FAST_SCALE
## like every other fixed hold, and it is fully skipped when a pace is 0 (auto-tail stays responsive).
const PACE_ATTENTION_S := 2.0


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


## The activation-choreography attention beat in seconds (PACE_ATTENTION_S), Fast-AI-compressed by
## PACE_FAST_SCALE — the named 2s pause the maintainer asked for between focus → corridors → glide →
## attacks. Static + pure so the staging is unit-testable and the Fast-AI compression is provable.
static func pace_attention_seconds(fast: bool) -> float:
	return PACE_ATTENTION_S * (PACE_FAST_SCALE if fast else 1.0)


## The per-model ROUTE-START positions from a published last_move_paths list (each entry {model, path,
## radius_m}; path[0] is the model's staging position). Field-test finding 2: the model NODES must be
## returned to these START positions BEFORE the camera-focus + announce beat + corridor display, so the
## planned path is shown with the models still at their start — the END STATE must never leak first. The
## logical/broadcast state is already final (the controller applied + synced it); this drives only the
## local visual replay. Pure: returns one Vector3 per input path (skips paths shorter than 2 points).
static func presentation_start_positions(move_paths: Array) -> Array:
	var out: Array = []
	for entry in move_paths:
		var path: Array = (entry as Dictionary).get("path", [])
		if path.size() >= 2:
			out.append(path[0])
	return out


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
			if bool(d.get("ambush_locked", false)):
				continue   # arrived from Ambush THIS round → can't seize or contest (GF/AoF v3.5.1 p.13)
			if bool(d.get("aircraft", false)):
				continue   # an Aircraft can never seize or contest objectives (GF v3.5.1, system-scoped flag)
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


## OPR "Who Can Strike" — BASE-EDGE measure (field-test round 7, finding 3): count `member`'s alive models
## whose base EDGE is within 2" (MELEE_REACH_IN) of ANY enemy base edge, via the shared SeparationChecker
## shapes. The official rule measures model-to-model distance — which OPR takes base to base — so the old
## centre-to-centre test with a fixed 1" contact allowance (striking_models, kept for the sim) excluded any
## BIG base from its own melee: a walker/vehicle base-touching its target had its centre >3" from the enemy's
## and rolled NOTHING while the small-based defender still struck back (the maintainer's one-sided charge).
## Models without a buildable shape fall back to the centre measure with their default radius folded in.
func striking_models_for(member: GameUnit, enemy: GameUnit) -> int:
	if member == null or enemy == null:
		return 0
	var enemy_shapes: Array = []
	for em in _moving_models(enemy):
		var es := SeparationChecker.shape_for_model(em as ModelInstance)
		if es != null:
			enemy_shapes.append(es)
	if enemy_shapes.is_empty():
		return striking_models(alive_positions(member), alive_positions(enemy))
	var n := 0
	for m in member.get_alive_models():
		var shape := SeparationChecker.shape_for_model(m as ModelInstance)
		if shape == null:
			continue
		for es in enemy_shapes:
			if SeparationChecker.edge_distance(shape, es) <= MELEE_REACH_IN:
				n += 1
				break
	return n


## OPR "Who Can Strike" (GF Advanced Rules v3.5.1 p.9, mirrors SoloSim._striking_models): count the striker's
## alive models within 2" (base contact folded in) of ANY enemy model. World positions in METRES. Falls back
## to the whole living set when either side has no positions (a focused test). The REAL-GAME path uses the
## base-edge striking_models_for above (round 7, finding 3); this centre-space form remains for the sim and
## for tests without scene shapes.
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


## Smallest base-to-base EDGE gap (inches) between ANY alive model of `a` (incl. attached heroes) and ANY
## of `b` — the TRUE melee-contact measure via the shared SeparationChecker shapes, replacing the coarse
## unit-centre distance that missed base contact for wide/multi-model units (field-test finding 5: the
## player could not attack an enemy his models were touching). 0 = touching/overlapping; INF when either
## side has no live models.
func nearest_melee_gap_in(a: GameUnit, b: GameUnit) -> float:
	var a_models := _moving_models(a)
	var b_models := _moving_models(b)
	if a_models.is_empty() or b_models.is_empty():
		return INF
	var b_shapes: Array = []
	for bm in b_models:
		var bs := SeparationChecker.shape_for_model(bm as ModelInstance)
		if bs != null:
			b_shapes.append(bs)
	var best := INF
	for am in a_models:
		var ashape := SeparationChecker.shape_for_model(am as ModelInstance)
		if ashape == null:
			continue
		for bs in b_shapes:
			best = minf(best, SeparationChecker.edge_distance(ashape, bs))
	return best


## The nearest charger-model / enemy-model pair, as the base-to-base gap (inches) to close and the world
## table-plane direction (normalised Vector2 x,z) from the charger's nearest model toward the enemy's. Uses
## the shared SeparationChecker shapes — the ONE base-contact truth behind both the charge move (finding 3)
## and the snap. gap == INF / dir == ZERO when either side has no live shapes (degenerate).
func nearest_charge_vector(charger: GameUnit, target: GameUnit) -> Dictionary:
	var best_gap := INF
	var best_dir := Vector2.ZERO
	var enemy_shapes: Array = []
	for em in _moving_models(target):
		var es := SeparationChecker.shape_for_model(em as ModelInstance)
		if es != null:
			enemy_shapes.append(es)
	for cm in _moving_models(charger):
		var cs := SeparationChecker.shape_for_model(cm as ModelInstance)
		if cs == null:
			continue
		for es in enemy_shapes:
			var gap: float = SeparationChecker.edge_distance(cs, es)
			if gap < best_gap:
				best_gap = gap
				best_dir = ((es as SeparationChecker.BaseShape).center - (cs as SeparationChecker.BaseShape).center)
	if best_dir.length() < 0.00001:
		return {"gap": best_gap, "dir": Vector2.ZERO}
	return {"gap": best_gap, "dir": best_dir.normalized()}


## Charge the unit into base contact (field-test finding 3 + charge-reach fix): the former "move toward the
## enemy centre, capped at the band" closed the CENTRE gap but left the nearest bases short. Measure the REAL
## base-to-base gap and the nearest-pair direction, AIM the nearest models at exact base contact (goal =
## contact point along that line), and grant the move the FULL charge band as its arc budget — NOT the tight
## straight-line gap. The old code used `travel` (gap + a hair) as both the aim AND the arc budget, so any
## DETOUR around an obstacle / other unit / a large enemy base (arc > straight gap) starved the charge and it
## fell 1–5" short (worse for large bases: bigger detours). With the full band as the arc allowance the route
## bends around and still closes to contact; the target's body-only planner zone clamps the stop AT contact,
## never through (GF/AoF v3.5.1 p.8), and the contact-aimed slot stops a straight charge from overrunning.
## Difficult terrain on the forced path still caps the whole move at 6" (p.11). Returns the Dangerous count.
func _charge_move(unit: GameUnit, target: GameUnit, band_in: float) -> int:
	var nv := nearest_charge_vector(unit, target)
	var gap: float = float(nv.get("gap", INF))
	var dir: Vector2 = nv.get("dir", Vector2.ZERO)
	if gap == INF or dir == Vector2.ZERO:
		return _move_toward(unit, unit_centre(target), band_in, true, target)   # degenerate → old aim
	# AIM the nearest model at the target's contact boundary (gap closed), NOT 0.25" inside it: a slot INSIDE
	# the target's body-only zone is an unreachable Theta* goal, so the router returned a straight line and the
	# model STALLED at the first obstacle instead of bending around it (the detour never happened). Aimed at
	# the boundary the goal is reachable, the route bends around obstacles, and the model lands at contact; any
	# sub-epsilon residual is closed by the melee snap (snap_charge, within MELEE_ENGAGE_IN). Capped at the band.
	var travel := minf(band_in, gap)
	var centre := unit_centre(unit)
	var goal := centre + Vector3(dir.x, 0.0, dir.y) * (travel * INCHES_TO_METERS)
	return _move_toward(unit, goal, band_in, true, target)


## Charge snap (field-test finding 5): rigidly translate the whole charging unit so its NEAREST model lands
## in clean base contact with the nearest enemy model, PRESERVING formation and thereby bringing the rest of
## the unit forward in coherency — GF/AoF v3.5.1 p.8: "Charging models must move … to get into base contact
## with an enemy model … or as close as possible, whilst still maintaining unit coherency." (The defender's
## own pull-in — "all models from the target unit that are not in base contact … must move by up to 3” to
## get into base contact … maintaining unit coherency", p.9 — is a SEPARATE rule, surfaced as a reminder.)
## A rigid translation keeps every relative spacing, so coherency is preserved by construction. Returns the
## snap distance in inches (0 when already in contact, or nothing to move). Positions broadcast for MP.
func snap_charge(charger: GameUnit, target: GameUnit) -> float:
	var models := _moving_models(charger)
	if models.is_empty():
		return 0.0
	var nv := nearest_charge_vector(charger, target)
	var best_gap: float = float(nv.get("gap", INF))
	var best_dir: Vector2 = nv.get("dir", Vector2.ZERO)
	if best_gap <= SeparationChecker.BASE_CONTACT_EPSILON_INCHES or best_gap == INF or best_dir == Vector2.ZERO:
		return 0.0   # already in clean contact (or degenerate) — nothing to snap
	var delta2 := best_dir * (best_gap * INCHES_TO_METERS)
	var delta := Vector3(delta2.x, 0.0, delta2.y)
	var positions := _positions_of(models)
	var moved: Array = []
	for p in positions:
		moved.append((p as Vector3) + delta)
	_apply_model_positions(models, moved)
	return best_gap


## Whether the MAJORITY of a unit's alive models sit in cover terrain (GF/AoF Advanced Rules v3.5.1 p.11:
## "If the majority of models in a unit are fully inside a piece of cover terrain … they get +1 to Defense
## rolls when blocking hits from shooting attacks."). Reads the REAL overlay via the injected
## terrain_type_at (the TerrainRules.gives_cover predicate — Forests + Ruins), so the EV metric sees true
## terrain instead of a constant (field-test finding 6). False when no terrain callback is wired.
func majority_in_cover(unit: GameUnit) -> bool:
	if unit == null or not terrain_type_at.is_valid():
		return false
	var models := unit.get_alive_models()
	if models.is_empty():
		return false
	var n := 0
	for m in models:
		var node := (m as ModelInstance).node
		if node != null and is_instance_valid(node) \
				and TerrainRules.gives_cover(int(terrain_type_at.call((node as Node3D).global_position))):
			n += 1
	return n * 2 > models.size()   # strict majority (p.11)


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
			u.unit_properties["ambush_reserve"] = true   # held off-table → not activatable until it arrives
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
		var footprint := _deploy_footprint_offsets(unit)   # exact per-model grid → checks every base (finding 1)
		var base_r := _deploy_base_radius(_deploy_models(unit))
		var ignores_terrain: bool = unit.has_special_rule("Strider") or unit.has_special_rule("Flying")
		var blocked := blocked_flying if ignores_terrain else blocked_normal
		var spot := AiDeployment.best_spot(sec, objectives, occupied, radius, blocked, 0.025, radius, footprint, base_r)
		var spot_why := "best legal spot toward nearest objective (section)"
		if spot == Vector2.INF:
			spot = AiDeployment.best_spot(zone, objectives, occupied, radius, blocked, 0.025, radius, footprint, base_r)
			spot_why = "section full — whole-zone fallback"
		if spot == Vector2.INF:
			# Crowded out of every spaced spot: relax the 1" spacing (allow neighbours to bunch) but STILL
			# reject blocking/impassable terrain — the army MUST deploy, yet a legal footprint always beats
			# a spot inside a wall/forest (field-test finding 3: units deployed inside blocking terrain).
			spot = AiDeployment.best_spot(zone, objectives, [], radius, blocked, 0.025, radius, footprint, base_r)
			spot_why = "crowded — nearest legal (non-terrain) spot, spacing relaxed"
		if spot == Vector2.INF:
			# Truly no fully terrain-legal cell anywhere (a terrain-choked table) — must still deploy, so pick
			# the CLEAREST ground: the spot with the fewest model bases in blocking/dangerous terrain (finding
			# 1: the old last resort dumped the unit blindly at the section centre, which sat inside a ruin).
			spot = AiDeployment.least_blocked_spot(zone, objectives, radius, blocked, 0.05, base_r, footprint)
			spot_why = "terrain-choked — clearest (least-blocked) ground in the zone"
		_place_unit_at(unit, spot)
		record_decision({"kind": "deploy", "unit": unit.get_name(),
			"rule": "Solo v3.5.0 AI deployment: objective-near spot in the unit's section; Scout/Ambush overlays",
			"candidates": [], "chosen": "", "why": spot_why,
			"data": {"section": int(section_of.get(int(id), 2)), "x_m": spot.x, "z_m": spot.y}})
		occupied.append({"pos": spot, "radius": radius})
		deployed += 1
	# Clear any residual base overlap the spacing-relaxed "must deploy" fallbacks leave behind (self-play R0:
	# two crowded units deployed stacked) — the same ZERO-overlap invariant the move gate enforces (finding 3),
	# so a unit never STARTS a game overlapping a neighbour (which would then poison the coherency-shorten every
	# round). Terrain-aware; regiments keep their rigid tray.
	_resolve_deploy_overlaps()
	return {"deployed": deployed, "reserved": ambush_reserve.size(), "seed": seed_value}


## Post-deploy absolute overlap cleanup (field-test finding 3 — "ZERO overlapping bases after every AI
## move/deploy"). Each non-regiment on-table unit is un-stacked as a RIGID WHOLE-UNIT translation (all its
## models shifted by one vector via SeparationResolver, escape-scan-guaranteed) so it clears every other
## on-table base WITHOUT disturbing its own formation — a per-model push here would spread the compact deploy
## grid and break the unit's coherency (self-play v4 lesson). A few Gauss-Seidel sweeps let a cluster settle;
## a model the shift lands in forbidden terrain is nudged out individually (rare — deployment already avoids
## terrain). Regiments keep their rigid tray. Uses the REAL base shapes the audit measures.
func _resolve_deploy_overlaps() -> void:
	if army_manager == null:
		return
	for _sweep in range(OVERLAP_GATE_PASSES):
		for u in army_manager.get_all_game_units():
			var unit := u as GameUnit
			if unit == null or unit.get_alive_count() <= 0 or unit_in_reserve(unit):
				continue
			if _is_regiment(unit) or (unit.has_method("is_attached") and unit.is_attached()):
				continue
			var models := _moving_models(unit)
			if models.is_empty():
				continue
			var cfg: Array = _positions_of(models)
			# (a) INTERNAL: separate the unit's OWN overlapping bases just to contact (a tight deploy grid can
			# pack a large-based model into its neighbour). Pushing only to edge ≈ 0 keeps every pair within the
			# 1" coherency link, so it never spreads the unit out of coherency (unlike an unbounded per-model push).
			var own_shapes := _moving_shapes_at(models, cfg)
			for _p in range(OVERLAP_GATE_PASSES):
				for i in range(own_shapes.size()):
					var others: Array = []
					for j in range(own_shapes.size()):
						if j != i:
							others.append(own_shapes[j])
					SeparationResolver.resolve_overlaps([own_shapes[i]], others)
			for i in range(cfg.size()):
				var oc: Vector2 = (own_shapes[i] as SeparationChecker.BaseShape).center
				cfg[i] = Vector3(oc.x, (cfg[i] as Vector3).y, oc.y)
			# (b) EXTERNAL: shift the WHOLE unit as one rigid item to clear every OTHER unit's bases — one
			# translation, formation intact (a per-model external push would spread the grid out of coherency).
			var shapes := _moving_shapes_at(models, cfg)
			var delta := SeparationResolver.resolve_overlaps(shapes, _external_obstacle_shapes(unit))
			for i in range(cfg.size()):
				var p: Vector3 = cfg[i]
				cfg[i] = _project_out_forbidden_world(Vector3(p.x + delta.x, p.y, p.z + delta.y),
					model_base_radius_m(models[i] as ModelInstance))
			# (c) The per-model terrain-out above pushes each base out of terrain by its own EDGE (finding 6), so
			# it can nudge two own bases into overlap. Re-separate the unit's OWN bases to contact so deploy NEVER
			# leaves an intra-unit stack (field-test finding 3) — a deploy overlap would otherwise persist every
			# round, because each move's coherency-shorten retreats toward the (overlapping) deploy START.
			var reshapes := _moving_shapes_at(models, cfg)
			for _q in range(OVERLAP_GATE_PASSES):
				for i in range(reshapes.size()):
					var others2: Array = []
					for j in range(reshapes.size()):
						if j != i:
							others2.append(reshapes[j])
					SeparationResolver.resolve_overlaps([reshapes[i]], others2)
			for i in range(cfg.size()):
				var rc: Vector2 = (reshapes[i] as SeparationChecker.BaseShape).center
				cfg[i] = Vector3(rc.x, (cfg[i] as Vector3).y, rc.y)
			_apply_model_positions(models, cfg)


const AMBUSH_MIN_ENEMY_DIST_M := 0.2286   # OPR: Ambush arrivals deploy MORE THAN 9" from enemy units


## OPR Ambush (GF/AoF Advanced Rules v3.5.1 p.13): reserved units arrive at the start of ANY round after
## the first, placed by the same deploy rules (near the nearest objective, avoiding blocked terrain,
## reusing the context stashed by deploy_army) but strictly MORE THAN 9" from any enemy. A unit with no
## legal spot on a crowded table stays in reserve for a LATER round (the p.13 "any round after the first").
## Batch form (kept for headless tests): loops the paced per-unit arrival. `arrival_zone` is the whole
## table; `enemy_positions` are enemy unit centres in table XZ. Returns {arrived (count), arrived_units,
## still_reserved}.
func arrive_ambush_reserve(arrival_zone: Rect2, enemy_positions: Array) -> Dictionary:
	var occupied: Array = []
	var round_no: int = army_manager.current_round if army_manager != null else 1
	var arrived: Array = []
	while true:
		var u := arrive_one_ambush_unit(arrival_zone, enemy_positions, occupied, round_no)
		if u == null:
			break
		arrived.append(u)
	return {"arrived": arrived.size(), "arrived_units": arrived, "still_reserved": ambush_reserve.size()}


## Bring in the NEXT reserve Ambush unit that has a legal spot — the PACED arrival step (field-test
## finding 4: arrival must be its own announced, camera-focused, paused beat, one unit at a time, not a
## silent simultaneous drop). Places the unit >9" from every enemy (AMBUSH_MIN_ENEMY_DIST_M), near an
## objective, out of blocking terrain (reusing the deploy context), then:
##   • clears its `ambush_reserve` flag so it becomes ACTIVATABLE this same round — arriving from Ambush is
##     DEPLOYMENT, NOT an activation (GF/AoF v3.5.1 p.13; field-test finding 5: the unit could act again);
##   • stamps `ambush_arrived_round` so seize_objectives can honour "Units that deploy via Ambush can't
##     seize or contest objectives on the round they deploy" (p.13).
## `occupied` accumulates placed footprints across calls (seeded once with the enemies' 9" no-go rings), so
## successive arrivals don't stack. Returns the arrived unit, or null when no remaining reserve unit fits
## right now (those stay reserved for a later round).
func arrive_one_ambush_unit(arrival_zone: Rect2, enemy_positions: Array, occupied: Array, round_no: int) -> GameUnit:
	if occupied.is_empty():
		for e in enemy_positions:
			occupied.append({"pos": e, "radius": AMBUSH_MIN_ENEMY_DIST_M})
	var remaining: Array = []
	var arrived: GameUnit = null
	for u in ambush_reserve:
		var unit: GameUnit = u
		if unit == null or unit.get_alive_count() <= 0:
			continue   # a reserve unit destroyed before arrival is simply gone
		if arrived != null:
			remaining.append(unit)
			continue   # one arrival per call (the caller paces each) — keep the rest reserved
		if _try_place_reserve_unit(unit, arrival_zone, occupied, round_no):
			arrived = unit
		else:
			remaining.append(unit)   # no legal spot this round — hold for a later one (p.13)
	ambush_reserve = remaining
	return arrived


## Place ONE reserve unit at a legal Ambush-arrival spot (GF/AoF v3.5.1 p.13): near an objective, out of
## blocking terrain (reusing the stashed deploy context), and — because the caller seeds `occupied` with the
## enemies' 9" no-go rings — strictly MORE THAN 9" from every enemy. On success clears the unit's reserve
## flag (activatable this round), stamps its arrival round (no seize/contest this round), appends its
## footprint to `occupied`, records the decision, and returns true. Returns false (the unit stays reserved)
## when no legal spot exists right now. Shared by the AI's paced arrival and the human's guided arrival.
func _try_place_reserve_unit(unit: GameUnit, arrival_zone: Rect2, occupied: Array, round_no: int) -> bool:
	var no_block := func(_p: Vector2) -> bool: return false
	var ignores_terrain: bool = unit.has_special_rule("Strider") or unit.has_special_rule("Flying")
	var blocked: Callable = _deploy_blocked_flying if ignores_terrain else _deploy_blocked_normal
	if not blocked.is_valid():
		blocked = no_block
	var radius := _deploy_footprint_radius(unit)
	var footprint := _deploy_footprint_offsets(unit)   # per-model footprint (finding 1)
	var base_r := _deploy_base_radius(_deploy_models(unit))
	var spot := AiDeployment.best_spot(arrival_zone, _deploy_objectives, occupied, radius, blocked, 0.025, radius, footprint, base_r)
	if spot == Vector2.INF:
		return false
	_place_unit_at(unit, spot)
	occupied.append({"pos": spot, "radius": radius})
	unit.unit_properties["ambush_reserve"] = false          # on the table now → activatable this round
	unit.unit_properties["ambush_arrived_round"] = round_no  # can't seize/contest objectives this round
	record_decision({"kind": "deploy", "unit": unit.get_name(),
		"rule": "GF/AoF v3.5.1 p.13 Ambush: arrive start of a round after the first, >9\" from enemies",
		"candidates": [], "chosen": "", "why": "ambush arrival (does not consume its activation)",
		"data": {"round": round_no, "x_m": spot.x, "z_m": spot.y}})
	return true


# === Human Ambush reserves (field-test finding 5 — the game must ASK) ========================

## The human's units still HELD in Ambush reserve (off-table, undeployed). The `ambush_reserve` flag is the
## single truth for BOTH sides (unit_in_reserve); the AI keeps its own paced `ambush_reserve` LIST, while
## the human's reserves are queried on demand from the army. GF/AoF v3.5.1 p.13.
func human_reserve_units() -> Array:
	var out: Array = []
	if army_manager == null:
		return out
	for u in army_manager.get_game_units_for_player(human_slot):
		var gu := u as GameUnit
		if gu != null and not gu.is_destroyed() and unit_in_reserve(gu):
			out.append(gu)
	return out


## Set aside the human's Ambush-rule units into reserve (GF/AoF v3.5.1 p.13: "May be set aside before
## deployment"), mirroring the AI's deploy_army handling so the human gets the same off-table reserve and
## round-2+ arrival prompt. Skips attached heroes (they deploy with their host) and already-reserved units.
## Returns the units newly set aside; the caller hides them + syncs. Idempotent.
func set_aside_human_ambush() -> Array:
	var out: Array = []
	if army_manager == null:
		return out
	for u in army_manager.get_game_units_for_player(human_slot):
		var gu := u as GameUnit
		if gu == null or gu.is_destroyed() or unit_in_reserve(gu):
			continue
		if gu.has_method("is_attached") and gu.is_attached():
			continue
		if gu.has_special_rule("Ambush"):
			gu.unit_properties["ambush_reserve"] = true
			out.append(gu)
	return out


## Should the game PROMPT the human to deploy Ambush reserves? GF/AoF v3.5.1 p.13: reserve units MAY be
## deployed at the start of ANY round after the first. Pure decision so the trigger is unit-testable.
static func should_prompt_human_ambush(round_number: int, undeployed_count: int) -> bool:
	return round_number >= 2 and undeployed_count > 0


## Guided arrival of ONE human Ambush-reserve unit (finding 5): seed `occupied` with the AI enemies' 9"
## no-go rings and place the unit >9" from them, near an objective, terrain-legal — the same legal core as
## the AI arrival. Returns true if placed (the caller reveals + syncs the unit). GF/AoF v3.5.1 p.13.
func arrive_human_reserve_unit(unit: GameUnit, arrival_zone: Rect2, enemy_positions: Array,
		occupied: Array, round_no: int) -> bool:
	if unit == null or unit.get_alive_count() <= 0 or not unit_in_reserve(unit):
		return false
	if occupied.is_empty():
		for e in enemy_positions:
			occupied.append({"pos": e, "radius": AMBUSH_MIN_ENEMY_DIST_M})
	return _try_place_reserve_unit(unit, arrival_zone, occupied, round_no)


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


## Footprint radius of the COMPACT grid the unit takes at deployment (not its staging formation). Includes
## the outer models' BASE radius so the whole footprint — bases, not just centres — is measured for clear
## ground and spacing (field-test finding 1: a model centre cleared terrain but its base overlapped it).
func _deploy_footprint_radius(unit: GameUnit) -> float:
	var models: Array = _deploy_models(unit)
	var n: int = maxi(models.size(), 1)
	var cols: int = mini(n, DEPLOY_COLS)
	var rows: int = int(ceil(float(n) / float(DEPLOY_COLS)))
	var half_w: float = float(cols - 1) * DEPLOY_SPACING_M * 0.5
	var half_d: float = float(rows - 1) * DEPLOY_SPACING_M * 0.5
	return sqrt(half_w * half_w + half_d * half_d) + _deploy_base_radius(models) + 0.01


## The largest base radius (metres) among a unit's deployment models — the per-model base extent the
## footprint check inflates each grid cell by (SeparationChecker shape truth; 32 mm fallback).
func _deploy_base_radius(models: Array) -> float:
	var r: float = SeparationChecker.DEFAULT_BASE_RADIUS_M
	for m in models:
		r = maxf(r, model_base_radius_m(m as ModelInstance))
	return r


## The model-local XZ offsets (metres, relative to the drop anchor) that the unit's models WILL occupy at
## deployment — the EXACT compact grid `_place_unit_at` builds, so the footprint check tests where each
## model actually lands. Empty for a regiment (its rigid tray reforms — the footprint circle covers it).
func _deploy_footprint_offsets(unit: GameUnit) -> Array:
	if _is_regiment(unit):
		return []
	var n: int = _deploy_models(unit).size()
	var offsets: Array = []
	if n == 0:
		return offsets
	var cols: int = mini(n, DEPLOY_COLS)
	var rows: int = int(ceil(float(n) / float(DEPLOY_COLS)))
	for i in range(n):
		var col: int = i % DEPLOY_COLS
		var row: int = i / DEPLOY_COLS
		offsets.append(Vector2(
			(float(col) - float(cols - 1) * 0.5) * DEPLOY_SPACING_M,
			(float(row) - float(rows - 1) * 0.5) * DEPLOY_SPACING_M))
	return offsets


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

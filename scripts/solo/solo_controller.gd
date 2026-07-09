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


func is_eligible(unit) -> bool:
	var u := unit as GameUnit
	return u != null and not u.is_activated and not u.is_destroyed()


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
## then a random eligible unit in that section (seeded _rng → reproducible).
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
	return section[_rng.randi_range(0, section.size() - 1)]


## Nearest valid human unit to `ai_unit` (centre-to-centre), PREFERRING not-yet-activated targets — the
## OPR Solo & Co-Op v3.5.0 targeting rule (nearest valid enemy, prefer un-activated). Falls back to the
## nearest activated unit if every human unit has already acted. Null if none alive.
func nearest_human_unit(ai_unit: GameUnit) -> GameUnit:
	if army_manager == null:
		return null
	var from := unit_centre(ai_unit)
	var best_fresh: GameUnit = null
	var best_fresh_d := INF
	var best_any: GameUnit = null
	var best_any_d := INF
	for h in army_manager.get_game_units_for_player(human_slot):
		var hu := h as GameUnit
		if hu == null or hu.is_destroyed():
			continue
		var d := MoveIntent.distance_inches(from, unit_centre(hu))
		if d < best_any_d:
			best_any_d = d
			best_any = hu
		if not hu.is_activated and d < best_fresh_d:
			best_fresh_d = d
			best_fresh = hu
	return best_fresh if best_fresh != null else best_any


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
	var archetype := AiArchetype.classify(weapons)
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
	# Relentless overlay (Solo & Co-Op Rules v3.5.0 p.2): a Relentless ranged weapon in range → Hold and shoot.
	if _forces_hold_and_shoot(weapons, shoot_range > 0 and enemy_dist <= float(shoot_range)):
		action = AiDecision.Action.HOLD
		do_shoot = true
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
			dang = _move_toward(unit, tcentre, rush, true)
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
func _move_toward(unit: GameUnit, goal_world: Vector3, inches: float, allow_contact: bool) -> int:
	if is_zero_approx(inches):
		return 0
	return _execute_move(unit, _clamp_to_bounds(goal_world), inches, allow_contact)


## Rigid move directly AWAY from `from_world` by `inches` (the shooter "stay at range edge" step), clamped.
func _move_away(unit: GameUnit, from_world: Vector3, inches: float) -> int:
	if is_zero_approx(inches):
		return 0
	var centre := unit_centre(unit)
	var goal := centre + (centre - _clamp_to_bounds(from_world))
	return _execute_move(unit, _clamp_to_bounds(goal), inches, false)


## Shared move executor: Difficult-halve, rigid clamp, wall-aware planning (loose units), apply + broadcast,
## and count Dangerous crossings. Returns that Dangerous-crossing model count.
func _execute_move(unit: GameUnit, goal: Vector3, inches: float, allow_contact: bool) -> int:
	var positions := alive_positions(unit)
	if positions.is_empty():
		return 0
	var centre := unit_centre(unit)
	# Difficult terrain (GF Advanced Rules v3.5.1 p.11): a move whose straight path crosses it is halved.
	var reach := inches
	if _path_crosses_terrain(centre, goal, TerrainRules.PathCheck.DIFFICULT):
		reach = inches * 0.5
	var delta := MoveIntent.plan_unit_move(positions, goal, reach)
	delta = _clamp_delta_to_bounds(positions, delta)
	if delta == Vector3.ZERO:
		return 0
	var new_positions := _plan_positions(unit, positions, delta, allow_contact)
	var dang := _count_dangerous(positions, new_positions)
	_apply_model_positions(unit, new_positions)
	return dang


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


## Set each alive model node to its planned world position (Y preserved) + broadcast the batch. The planned
## array is aligned to get_alive_models() order (same order alive_positions() produced it in).
func _apply_model_positions(unit: GameUnit, new_positions: Array) -> void:
	var batch: Array = []
	var models := unit.get_alive_models()
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


## Plan the per-model destination positions for a move by rigid `delta`. Fast path (no walls, a regiment, or
## no wall in the path) = the exact rigid slide (byte-identical to the old block move). A LOOSE unit whose
## rigid path crosses a wall steers each model around it in coherency via the shared MovementPlanner (run in
## the planner's 0-origin inch frame, then mapped back to world metres).
func _plan_positions(unit: GameUnit, positions: Array, delta: Vector3, allow_contact: bool) -> Array:
	var rigid: Array = []
	for p in positions:
		rigid.append((p as Vector3) + delta)
	if _is_regiment(unit):
		return rigid   # a regiment moves as its rigid tray block — no individual steering
	var walls_world: Array = _walls_world()
	if walls_world.is_empty():
		return rigid
	# Map world XZ (metres, centred at 0) into the planner's non-negative inch frame: shift by the table
	# half-extents, then divide by the inch scale. board_in is the larger table extent in inches.
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
	if not MovementPlanner.rigid_blocked(mpos, mdelta, walls_in):
		return rigid
	var planned: Array = MovementPlanner.plan_unit_step(mpos, mdelta, walls_in, {}, allow_contact, board_in)
	var out: Array = []
	for i in range(positions.size()):
		var pi: Vector2 = mpos[i]
		if i < planned.size():
			pi = planned[i]
		var world := (pi * INCHES_TO_METERS) - off
		var src: Vector3 = positions[i]
		out.append(Vector3(world.x, src.y, world.y))
	return out


## Count alive models whose path (old → new position) crossed Dangerous terrain (main rolls the real tests).
func _count_dangerous(old_positions: Array, new_positions: Array) -> int:
	var n := 0
	for i in range(mini(old_positions.size(), new_positions.size())):
		if _path_crosses_terrain(old_positions[i], new_positions[i], TerrainRules.PathCheck.DANGEROUS):
			n += 1
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


## OPR "Determine Attacks" (mirrors SoloSim._effective_attacks): only living models' weapons count, so scale
## a weapon group's attacks by alive/max. Pure — used by the real combat path to stop dead models attacking.
static func effective_attacks(base_attacks: int, alive: int, max_models: int) -> int:
	if max_models <= 0:
		return base_attacks
	return maxi(0, int(round(float(base_attacks) * float(alive) / float(max_models))))


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
		if spot == Vector2.INF:
			spot = AiDeployment.best_spot(zone, objectives, occupied, radius, blocked, 0.025, radius)
		if spot == Vector2.INF:
			# The army MUST deploy (rule) — worst case the unit forms up at its section centre even if
			# that crowds neighbours; never silently skip a unit again.
			spot = sec.get_center()
		_place_unit_at(unit, spot)
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

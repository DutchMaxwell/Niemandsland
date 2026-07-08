class_name SoloController
extends Node
## Solo/AI Milestone 1 — the "walking skeleton". Drives one army (the AI slot) through the shared
## TurnManager: on the AI's activation it picks an un-activated, non-destroyed unit, finds the nearest
## alive human unit, and rigidly advances the whole unit toward it by its OPR Advance distance (clamped
## to the movement allowance AND the table bounds), then marks it activated and hands the turn back.
##
## M1 is MOVEMENT ONLY — no shooting / charging / dice / morale / behaviour tables / pathfinding
## (deferred to M2+). It REUSES: MoveIntent (pure rigid-move planning), MovementRangeController (Advance
## inches), ActivationSelector (which unit), TurnManager (alternating-activation engine), GameUnit /
## OPRArmyManager (state), and NetworkManager.broadcast_move_batch / broadcast_unit_activation (sync).

signal ai_unit_activated(unit: GameUnit)   # emitted after the AI moves + activates a unit (for UI/log)

const BOUNDS_MARGIN_M := 0.02   # keep models a hair inside the table edge

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

var turn_manager: TurnManager = null
var _selector: ActivationSelector = null
var _rng := RandomNumberGenerator.new()


func setup(p_army_manager: OPRArmyManager, p_network_manager: Node, p_movement_range: MovementRangeController,
		p_human_slot: int = 1, p_ai_slot: int = 2) -> void:
	army_manager = p_army_manager
	network_manager = p_network_manager
	movement_range = p_movement_range
	human_slot = p_human_slot
	ai_slot = p_ai_slot
	_selector = ActivationSelector.new()
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


## Move + activate the next eligible AI unit (nearest human target, Advance distance). Returns the unit,
## or null when the AI has no eligible units left.
func activate_next_ai_unit() -> GameUnit:
	var eligible := eligible_ai_units()
	if eligible.is_empty():
		return null
	var unit := _selector.select(eligible, _rng) as GameUnit
	if unit == null:
		return null
	last_report = _act(unit)
	mark_activated(unit)
	if network_manager != null and network_manager.has_method("broadcast_unit_activation"):
		network_manager.broadcast_unit_activation(unit)
	if turn_manager != null:
		turn_manager.notify_activated(unit)
	ai_unit_activated.emit(unit)
	return unit


func eligible_ai_units() -> Array:
	var out: Array = []
	if army_manager == null:
		return out
	for u in army_manager.get_game_units_for_player(ai_slot):
		if is_eligible(u):
			out.append(u)
	return out


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


## One activation by the official decision tree (goal 001 P3): classify the archetype, decide the
## action (charge/advance/rush/kite), execute the move, and report what happened so main can resolve
## shooting (and, in P4, the charge melee). CHARGE degrades to its move-only part until P4 lands.
func _act(unit: GameUnit) -> Dictionary:
	var report := {"unit": unit, "target": null, "action": AiDecision.Action.HOLD, "can_shoot": false, "dist_in": INF}
	var target_unit := nearest_human_unit(unit)
	if target_unit == null or alive_positions(unit).is_empty():
		return report
	report["target"] = target_unit
	var weapons := _unit_weapons(unit)
	var bands: Dictionary = {"advance": 6, "rush": 12}
	if movement_range != null:
		bands = movement_range.move_bands_for_props(unit.unit_properties)
	var dist := MoveIntent.distance_inches(unit_centre(unit), unit_centre(target_unit))
	var shoot_range := AiArchetype.max_range_inches(weapons)
	var in_range_los: bool = shoot_range > 0 and dist <= float(shoot_range) and _has_los(unit, target_unit)
	var action := AiDecision.decide(AiArchetype.classify(weapons), dist, float(bands.get("advance", 6)),
		float(bands.get("rush", 12)), float(shoot_range), in_range_los)
	report["action"] = action
	match action:
		AiDecision.Action.ADVANCE:
			_move_relative(unit, target_unit, float(bands.get("advance", 6)))
		AiDecision.Action.RUSH, AiDecision.Action.CHARGE:
			_move_relative(unit, target_unit, float(bands.get("rush", 12)))
		AiDecision.Action.KITE:
			# Fall back just far enough to stay in range: never further than (range - dist) leaves room.
			var room: float = maxf(float(shoot_range) - dist, 0.0)
			_move_relative(unit, target_unit, -minf(float(bands.get("advance", 6)), room))
		_:
			pass   # HOLD: no move (M3 overlays)
	# Shooting eligibility AFTER the move — Rush/Charge cannot shoot (charge resolves in melee, P4).
	if action == AiDecision.Action.ADVANCE or action == AiDecision.Action.KITE or action == AiDecision.Action.HOLD:
		var d2 := MoveIntent.distance_inches(unit_centre(unit), unit_centre(target_unit))
		report["dist_in"] = d2
		report["can_shoot"] = shoot_range > 0 and d2 <= float(shoot_range) and _has_los(unit, target_unit)
	return report


## Rigid move toward (positive inches) or away from (negative inches) the target unit, table-clamped.
func _move_relative(unit: GameUnit, target_unit: GameUnit, inches: float) -> void:
	if is_zero_approx(inches):
		return
	var positions := alive_positions(unit)
	if positions.is_empty():
		return
	var centre := unit_centre(unit)
	var toward := _clamp_to_bounds(unit_centre(target_unit))
	var goal := toward if inches > 0.0 else centre + (centre - toward)
	var delta := MoveIntent.plan_unit_move(positions, _clamp_to_bounds(goal), absf(inches))
	delta = _clamp_delta_to_bounds(positions, delta)
	_apply_delta(unit, delta)


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


## Apply a rigid world-space delta to every alive model node (Y preserved) + broadcast the batch.
func _apply_delta(unit: GameUnit, delta: Vector3) -> void:
	if delta == Vector3.ZERO:
		return
	var batch: Array = []
	for m in unit.get_alive_models():
		var node := (m as ModelInstance).node
		if node == null or not is_instance_valid(node):
			continue
		node.global_position += delta
		if node.has_meta("network_id"):
			batch.append(node.get_meta("network_id"))
			batch.append(node.global_position.x)
			batch.append(node.global_position.y)
			batch.append(node.global_position.z)
	if network_manager != null and not batch.is_empty() and network_manager.has_method("broadcast_move_batch"):
		network_manager.broadcast_move_batch(batch)


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

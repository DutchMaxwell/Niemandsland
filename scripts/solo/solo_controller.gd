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
	_advance_toward_nearest_human(unit)
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


func _advance_toward_nearest_human(unit: GameUnit) -> void:
	var target_unit := nearest_human_unit(unit)
	if target_unit == null:
		return
	var positions := alive_positions(unit)
	if positions.is_empty():
		return
	var advance_inches := 6
	if movement_range != null:
		advance_inches = int(movement_range.move_bands_for_props(unit.unit_properties).get("advance", 6))
	var target := _clamp_to_bounds(unit_centre(target_unit))
	var delta := MoveIntent.plan_unit_move(positions, target, float(advance_inches))
	delta = _clamp_delta_to_bounds(positions, delta)
	_apply_delta(unit, delta)


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

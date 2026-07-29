class_name UndoManager
extends Node
## Central undo/redo history for table actions (delete, move, rotate).
##
## The undo/redo *stacks are local* to this client. Each action re-applies its
## effect to the shared game state and re-broadcasts the result to peers through
## NetworkManager, so multiplayer stays consistent ("delete syncs, undo local").
##
## Recorded actions only ever HIDE models/objects (casualty semantics) — they
## never free nodes — which is what keeps every action reversible.

# === Constants ===

## Maximum number of actions kept in the undo history (oldest are dropped).
const MAX_HISTORY: int = 100

# === Signals ===

## Emitted after any change to the history (push / undo / redo / clear), so UI
## can enable or disable its undo/redo affordances.
signal history_changed(can_undo: bool, can_redo: bool)

## An undo was actually performed (history_changed cannot distinguish push from
## undo). Seam for listeners that react to the ACT of undoing — e.g. the tutorial's
## "press Ctrl+Z" step — carrying the undone action's description.
signal action_undone(description: String)

# === Private variables ===

var _undo_stack: Array[UndoableAction] = []
var _redo_stack: Array[UndoableAction] = []

# === Public API ===

## Records an action that has *already been performed*. Starts a new branch, so
## the redo stack is discarded.
func push(action: UndoableAction) -> void:
	if action == null:
		return
	_undo_stack.append(action)
	if _undo_stack.size() > MAX_HISTORY:
		_undo_stack.pop_front()
	_redo_stack.clear()
	_emit_changed()


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


## Whether the given player has any of their OWN actions to undo/redo. In
## multiplayer each player only undoes what they did themselves.
func can_undo_for(peer_id: int) -> bool:
	for action in _undo_stack:
		if action.peer_id == peer_id:
			return true
	return false


func can_redo_for(peer_id: int) -> bool:
	for action in _redo_stack:
		if action.peer_id == peer_id:
			return true
	return false


## Reverts the most recent action. Returns its description, or "" if the undo
## stack is empty.
func undo() -> String:
	if _undo_stack.is_empty():
		return ""
	var action: UndoableAction = _undo_stack.pop_back()
	action.undo()
	if action.redoable:
		_redo_stack.append(action)
	_emit_changed()
	action_undone.emit(action.description)
	return action.description


## Reverts the most recent action OWNED BY peer_id, skipping other players'
## actions (they stay on the stack). Returns its description, or "" if the player
## has nothing of their own to undo.
func undo_for(peer_id: int) -> String:
	for i in range(_undo_stack.size() - 1, -1, -1):
		if _undo_stack[i].peer_id == peer_id:
			var action: UndoableAction = _undo_stack[i]
			_undo_stack.remove_at(i)
			action.undo()
			if action.redoable:
				_redo_stack.append(action)
			_emit_changed()
			action_undone.emit(action.description)
			return action.description
	return ""


## Re-applies the most recently undone action. Returns its description, or "".
func redo() -> String:
	if _redo_stack.is_empty():
		return ""
	var action: UndoableAction = _redo_stack.pop_back()
	action.redo()
	_undo_stack.append(action)
	_emit_changed()
	return action.description


## Re-applies the most recently undone action OWNED BY peer_id. Returns its
## description, or "".
func redo_for(peer_id: int) -> String:
	for i in range(_redo_stack.size() - 1, -1, -1):
		if _redo_stack[i].peer_id == peer_id:
			var action: UndoableAction = _redo_stack[i]
			_redo_stack.remove_at(i)
			action.redo()
			_undo_stack.append(action)
			_emit_changed()
			return action.description
	return ""


## #162 — the take-back window closes: dice hit the tray, or the next activation /
## round began. Removes every MoveTakebackAction (optionally only one unit's) from
## BOTH stacks; plain Move/Rotate/Delete actions (terrain, sandbox bookkeeping) stay.
func expire_move_takebacks(unit_key: String = "") -> void:
	var changed := false
	for stack: Array[UndoableAction] in [_undo_stack, _redo_stack]:
		for i in range(stack.size() - 1, -1, -1):
			var a := stack[i]
			if a is MoveTakebackAction and (unit_key.is_empty() \
					or (a as MoveTakebackAction).unit_key == unit_key):
				stack.remove_at(i)
				changed = true
	if changed:
		_emit_changed()


## Clears the entire history. Call when the table is replaced (new game / load),
## since recorded node references would otherwise be stale.
func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	_emit_changed()


# === Private helpers ===

func _emit_changed() -> void:
	history_changed.emit(can_undo(), can_redo())


# ============================================================================
# Action types
# ============================================================================

## Base class for a reversible action. Subclasses capture the before/after state
## of an action the user already performed.
class UndoableAction:
	var description: String = ""
	## Peer id of the player who performed this action (0 = local / single-player).
	## Undo/redo only act on the local player's own actions in multiplayer.
	var peer_id: int = 0
	## When false the action never enters the redo stack (a MOVEMENT take-back is
	## final: redoing it would re-place models without re-painting their proof).
	var redoable: bool = true

	func undo() -> void:
		pass

	func redo() -> void:
		pass


## Moves a set of objects between recorded start and end positions.
class MoveAction extends UndoableAction:
	var _objects: Array[Node3D] = []
	var _from: Array[Vector3] = []
	var _to: Array[Vector3] = []
	var _net: Node = null

	func _init(objects: Array[Node3D], from_positions: Array[Vector3], to_positions: Array[Vector3], network_manager: Node, owner_peer_id: int = 0) -> void:
		_objects = objects
		_from = from_positions
		_to = to_positions
		_net = network_manager
		peer_id = owner_peer_id
		description = "Move %d object(s)" % objects.size()

	func undo() -> void:
		_apply(_from)

	func redo() -> void:
		_apply(_to)

	func _apply(positions: Array[Vector3]) -> void:
		for i in _objects.size():
			var obj: Node3D = _objects[i]
			if not is_instance_valid(obj):
				continue
			obj.global_position = positions[i]
			if obj is RigidBody3D:
				var body := obj as RigidBody3D
				body.linear_velocity = Vector3.ZERO
				body.angular_velocity = Vector3.ZERO
			if _net != null and _net.is_multiplayer_active() and obj.has_meta("network_id"):
				_net.broadcast_move(obj.get_meta("network_id"), obj.global_position)


## #162 — a MOVEMENT TAKE-BACK: restores each moved model's pre-drop position AND facing,
## erases the drop's chalk ribbon + inch stamp + ledger proof (locally, and on every peer
## via the MP take-back message) and writes the battle-log line (rules-must-log: a silent
## take-back would read as a glitch). NOT redoable — a redone take-back would re-place
## the models without their proof, so it never enters the redo stack.
class MoveTakebackAction extends UndoableAction:
	var unit_key: String = ""
	var _models: Array[Node3D] = []
	var _from_pos: Array[Vector3] = []
	var _from_rot: Array[float] = []
	var _owner_slot: int = 0
	var _unit_name: String = ""
	var _drop_id: int = -1
	var _trails: Node = null
	var _net: Node = null
	var _log: Node = null

	func _init(models: Array[Node3D], from_pos: Array[Vector3], from_rot: Array[float],
			owner_slot: int, p_unit_key: String, unit_name: String, drop_id: int,
			move_trails: Node, network_manager: Node, battle_log: Node,
			owner_peer_id: int = 0) -> void:
		_models = models
		_from_pos = from_pos
		_from_rot = from_rot
		_owner_slot = owner_slot
		unit_key = p_unit_key
		_unit_name = unit_name
		_drop_id = drop_id
		_trails = move_trails
		_net = network_manager
		_log = battle_log
		peer_id = owner_peer_id
		redoable = false
		description = "Take back move (%s)" % unit_name

	func undo() -> void:
		for i in _models.size():
			var obj: Node3D = _models[i]
			if not is_instance_valid(obj):
				continue
			obj.global_position = _from_pos[i]
			obj.rotation.y = _from_rot[i]
			if obj is RigidBody3D:
				var body := obj as RigidBody3D
				body.linear_velocity = Vector3.ZERO
				body.angular_velocity = Vector3.ZERO
			if _net != null and _net.is_multiplayer_active() and obj.has_meta("network_id"):
				_net.broadcast_move(obj.get_meta("network_id"), obj.global_position)
				_net.broadcast_rotation(obj.get_meta("network_id"), obj.rotation.y)
		if _trails != null:
			_trails.undo_drop(_owner_slot, unit_key, _drop_id)
		if _net != null and _net.is_multiplayer_active():
			_net.broadcast_move_trails_undo(_owner_slot, unit_key, _drop_id)
		if _log != null:
			_log.log_event(BattleLog.Category.MOVEMENT, "%s takes back its move" % _unit_name, false)


## Rotates a set of objects between recorded start and end Y rotations (radians).
class RotateAction extends UndoableAction:
	var _objects: Array[Node3D] = []
	var _from: Array[float] = []
	var _to: Array[float] = []
	var _net: Node = null

	func _init(objects: Array[Node3D], from_rot_y: Array[float], to_rot_y: Array[float], network_manager: Node, owner_peer_id: int = 0) -> void:
		_objects = objects
		_from = from_rot_y
		_to = to_rot_y
		_net = network_manager
		peer_id = owner_peer_id
		description = "Rotate %d object(s)" % objects.size()

	func undo() -> void:
		_apply(_from)

	func redo() -> void:
		_apply(_to)

	func _apply(rotations: Array[float]) -> void:
		for i in _objects.size():
			var obj: Node3D = _objects[i]
			if not is_instance_valid(obj):
				continue
			obj.rotation.y = rotations[i]
			if _net != null and _net.is_multiplayer_active() and obj.has_meta("network_id"):
				_net.broadcast_rotation(obj.get_meta("network_id"), obj.rotation.y)


## Reforms a regiment movement-tray block between two frontages (models-per-rank).
## AoF:R v3.5.1 p.6 "Unit Formations" — a player may reform to any width 1..N.
## Captures the tray + its GameUnit + the before/after frontage; undo/redo re-rank
## the block at the recorded width (tray transform preserved) and re-broadcast.
class FrontageAction extends UndoableAction:
	var _tray: RegimentTray = null
	var _game_unit: GameUnit = null
	var _from: int = 5
	var _to: int = 5
	var _net: Node = null

	func _init(tray: RegimentTray, game_unit: GameUnit, from_frontage: int, to_frontage: int, network_manager: Node, owner_peer_id: int = 0) -> void:
		_tray = tray
		_game_unit = game_unit
		_from = from_frontage
		_to = to_frontage
		_net = network_manager
		peer_id = owner_peer_id
		description = "Regiment frontage %d -> %d" % [from_frontage, to_frontage]

	func undo() -> void:
		_apply(_from)

	func redo() -> void:
		_apply(_to)

	func _apply(frontage: int) -> void:
		if not is_instance_valid(_tray) or _game_unit == null:
			return
		var members := RegimentTray.collect_members(_game_unit)
		if members.nodes.is_empty():
			return
		_tray.reform(members.nodes, members.footprints, frontage)
		# Keep the Regiment companion + unit_properties in sync (save/load reads these).
		if _tray.has_meta("regiment"):
			var regiment := _tray.get_meta("regiment") as Regiment
			if regiment:
				regiment.frontage = frontage
		_game_unit.unit_properties["frontage"] = frontage
		if _net != null and _net.is_multiplayer_active():
			_net.broadcast_regiment_frontage(_game_unit.unit_id, frontage)


## Adjusts a regiment's pooled-wound counter between two values (AoF:R v3.5.1 p.9).
## Captures the Regiment companion + before/after wounds_taken; undo/redo re-apply
## the counter via the OPRArmyManager (which re-ranks the block, updates the counter
## label, and re-broadcasts). The Regiment is RefCounted so it stays alive across the
## stack; the army_manager is a long-lived Node held by direct reference.
class RegimentWoundAction extends UndoableAction:
	var _regiment: Regiment = null
	var _from: int = 0
	var _to: int = 0
	var _army_manager: Node = null
	var _net: Node = null

	func _init(regiment: Regiment, from_taken: int, to_taken: int, army_manager: Node, network_manager: Node, owner_peer_id: int = 0) -> void:
		_regiment = regiment
		_from = from_taken
		_to = to_taken
		_army_manager = army_manager
		_net = network_manager
		peer_id = owner_peer_id
		description = "Regiment wounds %d -> %d" % [from_taken, to_taken]

	func undo() -> void:
		_apply(_from)

	func redo() -> void:
		_apply(_to)

	func _apply(wounds_taken: int) -> void:
		if _regiment == null or not is_instance_valid(_regiment.tray):
			return
		if _army_manager and _army_manager.has_method("apply_regiment_wounds"):
			_army_manager.apply_regiment_wounds(_regiment, wounds_taken)


## Removes (hides) selected models/objects and restores them on undo.
##
## Unit models use casualty semantics (is_alive=false, wounds=0, node hidden) and
## are synced via NetworkManager.broadcast_model_wounds(). Plain nodes (custom
## minis / terrain) are only hidden locally — matching the existing terrain and
## generic delete, which are not networked.
class DeleteAction extends UndoableAction:
	var _models: Array[ModelInstance] = []
	var _prev_wounds: Array[int] = []
	var _prev_alive: Array[bool] = []
	var _nodes: Array[Node3D] = []
	var _net: Node = null

	func _init(models: Array[ModelInstance], prev_wounds: Array[int], prev_alive: Array[bool], nodes: Array[Node3D], network_manager: Node, owner_peer_id: int = 0) -> void:
		_models = models
		_prev_wounds = prev_wounds
		_prev_alive = prev_alive
		_nodes = nodes
		_net = network_manager
		peer_id = owner_peer_id
		description = "Delete %d object(s)" % (models.size() + nodes.size())

	## Applies (or re-applies) the deletion.
	func redo() -> void:
		for model in _models:
			model.is_alive = false
			model.wounds_current = 0
			_set_node_hidden(model.node, true)
			if _net != null:
				_net.broadcast_model_wounds(model)
		for node in _nodes:
			_set_node_hidden(node, true)
			_broadcast_node_visibility(node, false)

	## Restores the pre-deletion state.
	func undo() -> void:
		for i in _models.size():
			var model: ModelInstance = _models[i]
			model.is_alive = _prev_alive[i]
			model.wounds_current = _prev_wounds[i]
			var revived: bool = model.is_alive and model.wounds_current > 0
			_set_node_hidden(model.node, not revived)
			_remove_stain(model.node)
			if _net != null:
				_net.broadcast_model_wounds(model)
		for node in _nodes:
			_set_node_hidden(node, false)
			_broadcast_node_visibility(node, true)

	## Mirrors a plain node's delete/undo (hide/show) to remote peers by
	## network_id — the wounds path only covers OPR unit models.
	func _broadcast_node_visibility(node: Node3D, is_visible: bool) -> void:
		if _net == null or node == null or not is_instance_valid(node):
			return
		if not _net.is_multiplayer_active() or not node.has_meta("network_id"):
			return
		_net.broadcast_object_visibility(int(node.get_meta("network_id")), is_visible)

	func _set_node_hidden(node: Node3D, hidden: bool) -> void:
		if node == null or not is_instance_valid(node):
			return
		node.visible = not hidden
		node.set_meta("deleted", hidden)

	## Remove the blood/oil residue a removed model left behind when its deletion is UNDONE.
	## battlefield_stains.gd records the stain nodes in the model node's "stain_nodes" meta and sets a
	## "stained" guard; freeing the nodes + clearing both metas makes the model clean again, so a later
	## delete (e.g. after the player moved it) stains the model's CURRENT position instead of re-showing
	## the old stain at its previous spot (#72). Decoupled from BattlefieldStains (frees nodes + metas).
	func _remove_stain(node: Node3D) -> void:
		if node == null or not is_instance_valid(node):
			return
		if node.has_meta("stain_nodes"):
			for stain in node.get_meta("stain_nodes"):
				if stain is Node3D and is_instance_valid(stain):
					stain.queue_free()
			node.remove_meta("stain_nodes")
		node.remove_meta("stained")

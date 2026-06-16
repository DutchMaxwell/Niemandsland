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
	_redo_stack.append(action)
	_emit_changed()
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
			_redo_stack.append(action)
			_emit_changed()
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

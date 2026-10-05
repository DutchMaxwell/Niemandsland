class_name TableTheme
extends RefCounted
## A one-click table theme (S5, maintainer 05.10.): the biome, the mood and the free shelf pieces of a whole table,
## kept as data in res://assets/themes/<id>.json. Piece positions are inches from the table centre and the yaw is in
## degrees, the frame the save files use for free pieces.

const DIR := "res://assets/themes"
const IN2M := 0.0254

var id: String = ""
var label: String = ""
var table_feet := Vector2.ZERO
var biome: String = ""
var mood: String = ""
var pieces: Array[Dictionary] = []   # {prop_id, kind, position: Vector3 metres (y 0), yaw_deg}
var paths: Array = []   # worn paths, polylines of [x, z] inches from the centre (TablePaths, D14)


static func load_theme(theme_id: String) -> TableTheme:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(theme_id + ".json")))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[Theme] cannot read theme '%s'" % theme_id)
		return null
	var t := TableTheme.new()
	t.id = theme_id
	t.label = str(data.get("label", theme_id))
	var feet: Array = data.get("table_feet", [0, 0])
	t.table_feet = Vector2(float(feet[0]), float(feet[1]))
	t.biome = str(data.get("biome", ""))
	t.mood = str(data.get("mood", ""))
	t.paths = data.get("paths", [])
	for p: Dictionary in data.get("pieces", []):
		t.pieces.append({"prop_id": str(p["prop_id"]), "kind": int(p["kind"]),
			"position": Vector3(float(p["x_in"]), 0.0, float(p["z_in"])) * IN2M, "yaw_deg": float(p["yaw_deg"])})
	return t


## The theme is laid out for one table size; on any other the entry stays greyed out (D11).
func fits(size_feet: Vector2) -> bool:
	return size_feet.is_equal_approx(table_feet)


## Lay the theme out: the live free pieces are replaced (hidden the undoable way, D10), the theme pieces spawn at
## their spot and angle, the biome and the mood (local, D13) change. hooks = {started, biome_get, biome_set, mood_get,
## mood_set, optional relayout} (Callables) + optional net (NetworkManager): in a multiplayer game the spawns, angles,
## hidden pieces and the biome reach the other table, for undo and redo too. Returns the action to push on the undo
## history, or null once the game has started.
func apply(om: ObjectManager, hooks: Dictionary) -> ThemeAction:
	if hooks["started"].call():
		print("[Theme] '%s' refused: the game has started" % id)
		return null
	var action := ThemeAction.new()
	action.description = "Table theme: %s" % label
	action.hooks = hooks
	for n in ObjectManager.sandbox_pieces(om.get_tree()):
		if n is Node3D and not bool(n.get_meta("deleted", false)):
			action.replaced.append(n)
	for p: Dictionary in pieces:
		var node := om.spawn_sandbox_terrain(p["prop_id"], p["kind"], p["position"], true)   # broadcasts in multiplayer
		if node != null:
			node.rotation_degrees.y = p["yaw_deg"]
			if action.net_live():
				hooks["net"].broadcast_rotation(int(node.get_meta("network_id")), node.rotation.y)
			action.spawned.append(node)
			action._placed.append([node.global_position, node.rotation.y])
	action.before = [hooks["biome_get"].call(), hooks["mood_get"].call(),
		hooks["paths_get"].call() if hooks.has("paths_get") else []]
	action.after = [biome, mood, paths]
	action.redo()
	print("[Theme] '%s' applied: %d pieces, %d replaced" % [id, action.spawned.size(), action.replaced.size()])
	return action


## One undo step for a whole theme: hides or shows both piece sets (DeletedState, so the rules and the ground follow)
## and swaps biome and mood.
class ThemeAction extends UndoManager.UndoableAction:
	var replaced: Array[Node3D] = []
	var spawned: Array[Node3D] = []
	var before: Array = []   # [biome, mood]
	var after: Array = []
	var hooks: Dictionary = {}
	var applied := false
	var _placed: Array = []   # [position, yaw] of each spawned piece as laid out

	func undo() -> void:
		_swap(before, false)

	func redo() -> void:
		_swap(after, true)

	## The table still shows this theme exactly as laid out: applied, every piece live and unmoved, and no other live
	## free piece (D15 a: a second click there is a no-op instead of 14 more hidden pieces).
	func is_current(om: ObjectManager) -> bool:
		if not applied:
			return false
		var live := ObjectManager.sandbox_pieces(om.get_tree()).filter(func(n: Node) -> bool:
			return not bool(n.get_meta("deleted", false)))
		if live.size() != spawned.size():
			return false
		for i in spawned.size():
			var n := spawned[i]
			if not is_instance_valid(n) or not live.has(n) or not n.global_position.is_equal_approx(_placed[i][0]) \
					or not is_equal_approx(n.rotation.y, _placed[i][1]):
				return false
		return true

	func net_live() -> bool:
		var net: Node = hooks.get("net")
		return net != null and net.is_multiplayer_active()

	func _swap(to: Array, on: bool) -> void:
		applied = on
		for n in replaced:
			_hide(n, on)
		for n in spawned:
			_hide(n, not on)
		hooks["biome_set"].call(to[0])
		var settings := {"biome": to[0]}
		if hooks.has("paths_set"):   # the table's worn paths (D14), saved with the table
			hooks["paths_set"].call(to[2])
			settings["paths"] = to[2]
		if net_live():
			hooks["net"].broadcast_table_settings(settings)
		hooks["mood_set"].call(to[1])
		if hooks.has("relayout"):
			hooks["relayout"].call()   # the biome dressing places litter around woods: re-dress for the new layout

	func _hide(n: Node3D, hidden: bool) -> void:
		DeletedState.apply(n, hidden)
		if net_live() and n.has_meta("network_id"):
			hooks["net"].broadcast_object_visibility(int(n.get_meta("network_id")), not hidden)

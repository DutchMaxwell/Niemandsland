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
	for p: Dictionary in data.get("pieces", []):
		t.pieces.append({"prop_id": str(p["prop_id"]), "kind": int(p["kind"]),
			"position": Vector3(float(p["x_in"]), 0.0, float(p["z_in"])) * IN2M, "yaw_deg": float(p["yaw_deg"])})
	return t


## The theme is laid out for one table size; on any other the entry stays greyed out (D11).
func fits(size_feet: Vector2) -> bool:
	return size_feet.is_equal_approx(table_feet)


## Lay the theme out: the live free pieces are replaced (hidden the undoable way, D10), the theme pieces spawn at
## their spot and angle, the biome and the mood (local, D13) change. hooks = {started, biome_get, biome_set, mood_get,
## mood_set, optional relayout} (Callables). Returns the action to push on the undo history, or null once the game has started.
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
		var node := om.spawn_sandbox_terrain(p["prop_id"], p["kind"], p["position"], false)
		if node != null:
			node.rotation_degrees.y = p["yaw_deg"]
			action.spawned.append(node)
	action.before = [hooks["biome_get"].call(), hooks["mood_get"].call()]
	action.after = [biome, mood]
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

	func undo() -> void:
		_swap(before, false)

	func redo() -> void:
		_swap(after, true)

	func _swap(to: Array, applied: bool) -> void:
		for n in replaced:
			DeletedState.apply(n, applied)
		for n in spawned:
			DeletedState.apply(n, not applied)
		hooks["biome_set"].call(to[0])
		hooks["mood_set"].call(to[1])
		if hooks.has("relayout"):
			hooks["relayout"].call()   # the biome dressing places litter around woods: re-dress for the new layout

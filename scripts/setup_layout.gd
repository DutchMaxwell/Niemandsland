class_name SetupLayout
extends Node
## The layout behind step 04 of the table setup ("Lay out the table"): one hidden instance of the layout editor,
## run in the menu without a table. The only script that touches the editor from the menu. It lays out the chosen
## way, reads its facts for the rail, and on Create table hands the choice to the table (PendingLayout).

signal changed

const DEFAULT_WAY := "empty"
const FILE := "user://pending_layout.json"
const LABELS := {"empty": "Empty table", "generated": "Auto-generated"}
const CHECK := "✓"
const CROSS := "✗"

var way := DEFAULT_WAY
var editor: Control


func _init() -> void:
	editor = (load("res://scenes/map_layout.tscn") as PackedScene).instantiate()
	editor.visible = false
	add_child(editor)


## The setup's table size and game system; a generated layout is laid out again for a new size.
func set_table(size_feet: Vector2, system_id: String) -> void:
	editor.set_table_size(size_feet)
	editor.set_game_system(system_id, "Chosen in step 01")
	if way == "generated":
		generate()
	else:
		changed.emit()


func choose(new_way: String) -> void:
	way = new_way
	if way == "generated":
		generate()
		return
	editor._clear_terrain()
	changed.emit()


## The editor's own generator (unseeded): another press gives another layout.
func generate() -> void:
	editor._on_autogen_pressed()
	changed.emit()


func label() -> String:
	return str(LABELS.get(way, way))


## What the rail shows: pieces by type, their sum, the coverage and the editor's guideline lines as it prints them.
func facts() -> Dictionary:
	var by_type: Dictionary = editor._count_terrain_pieces()
	var pieces := 0
	for count: int in by_type.values():
		pieces += count
	var dims: Vector2i = editor._calculate_grid_dimensions()
	var cells: int = editor.grid_cells.values().filter(func(t: int) -> bool: return t != 0).size()
	var lines: Array[Dictionary] = []
	for line: String in str(editor.recommendations_label.text).split("\n"):
		if line.begins_with(CHECK) or line.begins_with(CROSS):
			lines.append({"ok": line.begins_with(CHECK), "text": line.substr(2)})
	return {"pieces_by_type": by_type, "pieces": pieces, "lines": lines,
		"coverage_pct": 100.0 * cells / maxi(1, dims.x * dims.y)}


## Create table: the empty way hands over {}, every other way the editor's own file of the layout.
func commit() -> void:
	if way == "empty":
		PendingLayout.store({})
		return
	editor.save_layout(FILE)
	PendingLayout.store({"path": FILE})

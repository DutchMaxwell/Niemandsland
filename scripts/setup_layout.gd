class_name SetupLayout
extends Node
## The layout behind step 04 of the table setup ("Lay out the table"): one hidden instance of the layout editor,
## run in the menu without a table. The only script that touches the editor from the menu. It lays out the chosen
## way, reads its facts for the rail, and on Create table hands the choice to the table (PendingLayout).

signal changed

const DEFAULT_WAY := "empty"
const FILE := "user://pending_layout.json"
const LABELS := {"empty": "Empty table", "generated": "Auto-generated", "theme": "Ruined Borderland",
	"file": "Loaded layout", "edited": "Edited layout"}
const THEME_ID := "ruined_borderland"
const CHECK := "✓"
const CROSS := "✗"

var way := DEFAULT_WAY
var editor: Control
var note := ""   # one line under the way cards: why a layout was dropped


func _init() -> void:
	editor = (load("res://scenes/map_layout.tscn") as PackedScene).instantiate()
	editor.visible = false
	add_child(editor)
	editor.layout_closed.connect(_on_editor_closed)
	editor.theme_requested.connect(func(_id: String) -> void:
		editor.hide()
		choose("theme"))


## Today's layout editor, full-window over the setup with whatever the chosen way laid out; its system row stays
## locked. Its Close returns to step 04 and the way reads "Edited layout".
## `mode` "deployment" opens its Deployment tab (custom zones are drawn there), "objectives" its objectives mode.
func open_editor(mode := "") -> void:
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor.show()
	if mode == "deployment":
		(editor.find_child("TabDeploymentButton", true, false) as Button).pressed.emit()
	elif mode == "objectives":
		(editor.find_child("TabObjectivesButton", true, false) as Button).pressed.emit()
		editor._objectives_toggle_btn.button_pressed = true


func _on_editor_closed() -> void:
	if way != "theme":
		way = "edited"
	changed.emit()


## The setup's table size and game system; a generated layout is laid out again for a new size.
func set_table(size_feet: Vector2, system_id: String) -> void:
	var resized: bool = editor.table_size_feet != size_feet
	editor.set_table_size(size_feet)
	editor.set_game_system(system_id, "Chosen in step 01")
	if way == "theme" and not TableTheme.load_theme(THEME_ID).fits(size_feet):
		way = DEFAULT_WAY   # the ready-made table needs 6 x 4 ft; the step-04 row says so by its new name
	elif way == "file" and resized:
		way = DEFAULT_WAY
		note = "The layout was made for another table size."
	if way == "generated":
		generate()
	else:
		changed.emit()


## Chooses a way; the ready-made table is refused off 6 x 4 ft (false).
func choose(new_way: String) -> bool:
	if new_way == "theme" and not TableTheme.load_theme(THEME_ID).fits(editor.table_size_feet):
		return false
	way = new_way
	note = ""
	if way == "generated":
		generate()
		return true
	editor._clear_terrain()
	changed.emit()
	return true


## A layout file saved in the editor; one made for another table size is refused with its line, nothing changes.
func load_file(path: String) -> String:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var size: Dictionary = data.get("table_size", {}) if data is Dictionary else {}
	var feet := Vector2(float(size.get("x", 0)), float(size.get("y", 0)))
	if feet != editor.table_size_feet:
		return "This layout is for a %s × %s ft table." % [String.num(feet.x).trim_suffix(".0"), String.num(feet.y).trim_suffix(".0")]
	editor.load_layout(path)
	way = "file"
	note = ""
	changed.emit()
	return ""


## Point symmetry; a generated layout is generated again with it.
func set_mirror(on: bool) -> void:
	editor._on_symmetry_toggled(on)
	if way == "generated":
		generate()


## The editor's deployment type (0 none, 1 front line, 2 custom zones).
func set_deployment(type: int) -> void:
	editor._on_deployment_type_selected(type)
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
	if way == "theme":
		PendingLayout.store({"theme": THEME_ID})
		return
	if way == "empty" and editor.deployment_type == 0 and editor.mission_objectives.is_empty():
		PendingLayout.store({})
		return
	editor.save_layout(FILE)
	PendingLayout.store({"path": FILE})

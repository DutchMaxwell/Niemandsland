class_name SandboxTerrainShelf
extends Window
## The casual "terrain shelf": a biome-filtered browser of free-placed terrain pieces
## (grassland ruins first, plus tree-group forests and minefield clusters). Picking a piece
## spawns it on the 3D table at the cursor as a draggable SandboxTerrainProp / TerrainGroupBase
## — the player then pushes and rotates it freely, ungated by the competitive 3" grid. The
## window is built entirely in code so it needs no scene wiring.

# === Constants ===

## Biome filter options: label + RuinsLibrary name-prefix ("" = grassland / no prefix).
const BIOMES: Array[Dictionary] = [
	{"label": "Grassland", "prefix": ""},
	{"label": "Arid Desert", "prefix": "desert_"},
	{"label": "Frozen Tundra", "prefix": "tundra_"},
	{"label": "Volcanic Ash", "prefix": "volcanic_"},
	{"label": "Alien Jungle", "prefix": "jungle_"},
	{"label": "Urban Ruins", "prefix": "urban_"},
]
const WINDOW_SIZE := Vector2i(380, 460)

# === Signals ===

## Emitted when the shelf is closed (X or Close button), so the host can leave terrain edit
## mode and re-lock the pieces.
signal closed
## Wave-3 tutorial seam: a shelf piece was actually spawned onto the table.
signal piece_placed(prop_id: String)

# === Private state ===

# Untyped (Node) on purpose: typing this as ObjectManager would make main.tscn's main.gd
# depend on the ObjectManager class while that very node is being instantiated, which the
# runtime script loader can't resolve ("Could not resolve external class member"). Calls are
# dynamic.
var _object_manager: Node = null
var _biome_option: OptionButton = null
var _list: ItemList = null

# === Lifecycle ===

func _ready() -> void:
	title = "Terrain Shelf"
	size = WINDOW_SIZE
	min_size = WINDOW_SIZE
	close_requested.connect(_emit_closed)
	visible = false
	_build_ui()

# === Public ===

## Bind the object manager (the spawn target) and fill the list. Call once after adding.
func setup(object_manager: Node) -> void:
	_object_manager = object_manager
	_refresh_list()


## Open the shelf centered.
func open() -> void:
	popup_centered()
	_refresh_list()

# === Private ===

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var hint := Label.new()
	hint.text = "Pick a piece, then click on the table to place it.\nDrag to push, hold R to rotate."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	_biome_option = OptionButton.new()
	for biome in BIOMES:
		_biome_option.add_item(biome["label"])
	_biome_option.item_selected.connect(_on_biome_selected)
	vbox.add_child(_biome_option)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(_on_item_activated)
	vbox.add_child(_list)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(button_row)

	var spawn_btn := Button.new()
	spawn_btn.text = "Place"
	spawn_btn.pressed.connect(_on_place_pressed)
	button_row.add_child(spawn_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_emit_closed)
	button_row.add_child(close_btn)


func _emit_closed() -> void:
	hide()
	closed.emit()


func _on_biome_selected(_index: int) -> void:
	_refresh_list()


func _refresh_list() -> void:
	if _list == null or _object_manager == null:
		return
	_list.clear()
	var prefix: String = BIOMES[_biome_option.selected]["prefix"] if _biome_option != null else ""
	for entry in _object_manager.sandbox_catalog(prefix):
		_list.add_item(entry.get("label", entry.get("prop_id", "?")))
		_list.set_item_metadata(_list.item_count - 1, entry)


func _on_item_activated(index: int) -> void:
	_place(index)


func _on_place_pressed() -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return
	_place(selected[0])


func _place(index: int) -> void:
	if _object_manager == null:
		return
	var entry: Dictionary = _list.get_item_metadata(index)
	if entry.is_empty():
		return
	var cursor_pos: Vector3 = _object_manager.get_cursor_table_position()
	_object_manager.spawn_sandbox_terrain(entry.get("prop_id", ""), int(entry.get("kind", 0)), cursor_pos)
	piece_placed.emit(str(entry.get("prop_id", "")))
	# Keep the shelf open for placing multiple pieces.

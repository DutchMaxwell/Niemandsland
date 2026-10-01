class_name SandboxTerrainShelf
extends PanelContainer
## The casual "terrain shelf": a biome-filtered browser of free-placed terrain pieces
## (grassland ruins first, plus tree-group forests and minefield clusters). Picking a piece
## spawns it on the 3D table at the cursor as a draggable SandboxTerrainProp / TerrainGroupBase
## — the player then pushes and rotates it freely, ungated by the competitive 3" grid. The
## panel is an in-viewport house-style panel docked at the left, built entirely in code (no scene wiring).

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
const PANEL_SIZE := Vector2(320, 440)
## Docked on the left, right of the left unit panel (it ends at x 270, main.tscn) and below the top bar.
const DOCK_OFFSET := Vector2(280, 96)

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
## Click-to-place: armed with the selected piece, follows the cursor on the table (see SandboxPlacementGhost).
var _ghost: SandboxPlacementGhost = null
## Last table point aimed at while the cursor was OUTSIDE this panel; Place lands there.
var _last_table_point := Vector3.ZERO
var _mouse_over_shelf := false

# === Lifecycle ===

func _ready() -> void:
	name = "TerrainShelf"
	HouseStyle.apply(self)
	theme_type_variation = HouseStyle.PANEL_VARIANT
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = DOCK_OFFSET
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _mouse_over_shelf = true)
	mouse_exited.connect(func(): _mouse_over_shelf = false)
	visible = false
	_build_ui()

# === Public ===

## Bind the object manager (the spawn target) and fill the list. Call once after adding.
func setup(object_manager: Node) -> void:
	_object_manager = object_manager
	_ghost = SandboxPlacementGhost.new()
	object_manager.add_child(_ghost)
	_ghost.setup(object_manager)
	_ghost.dropped.connect(func(prop_id: String) -> void: piece_placed.emit(prop_id))
	_refresh_list()


## Open the shelf (docked left).
func open() -> void:
	show()
	_refresh_list()

# === Private ===

func _process(_delta: float) -> void:
	if visible:
		_mouse_over_shelf = get_global_rect().has_point(get_viewport().get_mouse_position())
		_track_cursor()


## Remember where the player last aimed on the table (not while the cursor is over the shelf).
func _track_cursor() -> void:
	if _object_manager != null and not _mouse_over_shelf:
		_last_table_point = _object_manager.get_cursor_table_position()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", HouseStyle.GAP_ROW)
	add_child(vbox)

	vbox.add_child(HouseStyle.label("TERRAIN SHELF", HouseStyle.EYEBROW))

	var hint := HouseStyle.label("Pick a piece, then click on the table to drop it (Esc cancels).\nOr press Place. Drag to move it, hold R to rotate.", HouseStyle.CAPTION)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	_biome_option = OptionButton.new()
	for biome in BIOMES:
		_biome_option.add_item(biome["label"])
	_biome_option.item_selected.connect(_on_biome_selected)
	vbox.add_child(HouseStyle.field_row("Biome", _biome_option))

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(_on_item_activated)
	_list.item_selected.connect(_on_item_selected)
	vbox.add_child(_list)

	var button_row := HouseStyle.button_row(["Place", "Close"], HouseStyle.BUTTON, HouseStyle.H_ACTION)
	vbox.add_child(button_row)
	var spawn_btn: Button = button_row.get_child(0)
	spawn_btn.theme_type_variation = HouseStyle.PRIMARY
	spawn_btn.pressed.connect(_on_place_pressed)
	var close_btn: Button = button_row.get_child(1)
	close_btn.pressed.connect(_emit_closed)


## The click-to-place ghost (null before setup()).
func placement_ghost() -> SandboxPlacementGhost:
	return _ghost


func _on_item_selected(index: int) -> void:
	var entry: Dictionary = _list.get_item_metadata(index)
	if _ghost != null and not entry.is_empty():
		_ghost.arm(entry)


func _emit_closed() -> void:
	if _ghost != null:
		_ghost.cancel()
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
	var cursor_pos: Vector3 = _last_table_point if _mouse_over_shelf else _object_manager.get_cursor_table_position()
	_object_manager.spawn_sandbox_terrain(entry.get("prop_id", ""), int(entry.get("kind", 0)), cursor_pos)
	piece_placed.emit(str(entry.get("prop_id", "")))
	# Keep the shelf open for placing multiple pieces.

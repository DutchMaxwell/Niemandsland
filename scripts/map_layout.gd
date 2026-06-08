extends Control
## Map Layout Editor - Top-down view with 3" grid for terrain type assignment
## OPR terrain recommendations are displayed in real-time

signal layout_closed
signal layout_updated(grid_cells: Dictionary, table_size: Vector2, rotation: float,
	wall_segments: Array, placed_objects: Array)

# Terrain types with their properties
enum TerrainType {
	NONE,
	RUINS,      # Height 5, Cover + Walls Impassable, can see in/out but not through
	FOREST,     # Height 5, Difficult + Cover, can see in/out but not through
	CONTAINER,  # Height 5, Impassable + Blocking, can fly over but not land
	DANGEROUS   # Open, Dangerous (Minefields, Acid, Radiation)
}

const TERRAIN_COLORS := {
	TerrainType.NONE: Color(0.2, 0.2, 0.2, 0.3),
	TerrainType.RUINS: Color(0.3, 0.5, 0.8, 0.6),      # Blue
	TerrainType.FOREST: Color(0.2, 0.6, 0.2, 0.6),    # Green
	TerrainType.CONTAINER: Color(0.6, 0.4, 0.2, 0.6), # Brown/Orange
	TerrainType.DANGEROUS: Color(0.8, 0.2, 0.2, 0.6)  # Red
}

const TERRAIN_NAMES := {
	TerrainType.NONE: "None",
	TerrainType.RUINS: "Ruins",
	TerrainType.FOREST: "Forest",
	TerrainType.CONTAINER: "Container",
	TerrainType.DANGEROUS: "Dangerous"
}

const TERRAIN_DESCRIPTIONS := {
	TerrainType.RUINS: "Height 5, Cover\nWalls: Impassable (blue lines)\nCan see in/out, not through",
	TerrainType.FOREST: "Height 5, Difficult + Cover\nCan see in/out, not through",
	TerrainType.CONTAINER: "Height 5, Impassable + Blocking\nCan fly over, cannot land",
	TerrainType.DANGEROUS: "Open, Dangerous\n(Minefields/Acid/Radiation)"
}

const GRID_SIZE_INCHES := 3.0
const INCHES_TO_METERS := 0.0254

# Deployment zone types (must match terrain_overlay.gd)
# NOTE: Only FRONT_LINE is from OPR free rules.
# Other deployment types are behind OPR's paywall.
enum DeploymentType {
	NONE = 0,
	FRONT_LINE = 1,  # 12" from long edges (OPR free rule)
	CUSTOM = 2       # Custom polygon zones defined by user
}

# Custom zone editing state
var custom_zone_editing := false
var custom_zone_symmetric := true
var custom_zone_current_player := 1  # 1 or 2
# Vertices stored as FLOAT coordinates for precise boundary placement
# This allows vertices to be placed exactly at grid-boundary intersections
var custom_zone_vertices_p1: Array[Vector2] = []  # Precise positions
var custom_zone_vertices_p2: Array[Vector2] = []

# Vertex dragging state
var _dragging_vertex := false
var _dragging_player := 0  # 1 or 2
var _dragging_index := -1
const VERTEX_CLICK_RADIUS := 10.0  # Pixels for vertex selection

var table_size_feet := Vector2(6, 4)  # Default 6x4 table
var grid_rotation_degrees := 0.0
var grid_cells := {}  # Dictionary[Vector2i, TerrainType]
var selected_terrain_type := TerrainType.NONE
var is_painting := false
var point_symmetry_enabled := false  # Mirror placement across center

# ==============================================================================
# WALL & OBJECT DATA (modulares Terrain)
# ==============================================================================

## Editor modes: paint free cells, place walls on edges, drop complete prefab pieces,
## or select/move/rotate already-placed pieces.
enum EditorMode { PAINT_CELLS, PLACE_WALLS, PLACE_PREFAB, MOVE_PIECES }
var editor_mode := EditorMode.PAINT_CELLS

## Selected canonical prefab key for one-click placement (see terrain_prefabs.gd)
var selected_prefab_key := ""

## Live preview state while in PLACE_PREFAB mode (ghost piece at the cursor).
var _preview_cell := Vector2i.ZERO
var _preview_rotation := 0       # 0/90/180/270, cycled with R
var _preview_flip := false       # mirrored wall-L, toggled with F
var _preview_active := false     # true while the cursor is over the grid

## Selected / dragged placed piece (MOVE_PIECES mode).
var _selected_piece_id := -1
var _dragging_piece := false
var _drag_pushed := false           # undo snapshot taken for the current drag?
var _drag_grab_offset := Vector2i.ZERO  # piece.origin - grabbed cell

## A wall segment on a cell edge
## edge_cell: Cell the wall is attached to
## edge_side: 0=North, 1=East, 2=South, 3=West
## wall_key: Key matching terrain theme wall definition
## length_inches: 3.0 or 1.0
## sub_position: For 1"-segments, position 0/1/2 within the 3"-edge
var wall_segments: Array[Dictionary] = []

## Selected wall variant key for placement
var selected_wall_key := ""
## Wall granularity (true = 1" segments, false = 3" full edge)
var wall_fine_mode := false

## Placed objects (trees, containers, dangerous hazards). DERIVED — see below.
## Each entry: {object_key: String, cell: Vector2i, offset: Vector2, object_type: String}
var placed_objects: Array[Dictionary] = []

# ------------------------------------------------------------------------------
# Piece-identity model — the SOURCE OF TRUTH. grid_cells / wall_segments /
# placed_objects above are DERIVED from these via _rebuild_derived() so that whole
# pieces can be moved / rotated / deleted while the 3D renderer + multiplayer keep
# consuming the flat derived data unchanged.
# ------------------------------------------------------------------------------
## Placed prefab pieces: {id, prefab_key, origin: Vector2i, rotation:int, flip:bool, seed:int}
var placed_pieces: Array[Dictionary] = []
var _next_piece_id := 1
## Free-painted cells (PAINT_CELLS mode): Vector2i -> TerrainType
var free_cells: Dictionary = {}
## Manually placed wall segments (PLACE_WALLS mode)
var free_walls: Array[Dictionary] = []

## Undo / redo snapshot stacks of {pieces, free_cells, free_walls}
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
const UNDO_LIMIT := 50

## Available wall variants for manual edge placement (a single procedural default)
var available_walls: Array[Dictionary] = []

# Zoom and pan settings
var zoom_level := 1.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 3.0
const ZOOM_STEP := 0.1

# Pan offset (in unzoomed pixels, relative to grid center)
var pan_offset := Vector2.ZERO
var _is_panning := false
var _last_pan_pos := Vector2.ZERO

# Cached snap points (calculated during grid drawing, used for snapping)
# Each entry is {screen_pos: Vector2, inch_pos: Vector2} - floats for precision
var _cached_boundary_snap_points: Array[Dictionary] = []
var _snap_points_valid := false

# Deployment zones
var deployment_type := DeploymentType.NONE
var show_deployment_zones := false

# Mission objectives - positions stored in 1" coordinates (Vector2 for precision)
var mission_objectives: Array[Vector2] = []  # Positions in inches
var objectives_editing := false  # Whether we're in objective placement mode

# Signal to notify terrain_overlay of objectives changes
signal objectives_changed(objectives: Array)

# Signal to notify terrain_overlay of deployment changes
signal deployment_type_changed(type: int)

@onready var grid_container: Control = %GridContainer
@onready var rotation_slider: HSlider = %RotationSlider
@onready var rotation_label: Label = %RotationLabel
@onready var terrain_buttons: VBoxContainer = %TerrainButtons
@onready var stats_label: Label = %StatsLabel
@onready var recommendations_label: Label = %RecommendationsLabel
@onready var close_button: Button = %CloseButton
@onready var clear_button: Button = %ClearButton
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var symmetry_check: CheckBox = %SymmetryCheck
@onready var autogen_button: Button = %AutoGenButton
@onready var deployment_check: CheckBox = %DeploymentCheck
@onready var deployment_type_option: OptionButton = %DeploymentTypeOption
@onready var save_file_dialog: FileDialog = %SaveFileDialog
@onready var load_file_dialog: FileDialog = %LoadFileDialog

# Objectives UI (created programmatically)
var _objectives_panel: VBoxContainer = null
var _objectives_toggle_btn: Button = null
var _objectives_clear_btn: Button = null
var _objectives_status_label: Label = null
var _objectives_warning_label: Label = null

# Modular Terrain UI (prefab palette, walls, undo/redo)
var _modular_terrain_panel: VBoxContainer = null
var _prefab_option_btn: OptionButton = null
var _editor_mode_btn: Button = null
var _wall_option_btn: OptionButton = null
var _undo_btn: Button = null
var _redo_btn: Button = null
var _modular_status_label: Label = null


func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	clear_button.pressed.connect(_on_clear_pressed)
	rotation_slider.value_changed.connect(_on_rotation_changed)

	if save_button:
		save_button.pressed.connect(_on_save_pressed)
	if load_button:
		load_button.pressed.connect(_on_load_pressed)
	if symmetry_check:
		symmetry_check.toggled.connect(_on_symmetry_toggled)
	if autogen_button:
		autogen_button.pressed.connect(_on_autogen_pressed)
	if deployment_check:
		deployment_check.toggled.connect(_on_deployment_toggled)
	if save_file_dialog:
		save_file_dialog.file_selected.connect(_on_save_file_selected)
	if load_file_dialog:
		load_file_dialog.file_selected.connect(_on_load_file_selected)

	# Setup deployment zone type selection
	_setup_deployment_type_option()

	# Setup objectives UI (replaces the ObjectivesCheck checkbox)
	_setup_objectives_ui()

	_setup_terrain_buttons()
	_setup_modular_terrain_ui()
	_setup_tabs()
	_style_header_chrome()
	_update_stats()
	_update_recommendations()


## Restyle the scene-defined "MAP LAYOUT EDITOR" title to the tactical HUD language
## (Orbitron head font) and drop a thin amber->cyan accent line beneath the header row.
func _style_header_chrome() -> void:
	var title := get_node_or_null("MarginContainer/VBox/Header/Title") as Label
	if title:
		title.add_theme_font_override("font", HudTokens.head_font())
		title.add_theme_color_override("font_color", HudTokens.TEXT)

	var header := get_node_or_null("MarginContainer/VBox/Header")
	if header and header.get_parent():
		var vbox := header.get_parent()
		var line := HBoxContainer.new()
		line.name = "HeaderAccentLine"
		line.add_theme_constant_override("separation", 0)
		var amber := ColorRect.new()
		amber.color = HudTokens.AMBER
		amber.custom_minimum_size = Vector2(24, HudTokens.ACCENT_LINE)
		var cyan := ColorRect.new()
		cyan.color = Color(HudTokens.CYAN.r, HudTokens.CYAN.g, HudTokens.CYAN.b, 0.85)
		cyan.custom_minimum_size = Vector2(0, HudTokens.ACCENT_LINE)
		cyan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(amber)
		line.add_child(cyan)
		vbox.add_child(line)
		vbox.move_child(line, header.get_index() + 1)

	# Migrate the scene-defined header action buttons to token colours + variations.
	if save_button:
		save_button.theme_type_variation = "PrimaryButton"
	if clear_button:
		clear_button.add_theme_color_override("font_color", HudTokens.AMBER)
		clear_button.add_theme_color_override(
			"font_hover_color", Color(HudTokens.AMBER.r, HudTokens.AMBER.g, HudTokens.AMBER.b, 1.0))
	if close_button:
		close_button.theme_type_variation = "DangerButton"

	# Migrate the scene-defined left-panel labels to token greys/whites + amber accents.
	# These scene nodes have been reparented into tabs by _setup_tabs(), so search the
	# whole subtree recursively rather than by a flat child name.
	var left_panel := get_node_or_null(
		"MarginContainer/VBox/MainContent/LeftPanelContainer/LeftPanelScroll/LeftPanel")
	if left_panel:
		for label_name in ["TerrainLabel", "DeploymentLabel"]:
			var lbl := left_panel.find_child(label_name, true, false) as Label
			if lbl:
				lbl.add_theme_font_override("font", HudTokens.head_font())
				lbl.add_theme_color_override("font_color", HudTokens.TEXT)
		var rot_lbl := left_panel.find_child("RotationLabel", true, false) as Label
		if rot_lbl:
			rot_lbl.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
		var stats_lbl := left_panel.find_child("StatsLabel", true, false) as Label
		if stats_lbl:
			stats_lbl.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
		var recs_lbl := left_panel.find_child("RecommendationsLabel", true, false) as Label
		if recs_lbl:
			recs_lbl.add_theme_color_override("font_color", HudTokens.AMBER)
		var sym_chk := left_panel.find_child("SymmetryCheck", true, false) as CheckBox
		if sym_chk:
			sym_chk.add_theme_color_override("font_color", HudTokens.TEXT)
		var deploy_chk := left_panel.find_child("DeploymentCheck", true, false) as CheckBox
		if deploy_chk:
			deploy_chk.add_theme_color_override("font_color", HudTokens.TEXT)
		var deploy_opt := left_panel.find_child("DeploymentTypeOption", true, false) as OptionButton
		if deploy_opt:
			deploy_opt.add_theme_color_override("font_color", HudTokens.TEXT)
		var autogen := left_panel.find_child("AutoGenButton", true, false) as Button
		if autogen:
			autogen.add_theme_color_override("font_color", HudTokens.SUCCESS)
			autogen.add_theme_color_override(
				"font_hover_color", Color(HudTokens.SUCCESS.r, HudTokens.SUCCESS.g, HudTokens.SUCCESS.b, 1.0))

	# Make the left tool panel read as a HUD module: deep-navy fill + corner brackets.
	var left_container := get_node_or_null(
		"MarginContainer/VBox/MainContent/LeftPanelContainer") as PanelContainer
	if left_container:
		left_container.add_theme_stylebox_override("panel", HudTokens.panel_style())
		left_container.add_child(HudFrame.new())


## Reorganize the flat left panel into Terrain / Objectives / Deployment tabs.
## Reparents the existing scene + code-built controls into a TabContainer.
func _setup_tabs() -> void:
	var left_panel := terrain_buttons.get_parent()
	if not left_panel:
		return

	var tabs := TabContainer.new()
	tabs.name = "EditorTabs"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var gelaende := VBoxContainer.new()
	gelaende.name = "TabGelaende"
	gelaende.add_theme_constant_override("separation", 8)
	var ziele := VBoxContainer.new()
	ziele.name = "TabZiele"
	ziele.add_theme_constant_override("separation", 8)
	var aufstellung := VBoxContainer.new()
	aufstellung.name = "TabAufstellung"
	aufstellung.add_theme_constant_override("separation", 8)
	tabs.add_child(gelaende)
	tabs.add_child(ziele)
	tabs.add_child(aufstellung)
	left_panel.add_child(tabs)
	tabs.set_tab_title(0, "Terrain")
	tabs.set_tab_title(1, "Objectives")
	tabs.set_tab_title(2, "Deployment")

	var into := func(tab: VBoxContainer, node: Node) -> void:
		if node and is_instance_valid(node) and node.get_parent() == left_panel:
			node.reparent(tab)

	# Terrain: terrain placement tools
	into.call(gelaende, left_panel.get_node_or_null("TerrainLabel"))
	into.call(gelaende, terrain_buttons)
	into.call(gelaende, _modular_terrain_panel)
	into.call(gelaende, left_panel.get_node_or_null("RotationLabel"))
	into.call(gelaende, left_panel.get_node_or_null("RotationSlider"))
	into.call(gelaende, left_panel.get_node_or_null("SymmetryCheck"))
	into.call(gelaende, left_panel.get_node_or_null("AutoGenButton"))
	into.call(gelaende, left_panel.get_node_or_null("StatsLabel"))
	into.call(gelaende, left_panel.get_node_or_null("RecommendationsLabel"))

	# Missionsziele: objectives (the ObjectivesCheck was replaced by this panel)
	into.call(ziele, _objectives_panel)

	# Aufstellung: deployment zones + custom zone editor
	into.call(aufstellung, left_panel.get_node_or_null("DeploymentLabel"))
	into.call(aufstellung, left_panel.get_node_or_null("DeploymentTypeOption"))
	into.call(aufstellung, left_panel.get_node_or_null("DeploymentCheck"))
	into.call(aufstellung, _custom_zone_panel)

	# Drop the now-loose separators left behind in the panel
	for child in left_panel.get_children():
		if child != tabs and child is HSeparator:
			child.queue_free()


## Setup the deployment zone type option button
func _setup_deployment_type_option() -> void:
	if not deployment_type_option:
		return

	# Clear existing items
	deployment_type_option.clear()

	# Add deployment zone types (matching terrain_overlay.gd DeploymentType enum)
	deployment_type_option.add_item("None", 0)
	deployment_type_option.add_item("Front Line (12\")", 1)  # Standard OPR free rule
	deployment_type_option.add_item("Custom Zones", 2)  # User-defined polygon zones

	# Select current type
	deployment_type_option.selected = deployment_type

	# Connect signal
	deployment_type_option.item_selected.connect(_on_deployment_type_selected)

	# Setup custom zone UI (initially hidden)
	_setup_custom_zone_ui()


## Handle deployment zone type selection
func _on_deployment_type_selected(index: int) -> void:
	deployment_type = index
	deployment_type_changed.emit(index)

	# Auto-show deployment zones when a type is selected
	if index > 0:
		show_deployment_zones = true
		if deployment_check:
			deployment_check.button_pressed = true
	else:
		show_deployment_zones = false
		if deployment_check:
			deployment_check.button_pressed = false

	# Show/hide custom zone UI
	_update_custom_zone_ui_visibility()

	grid_container.queue_redraw()


# ============================================================================
# Custom Deployment Zone Editing
# ============================================================================

var _custom_zone_panel: VBoxContainer = null
var _custom_zone_symmetric_check: CheckBox = null
var _custom_zone_start_btn: Button = null
var _custom_zone_confirm_btn: Button = null
var _custom_zone_cancel_btn: Button = null
var _custom_zone_clear_btn: Button = null
var _custom_zone_status_label: Label = null


## Setup custom zone editing UI
func _setup_custom_zone_ui() -> void:
	# Find the LeftPanel to add custom zone controls
	var left_panel = deployment_type_option.get_parent()
	if not left_panel:
		return

	# Create custom zone panel (after DeploymentCheck)
	_custom_zone_panel = VBoxContainer.new()
	_custom_zone_panel.name = "CustomZonePanel"
	_custom_zone_panel.visible = false

	# Find DeploymentCheck and insert after it
	var deploy_check_idx = deployment_check.get_index()
	left_panel.add_child(_custom_zone_panel)
	left_panel.move_child(_custom_zone_panel, deploy_check_idx + 1)

	# Symmetric mode checkbox
	_custom_zone_symmetric_check = CheckBox.new()
	_custom_zone_symmetric_check.text = "Symmetric (point-mirrored)"
	_custom_zone_symmetric_check.button_pressed = true
	_custom_zone_symmetric_check.add_theme_color_override("font_color", HudTokens.TEXT)
	_custom_zone_symmetric_check.toggled.connect(func(v): custom_zone_symmetric = v)
	_custom_zone_panel.add_child(_custom_zone_symmetric_check)

	# Status label
	_custom_zone_status_label = Label.new()
	_custom_zone_status_label.text = "Click grid to add zone vertices"
	_custom_zone_status_label.add_theme_font_size_override("font_size", 12)
	_custom_zone_status_label.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
	_custom_zone_panel.add_child(_custom_zone_status_label)

	# Button container
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	_custom_zone_panel.add_child(btn_row)

	# Start button
	_custom_zone_start_btn = Button.new()
	_custom_zone_start_btn.text = "Start Drawing"
	_custom_zone_start_btn.add_theme_color_override("font_color", HudTokens.SUCCESS)
	_custom_zone_start_btn.pressed.connect(_on_custom_zone_start)
	btn_row.add_child(_custom_zone_start_btn)

	# Confirm button
	_custom_zone_confirm_btn = Button.new()
	_custom_zone_confirm_btn.text = "Confirm"
	_custom_zone_confirm_btn.disabled = true
	_custom_zone_confirm_btn.add_theme_color_override("font_color", HudTokens.CYAN)
	_custom_zone_confirm_btn.pressed.connect(_on_custom_zone_confirm)
	btn_row.add_child(_custom_zone_confirm_btn)

	# Clear button
	_custom_zone_clear_btn = Button.new()
	_custom_zone_clear_btn.text = "Clear"
	_custom_zone_clear_btn.add_theme_color_override("font_color", HudTokens.AMBER)
	_custom_zone_clear_btn.pressed.connect(_on_custom_zone_clear)
	btn_row.add_child(_custom_zone_clear_btn)


## Update visibility of custom zone UI based on deployment type
func _update_custom_zone_ui_visibility() -> void:
	if _custom_zone_panel:
		_custom_zone_panel.visible = (deployment_type == DeploymentType.CUSTOM)


## Start custom zone drawing
func _on_custom_zone_start() -> void:
	custom_zone_editing = true
	custom_zone_current_player = 1

	# Clear previous vertices if starting fresh
	if custom_zone_symmetric:
		custom_zone_vertices_p1.clear()
		custom_zone_vertices_p2.clear()
		_custom_zone_status_label.text = "Drawing zones (symmetric)..."
	else:
		custom_zone_vertices_p1.clear()
		_custom_zone_status_label.text = "Drawing Player 1 zone..."

	_custom_zone_start_btn.disabled = true
	_custom_zone_symmetric_check.disabled = true
	_custom_zone_confirm_btn.disabled = false

	grid_container.queue_redraw()


## Confirm current zone and move to next (or finish)
func _on_custom_zone_confirm() -> void:
	if custom_zone_symmetric:
		# Symmetric mode - both zones done at once
		custom_zone_editing = false
		_custom_zone_status_label.text = "Custom zones defined!"
		_finish_custom_zone_editing()
	else:
		# Asymmetric mode
		if custom_zone_current_player == 1:
			# Move to player 2
			custom_zone_current_player = 2
			_custom_zone_status_label.text = "Drawing Player 2 zone..."
		else:
			# Done with both
			custom_zone_editing = false
			_custom_zone_status_label.text = "Custom zones defined!"
			_finish_custom_zone_editing()

	grid_container.queue_redraw()


## Finish custom zone editing
func _finish_custom_zone_editing() -> void:
	_custom_zone_start_btn.disabled = false
	_custom_zone_symmetric_check.disabled = false
	_custom_zone_confirm_btn.disabled = true

	# Emit signal to update terrain_overlay with custom zones
	deployment_type_changed.emit(DeploymentType.CUSTOM)


## Clear all custom zone vertices
func _on_custom_zone_clear() -> void:
	custom_zone_vertices_p1.clear()
	custom_zone_vertices_p2.clear()
	custom_zone_editing = false
	custom_zone_current_player = 1
	_custom_zone_status_label.text = "Click grid to add zone vertices"
	_custom_zone_start_btn.disabled = false
	_custom_zone_symmetric_check.disabled = false
	_custom_zone_confirm_btn.disabled = true
	grid_container.queue_redraw()


## Handle click during custom zone editing
## cell: Float coordinates (Vector2) for precise boundary placement
func _handle_custom_zone_click(cell: Vector2) -> void:
	if not custom_zone_editing:
		return

	if custom_zone_symmetric:
		# Add to player 1 vertices, mirrored vertex added automatically
		custom_zone_vertices_p1.append(cell)
		var mirrored = _get_mirrored_cell(cell)
		# Insert at beginning to reverse winding order for 180° symmetry
		# This ensures the mirrored polygon has correct orientation
		custom_zone_vertices_p2.insert(0, mirrored)
		_custom_zone_status_label.text = "P1: %d vertices | P2: %d vertices" % [
			custom_zone_vertices_p1.size(), custom_zone_vertices_p2.size()
		]
	else:
		# Add to current player's vertices
		if custom_zone_current_player == 1:
			custom_zone_vertices_p1.append(cell)
			_custom_zone_status_label.text = "Player 1: %d vertices" % custom_zone_vertices_p1.size()
		else:
			custom_zone_vertices_p2.append(cell)
			_custom_zone_status_label.text = "Player 2: %d vertices" % custom_zone_vertices_p2.size()

	grid_container.queue_redraw()


func _setup_terrain_buttons() -> void:
	for child in terrain_buttons.get_children():
		child.queue_free()

	for type in [TerrainType.RUINS, TerrainType.FOREST, TerrainType.CONTAINER, TerrainType.DANGEROUS, TerrainType.NONE]:
		var btn = Button.new()
		btn.text = TERRAIN_NAMES[type]
		btn.custom_minimum_size = Vector2(0, 44)
		btn.toggle_mode = true
		btn.button_pressed = (type == selected_terrain_type)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Glassmorphism style - semi-transparent with terrain color tint
		var terrain_color = TERRAIN_COLORS[type]

		# Normal state - glass panel with terrain color
		var style = StyleBoxFlat.new()
		style.bg_color = Color(terrain_color.r, terrain_color.g, terrain_color.b, 0.25)
		style.set_corner_radius_all(HudTokens.RADIUS)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(terrain_color.r, terrain_color.g, terrain_color.b, 0.4)
		style.content_margin_left = 12
		style.content_margin_right = 12
		btn.add_theme_stylebox_override("normal", style)

		# Hover state - brighter
		var hover_style = style.duplicate()
		hover_style.bg_color = Color(terrain_color.r, terrain_color.g, terrain_color.b, 0.35)
		hover_style.border_color = Color(terrain_color.r, terrain_color.g, terrain_color.b, 0.6)
		btn.add_theme_stylebox_override("hover", hover_style)

		# Pressed/selected state - solid with glow border
		var pressed_style = style.duplicate()
		pressed_style.bg_color = Color(terrain_color.r, terrain_color.g, terrain_color.b, 0.5)
		pressed_style.border_width_left = 2
		pressed_style.border_width_top = 2
		pressed_style.border_width_right = 2
		pressed_style.border_width_bottom = 2
		pressed_style.border_color = Color(1.0, 1.0, 1.0, 0.8)
		btn.add_theme_stylebox_override("pressed", pressed_style)

		# Text color
		btn.add_theme_color_override("font_color", HudTokens.TEXT)
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))

		btn.pressed.connect(_on_terrain_button_pressed.bind(type, btn))
		terrain_buttons.add_child(btn)

		if TERRAIN_DESCRIPTIONS.has(type):
			btn.tooltip_text = TERRAIN_DESCRIPTIONS[type]


func _on_terrain_button_pressed(type: TerrainType, button: Button) -> void:
	selected_terrain_type = type
	# Update button states
	for child in terrain_buttons.get_children():
		if child is Button:
			child.button_pressed = (child == button)


# ==============================================================================
# MODULAR TERRAIN UI (Walls, Auto-Populate)
# ==============================================================================

func _setup_modular_terrain_ui() -> void:
	var left_panel: VBoxContainer = terrain_buttons.get_parent()
	if not left_panel:
		return

	_modular_terrain_panel = VBoxContainer.new()
	_modular_terrain_panel.name = "ModularTerrainPanel"
	_modular_terrain_panel.add_theme_constant_override("separation", 8)
	left_panel.add_child(_modular_terrain_panel)

	# Section header
	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.2)
	_modular_terrain_panel.add_child(sep)

	var header := Label.new()
	header.text = "Modular Terrain"
	header.add_theme_font_override("font", HudTokens.head_font())
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", HudTokens.TEXT)
	_modular_terrain_panel.add_child(header)

	# Prefab palette: canonical 1-click pieces (footprint + walls + decoration)
	var prefab_label := Label.new()
	prefab_label.text = "Terrain Piece:"
	prefab_label.add_theme_font_size_override("font_size", 13)
	prefab_label.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
	_modular_terrain_panel.add_child(prefab_label)

	_prefab_option_btn = OptionButton.new()
	_prefab_option_btn.add_theme_color_override("font_color", HudTokens.TEXT)
	for prefab_key in TerrainPrefabs.keys():
		_prefab_option_btn.add_item(TerrainPrefabs.display_name(prefab_key))
	_prefab_option_btn.item_selected.connect(_on_prefab_selected)
	_modular_terrain_panel.add_child(_prefab_option_btn)
	var prefab_keys := TerrainPrefabs.keys()
	if not prefab_keys.is_empty():
		selected_prefab_key = prefab_keys[0]

	# Editor mode toggle
	_editor_mode_btn = Button.new()
	_editor_mode_btn.text = "Mode: Paint Cells"
	_editor_mode_btn.custom_minimum_size = Vector2(0, 36)
	_editor_mode_btn.add_theme_color_override("font_color", HudTokens.AMBER)
	_editor_mode_btn.add_theme_color_override(
		"font_hover_color", Color(HudTokens.AMBER.r, HudTokens.AMBER.g, HudTokens.AMBER.b, 1.0))
	_editor_mode_btn.pressed.connect(_on_editor_mode_toggled)
	_modular_terrain_panel.add_child(_editor_mode_btn)

	# Wall variant selection (visible when PLACE_WALLS mode)
	var wall_label := Label.new()
	wall_label.text = "Wall Variant:"
	wall_label.add_theme_font_size_override("font_size", 13)
	wall_label.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
	_modular_terrain_panel.add_child(wall_label)

	_wall_option_btn = OptionButton.new()
	_wall_option_btn.add_theme_color_override("font_color", HudTokens.TEXT)
	_wall_option_btn.item_selected.connect(_on_wall_variant_selected)
	_modular_terrain_panel.add_child(_wall_option_btn)

	# Status label
	_modular_status_label = Label.new()
	_modular_status_label.text = "Walls: 0 | Objects: 0"
	_modular_status_label.add_theme_font_size_override("font_size", 12)
	_modular_status_label.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
	_modular_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_modular_terrain_panel.add_child(_modular_status_label)

	# Separator before undo/redo
	var sep2 := HSeparator.new()
	sep2.modulate = Color(1, 1, 1, 0.15)
	_modular_terrain_panel.add_child(sep2)

	# Undo / Redo row
	var undo_row := HBoxContainer.new()
	undo_row.add_theme_constant_override("separation", 8)
	_modular_terrain_panel.add_child(undo_row)

	_undo_btn = Button.new()
	_undo_btn.text = "↶ Undo"
	_undo_btn.custom_minimum_size = Vector2(0, 36)
	_undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_undo_btn.disabled = true
	_undo_btn.tooltip_text = "Undo (Ctrl+Z)"
	_undo_btn.pressed.connect(undo)
	undo_row.add_child(_undo_btn)

	_redo_btn = Button.new()
	_redo_btn.text = "↷ Redo"
	_redo_btn.custom_minimum_size = Vector2(0, 36)
	_redo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_redo_btn.disabled = true
	_redo_btn.tooltip_text = "Redo (Ctrl+Y)"
	_redo_btn.pressed.connect(redo)
	undo_row.add_child(_redo_btn)

	# Built-in default wall for manual edge placement (procedural hologram wall).
	# No terrain theme needed — the renderer builds wall geometry procedurally.
	available_walls = [{"key": TerrainPrefabs.PROC_WALL_KEY, "name": "Wall (3\")"}]
	selected_wall_key = TerrainPrefabs.PROC_WALL_KEY

	_update_modular_terrain_ui()


func _update_modular_terrain_ui() -> void:
	if not _editor_mode_btn:
		return

	match editor_mode:
		EditorMode.PAINT_CELLS:
			_editor_mode_btn.text = "Mode: Paint Cells"
		EditorMode.PLACE_WALLS:
			_editor_mode_btn.text = "Mode: Place Walls"
		EditorMode.PLACE_PREFAB:
			_editor_mode_btn.text = "Mode: Place Piece  (R rotate · F flip)"
		EditorMode.MOVE_PIECES:
			_editor_mode_btn.text = "Mode: Move Pieces  (R/F · Del)"

	# Wall selection only visible in PLACE_WALLS mode
	if _wall_option_btn:
		_wall_option_btn.visible = (editor_mode == EditorMode.PLACE_WALLS)
		var wall_label_node: Node = _wall_option_btn.get_parent().get_child(
			_wall_option_btn.get_index() - 1)
		if wall_label_node:
			wall_label_node.visible = (editor_mode == EditorMode.PLACE_WALLS)

	# Prefab selection only visible in PLACE_PREFAB mode
	if _prefab_option_btn:
		_prefab_option_btn.visible = (editor_mode == EditorMode.PLACE_PREFAB)
		var prefab_label_node: Node = _prefab_option_btn.get_parent().get_child(
			_prefab_option_btn.get_index() - 1)
		if prefab_label_node:
			prefab_label_node.visible = (editor_mode == EditorMode.PLACE_PREFAB)

	_update_wall_option_list()
	_update_modular_status()


func _update_wall_option_list() -> void:
	if not _wall_option_btn:
		return
	_wall_option_btn.clear()
	for i in range(available_walls.size()):
		var wall: Dictionary = available_walls[i]
		_wall_option_btn.add_item(wall.get("name", wall.get("key", "?")), i)
	# Select current
	for i in range(available_walls.size()):
		if available_walls[i].get("key", "") == selected_wall_key:
			_wall_option_btn.selected = i
			break


func _update_modular_status() -> void:
	if not _modular_status_label:
		return
	_modular_status_label.text = "Walls: %d | Objects: %d" % [
		wall_segments.size(), placed_objects.size()]


func _on_editor_mode_toggled() -> void:
	match editor_mode:
		EditorMode.PAINT_CELLS:
			editor_mode = EditorMode.PLACE_WALLS
		EditorMode.PLACE_WALLS:
			editor_mode = EditorMode.PLACE_PREFAB
		EditorMode.PLACE_PREFAB:
			editor_mode = EditorMode.MOVE_PIECES
		EditorMode.MOVE_PIECES:
			editor_mode = EditorMode.PAINT_CELLS
	_selected_piece_id = -1
	_dragging_piece = false
	_preview_active = false
	_update_modular_terrain_ui()
	if grid_container:
		grid_container.queue_redraw()


## Handle prefab selection from the palette and switch to placement mode.
func _on_prefab_selected(index: int) -> void:
	var prefab_keys := TerrainPrefabs.keys()
	if index < 0 or index >= prefab_keys.size():
		return
	selected_prefab_key = prefab_keys[index]
	editor_mode = EditorMode.PLACE_PREFAB
	_update_modular_terrain_ui()


## Place a complete canonical terrain piece (footprint + walls + decoration) in one
## click, in the given orientation. Mirrors across the table center when enabled.
func place_prefab(prefab_key: String, origin: Vector2i, rot_deg: int, flip: bool, mirror: bool) -> void:
	if not TerrainPrefabs.has_prefab(prefab_key):
		return
	_push_undo()
	_add_piece(prefab_key, origin, rot_deg, flip)
	if mirror:
		var dims := TerrainPrefabs.footprint_size(prefab_key, rot_deg)
		var mirrored := _mirror_position(origin, dims, _calculate_grid_dimensions())
		# Point symmetry = 180° rotation about the table center, so the mirrored piece's
		# walls land on the opposite corner (e.g. N+W -> S+E).
		_add_piece(prefab_key, mirrored, (rot_deg + 180) % 360, flip)
	_rebuild_derived()
	_update_modular_status()


## Append a new piece (source of truth). seed=id keeps its decoration layout stable.
func _add_piece(prefab_key: String, origin: Vector2i, rot_deg: int, flip: bool) -> int:
	var id := _next_piece_id
	_next_piece_id += 1
	placed_pieces.append({
		"id": id,
		"prefab_key": prefab_key,
		"origin": origin,
		"rotation": rot_deg,
		"flip": flip,
		"seed": id,
	})
	return id


## Index of the topmost placed piece whose footprint covers `cell`, or -1.
func _piece_index_at_cell(cell: Vector2i) -> int:
	for i in range(placed_pieces.size() - 1, -1, -1):
		var p: Dictionary = placed_pieces[i]
		for fc in TerrainPrefabs.footprint_cells(p["prefab_key"], p["origin"], p.get("rotation", 0), p.get("flip", false)):
			if fc == cell:
				return i
	return -1


func _piece_index_by_id(piece_id: int) -> int:
	for i in range(placed_pieces.size()):
		if placed_pieces[i]["id"] == piece_id:
			return i
	return -1


## Rotate the prefab preview (PLACE_PREFAB) or the selected piece (MOVE_PIECES) 90° CW.
func _rotate_active() -> void:
	if editor_mode == EditorMode.PLACE_PREFAB:
		_preview_rotation = wrapi(_preview_rotation + 90, 0, 360)
		if grid_container:
			grid_container.queue_redraw()
	elif editor_mode == EditorMode.MOVE_PIECES and _selected_piece_id >= 0:
		var idx := _piece_index_by_id(_selected_piece_id)
		if idx >= 0:
			_push_undo()
			placed_pieces[idx]["rotation"] = wrapi(int(placed_pieces[idx].get("rotation", 0)) + 90, 0, 360)
			_rebuild_derived()


## Flip the prefab preview / selected piece (mirror the wall L onto the other side).
func _flip_active() -> void:
	if editor_mode == EditorMode.PLACE_PREFAB:
		_preview_flip = not _preview_flip
		if grid_container:
			grid_container.queue_redraw()
	elif editor_mode == EditorMode.MOVE_PIECES and _selected_piece_id >= 0:
		var idx := _piece_index_by_id(_selected_piece_id)
		if idx >= 0:
			_push_undo()
			placed_pieces[idx]["flip"] = not bool(placed_pieces[idx].get("flip", false))
			_rebuild_derived()


## Delete the selected piece (MOVE_PIECES mode).
func _delete_selected_piece() -> void:
	var idx := _piece_index_by_id(_selected_piece_id)
	if idx < 0:
		return
	_push_undo()
	placed_pieces.remove_at(idx)
	_selected_piece_id = -1
	_rebuild_derived()
	_update_modular_status()


## Move the currently-dragged piece so it follows the cursor (gated on cell change).
func _drag_selected_piece(screen_pos: Vector2) -> void:
	var idx := _piece_index_by_id(_selected_piece_id)
	if idx < 0:
		return
	var new_origin: Vector2i = _get_cell_at_screen_pos(screen_pos) + _drag_grab_offset
	if new_origin == placed_pieces[idx]["origin"]:
		return
	if not _drag_pushed:
		_push_undo()
		_drag_pushed = true
	placed_pieces[idx]["origin"] = new_origin
	_rebuild_derived()


## Rebuild the derived grid_cells / wall_segments / placed_objects from the
## source-of-truth (free edits + placed pieces), then refresh UI + 3D + network.
func _rebuild_derived() -> void:
	grid_cells.clear()
	wall_segments.clear()
	placed_objects.clear()

	for cell: Vector2i in free_cells:
		grid_cells[cell] = free_cells[cell]
	for w: Dictionary in free_walls:
		wall_segments.append(w.duplicate())

	for piece: Dictionary in placed_pieces:
		var key: String = piece["prefab_key"]
		var origin: Vector2i = piece["origin"]
		var rot: int = piece.get("rotation", 0)
		var flip: bool = piece.get("flip", false)
		var ttype: int = TerrainPrefabs.terrain_type(key)
		for cell: Vector2i in TerrainPrefabs.footprint_cells(key, origin, rot, flip):
			grid_cells[cell] = ttype
		for seg: Dictionary in TerrainPrefabs.wall_segments_for(key, origin, rot, flip):
			wall_segments.append(seg)
		var rng := RandomNumberGenerator.new()
		rng.seed = piece.get("seed", piece["id"])
		for obj: Dictionary in TerrainPrefabs.decoration_for(key, origin, rng, rot, flip):
			placed_objects.append(obj)

	_update_stats()
	if grid_container:
		grid_container.queue_redraw()
	_emit_layout_update()


# ==============================================================================
# UNDO / REDO (snapshots of the source-of-truth)
# ==============================================================================

func _snapshot() -> Dictionary:
	return {
		"pieces": placed_pieces.duplicate(true),
		"free_cells": free_cells.duplicate(true),
		"free_walls": free_walls.duplicate(true),
		"next_id": _next_piece_id,
	}


func _apply_snapshot(snap: Dictionary) -> void:
	placed_pieces = (snap["pieces"] as Array).duplicate(true)
	free_cells = (snap["free_cells"] as Dictionary).duplicate(true)
	free_walls = (snap["free_walls"] as Array).duplicate(true)
	_next_piece_id = int(snap.get("next_id", _next_piece_id))
	_rebuild_derived()
	_update_modular_status()


## Push the current state onto the undo stack (call BEFORE a mutation).
func _push_undo() -> void:
	_undo_stack.append(_snapshot())
	if _undo_stack.size() > UNDO_LIMIT:
		_undo_stack.pop_front()
	_redo_stack.clear()
	_update_undo_redo_buttons()


func undo() -> void:
	if _undo_stack.is_empty():
		return
	_redo_stack.append(_snapshot())
	_apply_snapshot(_undo_stack.pop_back())
	_update_undo_redo_buttons()


func redo() -> void:
	if _redo_stack.is_empty():
		return
	_undo_stack.append(_snapshot())
	_apply_snapshot(_redo_stack.pop_back())
	_update_undo_redo_buttons()


func _update_undo_redo_buttons() -> void:
	if _undo_btn:
		_undo_btn.disabled = _undo_stack.is_empty()
	if _redo_btn:
		_redo_btn.disabled = _redo_stack.is_empty()


func _on_wall_variant_selected(index: int) -> void:
	if index >= 0 and index < available_walls.size():
		selected_wall_key = available_walls[index].get("key", "")


func _on_rotation_changed(value: float) -> void:
	grid_rotation_degrees = value
	rotation_label.text = "Grid Rotation: %.0f°" % value
	grid_container.queue_redraw()
	_emit_layout_update()


func _on_symmetry_toggled(enabled: bool) -> void:
	point_symmetry_enabled = enabled
	grid_container.queue_redraw()


func _on_close_pressed() -> void:
	# Send final update to 3D view before closing
	_emit_layout_update()
	# Reset zoom and pan for next open
	reset_zoom()
	layout_closed.emit()
	hide()


func _on_clear_pressed() -> void:
	_push_undo()
	placed_pieces.clear()
	free_cells.clear()
	free_walls.clear()
	_selected_piece_id = -1
	_rebuild_derived()
	_update_modular_status()


func _on_autogen_pressed() -> void:
	_push_undo()
	_generate_terrain_layout()
	_rebuild_derived()
	_update_modular_status()


func _on_save_pressed() -> void:
	if save_file_dialog:
		save_file_dialog.popup_centered()


func _on_load_pressed() -> void:
	if load_file_dialog:
		load_file_dialog.popup_centered()


func _on_deployment_toggled(enabled: bool) -> void:
	show_deployment_zones = enabled
	grid_container.queue_redraw()


# ============================================================================
# Mission Objectives UI Setup
# ============================================================================

## Setup the objectives deployment UI panel
func _setup_objectives_ui() -> void:
	# Find the LeftPanel to add objectives controls (after DeploymentCheck)
	var left_panel = deployment_check.get_parent() if deployment_check else null
	if not left_panel:
		return

	# Remove the old ObjectivesCheck if it exists
	var old_check = left_panel.get_node_or_null("ObjectivesCheck")
	if old_check:
		old_check.queue_free()

	# Create objectives panel
	_objectives_panel = VBoxContainer.new()
	_objectives_panel.name = "ObjectivesPanel"

	# Find position after DeploymentCheck
	var deploy_check_idx = deployment_check.get_index()
	left_panel.add_child(_objectives_panel)
	left_panel.move_child(_objectives_panel, deploy_check_idx + 1)

	# Section label
	var label = Label.new()
	label.text = "Mission Objectives"
	label.add_theme_font_override("font", HudTokens.head_font())
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", HudTokens.TEXT)
	_objectives_panel.add_child(label)

	# Status label
	_objectives_status_label = Label.new()
	_objectives_status_label.text = "No objectives placed"
	_objectives_status_label.add_theme_font_size_override("font_size", 12)
	_objectives_status_label.add_theme_color_override("font_color", HudTokens.TEXT_MUTED)
	_objectives_panel.add_child(_objectives_status_label)

	# Warning label (for 9" rule)
	_objectives_warning_label = Label.new()
	_objectives_warning_label.text = ""
	_objectives_warning_label.add_theme_font_size_override("font_size", 12)
	_objectives_warning_label.add_theme_color_override("font_color", HudTokens.DANGER)
	_objectives_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_objectives_panel.add_child(_objectives_warning_label)

	# Button container
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	_objectives_panel.add_child(btn_row)

	# Deploy/Stop button (toggle)
	_objectives_toggle_btn = Button.new()
	_objectives_toggle_btn.text = "Deploy Objectives"
	_objectives_toggle_btn.toggle_mode = true
	_objectives_toggle_btn.add_theme_color_override("font_color", HudTokens.AMBER)
	_objectives_toggle_btn.add_theme_color_override(
		"font_hover_color", Color(HudTokens.AMBER.r, HudTokens.AMBER.g, HudTokens.AMBER.b, 1.0))
	_objectives_toggle_btn.toggled.connect(_on_objectives_deploy_toggled)
	btn_row.add_child(_objectives_toggle_btn)

	# Clear button
	_objectives_clear_btn = Button.new()
	_objectives_clear_btn.text = "Clear"
	_objectives_clear_btn.add_theme_color_override("font_color", HudTokens.AMBER)
	_objectives_clear_btn.pressed.connect(_on_objectives_clear)
	btn_row.add_child(_objectives_clear_btn)

	_update_objectives_status()


## Toggle objectives deployment mode
func _on_objectives_deploy_toggled(enabled: bool) -> void:
	objectives_editing = enabled
	if enabled:
		_objectives_toggle_btn.text = "Stop Deploying"
		# Deselect terrain type when entering objectives mode
		selected_terrain_type = TerrainType.NONE
		for child in terrain_buttons.get_children():
			if child is Button:
				child.button_pressed = (child.text == "None")
	else:
		_objectives_toggle_btn.text = "Deploy Objectives"
		# Emit signal to update 3D view
		objectives_changed.emit(mission_objectives)

	grid_container.queue_redraw()


## Clear all objectives
func _on_objectives_clear() -> void:
	mission_objectives.clear()
	_update_objectives_status()
	grid_container.queue_redraw()
	objectives_changed.emit(mission_objectives)


## Update the objectives status label and check 9" rule
func _update_objectives_status() -> void:
	if not _objectives_status_label:
		return

	var count = mission_objectives.size()
	if count == 0:
		_objectives_status_label.text = "No objectives placed"
	else:
		_objectives_status_label.text = "%d objective%s placed" % [count, "s" if count != 1 else ""]

	# Check 9" minimum distance rule
	_check_objectives_distance_rule()


## Check if any objectives are closer than 9" and show warning
func _check_objectives_distance_rule() -> void:
	if not _objectives_warning_label:
		return

	const MIN_DISTANCE_INCHES := 9.0
	var violations: Array[String] = []

	for i in range(mission_objectives.size()):
		for j in range(i + 1, mission_objectives.size()):
			var dist = mission_objectives[i].distance_to(mission_objectives[j])
			if dist < MIN_DISTANCE_INCHES:
				violations.append("Obj %d & %d: %.1f\"" % [i + 1, j + 1, dist])

	if violations.size() > 0:
		_objectives_warning_label.text = "⚠ Too close (<9\"): " + ", ".join(violations)
	else:
		_objectives_warning_label.text = ""


func _on_save_file_selected(path: String) -> void:
	save_layout(path)


func _on_load_file_selected(path: String) -> void:
	if not load_layout(path):
		push_error("Failed to load layout")


func set_table_size(size_feet: Vector2) -> void:
	# Check if table size actually changed
	var size_changed = table_size_feet != size_feet

	table_size_feet = size_feet

	# CRITICAL: If table size changed and we have terrain/objective data, clear it
	# Grid cell coordinates are ABSOLUTE and become invalid when grid dimensions change
	if size_changed:
		if not placed_pieces.is_empty() or not free_cells.is_empty() or not free_walls.is_empty():
			print("  ⚠ Table size changed - clearing terrain data (grid coordinates are now invalid)")
			placed_pieces.clear()
			free_cells.clear()
			free_walls.clear()
			grid_cells.clear()
			wall_segments.clear()
			placed_objects.clear()
			_selected_piece_id = -1
		if not mission_objectives.is_empty():
			print("  ⚠ Table size changed - clearing mission objectives (coordinates are now invalid)")
			mission_objectives.clear()

	grid_container.queue_redraw()
	_update_stats()
	# NOTE: Don't emit layout_updated here - it may be called during initialization
	# before terrain_overlay exists. Updates are sent when user closes editor.


func _calculate_grid_dimensions() -> Vector2i:
	var width_inches = table_size_feet.x * 12.0
	var height_inches = table_size_feet.y * 12.0

	# Use diagonal to ensure grid covers entire table at any rotation
	var diagonal = sqrt(width_inches * width_inches + height_inches * height_inches)
	var grid_size = int(ceil(diagonal / GRID_SIZE_INCHES))

	# Round UP to even number to ensure intersection point at center
	# Even number of cells → odd number of lines → center line exists
	# E.g., 30 cells → 31 lines (0-30) → line 15 is center
	if grid_size % 2 != 0:
		grid_size += 1

	return Vector2i(grid_size, grid_size)


func _update_stats() -> void:
	var grid_dims = _calculate_grid_dimensions()
	var total_cells = grid_dims.x * grid_dims.y

	var counts := {
		TerrainType.NONE: 0,
		TerrainType.RUINS: 0,
		TerrainType.FOREST: 0,
		TerrainType.CONTAINER: 0,
		TerrainType.DANGEROUS: 0
	}

	for cell_pos in grid_cells:
		var type = grid_cells[cell_pos]
		counts[type] += 1

	counts[TerrainType.NONE] = total_cells - (counts[TerrainType.RUINS] + counts[TerrainType.FOREST] + counts[TerrainType.CONTAINER] + counts[TerrainType.DANGEROUS])

	# Count terrain pieces (connected cells of same type count as one piece)
	var piece_counts = _count_terrain_pieces()
	var total_pieces = piece_counts[TerrainType.RUINS] + piece_counts[TerrainType.FOREST] + piece_counts[TerrainType.CONTAINER] + piece_counts[TerrainType.DANGEROUS]

	# Calculate coverage percentages
	var terrain_cells = counts[TerrainType.RUINS] + counts[TerrainType.FOREST] + counts[TerrainType.CONTAINER] + counts[TerrainType.DANGEROUS]
	var coverage_pct = (float(terrain_cells) / total_cells) * 100.0 if total_cells > 0 else 0.0

	# Blocking LOS = everything that provides cover (Ruins, Forest, Container)
	var _blocking_cells = counts[TerrainType.RUINS] + counts[TerrainType.FOREST] + counts[TerrainType.CONTAINER]
	var blocking_pieces = piece_counts[TerrainType.RUINS] + piece_counts[TerrainType.FOREST] + piece_counts[TerrainType.CONTAINER]

	# Cover = Ruins, Forest, Container
	var cover_pieces = piece_counts[TerrainType.RUINS] + piece_counts[TerrainType.FOREST] + piece_counts[TerrainType.CONTAINER]

	# Difficult = Forest only
	var difficult_pieces = piece_counts[TerrainType.FOREST]

	# Dangerous pieces
	var dangerous_pieces = piece_counts[TerrainType.DANGEROUS]

	# Calculate piece percentages (relative to total terrain pieces)
	var blocking_pct = (float(blocking_pieces) / total_pieces) * 100.0 if total_pieces > 0 else 0.0
	var cover_pct = (float(cover_pieces) / total_pieces) * 100.0 if total_pieces > 0 else 0.0
	var difficult_pct = (float(difficult_pieces) / total_pieces) * 100.0 if total_pieces > 0 else 0.0

	stats_label.text = """Coverage: %.1f%% (%d/%d cells)
Terrain Pieces: %d (goal: 15-20)

Pieces by type:
  Ruins: %d | Forest: %d
  Container: %d | Dangerous: %d

Of %d pieces:
• Blocking LOS: %d (%.0f%%)
• Cover: %d (%.0f%%)
• Difficult: %d (%.0f%%)""" % [
		coverage_pct, terrain_cells, total_cells,
		total_pieces,
		piece_counts[TerrainType.RUINS],
		piece_counts[TerrainType.FOREST],
		piece_counts[TerrainType.CONTAINER],
		piece_counts[TerrainType.DANGEROUS],
		total_pieces,
		blocking_pieces, blocking_pct,
		cover_pieces, cover_pct,
		difficult_pieces, difficult_pct
	]

	_update_recommendations_with_values(total_pieces, coverage_pct, blocking_pct, cover_pct, difficult_pct, dangerous_pieces)


func _count_terrain_pieces() -> Dictionary:
	## Count connected terrain pieces using flood fill
	## Adjacent cells of the same type count as ONE piece
	var piece_counts := {
		TerrainType.RUINS: 0,
		TerrainType.FOREST: 0,
		TerrainType.CONTAINER: 0,
		TerrainType.DANGEROUS: 0
	}

	var visited := {}

	for cell_pos in grid_cells:
		if visited.has(cell_pos):
			continue

		var terrain_type = grid_cells[cell_pos]
		if terrain_type == TerrainType.NONE:
			continue

		# Flood fill to find all connected cells of same type
		_flood_fill(cell_pos, terrain_type, visited)
		piece_counts[terrain_type] += 1

	return piece_counts


func _flood_fill(start: Vector2i, terrain_type: int, visited: Dictionary) -> void:
	## Mark all connected cells of the same type as visited
	var stack := [start]

	while stack.size() > 0:
		var current = stack.pop_back()

		if visited.has(current):
			continue

		if not grid_cells.has(current):
			continue

		if grid_cells[current] != terrain_type:
			continue

		visited[current] = true

		# Check 4 neighbors (orthogonal only - not diagonal)
		var neighbors := [
			Vector2i(current.x + 1, current.y),
			Vector2i(current.x - 1, current.y),
			Vector2i(current.x, current.y + 1),
			Vector2i(current.x, current.y - 1)
		]

		for neighbor in neighbors:
			if not visited.has(neighbor):
				stack.append(neighbor)


## Flood-fill that collects and returns all connected cells of the same type
func _flood_fill_collect(start: Vector2i, terrain_type: int, visited: Dictionary) -> Array[Vector2i]:
	var collected: Array[Vector2i] = []
	var stack := [start]

	while stack.size() > 0:
		var current: Vector2i = stack.pop_back()

		if visited.has(current):
			continue
		if not grid_cells.has(current):
			continue
		if grid_cells[current] != terrain_type:
			continue

		visited[current] = true
		collected.append(current)

		var neighbors := [
			Vector2i(current.x + 1, current.y),
			Vector2i(current.x - 1, current.y),
			Vector2i(current.x, current.y + 1),
			Vector2i(current.x, current.y - 1)
		]
		for neighbor in neighbors:
			if not visited.has(neighbor):
				stack.append(neighbor)

	return collected


func _update_recommendations() -> void:
	_update_stats()


func _update_recommendations_with_values(total_pieces: int, coverage_pct: float, blocking_pct: float, cover_pct: float, difficult_pct: float, dangerous_pieces: int) -> void:
	# OPR Guidelines:
	# - 15-20 terrain pieces
	# - At least 25% table coverage
	# - 50% of pieces should block LOS
	# - 33% should provide cover
	# - 33% should be difficult
	# - 2 dangerous pieces (1 per player)

	var pieces_ok = total_pieces >= 15
	var coverage_ok = coverage_pct >= 25.0
	var blocking_ok = blocking_pct >= 50.0
	var cover_ok = cover_pct >= 33.0
	var difficult_ok = difficult_pct >= 33.0
	var dangerous_ok = dangerous_pieces >= 2

	# Extended guidelines
	var extended = _check_extended_guidelines()

	var check_mark = "✓"
	var cross_mark = "✗"

	recommendations_label.text = """OPR Terrain Guidelines:

%s 15-20 terrain pieces (have: %d)
%s At least 25%% table coverage (%.1f%%)
%s 50%% should block LOS (%.0f%%)
%s 33%% should provide cover (%.0f%%)
%s 33%% should be difficult (%.0f%%)
%s 1 dangerous piece per player (have: %d)

Extended Guidelines:
%s Max 12" gap between terrain (%.1f")
%s Balanced symmetry (%.0f%%)

Tip: Connected cells = 1 piece""" % [
		check_mark if pieces_ok else cross_mark, total_pieces,
		check_mark if coverage_ok else cross_mark, coverage_pct,
		check_mark if blocking_ok else cross_mark, blocking_pct,
		check_mark if cover_ok else cross_mark, cover_pct,
		check_mark if difficult_ok else cross_mark, difficult_pct,
		check_mark if dangerous_ok else cross_mark, dangerous_pieces,
		check_mark if extended.max_gap_ok else cross_mark, extended.max_gap_inches,
		check_mark if extended.symmetry_ok else cross_mark, extended.symmetry_score
	]

	# Color code the recommendations - Glassmorphism accent colors
	var all_ok = pieces_ok and coverage_ok and blocking_ok and cover_ok and difficult_ok and dangerous_ok and extended.max_gap_ok and extended.symmetry_ok
	if all_ok:
		recommendations_label.add_theme_color_override("font_color", HudTokens.SUCCESS)  # Accent green
	else:
		recommendations_label.add_theme_color_override("font_color", HudTokens.AMBER)  # Accent amber


func _get_grid_rect() -> Rect2:
	## Calculate the BASE grid rectangle that maintains table aspect ratio
	## This is without zoom/pan - used for internal calculations
	var table_aspect = table_size_feet.x / table_size_feet.y
	var available_size = grid_container.size
	var grid_size: Vector2

	if available_size.x / available_size.y > table_aspect:
		grid_size.y = available_size.y
		grid_size.x = grid_size.y * table_aspect
	else:
		grid_size.x = available_size.x
		grid_size.y = grid_size.x / table_aspect

	var offset = (available_size - grid_size) / 2.0
	return Rect2(offset, grid_size)


func _get_zoomed_grid_rect() -> Rect2:
	## Calculate the grid rectangle WITH zoom and pan applied
	## This is used for mouse interaction and drawing
	var base_rect = _get_grid_rect()

	# Calculate new size (zoomed)
	var new_size = base_rect.size * zoom_level

	# Calculate new position (centered, then panned)
	var container_center = grid_container.size / 2.0
	var new_pos = container_center - new_size / 2.0 + pan_offset * zoom_level

	return Rect2(new_pos, new_size)


func _get_cell_at_screen_pos(screen_pos: Vector2) -> Vector2i:
	var grid_dims = _calculate_grid_dimensions()
	var grid_rect = _get_zoomed_grid_rect()  # Use zoomed rect for mouse interaction

	# Calculate cell size using same method as grid drawing
	# (pixels per inch * 3" grid size) - includes zoom
	var table_size_inches = table_size_feet * 12.0
	var pixels_per_inch_x = grid_rect.size.x / table_size_inches.x
	var pixels_per_inch_y = grid_rect.size.y / table_size_inches.y
	var cell_size = Vector2(
		GRID_SIZE_INCHES * pixels_per_inch_x,
		GRID_SIZE_INCHES * pixels_per_inch_y
	)

	# Get position relative to grid container using proper coordinate transform
	var local_pos = grid_container.get_local_mouse_position()

	# Get center of grid (grid is centered in the container with zoom/pan)
	var center = grid_rect.position + grid_rect.size / 2.0

	# Half grid cells for centering calculation
	var half_grid_cells = Vector2(grid_dims.x / 2.0, grid_dims.y / 2.0)

	# Apply inverse rotation around center to get position in grid coordinate system
	var pos_from_center = local_pos - center
	var angle_rad = deg_to_rad(-grid_rotation_degrees)
	var rotated_pos = Vector2(
		pos_from_center.x * cos(angle_rad) - pos_from_center.y * sin(angle_rad),
		pos_from_center.x * sin(angle_rad) + pos_from_center.y * cos(angle_rad)
	)

	# Convert from center-relative position to cell coordinates
	# Cell (x,y) has its center at ((x - half_grid_cells.x + 0.5) * cell_size.x, ...)
	# So to get cell from position: cell_x = pos / cell_size + half_grid_cells - 0.5
	var cell_x = int(floor(rotated_pos.x / cell_size.x + half_grid_cells.x))
	var cell_y = int(floor(rotated_pos.y / cell_size.y + half_grid_cells.y))

	return Vector2i(cell_x, cell_y)


func _get_mirrored_cell(cell: Vector2) -> Vector2:
	## Get the point-symmetric (180° rotated) position relative to TABLE center
	## Cell coordinates are in 1" units (floats for precision)
	var valid_range = _get_valid_cell_range()
	# Convert cell bounds to inch bounds (multiply by 3)
	var table_min_x = valid_range.position.x * 3.0
	var table_min_y = valid_range.position.y * 3.0
	var table_max_x = (valid_range.position.x + valid_range.size.x) * 3.0
	var table_max_y = (valid_range.position.y + valid_range.size.y) * 3.0
	# Mirror: inch position at min maps to max, position at max maps to min
	return Vector2(table_min_x + table_max_x - cell.x, table_min_y + table_max_y - cell.y)


func _inch_to_screen_pos(inch_pos: Vector2) -> Vector2:
	## Convert 1" coordinates (floats for precision) to screen position
	## Uses zoomed grid rect for proper display
	var grid_dims = _calculate_grid_dimensions()
	var grid_rect = _get_zoomed_grid_rect()  # Use zoomed rect
	var center = grid_rect.position + grid_rect.size / 2.0
	var angle_rad = deg_to_rad(grid_rotation_degrees)

	var table_size_inches = table_size_feet * 12.0
	var pixels_per_inch_x = grid_rect.size.x / table_size_inches.x
	var pixels_per_inch_y = grid_rect.size.y / table_size_inches.y

	var half_inches_x = grid_dims.x * 3.0 / 2.0
	var half_inches_y = grid_dims.y * 3.0 / 2.0

	var local_x = (inch_pos.x - half_inches_x) * pixels_per_inch_x
	var local_y = (inch_pos.y - half_inches_y) * pixels_per_inch_y
	var cos_a = cos(angle_rad)
	var sin_a = sin(angle_rad)
	return Vector2(
		local_x * cos_a - local_y * sin_a,
		local_x * sin_a + local_y * cos_a
	) + center


func _is_valid_cell(cell: Vector2i) -> bool:
	## Check if 3" cell is within grid bounds (for terrain painting)
	var grid_dims = _calculate_grid_dimensions()
	return cell.x >= 0 and cell.x < grid_dims.x and cell.y >= 0 and cell.y < grid_dims.y


func _is_valid_inch_pos(inch_pos: Vector2) -> bool:
	## Check if 1" coordinate (float) is within the table boundary
	## When grid is rotated, we must check screen position against table bounds
	var grid_rect = _get_zoomed_grid_rect()  # Use zoomed rect
	var screen_pos = _inch_to_screen_pos(inch_pos)
	# Add small tolerance for boundary snap points
	var tolerance = 2.0 * zoom_level  # Scale tolerance with zoom
	var expanded_rect = grid_rect.grow(tolerance)
	return expanded_rect.has_point(screen_pos)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Check if mouse is over the grid container (for zoom/pan to work within container bounds)
	var container_rect = Rect2(Vector2.ZERO, grid_container.size)
	var local_mouse = grid_container.get_local_mouse_position()
	var mouse_in_grid = container_rect.has_point(local_mouse)

	# Keyboard shortcuts (skip while a text field is focused so filenames type normally)
	if event is InputEventKey and event.pressed and not event.echo \
			and not (get_viewport().gui_get_focus_owner() is LineEdit):
		var placing := editor_mode == EditorMode.PLACE_PREFAB or editor_mode == EditorMode.MOVE_PIECES
		if event.ctrl_pressed and event.keycode == KEY_Y:
			redo()
			get_viewport().set_input_as_handled()
			return
		if event.ctrl_pressed and event.keycode == KEY_Z:
			if event.shift_pressed:
				redo()
			else:
				undo()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_R and placing:
			_rotate_active()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F and placing:
			_flip_active()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_DELETE and editor_mode == EditorMode.MOVE_PIECES:
			_delete_selected_piece()
			get_viewport().set_input_as_handled()
			return

	# Handle zoom with mouse wheel (only when mouse is in grid area)
	if event is InputEventMouseButton:
		if mouse_in_grid:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				if editor_mode == EditorMode.PLACE_PREFAB:
					_rotate_active()
				else:
					_zoom_in(local_mouse)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				if editor_mode == EditorMode.PLACE_PREFAB:
					_preview_rotation = wrapi(_preview_rotation - 90, 0, 360)
					grid_container.queue_redraw()
				else:
					_zoom_out(local_mouse)
				get_viewport().set_input_as_handled()
				return

		# Handle middle mouse button for panning
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed and mouse_in_grid:
				_is_panning = true
				_last_pan_pos = event.position
				get_viewport().set_input_as_handled()
			else:
				_is_panning = false
			return

	# Handle pan motion
	if event is InputEventMouseMotion and _is_panning:
		var delta = event.position - _last_pan_pos
		pan_offset += delta / zoom_level
		_last_pan_pos = event.position
		grid_container.queue_redraw()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Check if clicking on an existing vertex (for dragging)
				# Allow dragging whenever custom zones are selected (not just during editing)
				var has_custom_zones = deployment_type == DeploymentType.CUSTOM and (
					custom_zone_vertices_p1.size() > 0 or custom_zone_vertices_p2.size() > 0
				)
				if custom_zone_editing or has_custom_zones:
					var vertex_hit = _find_vertex_at_screen_pos(event.global_position)
					if vertex_hit.player > 0:
						# Start dragging this vertex
						_dragging_vertex = true
						_dragging_player = vertex_hit.player
						_dragging_index = vertex_hit.index
						if _custom_zone_status_label:
							_custom_zone_status_label.text = "Dragging P%d vertex %d..." % [
								vertex_hit.player, vertex_hit.index + 1
							]
						return
				# Not dragging a vertex.
				# Objective / custom-zone editing ALWAYS take priority over the terrain
				# editor mode — they route through _paint_at_position regardless of mode.
				if objectives_editing or custom_zone_editing:
					_paint_at_position(event.global_position)
				elif editor_mode == EditorMode.MOVE_PIECES:
					var grab_cell := _get_cell_at_screen_pos(event.global_position)
					var grab_idx := _piece_index_at_cell(grab_cell)
					if grab_idx >= 0:
						_selected_piece_id = placed_pieces[grab_idx]["id"]
						_dragging_piece = true
						_drag_pushed = false
						_drag_grab_offset = placed_pieces[grab_idx]["origin"] - grab_cell
					else:
						_selected_piece_id = -1
					grid_container.queue_redraw()
				elif editor_mode == EditorMode.PLACE_WALLS or editor_mode == EditorMode.PLACE_PREFAB:
					# Single click only; place_prefab / add_wall_segment push their own undo
					_paint_at_position(event.global_position)
				else:
					# PAINT_CELLS: one undo snapshot per stroke, then drag-paint
					_push_undo()
					is_painting = true
					_paint_at_position(event.global_position)
			else:
				# Mouse released
				if _dragging_vertex:
					_dragging_vertex = false
					_dragging_player = 0
					_dragging_index = -1
					if _custom_zone_status_label:
						_custom_zone_status_label.text = "P1: %d vertices | P2: %d vertices" % [
							custom_zone_vertices_p1.size(), custom_zone_vertices_p2.size()
						]
					# Emit signal to update 3D terrain overlay
					deployment_type_changed.emit(DeploymentType.CUSTOM)
				is_painting = false
				_dragging_piece = false
				_drag_pushed = false

		# Right-click to remove walls in PLACE_WALLS mode
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if editor_mode == EditorMode.PLACE_WALLS:
				var edge := _get_edge_at_screen_pos(event.global_position)
				if edge.x >= 0:
					remove_wall_segment(Vector2i(edge.x, edge.y), edge.z)
					_update_modular_status()
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		if _dragging_vertex:
			_move_vertex_to_screen_pos(event.global_position)
		elif _dragging_piece:
			_drag_selected_piece(event.global_position)
		elif is_painting:
			_paint_at_position(event.global_position)
		elif editor_mode == EditorMode.PLACE_PREFAB and mouse_in_grid \
				and not objectives_editing and not custom_zone_editing:
			_preview_cell = _get_cell_at_screen_pos(event.global_position)
			_preview_active = true
			grid_container.queue_redraw()


func _paint_at_position(screen_pos: Vector2) -> void:
	# Check if we're editing custom deployment zones - use snap points
	if custom_zone_editing:
		var snap_result = _find_nearest_boundary_snap_point(screen_pos)
		if snap_result.found:
			_handle_custom_zone_click(snap_result.cell)
		else:
			# Fallback to 1" grid position if no snap point nearby
			var inch_pos = _get_inch_at_screen_pos(screen_pos)
			if _is_valid_inch_pos(inch_pos):
				_handle_custom_zone_click(inch_pos)
		return

	# If in objectives editing mode, place objectives on 1" grid
	if objectives_editing:
		var inch_pos = _get_inch_at_screen_pos(screen_pos)
		if _is_valid_inch_pos(inch_pos):
			_toggle_objective_at_position(inch_pos)
		return

	# Wall placement mode
	if editor_mode == EditorMode.PLACE_WALLS:
		_handle_wall_click(screen_pos)
		return

	# Prefab placement mode: one click drops a complete canonical piece (with orientation)
	if editor_mode == EditorMode.PLACE_PREFAB:
		var prefab_cell := _get_cell_at_screen_pos(screen_pos)
		if _is_valid_cell(prefab_cell):
			place_prefab(selected_prefab_key, prefab_cell, _preview_rotation, _preview_flip, point_symmetry_enabled)
		return

	# Paint free cells (undo snapshot is pushed once at stroke start in _input)
	var cell = _get_cell_at_screen_pos(screen_pos)
	if _is_valid_cell(cell):
		if selected_terrain_type == TerrainType.NONE:
			free_cells.erase(cell)
			if point_symmetry_enabled:
				free_cells.erase(Vector2i(_get_mirrored_cell(cell)))
		else:
			free_cells[cell] = selected_terrain_type
			if point_symmetry_enabled:
				free_cells[Vector2i(_get_mirrored_cell(cell))] = selected_terrain_type
		_rebuild_derived()


func _emit_layout_update() -> void:
	layout_updated.emit(grid_cells.duplicate(), table_size_feet, grid_rotation_degrees,
		wall_segments.duplicate(), placed_objects.duplicate())


## Auto-generate terrain layout following OPR guidelines
## Respects point symmetry if enabled, maintains 3" minimum spacing
func _generate_terrain_layout() -> void:
	# Keep trying until we successfully place all required terrain
	var max_retries = 10
	var success = false

	for retry in range(max_retries):
		placed_pieces.clear()

		if _try_generate_layout():
			success = true
			break

	if not success:
		push_error("Failed to generate compliant terrain layout after %d attempts" % max_retries)
		print("Grid rotation: %.1f°, Table size: %.0fx%.0f feet, Point symmetry: %s" % [
			grid_rotation_degrees, table_size_feet.x, table_size_feet.y,
			"enabled" if point_symmetry_enabled else "disabled"
		])


## Attempt to generate a complete terrain layout
func _try_generate_layout() -> bool:
	var grid_dims = _calculate_grid_dimensions()

	# Define terrain piece templates (in grid cells: width x height)
	var piece_templates := {
		TerrainType.RUINS: [
			Vector2i(3, 3),  # 9"x9"
			Vector2i(3, 2),  # 9"x6"
		],
		TerrainType.FOREST: [
			Vector2i(3, 3),  # 9"x9"
		],
		TerrainType.DANGEROUS: [
			Vector2i(2, 3),  # 6"x9"
		],
		TerrainType.CONTAINER: [
			Vector2i(2, 1),  # 6"x3"
		]
	}

	# Target: 15-20 pieces total (OPR requirements)
	var target_pieces := {
		TerrainType.RUINS: 5,      # ~30% of pieces
		TerrainType.FOREST: 6,     # ~35% of pieces (provides difficult terrain)
		TerrainType.CONTAINER: 4,  # ~25% of pieces
		TerrainType.DANGEROUS: 2   # ~10% of pieces (minimum 2)
	}

	var tracked := []  # spacing tracker: [{pos, size, type}] (not the member placed_pieces)
	var max_attempts = 500  # Increased for larger tables

	# Place pieces with symmetry support
	# Use explicit ordering to ensure all types are attempted
	var terrain_order = [TerrainType.FOREST, TerrainType.RUINS, TerrainType.CONTAINER, TerrainType.DANGEROUS]
	var pieces_placed_by_type := {}

	for terrain_type in terrain_order:
		if not target_pieces.has(terrain_type):
			continue

		var count = target_pieces[terrain_type]
		var templates = piece_templates[terrain_type]

		# When symmetry is enabled, place half the pieces (they will be mirrored)
		var pieces_to_place = count if not point_symmetry_enabled else int(ceil(count / 2.0))

		pieces_placed_by_type[terrain_type] = 0

		# Calculate valid cell range based on table bounds (at 0° rotation)
		# This ensures pieces are placed within the actual table, not just the grid
		var valid_range = _get_valid_cell_range()

		for i in range(pieces_to_place):
			for attempt in range(max_attempts):
				# Pick random template
				var template = templates[randi() % templates.size()]

				# Pick random position WITHIN VALID TABLE BOUNDS
				var min_x = valid_range.position.x
				var min_y = valid_range.position.y
				var max_x = valid_range.end.x - template.x
				var max_y = valid_range.end.y - template.y

				if max_x <= min_x or max_y <= min_y:
					break

				# Random position across entire table
				var pos = Vector2i(
					min_x + randi() % (max_x - min_x + 1),
					min_y + randi() % (max_y - min_y + 1)
				)

				# Check if placement is valid (3" minimum spacing)
				if _can_place_piece(pos, template, tracked):
					var prefab := _template_to_prefab(terrain_type, template)
					# If symmetry is enabled, check if mirrored position is also valid
					if point_symmetry_enabled:
						var mirrored_pos = _mirror_position(pos, template, grid_dims)

						# Check if mirrored piece can also be placed
						if not _can_place_piece(mirrored_pos, template, tracked):
							continue  # Try another position

						# Place both original and mirrored piece as prefab pieces
						_add_piece(prefab["key"], pos, prefab["rotation"], false)
						tracked.append({"pos": pos, "size": template, "type": terrain_type})

						# Point symmetry: mirrored piece is rotated 180° so its walls land
						# on the opposite corner (true point-symmetric layout).
						_add_piece(prefab["key"], mirrored_pos, (int(prefab["rotation"]) + 180) % 360, false)
						tracked.append({"pos": mirrored_pos, "size": template, "type": terrain_type})

						pieces_placed_by_type[terrain_type] += 2
					else:
						# No symmetry - just place the piece
						_add_piece(prefab["key"], pos, prefab["rotation"], false)
						tracked.append({"pos": pos, "size": template, "type": terrain_type})

						pieces_placed_by_type[terrain_type] += 1

					break

	# Tally how many pieces were placed across all terrain types.
	var total_placed = 0
	for terrain_type in terrain_order:
		if not pieces_placed_by_type.has(terrain_type):
			continue
		total_placed += pieces_placed_by_type[terrain_type]

	# Consider it successful if we placed at least 50% of target pieces
	var min_required = 8  # Minimum 8 pieces total (half of 15-20 range)
	return total_placed >= min_required


## Mirror a position across the TABLE center (point symmetry)
## For a piece at position pos with given piece_size, returns the mirrored top-left corner position
## IMPORTANT: Uses table bounds, not grid bounds, for correct edge-to-edge mirroring
func _mirror_position(pos: Vector2i, piece_size: Vector2i, _grid_dims: Vector2i) -> Vector2i:
	# Get actual table bounds in grid coordinates
	var valid_range = _get_valid_cell_range()
	var table_min_x = valid_range.position.x
	var table_min_y = valid_range.position.y
	var table_max_x = valid_range.position.x + valid_range.size.x - 1
	var table_max_y = valid_range.position.y + valid_range.size.y - 1

	# Point symmetry: a piece at the top-left edge should mirror to bottom-right edge
	# The mirrored piece's bottom-right corner should match the original's distance from top-left
	var mirrored_x = table_min_x + table_max_x - pos.x - piece_size.x + 1
	var mirrored_y = table_min_y + table_max_y - pos.y - piece_size.y + 1

	return Vector2i(mirrored_x, mirrored_y)


## Check if a piece can be placed without overlapping existing pieces
## Enforces 3" (1 cell) minimum spacing between all terrain pieces
func _can_place_piece(pos: Vector2i, piece_size: Vector2i, existing_pieces: Array) -> bool:
	# Check bounds
	var grid_dims = _calculate_grid_dimensions()
	if pos.x + piece_size.x > grid_dims.x or pos.y + piece_size.y > grid_dims.y:
		return false
	if pos.x < 0 or pos.y < 0:
		return false

	# Check if ALL cells of this piece are within table bounds (after rotation)
	for x in range(piece_size.x):
		for y in range(piece_size.y):
			var cell_pos = pos + Vector2i(x, y)
			if not _is_cell_within_table_bounds(cell_pos, grid_dims):
				return false  # Piece extends outside table

	# Define piece rectangle
	var piece_rect = Rect2i(pos, piece_size)

	# Check overlap with existing pieces
	for piece in existing_pieces:
		var other_rect = Rect2i(piece.pos, piece.size)
		if piece_rect.intersects(other_rect):
			return false

	# Enforce minimum 3" spacing (1 cell = 3")
	# Expand piece by 1 cell on all sides
	var expanded_rect = Rect2i(pos - Vector2i(1, 1), piece_size + Vector2i(2, 2))
	for piece in existing_pieces:
		var other_rect = Rect2i(piece.pos, piece.size)
		if expanded_rect.intersects(other_rect):
			return false

	return true


## Get the valid cell range for the current table size (at current rotation)
## Returns Rect2i with min/max cell coordinates that are within the table
func _get_valid_cell_range() -> Rect2i:
	var grid_dims = _calculate_grid_dimensions()
	var half_grid = Vector2(grid_dims.x / 2.0, grid_dims.y / 2.0)

	# Table size in cells (at 0° rotation)
	var table_cells_x = int(table_size_feet.x * 12.0 / GRID_SIZE_INCHES)
	var table_cells_y = int(table_size_feet.y * 12.0 / GRID_SIZE_INCHES)

	# For 0° rotation, valid cells are centered in the grid
	# No margin - we want terrain at all valid table positions including edges
	var min_x = int(half_grid.x) - int(table_cells_x / 2)
	var max_x = int(half_grid.x) + int((table_cells_x + 1) / 2) - 1  # Handle odd cell counts
	var min_y = int(half_grid.y) - int(table_cells_y / 2)
	var max_y = int(half_grid.y) + int((table_cells_y + 1) / 2) - 1

	# Clamp to grid bounds
	min_x = max(0, min_x)
	min_y = max(0, min_y)
	max_x = min(grid_dims.x - 1, max_x)
	max_y = min(grid_dims.y - 1, max_y)

	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## Check if a grid cell is within the actual table bounds (accounting for rotation)
func _is_cell_within_table_bounds(cell_pos: Vector2i, grid_dims: Vector2i) -> bool:
	# Calculate cell center position in grid coordinates (grid centered on intersection point)
	var cell_size_inches = GRID_SIZE_INCHES
	# Grid centered on intersection - cells offset by 0.5 from intersections
	var local_x = (cell_pos.x - grid_dims.x / 2.0 + 0.5) * cell_size_inches
	var local_y = (cell_pos.y - grid_dims.y / 2.0 + 0.5) * cell_size_inches

	# Calculate all 4 corners of the cell in local space
	var half_cell = cell_size_inches / 2.0
	var corners_local = [
		Vector2(local_x - half_cell, local_y - half_cell),
		Vector2(local_x + half_cell, local_y - half_cell),
		Vector2(local_x + half_cell, local_y + half_cell),
		Vector2(local_x - half_cell, local_y + half_cell)
	]

	# Table bounds
	var table_width_inches = table_size_feet.x * 12.0
	var table_height_inches = table_size_feet.y * 12.0

	# Apply rotation and check if ALL corners are inside table
	# For terrain placement, cells must be fully within bounds
	# Small epsilon for floating-point tolerance at exact boundaries
	var epsilon = 0.01
	var rotation_rad = deg_to_rad(grid_rotation_degrees)
	for corner in corners_local:
		var rotated_x = corner.x * cos(rotation_rad) - corner.y * sin(rotation_rad)
		var rotated_y = corner.x * sin(rotation_rad) + corner.y * cos(rotation_rad)

		# If ANY corner is outside (with small tolerance), cell is not valid
		if abs(rotated_x) > table_width_inches / 2.0 + epsilon or abs(rotated_y) > table_height_inches / 2.0 + epsilon:
			return false

	return true  # All corners inside table


## Place a piece on the grid
## Map an autogen (terrain_type, template-size) to a canonical prefab key + rotation.
func _template_to_prefab(terrain_type: int, template: Vector2i) -> Dictionary:
	match terrain_type:
		TerrainType.RUINS:
			return {"key": "ruine_9x9" if template == Vector2i(3, 3) else "ruine_9x6", "rotation": 0}
		TerrainType.FOREST:
			return {"key": "wald_9x9", "rotation": 0}
		TerrainType.CONTAINER:
			return {"key": "blocker_6x3", "rotation": 0}
		TerrainType.DANGEROUS:
			# prefab dangerous_9x6 is 3×2; the 2×3 template is that piece rotated 90°
			return {"key": "dangerous_9x6", "rotation": 90 if template == Vector2i(2, 3) else 0}
	return {"key": "", "rotation": 0}


## Save current layout to file
func save_layout(file_path: String) -> void:
	var data = {
		"version": "1.5",  # v1.5: piece-identity model (placed_pieces + free_cells/free_walls)
		"table_size": {"x": table_size_feet.x, "y": table_size_feet.y},
		"grid_rotation": grid_rotation_degrees,
		"deployment_type": deployment_type,
		"custom_zones": {
			"player1": [],
			"player2": []
		},
		"mission_objectives": [],
		"placed_pieces": [],
		"free_cells": {},
		"free_walls": []
	}

	# Save custom zone vertices as coordinate arrays
	for cell in custom_zone_vertices_p1:
		data.custom_zones.player1.append({"x": cell.x, "y": cell.y})
	for cell in custom_zone_vertices_p2:
		data.custom_zones.player2.append({"x": cell.x, "y": cell.y})

	# Save mission objectives (1" coordinates)
	for obj in mission_objectives:
		data.mission_objectives.append({"x": obj.x, "y": obj.y})

	# Save placed prefab pieces (the source of truth)
	for piece in placed_pieces:
		var origin: Vector2i = piece["origin"]
		data.placed_pieces.append({
			"prefab_key": piece["prefab_key"],
			"origin_x": origin.x,
			"origin_y": origin.y,
			"rotation": piece.get("rotation", 0),
			"flip": piece.get("flip", false),
			"seed": piece.get("seed", 0),
		})

	# Save free-painted cells
	for cell_pos in free_cells:
		data.free_cells["%d,%d" % [cell_pos.x, cell_pos.y]] = free_cells[cell_pos]

	# Save manually placed walls
	for wall in free_walls:
		var edge_cell: Vector2i = wall.get("edge_cell", Vector2i.ZERO)
		data.free_walls.append({
			"edge_cell_x": edge_cell.x,
			"edge_cell_y": edge_cell.y,
			"edge_side": wall.get("edge_side", 0),
			"wall_key": wall.get("wall_key", ""),
			"length_inches": wall.get("length_inches", GRID_SIZE_INCHES),
			"sub_position": wall.get("sub_position", 0),
		})

	var json_string = JSON.stringify(data, "\t")
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("Layout saved to: %s" % file_path)
	else:
		push_error("Failed to save layout: %s" % file_path)


## Load layout from file
func load_layout(file_path: String) -> bool:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open layout file: %s" % file_path)
		return false

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_text) != OK:
		push_error("Failed to parse JSON: %s" % file_path)
		return false

	var data = json.data
	if not data is Dictionary:
		push_error("Invalid layout data")
		return false

	# Load table size
	if data.has("table_size"):
		var ts = data.table_size
		table_size_feet = Vector2(ts.x, ts.y)

	# Load rotation
	if data.has("grid_rotation"):
		grid_rotation_degrees = data.grid_rotation
		if rotation_slider:
			rotation_slider.value = grid_rotation_degrees

	# Load deployment type
	if data.has("deployment_type"):
		deployment_type = data.deployment_type
		if deployment_type_option:
			deployment_type_option.selected = deployment_type
		_update_custom_zone_ui_visibility()

	# Load custom zone vertices (float precision for exact boundary placement)
	custom_zone_vertices_p1.clear()
	custom_zone_vertices_p2.clear()
	if data.has("custom_zones"):
		var zones = data.custom_zones
		if zones.has("player1"):
			for v in zones.player1:
				custom_zone_vertices_p1.append(Vector2(float(v.x), float(v.y)))
		if zones.has("player2"):
			for v in zones.player2:
				custom_zone_vertices_p2.append(Vector2(float(v.x), float(v.y)))

	# Load mission objectives (1" coordinates)
	mission_objectives.clear()
	if data.has("mission_objectives"):
		for obj in data.mission_objectives:
			mission_objectives.append(Vector2(float(obj.x), float(obj.y)))

	# Update visibility toggle based on deployment type
	if deployment_type > 0:
		show_deployment_zones = true
		if deployment_check:
			deployment_check.button_pressed = true

	# Emit signal to update terrain_overlay with deployment type and custom zones
	deployment_type_changed.emit(deployment_type)

	# --- Terrain source-of-truth: placed pieces + free cells + free walls ---
	placed_pieces.clear()
	free_cells.clear()
	free_walls.clear()
	_next_piece_id = 1
	_undo_stack.clear()
	_redo_stack.clear()
	_selected_piece_id = -1

	if data.has("placed_pieces"):
		for p in data.placed_pieces:
			var id := _next_piece_id
			_next_piece_id += 1
			placed_pieces.append({
				"id": id,
				"prefab_key": p.get("prefab_key", ""),
				"origin": Vector2i(int(p.get("origin_x", 0)), int(p.get("origin_y", 0))),
				"rotation": int(p.get("rotation", 0)),
				"flip": bool(p.get("flip", false)),
				"seed": int(p.get("seed", id)),
			})

	# Free cells: new "free_cells" key, else legacy "grid_cells"
	var cells_src: Dictionary = data.get("free_cells", data.get("grid_cells", {}))
	for key in cells_src:
		var coords: PackedStringArray = key.split(",")
		if coords.size() == 2:
			free_cells[Vector2i(int(coords[0]), int(coords[1]))] = int(cells_src[key])

	# Free walls: new "free_walls" key, else legacy "wall_segments"
	var walls_src: Array = data.get("free_walls", data.get("wall_segments", []))
	for w in walls_src:
		free_walls.append({
			"edge_cell": Vector2i(int(w.get("edge_cell_x", 0)), int(w.get("edge_cell_y", 0))),
			"edge_side": int(w.get("edge_side", 0)),
			"wall_key": w.get("wall_key", ""),
			"length_inches": float(w.get("length_inches", GRID_SIZE_INCHES)),
			"sub_position": int(w.get("sub_position", 0)),
		})

	_rebuild_derived()
	_update_modular_status()
	_update_undo_redo_buttons()

	# Apply the loaded mission objectives to the 3D table AND broadcast them to remote
	# peers (host -> clients). Without this, a loaded map's objectives stayed local and
	# never reached the other player. Table size + grid are already loaded above, so
	# get_objectives_for_overlay() resolves correctly.
	objectives_changed.emit(mission_objectives)

	print("Layout loaded from: %s" % file_path)
	return true


## Check extended OPR guidelines
func _check_extended_guidelines() -> Dictionary:
	var results = {
		"max_gap_ok": true,
		"max_gap_inches": 0.0,
		"deployment_coverage_ok": true,
		"symmetry_ok": true,
		"symmetry_score": 0.0
	}

	# Check maximum gap between terrain (should be < 12")
	# This is a simplified check - just finds largest empty circle
	var grid_dims = _calculate_grid_dimensions()
	var max_gap = 0.0

	# Sample points across the table
	for test_x in range(0, int(table_size_feet.x * 12), 3):
		for test_y in range(0, int(table_size_feet.y * 12), 3):
			var min_dist = INF
			# Find nearest terrain
			for cell_pos in grid_cells:
				if grid_cells[cell_pos] == TerrainType.NONE:
					continue
				var cell_center_x = (cell_pos.x + 0.5) * GRID_SIZE_INCHES
				var cell_center_y = (cell_pos.y + 0.5) * GRID_SIZE_INCHES
				var dist = Vector2(test_x, test_y).distance_to(Vector2(cell_center_x, cell_center_y))
				min_dist = min(min_dist, dist)
			max_gap = max(max_gap, min_dist)

	results.max_gap_inches = max_gap
	results.max_gap_ok = max_gap <= 12.0

	# Symmetry check (simplified - count terrain in each half)
	var half_x = grid_dims.x / 2
	var left_count = 0
	var right_count = 0

	for cell_pos in grid_cells:
		if grid_cells[cell_pos] == TerrainType.NONE:
			continue
		if cell_pos.x < half_x:
			left_count += 1
		else:
			right_count += 1

	var total = left_count + right_count
	if total > 0:
		var balance = float(min(left_count, right_count)) / float(max(left_count, right_count))
		results.symmetry_score = balance * 100.0
		results.symmetry_ok = balance >= 0.7  # At least 70% balanced

	return results


## Get all cells including their world positions for overlay rendering
func get_cells_for_overlay() -> Array:
	var result := []
	var grid_dims = _calculate_grid_dimensions()
	var cell_size_inches = GRID_SIZE_INCHES

	for cell_pos in grid_cells:
		var terrain_type = grid_cells[cell_pos]
		if terrain_type == TerrainType.NONE:
			continue

		# Calculate center position in inches from table center
		var center_x = (cell_pos.x + 0.5) * cell_size_inches - (grid_dims.x * cell_size_inches / 2.0)
		var center_y = (cell_pos.y + 0.5) * cell_size_inches - (grid_dims.y * cell_size_inches / 2.0)

		result.append({
			"cell": cell_pos,
			"type": terrain_type,
			"color": TERRAIN_COLORS[terrain_type],
			"center_inches": Vector2(center_x, center_y),
			"size_inches": cell_size_inches
		})

	return result


## Get current layout data (for table size changes)
func get_current_layout() -> Dictionary:
	return {
		"grid_cells": grid_cells.duplicate(),
		"table_size": table_size_feet,
		"rotation": grid_rotation_degrees,
		"deployment_type": deployment_type,
		"custom_zones": get_custom_zone_data(),
		"mission_objectives": mission_objectives.duplicate()
	}


## Get custom zone data in a format suitable for save/load and terrain_overlay
func get_custom_zone_data() -> Dictionary:
	return {
		"player1_cells": custom_zone_vertices_p1.duplicate(),
		"player2_cells": custom_zone_vertices_p2.duplicate(),
		"player1_world": _convert_zone_cells_to_world(custom_zone_vertices_p1),
		"player2_world": _convert_zone_cells_to_world(custom_zone_vertices_p2)
	}


## Convert 1" vertex coordinates (floats) to world coordinates (meters) for terrain_overlay
func _convert_zone_cells_to_world(vertices: Array[Vector2]) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var valid_range = _get_valid_cell_range()
	var inch_to_meters = 0.0254  # 1 inch = 0.0254 meters

	# Calculate table center in 1" coordinates (cell bounds * 3)
	var table_center_x = (valid_range.position.x + valid_range.size.x / 2.0) * 3.0
	var table_center_y = (valid_range.position.y + valid_range.size.y / 2.0) * 3.0

	for vertex in vertices:
		# Calculate position relative to TABLE center in inches, then convert to meters
		var local_x = (vertex.x - table_center_x) * inch_to_meters
		var local_z = (vertex.y - table_center_y) * inch_to_meters

		# Apply grid rotation to get world position
		var rotation_rad = deg_to_rad(grid_rotation_degrees)
		var world_x = local_x * cos(rotation_rad) - local_z * sin(rotation_rad)
		var world_z = local_x * sin(rotation_rad) + local_z * cos(rotation_rad)

		result.append(Vector3(world_x, 0.0, world_z))

	return result


## Find vertex at screen position for dragging
## Returns {player: int, index: int} or {player: 0} if no vertex found
func _find_vertex_at_screen_pos(screen_pos: Vector2) -> Dictionary:
	var grid_dims = _calculate_grid_dimensions()
	var grid_rect = _get_zoomed_grid_rect()  # Use zoomed rect
	var center = grid_rect.position + grid_rect.size / 2.0
	var angle_rad = deg_to_rad(grid_rotation_degrees)

	# Calculate pixels per inch (includes zoom)
	var table_size_inches = table_size_feet * 12.0
	var pixels_per_inch_x = grid_rect.size.x / table_size_inches.x
	var pixels_per_inch_y = grid_rect.size.y / table_size_inches.y

	# Half of total inches (for centering)
	var half_inches_x = grid_dims.x * 3.0 / 2.0
	var half_inches_y = grid_dims.y * 3.0 / 2.0

	# Helper to convert 1" vertex coords (float precision) to screen position
	var inch_to_screen = func(inch_pos: Vector2) -> Vector2:
		var local_x = (inch_pos.x - half_inches_x) * pixels_per_inch_x
		var local_y = (inch_pos.y - half_inches_y) * pixels_per_inch_y
		var cos_a = cos(angle_rad)
		var sin_a = sin(angle_rad)
		return Vector2(
			local_x * cos_a - local_y * sin_a,
			local_x * sin_a + local_y * cos_a
		) + center

	# Get position relative to grid container using proper coordinate transform
	var local_pos = grid_container.get_local_mouse_position()

	var closest_dist = INF
	var closest_player = 0
	var closest_index = -1

	# Scale click radius with zoom for consistent feel
	var scaled_click_radius = VERTEX_CLICK_RADIUS * zoom_level

	# Check Player 1 vertices
	for i in range(custom_zone_vertices_p1.size()):
		var vertex_screen = inch_to_screen.call(custom_zone_vertices_p1[i])
		var dist = local_pos.distance_to(vertex_screen)
		if dist < scaled_click_radius and dist < closest_dist:
			closest_dist = dist
			closest_player = 1
			closest_index = i

	# Check Player 2 vertices
	for i in range(custom_zone_vertices_p2.size()):
		var vertex_screen = inch_to_screen.call(custom_zone_vertices_p2[i])
		var dist = local_pos.distance_to(vertex_screen)
		if dist < scaled_click_radius and dist < closest_dist:
			closest_dist = dist
			closest_player = 2
			closest_index = i

	return {player = closest_player, index = closest_index}


## Move dragged vertex to new screen position
func _move_vertex_to_screen_pos(screen_pos: Vector2) -> void:
	if not _dragging_vertex or _dragging_player == 0 or _dragging_index < 0:
		return

	# First try to snap to boundary snap points (yellow dots)
	var snap_result = _find_nearest_boundary_snap_point(screen_pos)
	var new_cell: Vector2  # Float precision for exact boundary placement

	if snap_result.found:
		# Use the snapped position (exact boundary intersection)
		new_cell = snap_result.cell
	else:
		# Fallback to 1" grid position (rounded)
		new_cell = _get_inch_at_screen_pos(screen_pos)
		# Only update if position is within table bounds
		if not _is_valid_inch_pos(new_cell):
			return

	if custom_zone_symmetric:
		# In symmetric mode, moving P1 vertex updates P2 mirror, and vice versa
		if _dragging_player == 1:
			if _dragging_index < custom_zone_vertices_p1.size():
				custom_zone_vertices_p1[_dragging_index] = new_cell
				# Update mirrored vertex (P2 vertices are in reverse order)
				var mirror_index = custom_zone_vertices_p2.size() - 1 - _dragging_index
				if mirror_index >= 0 and mirror_index < custom_zone_vertices_p2.size():
					custom_zone_vertices_p2[mirror_index] = _get_mirrored_cell(new_cell)
		else:  # Player 2
			if _dragging_index < custom_zone_vertices_p2.size():
				custom_zone_vertices_p2[_dragging_index] = new_cell
				# Update mirrored vertex (P1 vertices are in reverse order relative to P2)
				var mirror_index = custom_zone_vertices_p1.size() - 1 - _dragging_index
				if mirror_index >= 0 and mirror_index < custom_zone_vertices_p1.size():
					custom_zone_vertices_p1[mirror_index] = _get_mirrored_cell(new_cell)
	else:
		# Non-symmetric mode - just update the single vertex
		if _dragging_player == 1:
			if _dragging_index < custom_zone_vertices_p1.size():
				custom_zone_vertices_p1[_dragging_index] = new_cell
		else:
			if _dragging_index < custom_zone_vertices_p2.size():
				custom_zone_vertices_p2[_dragging_index] = new_cell

	grid_container.queue_redraw()


## Find nearest boundary snap point (where grid lines intersect table edges)
## Returns {found: bool, cell: Vector2 (floats for precision), screen_pos: Vector2}
## Uses cached snap points from _draw_boundary_snap_points for exact consistency
const BOUNDARY_SNAP_RADIUS := 50.0  # Pixels - increased for better usability

func _find_nearest_boundary_snap_point(_screen_pos: Vector2) -> Dictionary:
	## Find the nearest cached boundary snap point to the current mouse position.
	## Uses cached snap points calculated during grid drawing.

	# Get mouse position in grid container local coordinates
	var local_pos = grid_container.get_local_mouse_position()

	var closest_dist = INF
	var closest_cell = Vector2.ZERO
	var closest_screen = Vector2.ZERO

	if _cached_boundary_snap_points.size() == 0:
		return {found = false, cell = Vector2.ZERO, screen_pos = Vector2.ZERO}

	# Find closest snap point within radius
	for snap_point in _cached_boundary_snap_points:
		var snap_screen: Vector2 = snap_point.screen_pos
		var dist = local_pos.distance_to(snap_screen)
		if dist < BOUNDARY_SNAP_RADIUS and dist < closest_dist:
			closest_dist = dist
			closest_screen = snap_screen
			closest_cell = snap_point.inch_pos

	if closest_dist < INF:
		return {found = true, cell = closest_cell, screen_pos = closest_screen}
	else:
		return {found = false, cell = Vector2.ZERO, screen_pos = Vector2.ZERO}

## Convert screen position to 1" coordinates (rounded to nearest inch for fallback)
## Returns Vector2 (floats) but values are rounded to integers
func _get_inch_at_screen_pos(screen_pos: Vector2) -> Vector2:
	var grid_dims = _calculate_grid_dimensions()
	var grid_rect = _get_zoomed_grid_rect()  # Use zoomed rect
	var center = grid_rect.position + grid_rect.size / 2.0
	var angle_rad = deg_to_rad(grid_rotation_degrees)

	# Calculate pixels per inch (includes zoom)
	var table_size_inches = table_size_feet * 12.0
	var pixels_per_inch_x = grid_rect.size.x / table_size_inches.x
	var pixels_per_inch_y = grid_rect.size.y / table_size_inches.y

	# Half of total inches
	var half_inches_x = grid_dims.x * 3.0 / 2.0
	var half_inches_y = grid_dims.y * 3.0 / 2.0

	# Get position relative to grid container using proper coordinate transform
	var local_pos = grid_container.get_local_mouse_position()

	# Reverse rotation
	var pos_from_center = local_pos - center
	var cos_a = cos(-angle_rad)
	var sin_a = sin(-angle_rad)
	var rotated_pos = Vector2(
		pos_from_center.x * cos_a - pos_from_center.y * sin_a,
		pos_from_center.x * sin_a + pos_from_center.y * cos_a
	)

	# Convert to inch coordinates (round to nearest integer for fallback)
	var inch_x = round(rotated_pos.x / pixels_per_inch_x + half_inches_x)
	var inch_y = round(rotated_pos.y / pixels_per_inch_y + half_inches_y)

	return Vector2(inch_x, inch_y)


# ============================================================================
# Mission Objectives Functions
# ============================================================================

const OBJECTIVE_SNAP_TOLERANCE := 1.5  # Inches - how close to click to remove an objective

## Toggle objective at the given 1" position (add if not present, remove if present)
func _toggle_objective_at_position(inch_pos: Vector2) -> void:
	# Check if there's already an objective near this position
	var existing_idx = _find_objective_near_position(inch_pos)

	if existing_idx >= 0:
		# Remove existing objective
		mission_objectives.remove_at(existing_idx)
		# Also remove mirrored if symmetry enabled
		if point_symmetry_enabled:
			var mirrored = _get_mirrored_cell(inch_pos)
			var mirrored_idx = _find_objective_near_position(mirrored)
			if mirrored_idx >= 0:
				mission_objectives.remove_at(mirrored_idx)
	else:
		# Add new objective at the snapped position
		mission_objectives.append(inch_pos)
		# Also add mirrored if symmetry enabled
		if point_symmetry_enabled:
			var mirrored = _get_mirrored_cell(inch_pos)
			mission_objectives.append(mirrored)

	_update_objectives_status()
	grid_container.queue_redraw()
	_emit_layout_update()
	# Update 3D view immediately
	objectives_changed.emit(mission_objectives)


## Find index of objective near the given position, returns -1 if none found
func _find_objective_near_position(inch_pos: Vector2) -> int:
	for i in range(mission_objectives.size()):
		if mission_objectives[i].distance_to(inch_pos) < OBJECTIVE_SNAP_TOLERANCE:
			return i
	return -1


## Get objectives for 3D overlay rendering
func get_objectives_for_overlay() -> Array[Vector3]:
	var result: Array[Vector3] = []
	var valid_range = _get_valid_cell_range()
	var inch_to_meters = 0.0254

	# Calculate table center in 1" coordinates
	var table_center_x = (valid_range.position.x + valid_range.size.x / 2.0) * 3.0
	var table_center_y = (valid_range.position.y + valid_range.size.y / 2.0) * 3.0

	for obj_pos in mission_objectives:
		var local_x = (obj_pos.x - table_center_x) * inch_to_meters
		var local_z = (obj_pos.y - table_center_y) * inch_to_meters

		# Apply grid rotation
		var rotation_rad = deg_to_rad(grid_rotation_degrees)
		var world_x = local_x * cos(rotation_rad) - local_z * sin(rotation_rad)
		var world_z = local_x * sin(rotation_rad) + local_z * cos(rotation_rad)

		result.append(Vector3(world_x, 0.0, world_z))

	return result


# ============================================================================
# Zoom Functions
# ============================================================================

func _zoom_in(mouse_pos: Vector2 = Vector2.ZERO) -> void:
	var old_zoom = zoom_level
	zoom_level = clampf(zoom_level + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	_adjust_pan_for_zoom(mouse_pos, old_zoom, zoom_level)
	_apply_zoom()


func _zoom_out(mouse_pos: Vector2 = Vector2.ZERO) -> void:
	var old_zoom = zoom_level
	zoom_level = clampf(zoom_level - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	_adjust_pan_for_zoom(mouse_pos, old_zoom, zoom_level)
	_apply_zoom()


func _adjust_pan_for_zoom(mouse_pos: Vector2, old_zoom: float, new_zoom: float) -> void:
	# Adjust pan offset so that the point under the mouse stays in place
	if old_zoom == new_zoom or mouse_pos == Vector2.ZERO:
		return

	var grid_rect = _get_grid_rect()
	var center = grid_rect.position + grid_rect.size / 2.0

	# Position relative to center (in unzoomed space)
	var rel_to_center = (mouse_pos - center) / old_zoom - pan_offset

	# After zoom, the same world point should be under the mouse
	# new_mouse_pos = (world_pos + new_pan) * new_zoom + center
	# We want new_mouse_pos == mouse_pos, so:
	# new_pan = (mouse_pos - center) / new_zoom - world_pos
	pan_offset = (mouse_pos - center) / new_zoom - rel_to_center


func _apply_zoom() -> void:
	if grid_container:
		# Don't use scale - we handle zoom in drawing code
		grid_container.scale = Vector2.ONE
		grid_container.queue_redraw()


func reset_zoom() -> void:
	zoom_level = 1.0
	pan_offset = Vector2.ZERO
	_apply_zoom()


# ==============================================================================
# WALL CLICK HANDLING
# ==============================================================================

## Handle a click in PLACE_WALLS mode
func _handle_wall_click(screen_pos: Vector2) -> void:
	var edge := _get_edge_at_screen_pos(screen_pos)
	if edge.x < 0:
		return  # No valid edge found

	var edge_cell := Vector2i(edge.x, edge.y)
	var edge_side: int = edge.z

	if selected_wall_key.is_empty():
		return

	# Toggle: if a free wall already exists at this edge, remove it, else place one.
	var found := false
	for seg in free_walls:
		if seg["edge_cell"] == edge_cell and seg["edge_side"] == edge_side:
			found = true
			break

	if found:
		remove_wall_segment(edge_cell, edge_side)
	else:
		var length: float = 3.0
		for w in available_walls:
			if w.get("key", "") == selected_wall_key:
				length = w.get("length_inches", 3.0)
				break
		add_wall_segment(edge_cell, edge_side, selected_wall_key, length)

	_update_modular_status()


## Detect which cell edge the screen position is closest to
## Returns Vector3i(cell_x, cell_y, edge_side) or Vector3i(-1,-1,-1) if no edge found
func _get_edge_at_screen_pos(screen_pos: Vector2) -> Vector3i:
	var grid_dims: Vector2i = _calculate_grid_dimensions()
	var grid_rect: Rect2 = _get_zoomed_grid_rect()

	var table_size_inches: Vector2 = table_size_feet * 12.0
	var pixels_per_inch_x: float = grid_rect.size.x / table_size_inches.x
	var pixels_per_inch_y: float = grid_rect.size.y / table_size_inches.y
	var cell_size := Vector2(
		GRID_SIZE_INCHES * pixels_per_inch_x,
		GRID_SIZE_INCHES * pixels_per_inch_y
	)

	var center: Vector2 = grid_rect.position + grid_rect.size / 2.0
	var half_grid_cells := Vector2(grid_dims.x / 2.0, grid_dims.y / 2.0)

	# Get local mouse position and undo rotation
	var local_pos: Vector2 = grid_container.get_local_mouse_position()
	var pos_from_center: Vector2 = local_pos - center
	var angle_rad: float = deg_to_rad(-grid_rotation_degrees)
	var rotated_pos := Vector2(
		pos_from_center.x * cos(angle_rad) - pos_from_center.y * sin(angle_rad),
		pos_from_center.x * sin(angle_rad) + pos_from_center.y * cos(angle_rad)
	)

	# Find which cell we're in
	var cell_x: int = int(floor(rotated_pos.x / cell_size.x + half_grid_cells.x))
	var cell_y: int = int(floor(rotated_pos.y / cell_size.y + half_grid_cells.y))

	if cell_x < 0 or cell_x >= grid_dims.x or cell_y < 0 or cell_y >= grid_dims.y:
		return Vector3i(-1, -1, -1)

	# Position within cell (0..1)
	var cell_origin_x: float = (cell_x - half_grid_cells.x) * cell_size.x
	var cell_origin_y: float = (cell_y - half_grid_cells.y) * cell_size.y
	var frac_x: float = (rotated_pos.x - cell_origin_x) / cell_size.x
	var frac_y: float = (rotated_pos.y - cell_origin_y) / cell_size.y

	# Determine closest edge (threshold: 25% from edge)
	const EDGE_THRESHOLD := 0.25
	var min_dist: float = 1.0
	var best_side: int = -1

	# North (top) edge
	if frac_y < EDGE_THRESHOLD and frac_y < min_dist:
		min_dist = frac_y
		best_side = 0
	# South (bottom) edge
	if (1.0 - frac_y) < EDGE_THRESHOLD and (1.0 - frac_y) < min_dist:
		min_dist = 1.0 - frac_y
		best_side = 2
	# West (left) edge
	if frac_x < EDGE_THRESHOLD and frac_x < min_dist:
		min_dist = frac_x
		best_side = 3
	# East (right) edge
	if (1.0 - frac_x) < EDGE_THRESHOLD and (1.0 - frac_x) < min_dist:
		min_dist = 1.0 - frac_x
		best_side = 1

	if best_side < 0:
		return Vector3i(-1, -1, -1)

	return Vector3i(cell_x, cell_y, best_side)


# ==============================================================================
# WALL SEGMENTS (S7)
# ==============================================================================

## Add a wall segment to a cell edge
func add_wall_segment(edge_cell: Vector2i, edge_side: int, wall_key: String,
		length_inches: float = 3.0, sub_position: int = 0) -> void:
	_push_undo()
	# Replace an existing free wall at the same edge, else append a new one.
	for existing in free_walls:
		if existing["edge_cell"] == edge_cell and existing["edge_side"] == edge_side \
				and existing["sub_position"] == sub_position:
			existing["wall_key"] = wall_key
			existing["length_inches"] = length_inches
			_rebuild_derived()
			return
	free_walls.append({
		"edge_cell": edge_cell,
		"edge_side": edge_side,
		"wall_key": wall_key,
		"length_inches": length_inches,
		"sub_position": sub_position,
	})
	_rebuild_derived()


## Remove a manually placed wall segment from a cell edge
func remove_wall_segment(edge_cell: Vector2i, edge_side: int, sub_position: int = 0) -> void:
	for i in range(free_walls.size() - 1, -1, -1):
		var seg: Dictionary = free_walls[i]
		if seg["edge_cell"] == edge_cell and seg["edge_side"] == edge_side \
				and seg["sub_position"] == sub_position:
			_push_undo()
			free_walls.remove_at(i)
			_rebuild_derived()
			return


## Clear all manually placed wall segments (piece walls stay with their pieces)
func clear_wall_segments() -> void:
	_push_undo()
	free_walls.clear()
	_rebuild_derived()



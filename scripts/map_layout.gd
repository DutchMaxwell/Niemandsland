extends Control
## Map Layout Editor - Top-down view with 3" grid for terrain type assignment
## OPR terrain recommendations are displayed in real-time

signal layout_closed
signal layout_updated(grid_cells: Dictionary, table_size: Vector2, rotation: float)

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

var table_size_feet := Vector2(6, 4)  # Default 6x4 table
var grid_rotation_degrees := 0.0
var grid_cells := {}  # Dictionary[Vector2i, TerrainType]
var selected_terrain_type := TerrainType.RUINS
var is_painting := false
var point_symmetry_enabled := false  # Mirror placement across center

@onready var grid_container: Control = %GridContainer
@onready var rotation_slider: HSlider = %RotationSlider
@onready var rotation_label: Label = %RotationLabel
@onready var terrain_buttons: VBoxContainer = %TerrainButtons
@onready var stats_label: Label = %StatsLabel
@onready var recommendations_label: Label = %RecommendationsLabel
@onready var close_button: Button = %CloseButton
@onready var clear_button: Button = %ClearButton
@onready var symmetry_check: CheckBox = %SymmetryCheck


func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	clear_button.pressed.connect(_on_clear_pressed)
	rotation_slider.value_changed.connect(_on_rotation_changed)
	if symmetry_check:
		symmetry_check.toggled.connect(_on_symmetry_toggled)

	_setup_terrain_buttons()
	_update_stats()
	_update_recommendations()


func _setup_terrain_buttons() -> void:
	for child in terrain_buttons.get_children():
		child.queue_free()

	for type in [TerrainType.RUINS, TerrainType.FOREST, TerrainType.CONTAINER, TerrainType.DANGEROUS, TerrainType.NONE]:
		var btn = Button.new()
		btn.text = TERRAIN_NAMES[type]
		btn.custom_minimum_size = Vector2(100, 40)
		btn.toggle_mode = true
		btn.button_pressed = (type == selected_terrain_type)

		# Color the button
		var style = StyleBoxFlat.new()
		style.bg_color = TERRAIN_COLORS[type]
		style.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", style)

		var pressed_style = style.duplicate()
		pressed_style.border_width_bottom = 3
		pressed_style.border_width_top = 3
		pressed_style.border_width_left = 3
		pressed_style.border_width_right = 3
		pressed_style.border_color = Color.WHITE
		btn.add_theme_stylebox_override("pressed", pressed_style)

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


func _on_rotation_changed(value: float) -> void:
	grid_rotation_degrees = value
	rotation_label.text = "Grid Rotation: %.0f°" % value
	grid_container.queue_redraw()
	_emit_layout_update()


func _on_symmetry_toggled(enabled: bool) -> void:
	point_symmetry_enabled = enabled
	grid_container.queue_redraw()


func _on_close_pressed() -> void:
	layout_closed.emit()
	hide()


func _on_clear_pressed() -> void:
	grid_cells.clear()
	grid_container.queue_redraw()
	_update_stats()
	_emit_layout_update()


func set_table_size(size_feet: Vector2) -> void:
	table_size_feet = size_feet
	grid_container.queue_redraw()
	_update_stats()


func _calculate_grid_dimensions() -> Vector2i:
	var width_inches = table_size_feet.x * 12.0
	var height_inches = table_size_feet.y * 12.0
	return Vector2i(
		int(ceil(width_inches / GRID_SIZE_INCHES)),
		int(ceil(height_inches / GRID_SIZE_INCHES))
	)


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
	var blocking_cells = counts[TerrainType.RUINS] + counts[TerrainType.FOREST] + counts[TerrainType.CONTAINER]
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

	var check_mark = "✓"
	var cross_mark = "✗"

	recommendations_label.text = """OPR Terrain Guidelines:

%s 15-20 terrain pieces (have: %d)
%s At least 25%% table coverage (%.1f%%)
%s 50%% should block LOS (%.0f%%)
%s 33%% should provide cover (%.0f%%)
%s 33%% should be difficult (%.0f%%)
%s 1 dangerous piece per player (have: %d)

Tip: Connected cells = 1 piece
No gaps >12" between terrain""" % [
		check_mark if pieces_ok else cross_mark, total_pieces,
		check_mark if coverage_ok else cross_mark, coverage_pct,
		check_mark if blocking_ok else cross_mark, blocking_pct,
		check_mark if cover_ok else cross_mark, cover_pct,
		check_mark if difficult_ok else cross_mark, difficult_pct,
		check_mark if dangerous_ok else cross_mark, dangerous_pieces
	]

	# Color code the recommendations
	var all_ok = pieces_ok and coverage_ok and blocking_ok and cover_ok and difficult_ok and dangerous_ok
	if all_ok:
		recommendations_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
	else:
		recommendations_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))


func _get_grid_rect() -> Rect2:
	## Calculate the grid rectangle that maintains table aspect ratio
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


func _get_cell_at_screen_pos(screen_pos: Vector2) -> Vector2i:
	var grid_dims = _calculate_grid_dimensions()
	var grid_rect = _get_grid_rect()

	# Calculate cell size in pixels
	var cell_size = Vector2(grid_rect.size.x / grid_dims.x, grid_rect.size.y / grid_dims.y)

	# Get position relative to grid container
	var local_pos = screen_pos - grid_container.global_position

	# Get center of grid
	var center = grid_rect.position + grid_rect.size / 2.0

	# Apply inverse rotation around center to get position in grid coordinate system
	var rotated_pos = local_pos - center
	var angle_rad = deg_to_rad(-grid_rotation_degrees)
	rotated_pos = Vector2(
		rotated_pos.x * cos(angle_rad) - rotated_pos.y * sin(angle_rad),
		rotated_pos.x * sin(angle_rad) + rotated_pos.y * cos(angle_rad)
	)

	# Convert back to grid coordinates (from center)
	rotated_pos += grid_rect.size / 2.0

	# Calculate cell coordinates
	var cell_x = int(rotated_pos.x / cell_size.x)
	var cell_y = int(rotated_pos.y / cell_size.y)

	return Vector2i(cell_x, cell_y)


func _get_mirrored_cell(cell: Vector2i) -> Vector2i:
	## Get the point-symmetric (180° rotated) cell position
	var grid_dims = _calculate_grid_dimensions()
	return Vector2i(grid_dims.x - 1 - cell.x, grid_dims.y - 1 - cell.y)


func _is_valid_cell(cell: Vector2i) -> bool:
	var grid_dims = _calculate_grid_dimensions()
	return cell.x >= 0 and cell.x < grid_dims.x and cell.y >= 0 and cell.y < grid_dims.y


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_painting = event.pressed
			if is_painting:
				_paint_at_position(event.global_position)

	elif event is InputEventMouseMotion and is_painting:
		_paint_at_position(event.global_position)


func _paint_at_position(screen_pos: Vector2) -> void:
	var cell = _get_cell_at_screen_pos(screen_pos)
	if _is_valid_cell(cell):
		if selected_terrain_type == TerrainType.NONE:
			grid_cells.erase(cell)
			# Also erase mirrored cell if symmetry is enabled
			if point_symmetry_enabled:
				var mirrored = _get_mirrored_cell(cell)
				grid_cells.erase(mirrored)
		else:
			grid_cells[cell] = selected_terrain_type
			# Also paint mirrored cell if symmetry is enabled
			if point_symmetry_enabled:
				var mirrored = _get_mirrored_cell(cell)
				grid_cells[mirrored] = selected_terrain_type
		grid_container.queue_redraw()
		_update_stats()
		_emit_layout_update()


func _emit_layout_update() -> void:
	layout_updated.emit(grid_cells.duplicate(), table_size_feet, grid_rotation_degrees)


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

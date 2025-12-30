extends Control
## Grid drawing control for Map Layout Editor
## Draws a rotatable 3" grid with terrain type coloring

var map_layout: Control = null  # Reference to parent MapLayout

func _ready() -> void:
	# Find MapLayout parent
	var parent = get_parent()
	while parent:
		if parent.has_method("_calculate_grid_dimensions"):
			map_layout = parent
			break
		parent = parent.get_parent()


func set_map_layout(layout: Control) -> void:
	map_layout = layout


func _get_grid_rect() -> Rect2:
	## Calculate the grid rectangle that maintains table aspect ratio
	if not map_layout:
		return Rect2(Vector2.ZERO, size)

	var table_size = map_layout.table_size_feet
	var table_aspect = table_size.x / table_size.y  # width / height

	var available_size = size
	var grid_size: Vector2

	# Fit grid to available space while maintaining aspect ratio
	if available_size.x / available_size.y > table_aspect:
		# Container is wider than table - fit to height
		grid_size.y = available_size.y
		grid_size.x = grid_size.y * table_aspect
	else:
		# Container is taller than table - fit to width
		grid_size.x = available_size.x
		grid_size.y = grid_size.x / table_aspect

	# Center the grid in the container
	var offset = (available_size - grid_size) / 2.0
	return Rect2(offset, grid_size)


func _draw() -> void:
	if not map_layout:
		return

	var grid_dims = map_layout._calculate_grid_dimensions()
	var grid_rect = _get_grid_rect()

	# Each cell is square (3" x 3"), calculate pixel size per cell
	var cell_size = Vector2(grid_rect.size.x / grid_dims.x, grid_rect.size.y / grid_dims.y)
	var grid_center = grid_rect.position + grid_rect.size / 2.0

	# Draw with rotation around grid center
	draw_set_transform(grid_center, deg_to_rad(map_layout.grid_rotation_degrees), Vector2.ONE)

	# Calculate offset to center grid
	var half_grid = grid_rect.size / 2.0

	# Draw cells
	for x in range(grid_dims.x):
		for y in range(grid_dims.y):
			var cell_pos = Vector2i(x, y)
			var rect_pos = Vector2(x * cell_size.x, y * cell_size.y) - half_grid
			var rect = Rect2(rect_pos, cell_size)

			# Get terrain type for this cell
			var terrain_type = map_layout.grid_cells.get(cell_pos, map_layout.TerrainType.NONE)
			var color = map_layout.TERRAIN_COLORS[terrain_type]

			# Fill cell
			draw_rect(rect, color, true)

			# Draw cell border
			draw_rect(rect, Color(0.5, 0.5, 0.5, 0.8), false, 1.0)

			# Draw special markers for Ruins (blue border lines for impassable walls)
			if terrain_type == map_layout.TerrainType.RUINS:
				var inset = 3.0
				var inner_rect = Rect2(rect_pos + Vector2(inset, inset), cell_size - Vector2(inset * 2, inset * 2))
				draw_rect(inner_rect, Color(0.2, 0.4, 0.9, 0.9), false, 2.0)

	# Draw major grid lines (every 4 cells = 12" = 1 foot)
	var major_line_color = Color(1.0, 1.0, 1.0, 0.5)
	for x in range(0, grid_dims.x + 1, 4):
		var start = Vector2(x * cell_size.x, 0) - half_grid
		var end = Vector2(x * cell_size.x, grid_rect.size.y) - half_grid
		draw_line(start, end, major_line_color, 2.0)

	for y in range(0, grid_dims.y + 1, 4):
		var start = Vector2(0, y * cell_size.y) - half_grid
		var end = Vector2(grid_rect.size.x, y * cell_size.y) - half_grid
		draw_line(start, end, major_line_color, 2.0)

	# Draw table outline
	draw_set_transform(grid_center, deg_to_rad(map_layout.grid_rotation_degrees), Vector2.ONE)
	var outline_rect = Rect2(-half_grid, grid_rect.size)
	draw_rect(outline_rect, Color.WHITE, false, 3.0)

	# Reset transform
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# Draw table size info (not rotated)
	var table_size = map_layout.table_size_feet
	var size_text = "%.0f' x %.0f' (%.0f\" x %.0f\")" % [table_size.x, table_size.y, table_size.x * 12, table_size.y * 12]
	draw_string(ThemeDB.fallback_font, Vector2(10, 20), size_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

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


func _draw() -> void:
	if not map_layout:
		return

	var grid_dims = map_layout._calculate_grid_dimensions()
	var cell_size = Vector2(size.x / grid_dims.x, size.y / grid_dims.y)
	var center = size / 2.0

	# Draw with rotation
	draw_set_transform(center, deg_to_rad(map_layout.grid_rotation_degrees), Vector2.ONE)

	# Draw cells
	for x in range(grid_dims.x):
		for y in range(grid_dims.y):
			var cell_pos = Vector2i(x, y)
			var rect_pos = Vector2(x * cell_size.x, y * cell_size.y) - center
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

	# Reset transform for grid lines
	draw_set_transform(center, deg_to_rad(map_layout.grid_rotation_degrees), Vector2.ONE)

	# Draw major grid lines (every 3 cells = 9")
	var major_line_color = Color(1.0, 1.0, 1.0, 0.5)
	for x in range(0, grid_dims.x + 1, 3):
		var start = Vector2(x * cell_size.x, 0) - center
		var end = Vector2(x * cell_size.x, size.y) - center
		draw_line(start, end, major_line_color, 2.0)

	for y in range(0, grid_dims.y + 1, 3):
		var start = Vector2(0, y * cell_size.y) - center
		var end = Vector2(size.x, y * cell_size.y) - center
		draw_line(start, end, major_line_color, 2.0)

	# Draw coordinate labels at corners
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)  # Reset transform for text

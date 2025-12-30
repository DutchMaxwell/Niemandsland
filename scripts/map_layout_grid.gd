extends Control
## Grid drawing control for Map Layout Editor
## Draws a 3" grid with terrain type coloring
## Grid lines can be rotated for diagonal terrain placement

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
	var table_aspect = table_size.x / table_size.y

	var available_size = size
	var grid_size: Vector2

	if available_size.x / available_size.y > table_aspect:
		grid_size.y = available_size.y
		grid_size.x = grid_size.y * table_aspect
	else:
		grid_size.x = available_size.x
		grid_size.y = grid_size.x / table_aspect

	var offset = (available_size - grid_size) / 2.0
	return Rect2(offset, grid_size)


func _draw() -> void:
	if not map_layout:
		return

	var grid_dims = map_layout._calculate_grid_dimensions()
	var grid_rect = _get_grid_rect()
	var cell_size = Vector2(grid_rect.size.x / grid_dims.x, grid_rect.size.y / grid_dims.y)

	# Draw table background (always axis-aligned)
	draw_rect(grid_rect, Color(0.15, 0.15, 0.15, 1.0), true)

	# Draw terrain cells (always axis-aligned - no rotation)
	for x in range(grid_dims.x):
		for y in range(grid_dims.y):
			var cell_pos = Vector2i(x, y)
			var rect_pos = grid_rect.position + Vector2(x * cell_size.x, y * cell_size.y)
			var rect = Rect2(rect_pos, cell_size)

			var terrain_type = map_layout.grid_cells.get(cell_pos, map_layout.TerrainType.NONE)
			var color = map_layout.TERRAIN_COLORS[terrain_type]

			# Fill cell
			draw_rect(rect, color, true)

			# Draw cell border
			draw_rect(rect, Color(0.4, 0.4, 0.4, 0.5), false, 1.0)

			# Draw special markers for Ruins (blue border lines for impassable walls)
			if terrain_type == map_layout.TerrainType.RUINS:
				var inset = 3.0
				var inner_rect = Rect2(rect_pos + Vector2(inset, inset), cell_size - Vector2(inset * 2, inset * 2))
				draw_rect(inner_rect, Color(0.2, 0.4, 0.9, 0.9), false, 2.0)

	# Draw table outline (always axis-aligned)
	draw_rect(grid_rect, Color.WHITE, false, 3.0)

	# Draw rotated grid overlay lines (for diagonal terrain placement visualization)
	if map_layout.grid_rotation_degrees != 0:
		_draw_rotated_grid_lines(grid_rect, grid_dims, cell_size)

	# Draw center point (for symmetry reference)
	var center = grid_rect.position + grid_rect.size / 2.0
	draw_circle(center, 5.0, Color(1.0, 1.0, 0.0, 0.8))

	# Draw symmetry indicator if enabled
	if map_layout.point_symmetry_enabled:
		# Draw symmetry axes
		draw_line(
			Vector2(grid_rect.position.x, center.y),
			Vector2(grid_rect.end.x, center.y),
			Color(1.0, 1.0, 0.0, 0.3), 2.0
		)
		draw_line(
			Vector2(center.x, grid_rect.position.y),
			Vector2(center.x, grid_rect.end.y),
			Color(1.0, 1.0, 0.0, 0.3), 2.0
		)

	# Draw table size info
	var table_size = map_layout.table_size_feet
	var size_text = "%.0f' x %.0f' (%.0f\" x %.0f\") - %dx%d cells" % [
		table_size.x, table_size.y,
		table_size.x * 12, table_size.y * 12,
		grid_dims.x, grid_dims.y
	]
	draw_string(ThemeDB.fallback_font, grid_rect.position + Vector2(5, -5), size_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _draw_rotated_grid_lines(grid_rect: Rect2, grid_dims: Vector2i, cell_size: Vector2) -> void:
	## Draw rotated grid lines as an overlay to show diagonal placement angles
	## Lines are clipped to the table boundaries
	var center = grid_rect.position + grid_rect.size / 2.0
	var angle_rad = deg_to_rad(map_layout.grid_rotation_degrees)
	var line_color = Color(1.0, 0.5, 0.0, 0.6)  # Orange for rotated lines
	var major_color = Color(1.0, 0.7, 0.0, 0.8)

	# Calculate how far lines need to extend to cover the entire grid when rotated
	var diagonal = grid_rect.size.length() * 0.75

	# Draw vertical lines (rotated)
	var num_lines_x = int(diagonal / cell_size.x) + 1
	for i in range(-num_lines_x, num_lines_x + 1):
		var offset = i * cell_size.x
		var start = Vector2(offset, -diagonal)
		var end = Vector2(offset, diagonal)

		# Rotate around origin
		start = start.rotated(angle_rad) + center
		end = end.rotated(angle_rad) + center

		# Clip line to grid bounds
		var clipped = _clip_line_to_rect(start, end, grid_rect)
		if clipped:
			var is_major = (i % 4 == 0)
			draw_line(clipped[0], clipped[1], major_color if is_major else line_color, 2.0 if is_major else 1.0)

	# Draw horizontal lines (rotated)
	var num_lines_y = int(diagonal / cell_size.y) + 1
	for i in range(-num_lines_y, num_lines_y + 1):
		var offset = i * cell_size.y
		var start = Vector2(-diagonal, offset)
		var end = Vector2(diagonal, offset)

		# Rotate around origin
		start = start.rotated(angle_rad) + center
		end = end.rotated(angle_rad) + center

		# Clip line to grid bounds
		var clipped = _clip_line_to_rect(start, end, grid_rect)
		if clipped:
			var is_major = (i % 4 == 0)
			draw_line(clipped[0], clipped[1], major_color if is_major else line_color, 2.0 if is_major else 1.0)


func _clip_line_to_rect(p1: Vector2, p2: Vector2, rect: Rect2):
	## Cohen-Sutherland line clipping algorithm
	## Returns null if line is outside, or [clipped_start, clipped_end] if inside
	const INSIDE = 0
	const LEFT = 1
	const RIGHT = 2
	const BOTTOM = 4
	const TOP = 8

	var xmin = rect.position.x
	var xmax = rect.end.x
	var ymin = rect.position.y
	var ymax = rect.end.y

	var _compute_code = func(p: Vector2) -> int:
		var code = INSIDE
		if p.x < xmin:
			code |= LEFT
		elif p.x > xmax:
			code |= RIGHT
		if p.y < ymin:
			code |= TOP
		elif p.y > ymax:
			code |= BOTTOM
		return code

	var code1 = _compute_code.call(p1)
	var code2 = _compute_code.call(p2)

	while true:
		if (code1 | code2) == 0:
			# Both inside
			return [p1, p2]
		elif (code1 & code2) != 0:
			# Both outside same region
			return null
		else:
			# Needs clipping
			var code_out = code1 if code1 != 0 else code2
			var p: Vector2

			if code_out & BOTTOM:
				p = Vector2(p1.x + (p2.x - p1.x) * (ymax - p1.y) / (p2.y - p1.y), ymax)
			elif code_out & TOP:
				p = Vector2(p1.x + (p2.x - p1.x) * (ymin - p1.y) / (p2.y - p1.y), ymin)
			elif code_out & RIGHT:
				p = Vector2(xmax, p1.y + (p2.y - p1.y) * (xmax - p1.x) / (p2.x - p1.x))
			elif code_out & LEFT:
				p = Vector2(xmin, p1.y + (p2.y - p1.y) * (xmin - p1.x) / (p2.x - p1.x))

			if code_out == code1:
				p1 = p
				code1 = _compute_code.call(p1)
			else:
				p2 = p
				code2 = _compute_code.call(p2)

	return null


func _line_intersects_rect(start: Vector2, end: Vector2, rect: Rect2) -> bool:
	## Check if a line segment intersects with a rectangle
	# Simple bounds check
	var min_x = min(start.x, end.x)
	var max_x = max(start.x, end.x)
	var min_y = min(start.y, end.y)
	var max_y = max(start.y, end.y)

	return not (max_x < rect.position.x or min_x > rect.end.x or
				max_y < rect.position.y or min_y > rect.end.y)

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
	## This is the BASE rect without zoom/pan - used for aspect ratio calculations
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


func _get_zoomed_grid_rect() -> Rect2:
	## Calculate the grid rectangle WITH zoom and pan applied
	var base_rect = _get_grid_rect()
	if not map_layout:
		return base_rect

	var zoom = map_layout.zoom_level
	var pan = map_layout.pan_offset

	# Calculate new size (zoomed)
	var new_size = base_rect.size * zoom

	# Calculate new position (centered, then panned)
	var container_center = size / 2.0
	var new_pos = container_center - new_size / 2.0 + pan * zoom

	return Rect2(new_pos, new_size)


func _draw() -> void:
	if not map_layout:
		return

	var grid_dims = map_layout._calculate_grid_dimensions()
	var grid_rect = _get_zoomed_grid_rect()  # Use zoomed rect for drawing
	var center = grid_rect.position + grid_rect.size / 2.0
	var angle_rad = deg_to_rad(map_layout.grid_rotation_degrees)

	# Calculate correct cell size in pixels (always 3" regardless of grid dimensions)
	# Uses zoomed grid_rect so cell_size is also zoomed
	var table_size_inches = map_layout.table_size_feet * 12.0
	var pixels_per_inch_x = grid_rect.size.x / table_size_inches.x
	var pixels_per_inch_y = grid_rect.size.y / table_size_inches.y
	var cell_size = Vector2(
		map_layout.GRID_SIZE_INCHES * pixels_per_inch_x,
		map_layout.GRID_SIZE_INCHES * pixels_per_inch_y
	)

	# Clip rect for the container bounds
	var clip_rect = Rect2(Vector2.ZERO, size)

	# Draw table background (always axis-aligned)
	# Clip to container bounds
	var visible_grid_rect = grid_rect.intersection(clip_rect)
	if visible_grid_rect.size.x > 0 and visible_grid_rect.size.y > 0:
		draw_rect(visible_grid_rect, Color(0.15, 0.15, 0.15, 1.0), true)

	# Calculate half extents for centering the grid
	var half_grid_cells = Vector2(grid_dims.x / 2.0, grid_dims.y / 2.0)

	# Helper function to rotate a point around center
	var rotate_point = func(p: Vector2) -> Vector2:
		var cos_a = cos(angle_rad)
		var sin_a = sin(angle_rad)
		return Vector2(
			p.x * cos_a - p.y * sin_a,
			p.x * sin_a + p.y * cos_a
		) + center

	# Draw terrain cells with manual rotation
	for x in range(grid_dims.x):
		for y in range(grid_dims.y):
			var cell_pos = Vector2i(x, y)

			# Position relative to grid center (grid centered on intersection)
			# Cells are offset by 0.5 from grid lines
			var local_x = (x - half_grid_cells.x + 0.5) * cell_size.x
			var local_y = (y - half_grid_cells.y + 0.5) * cell_size.y

			# Calculate 4 corners in local space, then rotate
			var corners_local = [
				Vector2(local_x - cell_size.x / 2.0, local_y - cell_size.y / 2.0),
				Vector2(local_x + cell_size.x / 2.0, local_y - cell_size.y / 2.0),
				Vector2(local_x + cell_size.x / 2.0, local_y + cell_size.y / 2.0),
				Vector2(local_x - cell_size.x / 2.0, local_y + cell_size.y / 2.0)
			]

			var corners_rotated = []
			var all_inside = true
			# Use slightly expanded rect for boundary check (has_point uses < not <=)
			var epsilon = 0.5
			var expanded_rect = Rect2(
				grid_rect.position - Vector2(epsilon, epsilon),
				grid_rect.size + Vector2(epsilon * 2, epsilon * 2)
			)
			for corner in corners_local:
				var rotated = rotate_point.call(corner)
				corners_rotated.append(rotated)
				# Check if ALL corners are inside table bounds (with epsilon tolerance)
				if not expanded_rect.has_point(rotated):
					all_inside = false

			# Skip if any corner is outside table
			if not all_inside:
				continue

			var terrain_type = map_layout.grid_cells.get(cell_pos, map_layout.TerrainType.NONE)
			var color = map_layout.TERRAIN_COLORS[terrain_type]

			# Draw filled polygon for cell
			draw_colored_polygon(PackedVector2Array(corners_rotated), color)

			# Draw cell border
			for i in range(4):
				var next_i = (i + 1) % 4
				draw_line(corners_rotated[i], corners_rotated[next_i], Color(0.4, 0.4, 0.4, 0.5), 1.0)

			# Draw special markers for Ruins (blue border lines for impassable walls)
			if terrain_type == map_layout.TerrainType.RUINS:
				var inset_ratio = 0.15  # 15% inset
				var center_cell = Vector2.ZERO
				for corner in corners_rotated:
					center_cell += corner
				center_cell /= 4.0

				var inner_corners = []
				for corner in corners_rotated:
					var dir = (corner - center_cell) * (1.0 - inset_ratio)
					inner_corners.append(center_cell + dir)

				for i in range(4):
					var next_i = (i + 1) % 4
					draw_line(inner_corners[i], inner_corners[next_i], Color(0.2, 0.4, 0.9, 0.9), 2.0)

	# Draw grid lines with manual rotation and clipping
	var line_color = Color(0.6, 0.6, 0.6, 0.4)

	# Vertical lines (centered on intersection point)
	for x in range(grid_dims.x + 1):
		var line_x = (x - half_grid_cells.x) * cell_size.x

		# Create line in local space (long enough to cover table at any rotation)
		var line_length = grid_rect.size.length()
		var start_local = Vector2(line_x, -line_length)
		var end_local = Vector2(line_x, line_length)

		# Rotate line
		var start = rotate_point.call(start_local)
		var end = rotate_point.call(end_local)

		# Clip to table bounds
		var clipped = _clip_line_to_rect(start, end, grid_rect)
		if clipped:
			draw_line(clipped[0], clipped[1], line_color, 1.0)

	# Horizontal lines (centered on intersection point)
	for y in range(grid_dims.y + 1):
		var line_y = (y - half_grid_cells.y) * cell_size.y

		# Create line in local space
		var line_length = grid_rect.size.length()
		var start_local = Vector2(-line_length, line_y)
		var end_local = Vector2(line_length, line_y)

		# Rotate line
		var start = rotate_point.call(start_local)
		var end = rotate_point.call(end_local)

		# Clip to table bounds
		var clipped = _clip_line_to_rect(start, end, grid_rect)
		if clipped:
			draw_line(clipped[0], clipped[1], line_color, 1.0)

	# Draw wall segments on cell edges
	if map_layout.wall_segments.size() > 0:
		_draw_wall_segments(grid_rect, cell_size, grid_dims)

	# Draw placed objects markers (trees, containers)
	if map_layout.placed_objects.size() > 0:
		_draw_placed_objects(grid_rect, cell_size, grid_dims)

	# Draw deployment zones (if enabled)
	if map_layout.show_deployment_zones:
		_draw_deployment_zones(grid_rect)

	# Draw mission objectives (always shown if any exist)
	if map_layout.mission_objectives.size() > 0 or map_layout.objectives_editing:
		_draw_mission_objectives(grid_rect, pixels_per_inch_x, pixels_per_inch_y)

	# Draw table outline (always axis-aligned - represents the actual table)
	draw_rect(grid_rect, Color.WHITE, false, 3.0)

	# Draw center point (for symmetry reference)
	draw_circle(center, 5.0, Color(1.0, 1.0, 0.0, 0.8))

	# Draw symmetry indicator if enabled
	if map_layout.point_symmetry_enabled:
		# Draw rotated symmetry axes
		var axis_length = grid_rect.size.length() / 2.0
		var h_start = Vector2(-axis_length, 0).rotated(angle_rad) + center
		var h_end = Vector2(axis_length, 0).rotated(angle_rad) + center
		var v_start = Vector2(0, -axis_length).rotated(angle_rad) + center
		var v_end = Vector2(0, axis_length).rotated(angle_rad) + center

		# Clip to grid bounds
		var h_clipped = _clip_line_to_rect(h_start, h_end, grid_rect)
		var v_clipped = _clip_line_to_rect(v_start, v_end, grid_rect)

		if h_clipped:
			draw_line(h_clipped[0], h_clipped[1], Color(1.0, 1.0, 0.0, 0.3), 2.0)
		if v_clipped:
			draw_line(v_clipped[0], v_clipped[1], Color(1.0, 1.0, 0.0, 0.3), 2.0)

	# Draw table size info
	var table_size = map_layout.table_size_feet
	var size_text = "%.0f' x %.0f' (%.0f\" x %.0f\") - %dx%d cells" % [
		table_size.x, table_size.y,
		table_size.x * 12, table_size.y * 12,
		grid_dims.x, grid_dims.y
	]
	draw_string(ThemeDB.fallback_font, grid_rect.position + Vector2(5, -5), size_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _clip_line_to_rect(p1: Vector2, p2: Vector2, rect: Rect2) -> Variant:
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


func _draw_deployment_zones(grid_rect: Rect2) -> void:
	## Draw deployment zones based on deployment type
	## Uses the same enum as terrain_overlay.gd: NONE=0, FRONT_LINE=1, CUSTOM=2
	if not map_layout:
		return

	var table_size_inches = map_layout.table_size_feet * 12.0
	var pixels_per_inch_x = grid_rect.size.x / table_size_inches.x
	var pixels_per_inch_y = grid_rect.size.y / table_size_inches.y

	var zone_color_p1 = Color(0.2, 0.5, 1.0, 0.25)  # Blue for player 1
	var zone_color_p2 = Color(1.0, 0.3, 0.3, 0.25)  # Red for player 2
	var zone_border_p1 = Color(0.3, 0.6, 1.0, 0.6)
	var zone_border_p2 = Color(1.0, 0.4, 0.4, 0.6)

	# Check deployment type by value (0=NONE, 1=FRONT_LINE, 2=CUSTOM)
	var deploy_type = map_layout.deployment_type

	if deploy_type == 1:  # FRONT_LINE - 12" from long edges
		var margin = 12.0 * pixels_per_inch_y  # 12" deployment zone

		# Player 1 zone (top/bottom depends on table orientation)
		var p1_rect = Rect2(grid_rect.position, Vector2(grid_rect.size.x, margin))
		draw_rect(p1_rect, zone_color_p1, true)
		draw_rect(p1_rect, zone_border_p1, false, 2.0)

		# Player 2 zone (opposite side)
		var p2_rect = Rect2(
			grid_rect.position + Vector2(0, grid_rect.size.y - margin),
			Vector2(grid_rect.size.x, margin)
		)
		draw_rect(p2_rect, zone_color_p2, true)
		draw_rect(p2_rect, zone_border_p2, false, 2.0)

		# Draw labels
		var font = ThemeDB.fallback_font
		draw_string(font, p1_rect.position + Vector2(10, 20), "Player 1 (12\")", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, zone_border_p1)
		draw_string(font, p2_rect.position + Vector2(10, 20), "Player 2 (12\")", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, zone_border_p2)

	elif deploy_type == 2:  # CUSTOM - user-defined polygon zones
		_draw_custom_zones(grid_rect, zone_color_p1, zone_color_p2, zone_border_p1, zone_border_p2)

	# Draw 1" fine grid and boundary snap points when:
	# 1. Actively editing custom zones, OR
	# 2. Custom zones exist and can be dragged
	var has_custom_vertices = map_layout.custom_zone_vertices_p1.size() > 0 or map_layout.custom_zone_vertices_p2.size() > 0
	var can_drag_vertices = deploy_type == 2 and has_custom_vertices
	if map_layout.custom_zone_editing or can_drag_vertices:
		_draw_fine_grid(grid_rect, pixels_per_inch_x, pixels_per_inch_y)


func _draw_custom_zones(grid_rect: Rect2, zone_color_p1: Color, zone_color_p2: Color, zone_border_p1: Color, zone_border_p2: Color) -> void:
	## Draw custom deployment zones defined by user clicks
	## Vertices are stored in 1" coordinates (not 3" cells)
	if not map_layout:
		return

	var grid_dims = map_layout._calculate_grid_dimensions()
	var center = grid_rect.position + grid_rect.size / 2.0
	var angle_rad = deg_to_rad(map_layout.grid_rotation_degrees)

	# Calculate pixels per inch
	var table_size_inches = map_layout.table_size_feet * 12.0
	var pixels_per_inch_x = grid_rect.size.x / table_size_inches.x
	var pixels_per_inch_y = grid_rect.size.y / table_size_inches.y

	# Half of total inches (for centering)
	var half_inches_x = grid_dims.x * 3.0 / 2.0
	var half_inches_y = grid_dims.y * 3.0 / 2.0

	# Helper to convert 1" coordinates (float precision) to screen position
	var inch_to_screen = func(inch_pos: Vector2) -> Vector2:
		var local_x = (inch_pos.x - half_inches_x) * pixels_per_inch_x
		var local_y = (inch_pos.y - half_inches_y) * pixels_per_inch_y
		var cos_a = cos(angle_rad)
		var sin_a = sin(angle_rad)
		return Vector2(
			local_x * cos_a - local_y * sin_a,
			local_x * sin_a + local_y * cos_a
		) + center

	# Draw Player 1 zone
	var p1_verts = map_layout.custom_zone_vertices_p1
	if p1_verts.size() >= 3:
		var screen_verts: PackedVector2Array = []
		for vertex in p1_verts:
			screen_verts.append(inch_to_screen.call(vertex))
		draw_colored_polygon(screen_verts, zone_color_p1)
		# Draw border
		for i in range(screen_verts.size()):
			var next_i = (i + 1) % screen_verts.size()
			draw_line(screen_verts[i], screen_verts[next_i], zone_border_p1, 2.0)

	# Draw Player 2 zone
	var p2_verts = map_layout.custom_zone_vertices_p2
	if p2_verts.size() >= 3:
		var screen_verts: PackedVector2Array = []
		for vertex in p2_verts:
			screen_verts.append(inch_to_screen.call(vertex))
		draw_colored_polygon(screen_verts, zone_color_p2)
		# Draw border
		for i in range(screen_verts.size()):
			var next_i = (i + 1) % screen_verts.size()
			draw_line(screen_verts[i], screen_verts[next_i], zone_border_p2, 2.0)

	# Draw vertex markers (always show during editing, or if we have vertices)
	var is_editing = map_layout.custom_zone_editing
	var zoom = map_layout.zoom_level if map_layout else 1.0
	var vertex_size = (6.0 if is_editing else 4.0) * zoom  # Scale with zoom

	# Player 1 vertices
	for i in range(p1_verts.size()):
		var screen_pos = inch_to_screen.call(p1_verts[i])
		draw_circle(screen_pos, vertex_size, zone_border_p1)
		if is_editing:
			# Show vertex number
			draw_string(ThemeDB.fallback_font, screen_pos + Vector2(8, -4), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, zone_border_p1)

	# Player 2 vertices
	for i in range(p2_verts.size()):
		var screen_pos = inch_to_screen.call(p2_verts[i])
		draw_circle(screen_pos, vertex_size, zone_border_p2)
		if is_editing:
			draw_string(ThemeDB.fallback_font, screen_pos + Vector2(8, -4), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, zone_border_p2)

	# Draw lines connecting vertices while editing (even if < 3 vertices)
	if is_editing:
		if p1_verts.size() >= 2:
			for i in range(p1_verts.size() - 1):
				var start = inch_to_screen.call(p1_verts[i])
				var end_pt = inch_to_screen.call(p1_verts[i + 1])
				draw_line(start, end_pt, zone_border_p1, 1.5)

		if p2_verts.size() >= 2:
			for i in range(p2_verts.size() - 1):
				var start = inch_to_screen.call(p2_verts[i])
				var end_pt = inch_to_screen.call(p2_verts[i + 1])
				draw_line(start, end_pt, zone_border_p2, 1.5)

	# Draw labels
	var font = ThemeDB.fallback_font
	if p1_verts.size() > 0:
		var first_pos = inch_to_screen.call(p1_verts[0])
		draw_string(font, first_pos + Vector2(-40, -20), "P1", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, zone_border_p1)
	if p2_verts.size() > 0:
		var first_pos = inch_to_screen.call(p2_verts[0])
		draw_string(font, first_pos + Vector2(-40, -20), "P2", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, zone_border_p2)


func _draw_fine_grid(grid_rect: Rect2, pixels_per_inch_x: float, pixels_per_inch_y: float) -> void:
	## Draw 1" fine grid for custom deployment zone editing
	## Grid lines rotate with the main 3" grid, covering the full diagonal
	var line_color = Color(0.5, 0.5, 0.5, 0.3)
	var center = grid_rect.position + grid_rect.size / 2.0
	var angle_rad = deg_to_rad(map_layout.grid_rotation_degrees)

	# Use grid dimensions (covers diagonal) - each 3" cell has 3 subdivisions of 1"
	var grid_dims = map_layout._calculate_grid_dimensions()
	var total_inches_x = grid_dims.x * 3  # 3 inches per cell
	var total_inches_y = grid_dims.y * 3
	var half_inches_x = total_inches_x / 2.0
	var half_inches_y = total_inches_y / 2.0

	# Helper function to rotate a point around center
	var rotate_point = func(p: Vector2) -> Vector2:
		var cos_a = cos(angle_rad)
		var sin_a = sin(angle_rad)
		return Vector2(
			p.x * cos_a - p.y * sin_a,
			p.x * sin_a + p.y * cos_a
		) + center

	# Draw vertical lines (every inch)
	var line_length = grid_rect.size.length()
	for i in range(total_inches_x + 1):
		var line_x = (i - half_inches_x) * pixels_per_inch_x

		var start_local = Vector2(line_x, -line_length)
		var end_local = Vector2(line_x, line_length)

		var start = rotate_point.call(start_local)
		var end_point = rotate_point.call(end_local)

		var clipped = _clip_line_to_rect(start, end_point, grid_rect)
		if clipped != null:
			draw_line(clipped[0], clipped[1], line_color, 0.5)

	# Draw horizontal lines (every inch)
	for i in range(total_inches_y + 1):
		var line_y = (i - half_inches_y) * pixels_per_inch_y

		var start_local = Vector2(-line_length, line_y)
		var end_local = Vector2(line_length, line_y)

		var start = rotate_point.call(start_local)
		var end_point = rotate_point.call(end_local)

		var clipped = _clip_line_to_rect(start, end_point, grid_rect)
		if clipped != null:
			draw_line(clipped[0], clipped[1], line_color, 0.5)

	# Draw table boundary intersection points as snap targets
	_draw_boundary_snap_points(grid_rect, pixels_per_inch_x, pixels_per_inch_y)


func _draw_boundary_snap_points(grid_rect: Rect2, pixels_per_inch_x: float, pixels_per_inch_y: float) -> void:
	## Draw snap points at EXACT intersections where 1" grid lines cross the table boundary
	## Also draws corner snap points for the 4 table corners
	var center = grid_rect.position + grid_rect.size / 2.0
	var angle_rad = deg_to_rad(map_layout.grid_rotation_degrees)

	var grid_dims = map_layout._calculate_grid_dimensions()
	var total_inches_x = grid_dims.x * 3
	var total_inches_y = grid_dims.y * 3
	var half_inches_x = total_inches_x / 2.0
	var half_inches_y = total_inches_y / 2.0

	var rotate_point = func(p: Vector2) -> Vector2:
		var cos_a = cos(angle_rad)
		var sin_a = sin(angle_rad)
		return Vector2(
			p.x * cos_a - p.y * sin_a,
			p.x * sin_a + p.y * cos_a
		) + center

	# Convert screen position to EXACT inch coordinates (floats for precision)
	# This allows vertices to be placed at exact grid-boundary intersections
	var screen_to_inch = func(screen_pt: Vector2) -> Vector2:
		var rel = screen_pt - center
		var cos_a = cos(-angle_rad)
		var sin_a = sin(-angle_rad)
		var local = Vector2(
			rel.x * cos_a - rel.y * sin_a,
			rel.x * sin_a + rel.y * cos_a
		)
		var inch_x = local.x / pixels_per_inch_x + half_inches_x
		var inch_y = local.y / pixels_per_inch_y + half_inches_y
		return Vector2(inch_x, inch_y)

	var snap_color = Color(1.0, 1.0, 0.3, 0.9)  # Yellow
	var zoom = map_layout.zoom_level if map_layout else 1.0
	var snap_size = 4.0 * zoom

	map_layout._cached_boundary_snap_points.clear()

	var line_length = grid_rect.size.length()

	# Track added positions to avoid duplicates
	var added_positions: Dictionary = {}
	var pos_tolerance = 2.0

	var add_snap_point = func(screen_pos: Vector2, color: Color, size: float) -> void:
		# Check for duplicates
		var pos_key = "%d_%d" % [int(screen_pos.x / pos_tolerance), int(screen_pos.y / pos_tolerance)]
		if added_positions.has(pos_key):
			return
		added_positions[pos_key] = true

		draw_circle(screen_pos, size, color)
		var inch_pos = screen_to_inch.call(screen_pos)
		map_layout._cached_boundary_snap_points.append({
			"screen_pos": screen_pos,
			"inch_pos": inch_pos
		})

	# Find intersections of vertical grid lines (at 1" intervals) with table boundary
	for i in range(total_inches_x + 1):
		var line_x = (i - half_inches_x) * pixels_per_inch_x
		var start_local = Vector2(line_x, -line_length)
		var end_local = Vector2(line_x, line_length)
		var start = rotate_point.call(start_local)
		var end_point = rotate_point.call(end_local)

		# Clip line to table boundary - gives exact intersection points
		var clipped = _clip_line_to_rect(start, end_point, grid_rect)
		if clipped != null:
			add_snap_point.call(clipped[0], snap_color, snap_size)
			add_snap_point.call(clipped[1], snap_color, snap_size)

	# Find intersections of horizontal grid lines with table boundary
	for i in range(total_inches_y + 1):
		var line_y = (i - half_inches_y) * pixels_per_inch_y
		var start_local = Vector2(-line_length, line_y)
		var end_local = Vector2(line_length, line_y)
		var start = rotate_point.call(start_local)
		var end_point = rotate_point.call(end_local)

		var clipped = _clip_line_to_rect(start, end_point, grid_rect)
		if clipped != null:
			add_snap_point.call(clipped[0], snap_color, snap_size)
			add_snap_point.call(clipped[1], snap_color, snap_size)

	# Always add the 4 table corners as snap points
	var corner_color = Color(1.0, 0.6, 0.2, 1.0)  # Orange for corners
	var corner_size = 6.0 * zoom
	var corners = [
		grid_rect.position,                                      # Top-left
		grid_rect.position + Vector2(grid_rect.size.x, 0),       # Top-right
		grid_rect.position + Vector2(0, grid_rect.size.y),       # Bottom-left
		grid_rect.end                                            # Bottom-right
	]
	for corner in corners:
		add_snap_point.call(corner, corner_color, corner_size)

	map_layout._snap_points_valid = true


func _draw_mission_objectives(grid_rect: Rect2, pixels_per_inch_x: float, pixels_per_inch_y: float) -> void:
	## Draw mission objectives on the 1" grid
	## Objectives are displayed as target circles with 3" seize radius rings
	if not map_layout:
		return

	var grid_dims = map_layout._calculate_grid_dimensions()
	var center = grid_rect.position + grid_rect.size / 2.0
	var angle_rad = deg_to_rad(map_layout.grid_rotation_degrees)

	# Half of total inches (for centering)
	var half_inches_x = grid_dims.x * 3.0 / 2.0
	var half_inches_y = grid_dims.y * 3.0 / 2.0

	# Helper to convert 1" coordinates to screen position
	var inch_to_screen = func(inch_pos: Vector2) -> Vector2:
		var local_x = (inch_pos.x - half_inches_x) * pixels_per_inch_x
		var local_y = (inch_pos.y - half_inches_y) * pixels_per_inch_y
		var cos_a = cos(angle_rad)
		var sin_a = sin(angle_rad)
		return Vector2(
			local_x * cos_a - local_y * sin_a,
			local_x * sin_a + local_y * cos_a
		) + center

	var zoom = map_layout.zoom_level if map_layout else 1.0

	# Draw 1" fine grid when in objectives editing mode
	if map_layout.objectives_editing:
		_draw_fine_grid(grid_rect, pixels_per_inch_x, pixels_per_inch_y)

	# Calculate 3" seize radius in pixels (average of x and y scale)
	var seize_radius_inches = 3.0
	var seize_radius_pixels = seize_radius_inches * (pixels_per_inch_x + pixels_per_inch_y) / 2.0

	# Colors
	var objective_color = Color(1.0, 0.85, 0.2, 1.0)  # Gold/yellow
	var objective_outline = Color(0.2, 0.15, 0.05, 1.0)  # Dark outline
	var seize_ring_color = Color(1.0, 0.85, 0.2, 0.3)  # Semi-transparent gold
	var seize_ring_border = Color(1.0, 0.85, 0.2, 0.6)  # Brighter border
	var objective_size = 12.0 * zoom  # Size in pixels

	# First pass: Draw 3" seize radius rings (behind objectives)
	for i in range(map_layout.mission_objectives.size()):
		var obj_pos = map_layout.mission_objectives[i]
		var screen_pos = inch_to_screen.call(obj_pos)

		# Draw seize radius ring (3" = capture zone)
		_draw_circle_ring(screen_pos, seize_radius_pixels, seize_ring_color, seize_ring_border, 2.0 * zoom)

	# Second pass: Draw objective markers (on top of rings)
	for i in range(map_layout.mission_objectives.size()):
		var obj_pos = map_layout.mission_objectives[i]
		var screen_pos = inch_to_screen.call(obj_pos)

		# Skip marker if outside visible area (ring may still be partially visible)
		if not grid_rect.grow(seize_radius_pixels).has_point(screen_pos):
			continue

		# Draw objective marker (concentric circles like a target)
		# Outer ring
		draw_circle(screen_pos, objective_size, objective_outline)
		draw_circle(screen_pos, objective_size - 2 * zoom, objective_color)

		# Middle ring
		draw_circle(screen_pos, objective_size * 0.6, objective_outline)
		draw_circle(screen_pos, objective_size * 0.6 - 1.5 * zoom, objective_color)

		# Center dot
		draw_circle(screen_pos, objective_size * 0.25, objective_outline)

		# Draw objective number
		var font = ThemeDB.fallback_font
		var label = str(i + 1)
		draw_string(font, screen_pos + Vector2(objective_size + 4, 4) * zoom, label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * zoom), objective_color)

	# Third pass: Draw warning lines between objectives that are too close (<9")
	_draw_objective_distance_warnings(inch_to_screen, zoom)


## Draw warning indicators between objectives that are closer than 9"
func _draw_objective_distance_warnings(inch_to_screen: Callable, zoom: float) -> void:
	const MIN_DISTANCE_INCHES := 9.0
	var warning_color = Color(1.0, 0.25, 0.2, 0.9)  # Bright red
	var warning_fill = Color(1.0, 0.25, 0.2, 0.3)  # Semi-transparent red

	for i in range(map_layout.mission_objectives.size()):
		for j in range(i + 1, map_layout.mission_objectives.size()):
			var pos_i = map_layout.mission_objectives[i]
			var pos_j = map_layout.mission_objectives[j]
			var dist = pos_i.distance_to(pos_j)

			if dist < MIN_DISTANCE_INCHES:
				var screen_i = inch_to_screen.call(pos_i)
				var screen_j = inch_to_screen.call(pos_j)

				# Draw red dashed line between the two objectives
				_draw_warning_line(screen_i, screen_j, warning_color, 3.0 * zoom)

				# Draw exclamation mark at midpoint
				var midpoint = (screen_i + screen_j) / 2.0
				_draw_exclamation_mark(midpoint, warning_color, warning_fill, zoom)

				# Draw distance label
				var font = ThemeDB.fallback_font
				var dist_label = "%.1f\"" % dist
				draw_string(font, midpoint + Vector2(12, -8) * zoom, dist_label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * zoom), warning_color)


## Draw a warning line (dashed red line with arrow heads)
func _draw_warning_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var direction = (to - from).normalized()
	var length = from.distance_to(to)
	var dash_length = 8.0
	var gap_length = 4.0

	# Draw dashed line
	var current_dist = 0.0
	while current_dist < length:
		var dash_start = from + direction * current_dist
		var dash_end_dist = min(current_dist + dash_length, length)
		var dash_end = from + direction * dash_end_dist
		draw_line(dash_start, dash_end, color, width)
		current_dist += dash_length + gap_length

	# Draw small arrow heads at both ends pointing inward (indicating "too close")
	var arrow_size = 8.0
	var arrow_angle = 0.5  # radians

	# Arrow at 'from' pointing toward 'to'
	var arrow1_dir = direction
	var arrow1_left = from + arrow1_dir.rotated(PI - arrow_angle) * arrow_size + direction * 5
	var arrow1_right = from + arrow1_dir.rotated(PI + arrow_angle) * arrow_size + direction * 5
	var arrow1_tip = from + direction * 5
	draw_line(arrow1_tip, arrow1_left, color, width)
	draw_line(arrow1_tip, arrow1_right, color, width)

	# Arrow at 'to' pointing toward 'from'
	var arrow2_dir = -direction
	var arrow2_left = to + arrow2_dir.rotated(PI - arrow_angle) * arrow_size - direction * 5
	var arrow2_right = to + arrow2_dir.rotated(PI + arrow_angle) * arrow_size - direction * 5
	var arrow2_tip = to - direction * 5
	draw_line(arrow2_tip, arrow2_left, color, width)
	draw_line(arrow2_tip, arrow2_right, color, width)


## Draw an exclamation mark warning symbol
func _draw_exclamation_mark(pos: Vector2, color: Color, fill_color: Color, zoom: float) -> void:
	var size = 20.0 * zoom

	# Draw warning triangle background
	var triangle_points = PackedVector2Array([
		pos + Vector2(0, -size * 0.6),      # Top
		pos + Vector2(-size * 0.5, size * 0.4),  # Bottom left
		pos + Vector2(size * 0.5, size * 0.4)    # Bottom right
	])
	draw_colored_polygon(triangle_points, fill_color)

	# Draw triangle border
	for i in range(3):
		var next_i = (i + 1) % 3
		draw_line(triangle_points[i], triangle_points[next_i], color, 2.0 * zoom)

	# Draw exclamation mark
	var exclaim_color = color
	# Vertical bar
	draw_line(pos + Vector2(0, -size * 0.35), pos + Vector2(0, size * 0.05), exclaim_color, 3.0 * zoom)
	# Dot
	draw_circle(pos + Vector2(0, size * 0.22), 2.5 * zoom, exclaim_color)


## Draw a filled circle with a border ring
func _draw_circle_ring(pos: Vector2, radius: float, fill_color: Color, border_color: Color, border_width: float) -> void:
	# Draw filled circle
	draw_circle(pos, radius, fill_color)
	# Draw border as arc (full circle)
	draw_arc(pos, radius, 0, TAU, 64, border_color, border_width)


# ==============================================================================
# WAND-SEGMENT-RENDERING
# ==============================================================================

func _draw_wall_segments(grid_rect: Rect2, cell_size: Vector2, grid_dims: Vector2i) -> void:
	## Draw placed wall segments as thick colored lines on cell edges
	if not map_layout:
		return

	var center = grid_rect.position + grid_rect.size / 2.0
	var angle_rad = deg_to_rad(map_layout.grid_rotation_degrees)
	var half_grid_cells = Vector2(grid_dims.x / 2.0, grid_dims.y / 2.0)

	var wall_color = Color(0.9, 0.6, 0.2, 0.9)  # Orange for walls
	var wall_outline = Color(0.3, 0.2, 0.05, 0.8)
	var zoom = map_layout.zoom_level if map_layout else 1.0
	var wall_width = 4.0 * zoom

	var rotate_point = func(p: Vector2) -> Vector2:
		var cos_a = cos(angle_rad)
		var sin_a = sin(angle_rad)
		return Vector2(
			p.x * cos_a - p.y * sin_a,
			p.x * sin_a + p.y * cos_a
		) + center

	for wall in map_layout.wall_segments:
		var cell: Vector2i = wall.get("edge_cell", Vector2i.ZERO)
		var side: int = wall.get("edge_side", 0)

		# Calculate edge start/end in local space (relative to grid center)
		var edge_points = _get_edge_local_points(cell, side, cell_size, half_grid_cells)
		if edge_points.is_empty():
			continue

		var start = rotate_point.call(edge_points[0])
		var end_pt = rotate_point.call(edge_points[1])

		# Draw outline first (slightly wider)
		draw_line(start, end_pt, wall_outline, wall_width + 2.0)
		# Draw wall line on top
		draw_line(start, end_pt, wall_color, wall_width)

		# Draw small perpendicular ticks at each end to indicate wall height
		var dir = (end_pt - start).normalized()
		var perp = Vector2(-dir.y, dir.x) * 6.0 * zoom
		draw_line(start - perp, start + perp, wall_color, 1.5)
		draw_line(end_pt - perp, end_pt + perp, wall_color, 1.5)


func _get_edge_local_points(cell: Vector2i, side: int, cell_size: Vector2, half_grid_cells: Vector2) -> Array:
	## Calculate edge start/end points in local (unrotated) space
	## side: 0=North, 1=East, 2=South, 3=West
	var cx = (cell.x - half_grid_cells.x + 0.5) * cell_size.x
	var cy = (cell.y - half_grid_cells.y + 0.5) * cell_size.y
	var hx = cell_size.x / 2.0
	var hy = cell_size.y / 2.0

	match side:
		0:  # North edge
			return [Vector2(cx - hx, cy - hy), Vector2(cx + hx, cy - hy)]
		1:  # East edge
			return [Vector2(cx + hx, cy - hy), Vector2(cx + hx, cy + hy)]
		2:  # South edge
			return [Vector2(cx - hx, cy + hy), Vector2(cx + hx, cy + hy)]
		3:  # West edge
			return [Vector2(cx - hx, cy - hy), Vector2(cx - hx, cy + hy)]

	return []


# ==============================================================================
# PLATZIERTE OBJEKTE RENDERING
# ==============================================================================

func _draw_placed_objects(grid_rect: Rect2, cell_size: Vector2, grid_dims: Vector2i) -> void:
	## Draw markers for auto-placed trees and containers on the 2D grid
	if not map_layout:
		return

	var center = grid_rect.position + grid_rect.size / 2.0
	var angle_rad = deg_to_rad(map_layout.grid_rotation_degrees)
	var half_grid_cells = Vector2(grid_dims.x / 2.0, grid_dims.y / 2.0)
	var zoom = map_layout.zoom_level if map_layout else 1.0

	var tree_color = Color(0.1, 0.7, 0.1, 0.8)
	var container_color = Color(0.7, 0.4, 0.1, 0.8)
	var marker_size = 4.0 * zoom

	var rotate_point = func(p: Vector2) -> Vector2:
		var cos_a = cos(angle_rad)
		var sin_a = sin(angle_rad)
		return Vector2(
			p.x * cos_a - p.y * sin_a,
			p.x * sin_a + p.y * cos_a
		) + center

	for obj in map_layout.placed_objects:
		var cell: Vector2i = obj.get("cell", Vector2i.ZERO)
		var offset: Vector2 = obj.get("offset", Vector2(0.5, 0.5))
		var obj_type: String = obj.get("object_type", "tree")

		# Calculate position within cell (offset 0-1 maps to cell area)
		var local_x = (cell.x - half_grid_cells.x + offset.x) * cell_size.x
		var local_y = (cell.y - half_grid_cells.y + offset.y) * cell_size.y
		var screen_pos = rotate_point.call(Vector2(local_x, local_y))

		var color = tree_color if obj_type == "tree" else container_color

		if obj_type == "tree":
			# Draw tree as small filled circle with cross
			draw_circle(screen_pos, marker_size, color)
			var cross_len = marker_size * 0.7
			draw_line(screen_pos - Vector2(cross_len, 0), screen_pos + Vector2(cross_len, 0), Color.WHITE, 1.0)
			draw_line(screen_pos - Vector2(0, cross_len), screen_pos + Vector2(0, cross_len), Color.WHITE, 1.0)
		else:
			# Draw container as small filled square
			var half = marker_size * 0.8
			var rect = Rect2(screen_pos - Vector2(half, half), Vector2(half * 2, half * 2))
			draw_rect(rect, color, true)
			draw_rect(rect, Color.WHITE, false, 1.0)

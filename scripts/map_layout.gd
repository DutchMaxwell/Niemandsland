extends Control
## Map Layout Editor - Top-down view with 3" grid for terrain type assignment
## OPR terrain recommendations are displayed in real-time

signal layout_closed

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

@onready var grid_container: Control = %GridContainer
@onready var rotation_slider: HSlider = %RotationSlider
@onready var rotation_label: Label = %RotationLabel
@onready var terrain_buttons: VBoxContainer = %TerrainButtons
@onready var stats_label: Label = %StatsLabel
@onready var recommendations_label: Label = %RecommendationsLabel
@onready var close_button: Button = %CloseButton
@onready var clear_button: Button = %ClearButton


func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	clear_button.pressed.connect(_on_clear_pressed)
	rotation_slider.value_changed.connect(_on_rotation_changed)

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
	rotation_label.text = "Rotation: %.0f°" % value
	grid_container.queue_redraw()


func _on_close_pressed() -> void:
	layout_closed.emit()
	hide()


func _on_clear_pressed() -> void:
	grid_cells.clear()
	grid_container.queue_redraw()
	_update_stats()


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

	# Calculate percentages
	var blocking_count = counts[TerrainType.CONTAINER]  # Blocking LOS
	var cover_count = counts[TerrainType.RUINS] + counts[TerrainType.FOREST]  # Provide cover
	var difficult_count = counts[TerrainType.FOREST]  # Difficult terrain
	var dangerous_count = counts[TerrainType.DANGEROUS]

	var blocking_pct = (float(blocking_count) / total_cells) * 100.0 if total_cells > 0 else 0.0
	var cover_pct = (float(cover_count) / total_cells) * 100.0 if total_cells > 0 else 0.0
	var difficult_pct = (float(difficult_count) / total_cells) * 100.0 if total_cells > 0 else 0.0
	var dangerous_pct = (float(dangerous_count) / total_cells) * 100.0 if total_cells > 0 else 0.0

	stats_label.text = """Current Coverage (%d total cells):
• Blocking LOS: %d cells (%.1f%%)
• Cover: %d cells (%.1f%%)
• Difficult: %d cells (%.1f%%)
• Dangerous: %d cells (%.1f%%)

Terrain breakdown:
  Ruins: %d | Forest: %d | Container: %d | Dangerous: %d""" % [
		total_cells,
		blocking_count, blocking_pct,
		cover_count, cover_pct,
		difficult_count, difficult_pct,
		dangerous_count, dangerous_pct,
		counts[TerrainType.RUINS],
		counts[TerrainType.FOREST],
		counts[TerrainType.CONTAINER],
		counts[TerrainType.DANGEROUS]
	]

	_update_recommendations_with_values(total_cells, blocking_pct, cover_pct, difficult_pct, dangerous_count)


func _update_recommendations() -> void:
	_update_stats()


func _update_recommendations_with_values(total_cells: int, blocking_pct: float, cover_pct: float, difficult_pct: float, dangerous_count: int) -> void:
	var blocking_ok = blocking_pct >= 50.0
	var cover_ok = cover_pct >= 33.0
	var difficult_ok = difficult_pct >= 33.0
	var dangerous_ok = dangerous_count >= 2  # Each player picks 1 piece

	var check_mark = "✓"
	var cross_mark = "✗"

	recommendations_label.text = """OPR Terrain Recommendations:

%s At least 50%% should block LOS (current: %.1f%%)
%s At least 33%% should provide cover (current: %.1f%%)
%s At least 33%% should be difficult (current: %.1f%%)
%s Each player picks 1 dangerous piece (need 2, have: %d)

Example for 12 terrain pieces:
6 block LOS, 4 cover, 4 difficult, 2 dangerous""" % [
		check_mark if blocking_ok else cross_mark, blocking_pct,
		check_mark if cover_ok else cross_mark, cover_pct,
		check_mark if difficult_ok else cross_mark, difficult_pct,
		check_mark if dangerous_ok else cross_mark, dangerous_count
	]

	# Color code the recommendations
	if blocking_ok and cover_ok and difficult_ok and dangerous_ok:
		recommendations_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
	else:
		recommendations_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))


func _get_cell_at_screen_pos(screen_pos: Vector2) -> Vector2i:
	var grid_rect = grid_container.get_rect()
	var grid_dims = _calculate_grid_dimensions()

	# Calculate cell size in pixels
	var cell_size = Vector2(
		grid_rect.size.x / grid_dims.x,
		grid_rect.size.y / grid_dims.y
	)

	# Get position relative to grid container
	var local_pos = screen_pos - grid_container.global_position

	# Apply inverse rotation around center
	var center = grid_rect.size / 2.0
	var rotated_pos = local_pos - center
	var angle_rad = deg_to_rad(-grid_rotation_degrees)
	rotated_pos = Vector2(
		rotated_pos.x * cos(angle_rad) - rotated_pos.y * sin(angle_rad),
		rotated_pos.x * sin(angle_rad) + rotated_pos.y * cos(angle_rad)
	)
	rotated_pos += center

	# Calculate cell coordinates
	var cell_x = int(rotated_pos.x / cell_size.x)
	var cell_y = int(rotated_pos.y / cell_size.y)

	return Vector2i(cell_x, cell_y)


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
		else:
			grid_cells[cell] = selected_terrain_type
		grid_container.queue_redraw()
		_update_stats()

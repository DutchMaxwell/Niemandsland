extends Node3D
## Main scene controller for OpenTTS
## Handles initialization and connects UI signals

@onready var object_manager: Node3D = $ObjectManager
@onready var table: StaticBody3D = $Table
@onready var camera_pivot: Node3D = $CameraPivot
@onready var dice_result_label: Label = $UI/HUD/DiceResult
@onready var distance_label: Label = $UI/HUD/DistanceLabel
@onready var spawn_miniature_btn: Button = $UI/HUD/SpawnPanel/SpawnMiniature
@onready var spawn_dice_btn: Button = $UI/HUD/SpawnPanel/SpawnDice
@onready var spawn_terrain_btn: Button = $UI/HUD/SpawnPanel/SpawnTerrain
@onready var clear_all_btn: Button = $UI/HUD/SpawnPanel/ClearAll
@onready var spawn_200_btn: Button = $UI/HUD/SpawnPanel/Spawn200
@onready var spawn_500_btn: Button = $UI/HUD/SpawnPanel/Spawn500
@onready var spawn_1000_btn: Button = $UI/HUD/SpawnPanel/Spawn1000
@onready var spawn_complex_btn: Button = $UI/HUD/SpawnPanel/SpawnComplex
@onready var performance_label: Label = %PerformanceLabel

# Table size UI elements
@onready var table_size_option: OptionButton = $UI/HUD/TableSizePanel/TableSizeOption
@onready var custom_size_container: VBoxContainer = $UI/HUD/TableSizePanel/CustomSizeContainer
@onready var unit_option: OptionButton = $UI/HUD/TableSizePanel/CustomSizeContainer/UnitOption
@onready var width_input: SpinBox = $UI/HUD/TableSizePanel/CustomSizeContainer/WidthContainer/WidthInput
@onready var length_input: SpinBox = $UI/HUD/TableSizePanel/CustomSizeContainer/LengthContainer/LengthInput
@onready var apply_custom_btn: Button = $UI/HUD/TableSizePanel/CustomSizeContainer/ApplyCustomBtn

# Dice Roller Plugin UI
@onready var dice_roller_control = %DiceRollerControl
@onready var roll_button: Button = %RollButton
@onready var quick_roll_button: Button = %QuickRollButton
@onready var roller_result_label: Label = %RollerResultLabel
@onready var dice_count_spinner: SpinBox = %DiceCountSpinner
@onready var current_dice_label: Label = %CurrentDiceLabel

const INCHES_TO_FEET: float = 1.0 / 12.0
const CM_TO_FEET: float = 1.0 / 30.48


func _ready() -> void:
	print("OpenTTS Prototype v0.1 - Initializing...")

	# Connect UI buttons
	spawn_miniature_btn.pressed.connect(_on_spawn_miniature)
	# Tabletop dice disabled - use Dice Roller Plugin instead
	spawn_dice_btn.visible = false
	spawn_terrain_btn.pressed.connect(_on_spawn_terrain)
	clear_all_btn.pressed.connect(_on_clear_all)
	spawn_200_btn.pressed.connect(_on_spawn_200)
	spawn_500_btn.pressed.connect(_on_spawn_500)
	spawn_1000_btn.pressed.connect(_on_spawn_1000)
	spawn_complex_btn.pressed.connect(_on_spawn_complex)

	# Connect table size UI
	table_size_option.item_selected.connect(_on_table_size_selected)
	apply_custom_btn.pressed.connect(_on_apply_custom_size)
	unit_option.item_selected.connect(_on_unit_changed)

	# Connect to object manager signals
	object_manager.dice_rolled.connect(_on_dice_rolled)
	object_manager.distance_changed.connect(_on_distance_changed)
	object_manager.measurement_finished.connect(_on_measurement_finished)
	object_manager.drag_ended.connect(_on_drag_ended)

	# Hide distance label initially
	distance_label.text = ""

	# Connect Dice Roller Plugin
	roll_button.pressed.connect(_on_roll_button_pressed)
	quick_roll_button.pressed.connect(_on_quick_roll_button_pressed)
	dice_roller_control.roll_finnished.connect(_on_roller_finished)
	dice_roller_control.roll_started.connect(_on_roller_started)
	dice_count_spinner.value_changed.connect(_on_dice_count_changed)

	# Initialize dice roller with default count
	_update_dice_set(int(dice_count_spinner.value))

	# Initialize table with default size (6x4 feet = 72x48 inches, landscape)
	# Long side (72") faces the viewer (X-axis), short side (48") is depth (Z-axis)
	table.setup_table(Vector2(6, 4))
	_adjust_camera_for_table_size(Vector2(6, 4))
	table_size_option.selected = 1  # Select 72x48 option

	print("OpenTTS ready!")


func _process(_delta: float) -> void:
	# Update performance label
	var fps = Engine.get_frames_per_second()
	var object_count = object_manager.get_child_count()

	# Color FPS based on performance
	var fps_color: Color
	if fps >= 55:
		fps_color = Color.GREEN
	elif fps >= 30:
		fps_color = Color.YELLOW
	else:
		fps_color = Color.RED

	performance_label.add_theme_color_override("font_color", fps_color)
	performance_label.text = "FPS: %d | Objects: %d" % [fps, object_count]


func _on_spawn_miniature() -> void:
	var spawn_pos = _get_random_table_position()
	object_manager.spawn_miniature(spawn_pos)


func _on_spawn_dice() -> void:
	var spawn_pos = _get_random_table_position()
	spawn_pos.y = 0.5  # Drop from reasonable height above table
	object_manager.spawn_dice(spawn_pos)


func _on_spawn_terrain() -> void:
	var spawn_pos = _get_random_table_position()
	object_manager.spawn_terrain(spawn_pos)


## Performance test: Spawn 200 miniatures in a grid
func _on_spawn_200() -> void:
	print("=== PERFORMANCE TEST: Spawning 200 miniatures ===")
	var start_time = Time.get_ticks_msec()

	# Clear existing objects first
	object_manager.clear_all_objects()

	# Calculate grid layout (20 columns x 10 rows = 200)
	var cols = 20
	var rows = 10

	# Table size in meters
	var size_meters = table.table_size * 0.3048  # FEET_TO_METERS
	var margin = 0.05  # 5cm margin from edges

	# Calculate spacing
	var usable_width = size_meters.x - (margin * 2)
	var usable_depth = size_meters.y - (margin * 2)
	var spacing_x = usable_width / (cols - 1)
	var spacing_z = usable_depth / (rows - 1)

	# Start position (top-left corner)
	var start_x = -size_meters.x / 2 + margin
	var start_z = -size_meters.y / 2 + margin

	# Spawn miniatures in grid
	var count = 0
	for row in range(rows):
		for col in range(cols):
			var pos = Vector3(
				start_x + col * spacing_x,
				0,
				start_z + row * spacing_z
			)
			object_manager.spawn_miniature(pos)
			count += 1

	var end_time = Time.get_ticks_msec()
	var spawn_duration = end_time - start_time

	print("Spawned %d miniatures in %d ms" % [count, spawn_duration])
	print("Grid: %dx%d, Spacing: %.3fm x %.3fm" % [cols, rows, spacing_x, spacing_z])
	print("=== Monitor FPS for performance test ===")


## Performance test: Spawn 500 miniatures
func _on_spawn_500() -> void:
	_spawn_grid(500, 25, 20)


## Performance test: Spawn 1000 miniatures
func _on_spawn_1000() -> void:
	_spawn_grid(1000, 40, 25)


## Performance test: Spawn 100 complex terrain objects
func _on_spawn_complex() -> void:
	print("=== PERFORMANCE TEST: Spawning 100 complex terrain objects ===")
	var start_time = Time.get_ticks_msec()

	object_manager.clear_all_objects()

	var cols = 10
	var rows = 10
	var size_meters = table.table_size * 0.3048
	var margin = 0.1

	var usable_width = size_meters.x - (margin * 2)
	var usable_depth = size_meters.y - (margin * 2)
	var spacing_x = usable_width / (cols - 1)
	var spacing_z = usable_depth / (rows - 1)

	var start_x = -size_meters.x / 2 + margin
	var start_z = -size_meters.y / 2 + margin

	var count = 0
	for row in range(rows):
		for col in range(cols):
			var pos = Vector3(
				start_x + col * spacing_x,
				0,
				start_z + row * spacing_z
			)
			object_manager.spawn_terrain(pos)
			count += 1

	var end_time = Time.get_ticks_msec()
	print("Spawned %d terrain objects in %d ms" % [count, end_time - start_time])


## Helper function to spawn miniatures in a grid
func _spawn_grid(total: int, cols: int, rows: int) -> void:
	print("=== PERFORMANCE TEST: Spawning %d miniatures ===" % total)
	var start_time = Time.get_ticks_msec()

	object_manager.clear_all_objects()

	var size_meters = table.table_size * 0.3048
	var margin = 0.03  # Smaller margin for more objects

	var usable_width = size_meters.x - (margin * 2)
	var usable_depth = size_meters.y - (margin * 2)
	var spacing_x = usable_width / (cols - 1)
	var spacing_z = usable_depth / (rows - 1)

	var start_x = -size_meters.x / 2 + margin
	var start_z = -size_meters.y / 2 + margin

	var count = 0
	for row in range(rows):
		for col in range(cols):
			if count >= total:
				break
			var pos = Vector3(
				start_x + col * spacing_x,
				0,
				start_z + row * spacing_z
			)
			object_manager.spawn_miniature(pos)
			count += 1
		if count >= total:
			break

	var end_time = Time.get_ticks_msec()
	print("Spawned %d miniatures in %d ms" % [count, end_time - start_time])
	print("=== Monitor FPS for performance test ===")


func _on_clear_all() -> void:
	object_manager.clear_all_objects()
	dice_result_label.text = ""


func _on_dice_rolled(total: int, results: Array) -> void:
	var result_text = "Dice: %s = %d" % [str(results), total]
	dice_result_label.text = result_text

	# Fade out after 5 seconds
	var tween = create_tween()
	tween.tween_interval(5.0)
	tween.tween_property(dice_result_label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func():
		dice_result_label.text = ""
		dice_result_label.modulate.a = 1.0
	)


## Display distance while dragging or measuring
func _on_distance_changed(distance_inches: float, _from_pos: Vector3, _to_pos: Vector3) -> void:
	distance_label.text = "%.1f\"" % distance_inches


## Clear distance display after measurement finishes
func _on_measurement_finished(distance_inches: float) -> void:
	distance_label.text = "%.1f\"" % distance_inches
	# Fade out after 2 seconds
	var tween = create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(distance_label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		distance_label.text = ""
		distance_label.modulate.a = 1.0
	)


## Clear distance display after drag ends
func _on_drag_ended() -> void:
	# Fade out after 1 second
	var tween = create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(distance_label, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func():
		distance_label.text = ""
		distance_label.modulate.a = 1.0
	)


## Dice Roller Plugin handlers
func _on_roll_button_pressed() -> void:
	dice_roller_control.roll()


func _on_quick_roll_button_pressed() -> void:
	dice_roller_control.quick_roll()


func _on_roller_started() -> void:
	roller_result_label.text = "Rolling..."


func _on_roller_finished(result: int) -> void:
	var per_dice = dice_roller_control.per_dice_result()
	roller_result_label.text = _format_dice_results(per_dice, result)


func _on_dice_count_changed(new_value: float) -> void:
	_update_dice_set(int(new_value))


## Update the dice set with the specified number of D6 dice
func _update_dice_set(count: int) -> void:
	var dice_set: Array[DiceDef] = []
	for i in range(count):
		var dice_def = DiceDef.new()
		dice_def.name = "D6_%d" % (i + 1)
		dice_def.color = Color.WHITE
		dice_def.shape = DiceShape.new("D6")
		dice_set.append(dice_def)

	dice_roller_control.dice_set = dice_set
	current_dice_label.text = "In box: %d D6" % count

	# Adjust roller size based on dice count
	var size_factor = sqrt(count / 6.0)
	dice_roller_control.roller_size = Vector3(
		max(12, 18 * size_factor),
		15,
		max(8, 12 * size_factor)
	)


## Format dice results as "x times 6, x times 5, ..." stacked vertically
func _format_dice_results(per_dice: Dictionary, _total: int) -> String:
	# Count occurrences of each face value
	var counts = {6: 0, 5: 0, 4: 0, 3: 0, 2: 0, 1: 0}
	for dice_name in per_dice:
		var value = per_dice[dice_name]
		if value in counts:
			counts[value] += 1

	# Build result string (no total, just face counts)
	var lines: Array[String] = []
	for face in [6, 5, 4, 3, 2, 1]:
		if counts[face] > 0:
			lines.append("%d× %d" % [counts[face], face])

	return "\n".join(lines)


func _get_random_table_position() -> Vector3:
	# Table size is in feet, convert to meters for positioning
	var size_meters = table.table_size * 0.3048  # FEET_TO_METERS
	var margin = 0.15  # Stay away from edges
	var x = randf_range(-size_meters.x / 2 + margin, size_meters.x / 2 - margin)
	var z = randf_range(-size_meters.y / 2 + margin, size_meters.y / 2 - margin)
	return Vector3(x, 0, z)  # Spawn at table surface (y=0)


## Handle table size preset selection
func _on_table_size_selected(index: int) -> void:
	match index:
		0:  # 48x48 inches (4x4 feet) - square
			custom_size_container.visible = false
			_set_table_size(Vector2(4, 4))
		1:  # 72x48 inches (6x4 feet) - landscape, standard wargaming
			custom_size_container.visible = false
			_set_table_size(Vector2(6, 4))
		2:  # Custom
			custom_size_container.visible = true


## Apply custom table size
func _on_apply_custom_size() -> void:
	var width = width_input.value
	var length = length_input.value

	# Convert to feet based on selected unit
	var size_feet: Vector2
	if unit_option.selected == 0:  # Inches
		size_feet = Vector2(width * INCHES_TO_FEET, length * INCHES_TO_FEET)
	else:  # Centimeters
		size_feet = Vector2(width * CM_TO_FEET, length * CM_TO_FEET)

	_set_table_size(size_feet)


## Update input fields when unit changes
func _on_unit_changed(index: int) -> void:
	if index == 0:  # Inches
		width_input.max_value = 240.0  # 20 feet max
		length_input.max_value = 240.0
		width_input.suffix = " in"
		length_input.suffix = " in"
	else:  # Centimeters
		width_input.max_value = 600.0  # ~20 feet max
		length_input.max_value = 600.0
		width_input.suffix = " cm"
		length_input.suffix = " cm"


## Set table to specific size and clear objects
func _set_table_size(size_feet: Vector2) -> void:
	# Clear existing objects
	object_manager.clear_all_objects()
	dice_result_label.text = ""

	# Rebuild table
	table.setup_table(size_feet)

	# Adjust camera view
	_adjust_camera_for_table_size(size_feet)

	print("Table resized to %.1fx%.1f feet" % [size_feet.x, size_feet.y])


## Adjust camera zoom based on table size
func _adjust_camera_for_table_size(size_feet: Vector2) -> void:
	# Calculate appropriate zoom based on table diagonal
	var diagonal = sqrt(size_feet.x * size_feet.x + size_feet.y * size_feet.y)
	var target_zoom = diagonal * 0.4  # Scale factor for good view

	# Reset camera view with appropriate zoom
	if camera_pivot.has_method("reset_view"):
		camera_pivot.reset_view()
	camera_pivot._current_zoom = clamp(target_zoom, camera_pivot.min_zoom, camera_pivot.max_zoom)
	camera_pivot._update_camera_transform()

extends Node3D
## Main scene controller for OpenTTS
## Handles initialization and connects UI signals

@onready var object_manager: Node3D = $ObjectManager
@onready var table: StaticBody3D = $Table
@onready var camera_pivot: Node3D = $CameraPivot
@onready var dice_result_label: Label = $UI/HUD/DiceResult
@onready var spawn_miniature_btn: Button = $UI/HUD/SpawnPanel/SpawnMiniature
@onready var spawn_dice_btn: Button = $UI/HUD/SpawnPanel/SpawnDice
@onready var spawn_terrain_btn: Button = $UI/HUD/SpawnPanel/SpawnTerrain
@onready var clear_all_btn: Button = $UI/HUD/SpawnPanel/ClearAll

# Table size UI elements
@onready var table_size_option: OptionButton = $UI/HUD/TableSizePanel/TableSizeOption
@onready var custom_size_container: VBoxContainer = $UI/HUD/TableSizePanel/CustomSizeContainer
@onready var unit_option: OptionButton = $UI/HUD/TableSizePanel/CustomSizeContainer/UnitOption
@onready var width_input: SpinBox = $UI/HUD/TableSizePanel/CustomSizeContainer/WidthContainer/WidthInput
@onready var length_input: SpinBox = $UI/HUD/TableSizePanel/CustomSizeContainer/LengthContainer/LengthInput
@onready var apply_custom_btn: Button = $UI/HUD/TableSizePanel/CustomSizeContainer/ApplyCustomBtn

const INCHES_TO_FEET: float = 1.0 / 12.0
const CM_TO_FEET: float = 1.0 / 30.48


func _ready() -> void:
	print("OpenTTS Prototype v0.1 - Initializing...")

	# Connect UI buttons
	spawn_miniature_btn.pressed.connect(_on_spawn_miniature)
	spawn_dice_btn.pressed.connect(_on_spawn_dice)
	spawn_terrain_btn.pressed.connect(_on_spawn_terrain)
	clear_all_btn.pressed.connect(_on_clear_all)

	# Connect table size UI
	table_size_option.item_selected.connect(_on_table_size_selected)
	apply_custom_btn.pressed.connect(_on_apply_custom_size)
	unit_option.item_selected.connect(_on_unit_changed)

	# Connect to object manager signals
	object_manager.dice_rolled.connect(_on_dice_rolled)

	# Initialize table with default size (4x4 feet = 48x48 inches)
	table.setup_table(Vector2(4, 4))
	_adjust_camera_for_table_size(Vector2(4, 4))

	print("OpenTTS ready!")


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


func _get_random_table_position() -> Vector3:
	# Table size is in feet, convert to meters for positioning
	var size_meters = table.table_size * 0.3048  # FEET_TO_METERS
	var margin = 0.15  # Stay away from edges
	var x = randf_range(-size_meters.x / 2 + margin, size_meters.x / 2 - margin)
	var z = randf_range(-size_meters.y / 2 + margin, size_meters.y / 2 - margin)
	return Vector3(x, 0.05, z)  # Slightly above table surface


## Handle table size preset selection
func _on_table_size_selected(index: int) -> void:
	match index:
		0:  # 48x48 inches (4x4 feet)
			custom_size_container.visible = false
			_set_table_size(Vector2(4, 4))
		1:  # 48x72 inches (4x6 feet)
			custom_size_container.visible = false
			_set_table_size(Vector2(4, 6))
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

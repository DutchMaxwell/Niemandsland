extends Node3D
## Main scene controller for OpenTTS
## Handles initialization and connects UI signals

@onready var object_manager: Node3D = $ObjectManager
@onready var table: StaticBody3D = $Table
@onready var dice_result_label: Label = $UI/HUD/DiceResult
@onready var spawn_miniature_btn: Button = $UI/HUD/SpawnPanel/SpawnMiniature
@onready var spawn_dice_btn: Button = $UI/HUD/SpawnPanel/SpawnDice
@onready var spawn_terrain_btn: Button = $UI/HUD/SpawnPanel/SpawnTerrain
@onready var clear_all_btn: Button = $UI/HUD/SpawnPanel/ClearAll


func _ready() -> void:
	print("OpenTTS Prototype v0.1 - Initializing...")

	# Connect UI buttons
	spawn_miniature_btn.pressed.connect(_on_spawn_miniature)
	spawn_dice_btn.pressed.connect(_on_spawn_dice)
	spawn_terrain_btn.pressed.connect(_on_spawn_terrain)
	clear_all_btn.pressed.connect(_on_clear_all)

	# Connect to object manager signals
	object_manager.dice_rolled.connect(_on_dice_rolled)

	# Initialize table
	table.setup_table(Vector2(4, 4))  # 4x4 feet table (scaled to meters)

	print("OpenTTS ready!")


func _on_spawn_miniature() -> void:
	var spawn_pos = _get_random_table_position()
	object_manager.spawn_miniature(spawn_pos)


func _on_spawn_dice() -> void:
	var spawn_pos = _get_random_table_position()
	spawn_pos.y = 2.0  # Drop from height
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
	var table_size = table.table_size
	var x = randf_range(-table_size.x / 2 + 0.3, table_size.x / 2 - 0.3)
	var z = randf_range(-table_size.y / 2 + 0.3, table_size.y / 2 - 0.3)
	return Vector3(x, 0.1, z)

extends Node
class_name OPRArmyManager
## Manages OPR armies, players, and spawned unit models
## Handles the relationship between game units and their visual representations

signal army_spawned(army: OPRApiClient.OPRArmy, models: Array[Node3D])
# Reserved for future hover functionality
#signal unit_hovered(unit: OPRApiClient.OPRUnit)
#signal unit_unhovered()

## Player colors for army identification
const PLAYER_COLORS = {
	1: Color(0.2, 0.4, 0.8),   # Blue
	2: Color(0.8, 0.2, 0.2),   # Red
	3: Color(0.2, 0.7, 0.2),   # Green
	4: Color(0.7, 0.5, 0.1),   # Orange/Gold
}

## Tray positions relative to table (player_id -> side)
## Player 1: left, Player 2: right, Player 3: front, Player 4: back
const TRAY_SIDES = {
	1: "left",
	2: "right",
	3: "front",
	4: "back",
}

const FEET_TO_METERS: float = 0.3048
const INCHES_TO_METERS: float = 0.0254
const TRAY_SIZE_INCHES: float = 32.0  # 32x32 inch tray
const TRAY_MARGIN: float = 0.05  # 5cm gap from table edge
const TRAY_DROP_HEIGHT: float = 0.5  # Start 50cm above table
const TRAY_DROP_DURATION: float = 1.5  # Animation duration in seconds

## Reference to the object manager for spawning
var object_manager: Node3D

## Reference to the table for positioning
var table: Node3D

## Loaded armies by player
var armies: Dictionary = {}  # player_id -> OPRArmy

## Mapping from spawned model to unit data
var model_to_unit: Dictionary = {}  # Node3D -> OPRUnit

## Mapping from unit to spawned models
var unit_to_models: Dictionary = {}  # OPRUnit -> Array[Node3D]

## Mapping from OPRUnit to GameUnit wrapper
var unit_to_game_unit: Dictionary = {}  # OPRUnit -> GameUnit

## All GameUnits by unit_id
var game_units: Dictionary = {}  # unit_id (String) -> GameUnit

## Army trays by player
var army_trays: Dictionary = {}  # player_id -> Node3D

## OPR API Client
var api_client: OPRApiClient

## Model registry: faction_folder -> Array of {name: String, path: String}
## This is loaded at startup to work around DirAccess not working in exports
var model_registry: Dictionary = {}


func _ready() -> void:
	api_client = OPRApiClient.new()
	add_child(api_client)
	api_client.army_loaded.connect(_on_army_loaded)
	api_client.import_failed.connect(_on_import_failed)
	_load_model_registry()


## Import army from file for a specific player
func import_army_for_player(file_path: String, player_id: int) -> void:
	var army = await api_client.import_from_file(file_path)
	if army:
		army.player_id = player_id
		armies[player_id] = army


## Spawn all units of an army on an army tray beside the table
func spawn_army(army: OPRApiClient.OPRArmy, _start_position: Vector3 = Vector3.ZERO) -> Array[Node3D]:
	if not object_manager:
		push_error("OPRArmyManager: No object_manager set")
		return []

	var all_models: Array[Node3D] = []
	var player_color = PLAYER_COLORS.get(army.player_id, Color.GRAY)

	# Create army tray and get spawn position (starts elevated)
	var tray = _create_army_tray(army.player_id, army.name, player_color)
	var tray_info = _get_tray_position_and_bounds(army.player_id)
	var tray_pos = tray_info.position
	var tray_bounds = tray_info.bounds  # Vector2 (width, depth)

	# Default spacing values - will be adjusted per unit based on base size
	var _default_base_diameter = 0.032  # 32mm default
	var unit_gap = 0.08  # 8cm gap between different units
	var row_height = 0.10  # 10cm between rows for clear separation
	var edge_padding = 0.06  # Padding from tray edge

	# Start position on tray (at elevated height)
	var spawn_height = TRAY_DROP_HEIGHT
	var current_pos = Vector3(
		tray_pos.x - tray_bounds.x / 2 + edge_padding,
		spawn_height,
		tray_pos.z - tray_bounds.y / 2 + edge_padding
	)
	var row_max_x = tray_pos.x + tray_bounds.x / 2 - edge_padding

	# Track unit counts for naming duplicates
	var unit_name_counts: Dictionary = {}
	var unit_name_indices: Dictionary = {}

	# First pass: count units by name
	for unit in army.units:
		var base_name = unit.name
		unit_name_counts[base_name] = unit_name_counts.get(base_name, 0) + 1

	# Second pass: spawn with indices
	for unit in army.units:
		var base_name = unit.name
		var unit_index = unit_name_indices.get(base_name, 0) + 1
		unit_name_indices[base_name] = unit_index

		# Only add index suffix if there are multiple units with same name
		var display_suffix = ""
		if unit_name_counts[base_name] > 1:
			display_suffix = " (%d)" % unit_index

		# Use unit's actual base size for spacing calculations
		var unit_base_diameter = unit.get_base_diameter_meters()
		var edge_gap = 0.008  # 8mm constant gap between base edges
		var model_spacing = unit_base_diameter + edge_gap  # diameter + constant edge gap

		# Calculate unit width before spawning to check if we need a new row
		var unit_width = unit_base_diameter + (unit.size - 1) * model_spacing

		# Check if this unit would exceed row width - if so, start new row first
		if current_pos.x + unit_width > row_max_x and current_pos.x > tray_pos.x - tray_bounds.x / 2 + edge_padding + 0.01:
			current_pos.x = tray_pos.x - tray_bounds.x / 2 + edge_padding
			current_pos.z += row_height

		var unit_models = _spawn_unit(unit, current_pos, player_color, display_suffix, army.player_id, army)
		all_models.append_array(unit_models)

		# Store mappings
		unit_to_models[unit] = unit_models
		for model in unit_models:
			model_to_unit[model] = unit
			model.set_meta("unit_suffix", display_suffix)

		# Move to next position with gap between units
		current_pos.x += unit_width + unit_gap

	# Animate tray and models dropping down
	_animate_tray_drop(tray, all_models, spawn_height)

	print("OPRArmyManager: Spawned %d models for army '%s' on tray" % [all_models.size(), army.name])
	army_spawned.emit(army, all_models)
	return all_models


## Animate tray and models dropping from above - smooth deceleration
func _animate_tray_drop(tray: Node3D, models: Array[Node3D], start_height: float) -> void:
	# Position tray at elevated height
	tray.position.y = start_height

	# Create tween for smooth drop animation (fast start, gradual slowdown)
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)  # Smooth deceleration, no bounce

	# Animate tray dropping
	tween.tween_property(tray, "position:y", 0.0, TRAY_DROP_DURATION)

	# Animate all models dropping together
	for model in models:
		var model_tween = create_tween()
		model_tween.set_ease(Tween.EASE_OUT)
		model_tween.set_trans(Tween.TRANS_CUBIC)  # Smooth deceleration, no bounce
		var target_y = 0.0
		model_tween.tween_property(model, "global_position:y", target_y, TRAY_DROP_DURATION)
		# Ensure final position is exactly at table surface
		model_tween.tween_callback(func(): model.global_position.y = 0.0)


## Create an army tray beside the table for a player
func _create_army_tray(player_id: int, army_name: String, player_color: Color) -> Node3D:
	# Remove existing tray for this player
	if army_trays.has(player_id) and is_instance_valid(army_trays[player_id]):
		army_trays[player_id].queue_free()

	var tray_info = _get_tray_position_and_bounds(player_id)
	var tray_pos = tray_info.position
	var tray_size = tray_info.bounds

	# Create tray container
	var tray = StaticBody3D.new()
	tray.name = "ArmyTray_Player%d" % player_id

	# Tray surface (slightly raised platform)
	var tray_mesh = BoxMesh.new()
	tray_mesh.size = Vector3(tray_size.x, 0.01, tray_size.y)

	var tray_instance = MeshInstance3D.new()
	tray_instance.mesh = tray_mesh
	tray_instance.position.y = -0.005

	var tray_material = StandardMaterial3D.new()
	tray_material.albedo_color = player_color.darkened(0.6)
	tray_material.roughness = 0.8
	tray_instance.material_override = tray_material

	tray.add_child(tray_instance)

	# Tray border
	var border_color = player_color.darkened(0.3)
	_add_tray_border(tray, tray_size, border_color)

	# Army name label (as 3D text or just metadata for now)
	tray.set_meta("army_name", army_name)
	tray.set_meta("player_id", player_id)

	# Collision for tray surface
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(tray_size.x, 0.02, tray_size.y)
	collision.shape = shape
	collision.position.y = -0.01
	tray.add_child(collision)

	# Add to scene tree BEFORE setting global_position
	object_manager.get_parent().add_child(tray)
	tray.global_position = tray_pos

	army_trays[player_id] = tray
	return tray


## Add border around tray
func _add_tray_border(tray: Node3D, tray_size: Vector2, border_color: Color) -> void:
	var border_height = 0.02
	var border_width = 0.01

	var border_material = StandardMaterial3D.new()
	border_material.albedo_color = border_color
	border_material.roughness = 0.7

	# Four sides
	var positions = [
		Vector3(0, border_height / 2, -tray_size.y / 2),  # Front
		Vector3(0, border_height / 2, tray_size.y / 2),   # Back
		Vector3(-tray_size.x / 2, border_height / 2, 0),  # Left
		Vector3(tray_size.x / 2, border_height / 2, 0),   # Right
	]

	var sizes = [
		Vector3(tray_size.x, border_height, border_width),
		Vector3(tray_size.x, border_height, border_width),
		Vector3(border_width, border_height, tray_size.y),
		Vector3(border_width, border_height, tray_size.y),
	]

	for i in range(4):
		var border_mesh = BoxMesh.new()
		border_mesh.size = sizes[i]

		var border_instance = MeshInstance3D.new()
		border_instance.mesh = border_mesh
		border_instance.material_override = border_material
		border_instance.position = positions[i]
		tray.add_child(border_instance)


## Get tray position and bounds based on player ID and table size
func _get_tray_position_and_bounds(player_id: int) -> Dictionary:
	# Get table size (default 4x4 feet)
	var table_size_feet = Vector2(4, 4)
	if table and table.get("table_size"):
		table_size_feet = table.table_size

	var table_size_m = table_size_feet * FEET_TO_METERS

	# Fixed tray size: 32x32 inches
	var tray_size_m = TRAY_SIZE_INCHES * INCHES_TO_METERS  # ~0.81m

	var pos = Vector3.ZERO
	var bounds = Vector2(tray_size_m, tray_size_m)  # Square tray

	var side = TRAY_SIDES.get(player_id, "left")

	match side:
		"left":
			pos.x = -table_size_m.x / 2 - TRAY_MARGIN - tray_size_m / 2
			pos.z = 0
		"right":
			pos.x = table_size_m.x / 2 + TRAY_MARGIN + tray_size_m / 2
			pos.z = 0
		"front":
			pos.x = 0
			pos.z = -table_size_m.y / 2 - TRAY_MARGIN - tray_size_m / 2
		"back":
			pos.x = 0
			pos.z = table_size_m.y / 2 + TRAY_MARGIN + tray_size_m / 2

	return {"position": pos, "bounds": bounds}


## Spawn a single unit with all its models
func _spawn_unit(unit: OPRApiClient.OPRUnit, spawn_pos: Vector3, player_color: Color, name_suffix: String = "", player_id: int = 1, army: OPRApiClient.OPRArmy = null) -> Array[Node3D]:
	var models: Array[Node3D] = []
	# Use unit's base diameter + constant edge gap for spacing (prevents overlap)
	var edge_gap = 0.008  # 8mm constant gap between base edges
	var spacing = unit.get_base_diameter_meters() + edge_gap

	# Get faction folder for GLB model lookup
	var faction_folder = army.faction_folder if army else ""

	for i in range(unit.size):
		var model_pos = Vector3(
			spawn_pos.x + i * spacing,
			spawn_pos.y,  # Preserve Y position for animation
			spawn_pos.z
		)

		var model = _create_unit_model(unit, player_color, name_suffix, faction_folder)
		if model:
			# Assign network_id for multiplayer position sync
			object_manager._object_counter += 1
			model.set_meta("network_id", object_manager._object_counter)

			object_manager.add_child(model)
			model.global_position = model_pos

			# Add to groups
			model.add_to_group("selectable")
			model.add_to_group("miniature")  # Required for measurement
			model.add_to_group("opr_unit")
			model.add_to_group("unit")

			# Store unit reference in model metadata (legacy)
			model.set_meta("opr_unit", unit)
			model.set_meta("opr_player_id", player_id)

			models.append(model)

	# NEW: Create GameUnit wrapper with ModelInstances
	if not models.is_empty():
		var typed_models: Array[Node3D] = []
		typed_models.assign(models)
		var game_unit = EquipmentDistributor.create_from_opr_unit(unit, typed_models, player_id)

		# Store mappings
		unit_to_game_unit[unit] = game_unit
		game_units[game_unit.unit_id] = game_unit

		# Store name suffix and faction folder on GameUnit (needed for save/load)
		game_unit.unit_properties["display_suffix"] = name_suffix
		game_unit.unit_properties["faction_folder"] = faction_folder

		# Store import positions on ModelInstances (for Sort Table reset)
		for i in range(game_unit.models.size()):
			var model_instance = game_unit.models[i]
			if model_instance and model_instance.node and is_instance_valid(model_instance.node):
				model_instance.import_position = model_instance.node.global_position
				model_instance.import_rotation = model_instance.node.rotation

	return models


## Create a visual model for a unit (GLB model if available, otherwise placeholder)
func _create_unit_model(unit: OPRApiClient.OPRUnit, player_color: Color, name_suffix: String = "", faction_folder: String = "") -> StaticBody3D:
	var wrapper = StaticBody3D.new()
	var display_name = unit.name + name_suffix
	wrapper.name = "OPR_%s" % display_name.replace(" ", "_")

	# Get base dimensions from Army Forge
	var base_is_oval = unit.base_is_oval
	var base_width = unit.base_width_mm * 0.001  # mm to meters (perpendicular to facing)
	var base_depth = unit.base_depth_mm * 0.001  # mm to meters (in facing direction / "north")
	var base_radius = unit.get_base_radius_meters()  # For body scaling

	# Create base mesh
	var base_instance = MeshInstance3D.new()

	if base_is_oval:
		# Oval base: use cylinder with non-uniform scale
		# Long side (depth) faces north (+Z direction)
		var base_mesh = CylinderMesh.new()
		base_mesh.top_radius = 0.5  # Unit radius, will be scaled
		base_mesh.bottom_radius = 0.5
		base_mesh.height = 0.003
		base_instance.mesh = base_mesh
		# Scale: X = width, Y = height (unchanged), Z = depth
		base_instance.scale = Vector3(base_width, 1.0, base_depth)
		base_instance.position.y = 0.0015
	else:
		# Round base: normal cylinder
		var base_mesh = CylinderMesh.new()
		base_mesh.top_radius = base_radius
		base_mesh.bottom_radius = base_radius
		base_mesh.height = 0.003
		base_instance.mesh = base_mesh
		base_instance.position.y = 0.0015

	var base_material = StandardMaterial3D.new()
	base_material.albedo_color = player_color
	base_material.roughness = 0.7
	base_instance.material_override = base_material
	base_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	wrapper.add_child(base_instance)

	# Try to load GLB model for this unit
	var model_path = _find_model_for_unit(unit.name, faction_folder)
	var model_height: float = 0.032  # Default 32mm height for collision calculation
	var use_glb_model = false

	if not model_path.is_empty():
		# Load GLB model — use CACHE_MODE_REUSE so host and client share cached resources
		var glb_scene = ResourceLoader.load(model_path, "", ResourceLoader.CACHE_MODE_REUSE)
		if glb_scene:
			var glb_instance = glb_scene.instantiate()

			# 1. Get raw model height from AABB
			var aabb = _get_model_aabb(glb_instance)
			var raw_height = aabb.size.y

			# 2. Target height based on base size (in meters)
			# 25mm base → 28mm, 32mm+ base → same as base
			var base_mm = unit.base_size_round
			var target_height_mm = base_mm + 3 if base_mm <= 25 else base_mm
			var target_height_m = target_height_mm * 0.001

			# 3. Scale to match target height
			var base_scale = target_height_m / raw_height if raw_height > 0 else 0.001

			# 4. Apply Tough scaling: 1.3^(tough/3)
			var tough = _get_tough_value(unit)
			var tough_scale = _calculate_model_scale(tough)
			var final_scale = base_scale * tough_scale

			glb_instance.scale = Vector3(final_scale, final_scale, final_scale)

			# 5. Position model so feet are on base
			var bottom_offset = -aabb.position.y * final_scale
			glb_instance.position.y = bottom_offset + 0.003

			_brighten_trellis_materials(glb_instance)
			wrapper.add_child(glb_instance)
			use_glb_model = true
			model_height = raw_height * final_scale

			print("OPRArmyManager: GLB '%s' base:%dmm target:%dmm tough:%d scale:%.4f" % [
				unit.name, base_mm, target_height_mm, tough, final_scale])

	# Fallback: Create placeholder body if no GLB model found
	if not use_glb_model:
		# Create placeholder body (cylinder) - moderately scaled to base size
		# Use sqrt for gentler scaling: 60mm base gets ~1.37x height, not 1.875x
		var scale_factor = sqrt(base_radius / 0.016)  # Gentler scaling
		var body_height = (0.025 + randf() * 0.005) * scale_factor
		var body_mesh = CylinderMesh.new()
		# Body width relative to base - slightly narrower for larger bases
		var body_width_ratio = lerp(0.5, 0.35, clampf((base_radius - 0.016) / 0.03, 0.0, 1.0))
		body_mesh.top_radius = base_radius * body_width_ratio
		body_mesh.bottom_radius = base_radius * (body_width_ratio + 0.1)
		body_mesh.height = body_height

		var body_instance = MeshInstance3D.new()
		body_instance.mesh = body_mesh
		body_instance.position.y = 0.003 + body_height / 2

		var body_material = StandardMaterial3D.new()
		body_material.albedo_color = player_color.lightened(0.3)
		body_material.roughness = 0.8
		body_instance.material_override = body_material
		body_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		wrapper.add_child(body_instance)

		# Create head (sphere) - scaled to base size
		var head_radius = base_radius * 0.375
		var head_mesh = SphereMesh.new()
		head_mesh.radius = head_radius
		head_mesh.height = head_radius * 2

		var head_instance = MeshInstance3D.new()
		head_instance.mesh = head_mesh
		head_instance.position.y = 0.003 + body_height + head_radius

		var head_material = StandardMaterial3D.new()
		head_material.albedo_color = Color(0.9, 0.75, 0.6)  # Skin tone
		head_material.roughness = 0.9
		head_instance.material_override = head_material
		head_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		wrapper.add_child(head_instance)

		model_height = body_height + head_radius * 2

	# Add collision shape - scaled to base size (use larger dimension for oval)
	var collision_radius = max(base_width, base_depth) / 2.0 if base_is_oval else base_radius
	var total_height = 0.003 + model_height
	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = collision_radius
	shape.height = total_height
	collision.shape = shape
	collision.position.y = total_height / 2
	wrapper.add_child(collision)

	# Add script for selection
	wrapper.set_script(load("res://scripts/selectable_object.gd"))

	return wrapper


## Create a visual model from saved unit_properties dictionary (for save/load)
## Uses the same visual logic as _create_unit_model() but reads from Dictionary instead of OPRUnit
func create_model_from_properties(props: Dictionary) -> StaticBody3D:
	var wrapper = StaticBody3D.new()
	var unit_name = props.get("name", "Unknown")
	var display_suffix = props.get("display_suffix", "")
	var display_name = unit_name + display_suffix
	wrapper.name = "OPR_%s" % display_name.replace(" ", "_")

	# Get base dimensions from saved properties
	var base_is_oval: bool = props.get("base_is_oval", false)
	var base_width: float = props.get("base_width_mm", 32) * 0.001
	var base_depth: float = props.get("base_depth_mm", 32) * 0.001
	var base_size_round: int = props.get("base_size_round", 32)
	var base_radius: float = (base_size_round / 2.0) * 0.001

	# Get player color
	var player_id: int = props.get("player_id", 1)
	var player_color: Color = PLAYER_COLORS.get(player_id, Color.GRAY)

	# Create base mesh
	var base_instance = MeshInstance3D.new()

	if base_is_oval:
		var base_mesh = CylinderMesh.new()
		base_mesh.top_radius = 0.5
		base_mesh.bottom_radius = 0.5
		base_mesh.height = 0.003
		base_instance.mesh = base_mesh
		base_instance.scale = Vector3(base_width, 1.0, base_depth)
		base_instance.position.y = 0.0015
	else:
		var base_mesh = CylinderMesh.new()
		base_mesh.top_radius = base_radius
		base_mesh.bottom_radius = base_radius
		base_mesh.height = 0.003
		base_instance.mesh = base_mesh
		base_instance.position.y = 0.0015

	var base_material = StandardMaterial3D.new()
	base_material.albedo_color = player_color
	base_material.roughness = 0.7
	base_instance.material_override = base_material
	base_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	wrapper.add_child(base_instance)

	# Try to load GLB model for this unit
	var faction_folder: String = props.get("faction_folder", "")
	var model_path = _find_model_for_unit(unit_name, faction_folder)
	var model_height: float = 0.032

	var use_glb_model = false
	if not model_path.is_empty():
		# Use CACHE_MODE_REUSE so host and client share cached resources
		var glb_scene = ResourceLoader.load(model_path, "", ResourceLoader.CACHE_MODE_REUSE)
		if glb_scene:
			var glb_instance = glb_scene.instantiate()

			var aabb = _get_model_aabb(glb_instance)
			var raw_height = aabb.size.y

			var base_mm = base_size_round
			var target_height_mm = base_mm + 3 if base_mm <= 25 else base_mm
			var target_height_m = target_height_mm * 0.001

			var base_scale_val = target_height_m / raw_height if raw_height > 0 else 0.001

			var tough = _get_tough_value_from_rules(props.get("special_rules", []))
			var tough_scale = _calculate_model_scale(tough)
			var final_scale = base_scale_val * tough_scale

			glb_instance.scale = Vector3(final_scale, final_scale, final_scale)

			var bottom_offset = -aabb.position.y * final_scale
			glb_instance.position.y = bottom_offset + 0.003

			_brighten_trellis_materials(glb_instance)
			wrapper.add_child(glb_instance)
			use_glb_model = true
			model_height = raw_height * final_scale

	# Fallback: Create placeholder body if no GLB model found
	if not use_glb_model:
		var scale_factor = sqrt(base_radius / 0.016)
		var body_height = (0.025 + randf() * 0.005) * scale_factor
		var body_mesh = CylinderMesh.new()
		var body_width_ratio = lerp(0.5, 0.35, clampf((base_radius - 0.016) / 0.03, 0.0, 1.0))
		body_mesh.top_radius = base_radius * body_width_ratio
		body_mesh.bottom_radius = base_radius * (body_width_ratio + 0.1)
		body_mesh.height = body_height

		var body_instance = MeshInstance3D.new()
		body_instance.mesh = body_mesh
		body_instance.position.y = 0.003 + body_height / 2

		var body_material = StandardMaterial3D.new()
		body_material.albedo_color = player_color.lightened(0.3)
		body_material.roughness = 0.8
		body_instance.material_override = body_material
		body_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		wrapper.add_child(body_instance)

		var head_radius = base_radius * 0.375
		var head_mesh = SphereMesh.new()
		head_mesh.radius = head_radius
		head_mesh.height = head_radius * 2

		var head_instance = MeshInstance3D.new()
		head_instance.mesh = head_mesh
		head_instance.position.y = 0.003 + body_height + head_radius

		var head_material = StandardMaterial3D.new()
		head_material.albedo_color = Color(0.9, 0.75, 0.6)
		head_material.roughness = 0.9
		head_instance.material_override = head_material
		head_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		wrapper.add_child(head_instance)

		model_height = body_height + head_radius * 2

	# Add collision shape
	var collision_radius = max(base_width, base_depth) / 2.0 if base_is_oval else base_radius
	var total_height = 0.003 + model_height
	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = collision_radius
	shape.height = total_height
	collision.shape = shape
	collision.position.y = total_height / 2
	wrapper.add_child(collision)

	# Add script for selection and groups
	wrapper.set_script(load("res://scripts/selectable_object.gd"))
	wrapper.add_to_group("selectable")
	wrapper.add_to_group("miniature")
	wrapper.add_to_group("opr_unit")
	wrapper.add_to_group("unit")

	return wrapper


## Extract Tough value from a special_rules array (for save/load)
func _get_tough_value_from_rules(rules: Array) -> int:
	for rule in rules:
		var rule_str = ""
		if rule is String:
			rule_str = rule
		elif rule is Dictionary:
			rule_str = rule.get("name", "")
		if rule_str.begins_with("Tough("):
			var value_str = rule_str.trim_prefix("Tough(").trim_suffix(")")
			if value_str.is_valid_int():
				return value_str.to_int()
	return 0


## Get unit data for a model
func get_unit_for_model(model: Node3D) -> OPRApiClient.OPRUnit:
	return model_to_unit.get(model, null)


## Get all models for a unit
func get_models_for_unit(unit: OPRApiClient.OPRUnit) -> Array:
	return unit_to_models.get(unit, [])


## Get army for a player
func get_army(player_id: int) -> OPRApiClient.OPRArmy:
	return armies.get(player_id, null)


# ===== NEW: GameUnit Access Methods =====

## Get GameUnit wrapper for a model
func get_game_unit_for_model(model: Node3D) -> GameUnit:
	return model.get_meta("game_unit", null)


## Get ModelInstance for a model node
func get_model_instance(model: Node3D) -> ModelInstance:
	return model.get_meta("model_instance", null)


## Get GameUnit for an OPRUnit
func get_game_unit(opr_unit: OPRApiClient.OPRUnit) -> GameUnit:
	return unit_to_game_unit.get(opr_unit, null)


## Get GameUnit by unit_id
func get_game_unit_by_id(unit_id: String) -> GameUnit:
	return game_units.get(unit_id, null)


## Get all GameUnits for a player
func get_game_units_for_player(player_id: int) -> Array[GameUnit]:
	var result: Array[GameUnit] = []
	for game_unit in game_units.values():
		if game_unit.unit_properties.get("player_id", 0) == player_id:
			result.append(game_unit)
	return result


## Get all GameUnits
func get_all_game_units() -> Array[GameUnit]:
	var result: Array[GameUnit] = []
	for game_unit in game_units.values():
		result.append(game_unit)
	return result


## Check if a node is a unit model
func is_unit_model(node: Node3D) -> bool:
	return node.is_in_group("unit") or node.is_in_group("opr_unit")


## Clear all armies and spawned models
func clear_all() -> void:
	# Remove all spawned models
	for unit in unit_to_models:
		var models = unit_to_models[unit]
		for model in models:
			if is_instance_valid(model):
				model.queue_free()

	# Remove all army trays
	for player_id in army_trays:
		if is_instance_valid(army_trays[player_id]):
			army_trays[player_id].queue_free()

	armies.clear()
	model_to_unit.clear()
	unit_to_models.clear()
	unit_to_game_unit.clear()
	game_units.clear()
	army_trays.clear()


## Clear army for a specific player
func clear_army(player_id: int) -> void:
	var army = armies.get(player_id)
	if not army:
		return

	for unit in army.units:
		# Clear GameUnit mappings
		if unit in unit_to_game_unit:
			var game_unit = unit_to_game_unit[unit]
			game_units.erase(game_unit.unit_id)
			unit_to_game_unit.erase(unit)

		if unit in unit_to_models:
			var models = unit_to_models[unit]
			for model in models:
				if is_instance_valid(model):
					model.queue_free()
				model_to_unit.erase(model)
			unit_to_models.erase(unit)

	# Remove army tray for this player
	if army_trays.has(player_id) and is_instance_valid(army_trays[player_id]):
		army_trays[player_id].queue_free()
		army_trays.erase(player_id)

	armies.erase(player_id)


# ===== GLB Model Loading Functions =====

## Load the model registry from units.json files in each faction folder
## This is necessary because DirAccess does not work with res:// paths in exported builds
func _load_model_registry() -> void:
	# List of known faction folders with GLB models
	var faction_folders = ["alien_hives"]

	for folder in faction_folders:
		var units_json_path = "res://assets/miniatures/%s/units.json" % folder
		var glb_base_path = "res://assets/miniatures/%s/glb/" % folder

		if not ResourceLoader.exists(units_json_path):
			print("OPRArmyManager: units.json not found for faction: %s" % folder)
			continue

		# Load and parse units.json
		var file = FileAccess.open(units_json_path, FileAccess.READ)
		if not file:
			print("OPRArmyManager: Could not open units.json for faction: %s" % folder)
			continue

		var json_text = file.get_as_text()
		file.close()

		var json = JSON.new()
		var parse_result = json.parse(json_text)
		if parse_result != OK:
			print("OPRArmyManager: Failed to parse units.json for faction: %s" % folder)
			continue

		var data = json.data
		if not data.has("units"):
			continue

		var models: Array = []
		var units_dict = data.get("units", {})

		# For each unit, try to find matching GLB file using numbered prefixes
		for unit_key in units_dict.keys():
			var unit_data = units_dict[unit_key]
			var unit_name = unit_data.get("name", unit_key)

			# Try numbered prefixes 01-99
			for i in range(1, 100):
				var prefix = "%02d" % i
				var glb_filename = "%s_%s.glb" % [prefix, unit_name]
				var full_path = glb_base_path + glb_filename

				if ResourceLoader.exists(full_path):
					models.append({"name": unit_name, "path": full_path})
					break

		model_registry[folder] = models
		print("OPRArmyManager: Loaded %d models for faction '%s'" % [models.size(), folder])


## Find the GLB model file for a unit based on faction folder and unit name
## Uses the pre-loaded model registry to work in exported builds
func _find_model_for_unit(unit_name: String, faction_folder: String) -> String:
	if faction_folder.is_empty():
		return ""

	# Check if we have models registered for this faction
	if model_registry.has(faction_folder):
		var models = model_registry[faction_folder]
		for model_entry in models:
			# Check if unit name matches (case insensitive)
			if unit_name.to_lower() in model_entry.name.to_lower():
				print("OPRArmyManager: Found model for '%s' -> %s" % [unit_name, model_entry.path])
				return model_entry.path

	# Fallback: Try direct path construction with ResourceLoader.exists()
	# This handles cases where the model might exist but isn't in the registry
	var glb_base_path = "res://assets/miniatures/%s/glb/" % faction_folder

	# Try numbered prefixes 01-99
	for i in range(1, 100):
		var prefix = "%02d" % i
		var glb_filename = "%s_%s.glb" % [prefix, unit_name]
		var full_path = glb_base_path + glb_filename

		if ResourceLoader.exists(full_path):
			print("OPRArmyManager: Found model for '%s' -> %s (fallback)" % [unit_name, full_path])
			return full_path

	# Also try without prefix (in case naming convention changes)
	var direct_path = glb_base_path + unit_name + ".glb"
	if ResourceLoader.exists(direct_path):
		print("OPRArmyManager: Found model for '%s' -> %s (direct)" % [unit_name, direct_path])
		return direct_path

	print("OPRArmyManager: No model found for '%s' in %s" % [unit_name, faction_folder])
	return ""


## Extract Tough value from unit's special rules
## Returns 0 if no Tough rule found
func _get_tough_value(unit: OPRApiClient.OPRUnit) -> int:
	return _get_tough_value_from_rules(unit.special_rules)


## Calculate model scale based on Tough value
## Formula: scale = 1.05^(tough/3)
## Tough(0)=1.0, Tough(3)=1.05, Tough(6)=1.10, Tough(12)=1.22
func _calculate_model_scale(tough: int) -> float:
	return pow(1.05, tough / 3.0)


## Calculate the combined AABB (bounding box) of a 3D model and all its children
func _get_model_aabb(node: Node3D) -> AABB:
	var combined_aabb = AABB()
	var first = true

	# Recursively collect AABBs from all MeshInstance3D children
	var nodes_to_check: Array[Node] = [node]
	while not nodes_to_check.is_empty():
		var current = nodes_to_check.pop_back()
		nodes_to_check.append_array(current.get_children())

		if current is MeshInstance3D:
			var mesh_instance = current as MeshInstance3D
			if mesh_instance.mesh:
				var mesh_aabb = mesh_instance.mesh.get_aabb()
				# Transform AABB to node's local space
				var transformed_aabb = mesh_instance.transform * mesh_aabb
				if first:
					combined_aabb = transformed_aabb
					first = false
				else:
					combined_aabb = combined_aabb.merge(transformed_aabb)

	return combined_aabb


## Adjust Trellis-generated GLB materials for better visibility
## Trellis bakes very dark textures — subtle emission + roughness fix compensates
func _brighten_trellis_materials(node: Node) -> void:
	var nodes_to_check: Array[Node] = [node]
	while not nodes_to_check.is_empty():
		var current = nodes_to_check.pop_back()
		nodes_to_check.append_array(current.get_children())

		if current is MeshInstance3D:
			var mesh_instance = current as MeshInstance3D
			if not mesh_instance.mesh:
				continue
			for surface_idx in range(mesh_instance.mesh.get_surface_count()):
				var mat = mesh_instance.mesh.surface_get_material(surface_idx)
				if mat is StandardMaterial3D:
					var adjusted_mat = mat.duplicate() as StandardMaterial3D
					# Force non-metallic so ambient/fill light works as diffuse
					adjusted_mat.metallic = 0.0
					adjusted_mat.roughness = 0.7
					mesh_instance.mesh.surface_set_material(surface_idx, adjusted_mat)


func _on_army_loaded(army: OPRApiClient.OPRArmy) -> void:
	print("Army loaded: %s (faction: %s)" % [army.name, army.faction_name])


func _on_import_failed(error: String) -> void:
	push_error("OPR Import failed: %s" % error)

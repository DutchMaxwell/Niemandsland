extends Node
class_name OPRArmyManager
## Manages OPR armies, players, and spawned unit models
## Handles the relationship between game units and their visual representations

signal army_spawned(army: OPRApiClient.OPRArmy, models: Array[Node3D])
## Per-unit spawn progress so a loading bar can advance during the (synchronous) spawn.
signal spawn_progress(done: int, total: int)
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
## Modell-Fit relativ zur Base (gegen Scale-Creep):
## Die groesste horizontale Ausdehnung darf max. 125% der Base-Langseite betragen.
const FOOTPRINT_MAX_RATIO: float = 1.25
## Schwebehoehe fuer Flying-Units, relativ zur Base-Langseite (40mm Base → ~14mm).
const FLYING_HOVER_RATIO: float = 0.35
const TRAY_SIZE_INCHES: float = 32.0  # 32x32 inch tray
const TRAY_MARGIN: float = 0.05  # 5cm gap from table edge
const TRAY_DROP_HEIGHT: float = 0.5  # Start 50cm above table
const TRAY_DROP_DURATION: float = 1.5  # Animation duration in seconds

## Physics layers (kept in sync with ObjectManager): miniatures sit on layer 2 so the
## placement raycast (which masks ground-only) rests them on terrain, not on each other.
const GROUND_COLLISION_LAYER: int = 1
const MINIATURE_COLLISION_LAYER: int = 2

## Reference to the object manager for spawning
var object_manager: Node3D

## Reference to the table for positioning
var table: Node3D

## Loaded armies by player
var armies: Dictionary = {}  # player_id -> OPRArmy
## Session-wide special-rule name -> description, populated from save/load and from
## the multiplayer state sync. Lets loaded saves and remote-only armies (which carry no
## OPRArmy) still resolve rule descriptions, not just freshly imported armies.
var rule_descriptions: Dictionary = {}

## Mapping from spawned model to unit data
var model_to_unit: Dictionary = {}  # Node3D -> OPRUnit

## Mapping from unit to spawned models
var unit_to_models: Dictionary = {}  # OPRUnit -> Array[Node3D]

## Mapping from OPRUnit to GameUnit wrapper
var unit_to_game_unit: Dictionary = {}  # OPRUnit -> GameUnit

## All GameUnits by unit_id
var game_units: Dictionary = {}  # unit_id (String) -> GameUnit
var regiments: Dictionary = {}  # unit_id (String) -> Regiment (AoF:R movement-tray blocks)

## Whether the regiment front-arc wedges are currently shown (toggled with KEY_F). The
## facing arrows are always visible; only the wedges toggle. Display only.
var _regiment_arcs_visible: bool = false

## Current game round (OPR rounds start at 1). Bookkeeping only - the players
## decide when a round ends; advance_round() does the standard transition.
var current_round: int = 1

## Army trays by player
var army_trays: Dictionary = {}  # player_id -> Node3D

## OPR API Client
var api_client: OPRApiClient

## On-demand model delivery (manifest + CDN cache); see docs/ASSET_DELIVERY.md
var model_library: ModelLibrary

## Parsed-model cache: model path -> PackedScene. Runtime glTF models (user://) are
## otherwise re-parsed on every spawn, so a unit of N identical models paid N full
## glTF parses; cached, each distinct model is parsed once and instanced cheaply.
var _scene_cache: Dictionary = {}

func _ready() -> void:
	api_client = OPRApiClient.new()
	add_child(api_client)
	api_client.army_loaded.connect(_on_army_loaded)
	api_client.import_failed.connect(_on_import_failed)

	model_library = ModelLibrary.new()
	model_library.name = "ModelLibrary"
	add_child(model_library)


## Import army from file for a specific player
func import_army_for_player(file_path: String, player_id: int) -> void:
	var army = await api_client.import_from_file(file_path)
	if army:
		army.player_id = player_id
		armies[player_id] = army


## Spawn all units of an army on an army tray beside the table.
## Awaitable: any on-demand models the army needs are downloaded up front.
func spawn_army(army: OPRApiClient.OPRArmy, _start_position: Vector3 = Vector3.ZERO) -> Array[Node3D]:
	if not object_manager:
		push_error("OPRArmyManager: No object_manager set")
		return []

	# Fetch on-demand models this army needs (no-op when the manifest is empty or
	# everything is cached); the spawn loop below then resolves them locally.
	await _ensure_army_models_cached(army)

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

	# Order units so each joined Hero spawns right after its host unit (adjacent
	# on the tray), instead of as a separate group elsewhere.
	var ordered_units := _order_units_heroes_after_host(army.units)

	# Second pass: spawn with indices
	var total_units := ordered_units.size()
	var spawned_units := 0
	for unit in ordered_units:
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

		# Report progress and yield so the loading bar animates instead of the whole
		# spawn blocking the main thread in one frozen frame.
		spawned_units += 1
		spawn_progress.emit(spawned_units, total_units)
		await get_tree().process_frame

	# Animate tray and models dropping down
	_animate_tray_drop(tray, all_models, spawn_height)

	# Wire up joined Heroes (OPR: a Hero "joined to" a unit belongs to it).
	_attach_joined_heroes(army)

	print("OPRArmyManager: Spawned %d models for army '%s' on tray" % [all_models.size(), army.name])
	army_spawned.emit(army, all_models)

	# Age of Fantasy: Regiments — form each unit into a movement-tray block once the
	# drop animation has settled (deferred so it does not fight the drop tween).
	if army.game_system_abbrev == "aofr":
		_form_regiments_after_drop(army)

	return all_models


## Form a single Age of Fantasy: Regiments unit into a movement-tray block. Collects
## the unit's live model nodes, creates a RegimentTray under ObjectManager and ranks
## them. Returns the Regiment, or null if the unit is not a regiment / has no models.
## Representation only — no rules are enforced.
func form_regiment(game_unit) -> Regiment:
	if game_unit == null:
		return null
	var props: Dictionary = game_unit.unit_properties
	if not props.get("regiment_mode", false):
		return null
	var members := RegimentTray.collect_members(game_unit)
	var nodes: Array = members.nodes
	var footprints: Array = members.footprints
	if nodes.is_empty():
		return null

	var tray := RegimentTray.new()
	tray.name = "Regiment_%s" % game_unit.unit_id
	object_manager._object_counter += 1
	tray.set_meta("network_id", object_manager._object_counter)
	object_manager.add_child(tray)

	var frontage: int = RegimentFormation.default_frontage(nodes.size())
	tray.form(nodes, footprints, frontage)

	var regiment := Regiment.new(game_unit, tray, frontage)
	tray.set_meta("regiment", regiment)
	game_unit.unit_properties["frontage"] = frontage
	regiments[game_unit.unit_id] = regiment
	return regiment


## Rebuild a regiment movement-tray block on load: create the tray at the saved
## transform and adopt the unit's already-restored model nodes (no re-layout — the
## exact saved arrangement, including casualty gaps, is preserved).
func restore_regiment(game_unit, frontage: int, pos: Vector3, rot_y: float) -> Regiment:
	if game_unit == null:
		return null
	var tray := RegimentTray.new()
	tray.name = "Regiment_%s" % game_unit.unit_id
	object_manager._object_counter += 1
	tray.set_meta("network_id", object_manager._object_counter)
	object_manager.add_child(tray)
	tray.frontage = maxi(frontage, 1)
	tray.global_position = pos
	tray.rotation.y = rot_y

	var nodes: Array = []
	for m in game_unit.models:
		if m.node and is_instance_valid(m.node):
			nodes.append(m.node)
	tray.adopt_existing(nodes)

	var regiment := Regiment.new(game_unit, tray, tray.frontage)
	tray.set_meta("regiment", regiment)
	game_unit.unit_properties["frontage"] = tray.frontage
	regiments[game_unit.unit_id] = regiment
	return regiment


## Toggle the front-arc wedges on every regiment block (display only). Returns the new
## visibility state; the facing arrows stay visible regardless.
func toggle_all_regiment_arcs() -> bool:
	_regiment_arcs_visible = not _regiment_arcs_visible
	set_all_regiment_arcs_visible(_regiment_arcs_visible)
	return _regiment_arcs_visible


## Show or hide the front-arc wedge on every regiment block.
func set_all_regiment_arcs_visible(p_visible: bool) -> void:
	_regiment_arcs_visible = p_visible
	for unit_id in regiments:
		var regiment = regiments[unit_id]
		if regiment and is_instance_valid(regiment.tray):
			regiment.tray.set_arc_visible(p_visible)


## Form every regiment-mode unit of an army into a movement-tray block.
func form_all_regiments(army) -> void:
	for unit in army.units:
		var gu = unit_to_game_unit.get(unit, null)
		if gu:
			form_regiment(gu)


## Defer regiment forming until the spawn drop animation has settled.
func _form_regiments_after_drop(army) -> void:
	await get_tree().create_timer(TRAY_DROP_DURATION + 0.1).timeout
	form_all_regiments(army)


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

		# Store import positions on ModelInstances (for Sort Table reset).
		# Capture the resting height (table surface, y=0), NOT the elevated
		# TRAY_DROP_HEIGHT the models currently sit at before _animate_tray_drop
		# lowers them - otherwise Sort Table would restore them in mid-air.
		for i in range(game_unit.models.size()):
			var model_instance = game_unit.models[i]
			if model_instance and model_instance.node and is_instance_valid(model_instance.node):
				var resting_pos: Vector3 = model_instance.node.global_position
				resting_pos.y = 0.0
				model_instance.import_position = resting_pos
				model_instance.import_rotation = model_instance.node.rotation

	return models


## Create a visual model for a unit (GLB model if available, otherwise placeholder)
func _create_unit_model(unit: OPRApiClient.OPRUnit, player_color: Color, name_suffix: String = "", faction_folder: String = "") -> StaticBody3D:
	var wrapper = StaticBody3D.new()
	wrapper.collision_layer = MINIATURE_COLLISION_LAYER
	wrapper.collision_mask = GROUND_COLLISION_LAYER
	var display_name = unit.name + name_suffix
	wrapper.name = "OPR_%s" % display_name.replace(" ", "_")

	# Get base dimensions from Army Forge
	var base_is_oval = unit.base_is_oval
	var base_width = unit.base_width_mm * 0.001  # mm to meters (perpendicular to facing)
	var base_depth = unit.base_depth_mm * 0.001  # mm to meters (in facing direction / "north")
	var base_radius = unit.get_base_radius_meters()  # For body scaling

	# Create base mesh
	var base_instance = MeshInstance3D.new()

	if unit.base_is_square:
		# Square/rectangular base (Age of Fantasy: Regiments): flat box.
		# Long side (depth) faces north (+Z direction), matching the oval convention.
		var base_mesh = BoxMesh.new()
		base_mesh.size = Vector3(base_width, 0.003, base_depth)
		base_instance.mesh = base_mesh
		base_instance.position.y = 0.0015
	elif base_is_oval:
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

	# Visual hover: Flying units, drones and hover vehicles float above the base.
	var should_hover := _should_hover(unit.name, unit.special_rules)
	var base_long_mm: int = max(unit.base_width_mm, unit.base_depth_mm) if (base_is_oval or unit.base_is_square) else unit.base_size_round
	var hover_lift: float = base_long_mm * FLYING_HOVER_RATIO * 0.001 if should_hover else 0.0

	# Try to load GLB model for this unit
	var model_path = _find_model_for_unit(unit.name, faction_folder)
	var model_height: float = 0.032  # Default 32mm height for collision calculation
	var use_glb_model = false

	if not model_path.is_empty():
		# Bundled res:// GLBs load via ResourceLoader; downloaded user:// GLBs via glTF.
		var glb_instance = _instantiate_model(model_path)
		if glb_instance:
			# Modell an die Base anpassen (Footprint-Cap gegen Scale-Creep, Flying schwebt)
			var aabb = _get_model_aabb(glb_instance)
			var tough = _get_tough_value(unit)
			var fit = _compute_model_fit(aabb, base_long_mm, tough, should_hover)
			var final_scale = fit.scale

			glb_instance.scale = Vector3(final_scale, final_scale, final_scale)
			glb_instance.position.y = fit.y_offset

			_brighten_trellis_materials(glb_instance)
			wrapper.add_child(glb_instance)
			use_glb_model = true
			model_height = fit.height

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
		body_instance.position.y = 0.003 + body_height / 2 + hover_lift

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
		head_instance.position.y = 0.003 + body_height + head_radius + hover_lift

		var head_material = StandardMaterial3D.new()
		head_material.albedo_color = Color(0.9, 0.75, 0.6)  # Skin tone
		head_material.roughness = 0.9
		head_instance.material_override = head_material
		head_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		wrapper.add_child(head_instance)

		model_height = body_height + head_radius * 2 + hover_lift

	# Add collision shape - scaled to base size (box for square/rectangular regiment
	# bases so they sit edge-to-edge without overlap-reject; cylinder otherwise).
	var total_height = 0.003 + model_height
	var collision = CollisionShape3D.new()
	if unit.base_is_square:
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(base_width, total_height, base_depth)
		collision.shape = box_shape
	else:
		var collision_radius = max(base_width, base_depth) / 2.0 if base_is_oval else base_radius
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
	wrapper.collision_layer = MINIATURE_COLLISION_LAYER
	wrapper.collision_mask = GROUND_COLLISION_LAYER
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

	# Visual hover: Flying units, drones and hover vehicles float above the base.
	var should_hover := _should_hover(unit_name, props.get("special_rules", []))
	var base_long_mm: int = max(int(props.get("base_width_mm", 32)), int(props.get("base_depth_mm", 32))) if base_is_oval else base_size_round
	var hover_lift: float = base_long_mm * FLYING_HOVER_RATIO * 0.001 if should_hover else 0.0

	# Try to load GLB model for this unit
	var faction_folder: String = props.get("faction_folder", "")
	var model_path = _find_model_for_unit(unit_name, faction_folder)
	var model_height: float = 0.032

	var use_glb_model = false
	if not model_path.is_empty():
		# Bundled res:// GLBs load via ResourceLoader; downloaded user:// GLBs via glTF.
		var glb_instance = _instantiate_model(model_path)
		if glb_instance:
			var aabb = _get_model_aabb(glb_instance)
			var tough = _get_tough_value_from_rules(props.get("special_rules", []))
			var fit = _compute_model_fit(aabb, base_long_mm, tough, should_hover)
			var final_scale = fit.scale

			glb_instance.scale = Vector3(final_scale, final_scale, final_scale)
			glb_instance.position.y = fit.y_offset

			_brighten_trellis_materials(glb_instance)
			wrapper.add_child(glb_instance)
			use_glb_model = true
			model_height = fit.height

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
		body_instance.position.y = 0.003 + body_height / 2 + hover_lift

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
		head_instance.position.y = 0.003 + body_height + head_radius + hover_lift

		var head_material = StandardMaterial3D.new()
		head_material.albedo_color = Color(0.9, 0.75, 0.6)
		head_material.roughness = 0.9
		head_instance.material_override = head_material
		head_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		wrapper.add_child(head_instance)

		model_height = body_height + head_radius * 2 + hover_lift

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


## Look up an OPR special-rule description. Checks the session cache first (populated
## from save/load + multiplayer sync), then the in-memory imported armies. Handles
## parameterised rules ("Tough(3)" -> "Tough"). Returns "" if unknown.
func get_rule_description(rule_name: String) -> String:
	if rule_descriptions.has(rule_name):
		return rule_descriptions[rule_name]
	var paren := rule_name.find("(")
	if paren > 0:
		var base := rule_name.substr(0, paren).strip_edges()
		if rule_descriptions.has(base):
			return rule_descriptions[base]
	for army in armies.values():
		if army == null:
			continue
		var desc := OPRApiClient.get_rule_description(rule_name, army)
		if not desc.is_empty():
			return desc
	return ""


## All known rule descriptions (imported armies + session cache), for serialization
## into a save / the multiplayer state sync.
func get_all_rule_descriptions() -> Dictionary:
	var out: Dictionary = rule_descriptions.duplicate()
	for army in armies.values():
		if army and army.rule_descriptions is Dictionary:
			for k in army.rule_descriptions:
				out[k] = army.rule_descriptions[k]
	return out


## Merge incoming rule descriptions (from a loaded save or a peer's state sync) into
## the session cache, so loaded/remote units can resolve descriptions too.
func merge_rule_descriptions(incoming: Dictionary) -> void:
	for k in incoming:
		rule_descriptions[k] = incoming[k]


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


# ===== Hero Attachment =====

## Returns the units ordered so each joined Hero comes right after its host unit
## (matched by selectionId). Heroes whose host is missing keep their place.
func _order_units_heroes_after_host(units: Array) -> Array:
	var heroes_by_host: Dictionary = {}
	for unit in units:
		if not unit.join_to_unit.is_empty():
			if not heroes_by_host.has(unit.join_to_unit):
				heroes_by_host[unit.join_to_unit] = []
			heroes_by_host[unit.join_to_unit].append(unit)

	var ordered: Array = []
	for unit in units:
		if not unit.join_to_unit.is_empty():
			continue  # placed right after its host below
		ordered.append(unit)
		if heroes_by_host.has(unit.selection_id):
			for hero in heroes_by_host[unit.selection_id]:
				ordered.append(hero)

	# Heroes whose host was not found must not be dropped - append them.
	for unit in units:
		if not unit.join_to_unit.is_empty() and unit not in ordered:
			ordered.append(unit)

	return ordered


## Attaches joined Heroes to their host units after spawning.
## OPR: a Hero unit can be "joined to" another unit (Army Forge sets the Hero's
## joinToUnit to the host's selectionId). Combined-unit halves were already merged
## away during parsing, so the remaining units carrying join_to_unit are Heroes.
func _attach_joined_heroes(army: OPRApiClient.OPRArmy) -> void:
	# Index every unit's GameUnit by its selectionId.
	var by_selection: Dictionary = {}
	for unit in army.units:
		var game_unit: GameUnit = unit_to_game_unit.get(unit)
		if game_unit and not unit.selection_id.is_empty():
			by_selection[unit.selection_id] = game_unit

	for unit in army.units:
		if unit.join_to_unit.is_empty():
			continue
		var hero_unit: GameUnit = unit_to_game_unit.get(unit)
		var host_unit: GameUnit = by_selection.get(unit.join_to_unit)
		if hero_unit and host_unit and hero_unit != host_unit:
			EquipmentDistributor.attach_hero_to_unit(hero_unit, host_unit)


# ===== Round Management =====

## Advances to the next game round (OPR round transition - pure bookkeeping):
## every unit may activate again and casters gain their per-round points (capped).
## The players, not the app, decide when to call this.
func advance_round() -> void:
	current_round += 1
	for game_unit in game_units.values():
		if game_unit:
			game_unit.reset_activation()
			game_unit.add_round_caster_points()


## Sets the current round (used by save/load restore).
func set_current_round(value: int) -> void:
	current_round = maxi(1, value)


## Clear all armies and spawned models
func clear_all() -> void:
	# Remove all spawned models. Guard against double-free: ObjectManager.
	# clear_all_objects() may have already queued these (the models are its
	# children) before delegating here.
	for unit in unit_to_models:
		var models = unit_to_models[unit]
		for model in models:
			if is_instance_valid(model) and not model.is_queued_for_deletion():
				model.queue_free()

	# Remove all army trays
	for player_id in army_trays:
		if is_instance_valid(army_trays[player_id]) and not army_trays[player_id].is_queued_for_deletion():
			army_trays[player_id].queue_free()

	armies.clear()
	model_to_unit.clear()
	unit_to_models.clear()
	unit_to_game_unit.clear()
	game_units.clear()
	army_trays.clear()
	_scene_cache.clear()  # release parsed PackedScenes; rebuilt lazily on next spawn
	current_round = 1


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

## Downloads any on-demand models the army needs (manifest + CDN) so the spawn
## loop can resolve them from the local cache. No-op without a populated manifest.
func _ensure_army_models_cached(army: OPRApiClient.OPRArmy) -> void:
	if model_library == null or army == null:
		return
	var faction_folder: String = army.faction_folder
	if faction_folder.is_empty():
		return
	var specs: Array = []
	for unit: OPRApiClient.OPRUnit in army.units:
		specs.append({"faction": faction_folder, "unit_name": unit.name})
	await model_library.ensure_models(specs)


## Instantiates a model from a local path, reusing a per-path PackedScene so each
## distinct model is parsed once. Bundled res:// GLBs load via ResourceLoader;
## downloaded user:// GLBs are parsed once via runtime glTF (GLTFDocument) and packed.
func _instantiate_model(path: String) -> Node3D:
	var packed: PackedScene = _scene_cache.get(path, null)
	if packed == null:
		packed = _load_model_scene(path)
		if packed == null:
			return null
		_scene_cache[path] = packed
	return packed.instantiate() as Node3D


## Loads a model path into a reusable PackedScene (no caching/instancing here).
func _load_model_scene(path: String) -> PackedScene:
	if path.begins_with("res://"):
		return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene

	# Runtime glTF for downloaded user:// GLBs: parse once, then pack so subsequent
	# spawns instance instead of re-parsing.
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	var scene_root := doc.generate_scene(state)
	if scene_root == null:
		return null
	# pack() only stores descendants whose owner is the packed root.
	_set_owner_recursive(scene_root, scene_root)
	var packed := PackedScene.new()
	var ok := packed.pack(scene_root)
	scene_root.free()
	return packed if ok == OK else null


func _set_owner_recursive(node: Node, scene_owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = scene_owner
		_set_owner_recursive(child, scene_owner)


## Find the GLB model for a unit. Prefers an on-demand model already cached locally
## (manifest + CDN), then falls back to a bundled GLB probed by name. OPR unit data
## (incl. names) comes exclusively from the API at runtime.
func _find_model_for_unit(unit_name: String, faction_folder: String) -> String:
	if faction_folder.is_empty():
		return ""

	# On-demand model already downloaded? (manifest-driven, content-addressed cache)
	if model_library != null:
		var cached: String = model_library.get_cached_path(faction_folder, unit_name)
		if not cached.is_empty():
			return cached

	# Probe bundled GLBs by name with ResourceLoader.exists() (works in exports).
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


## True wenn die Regeln "Flying" (oder Flying(x)) enthalten.
func _is_flying_from_rules(rules: Array) -> bool:
	for r in rules:
		if String(r).strip_edges().to_lower().begins_with("flying"):
			return true
	return false


## True if a unit should visually hover above its base: it has the Flying rule,
## or its name marks it as a drone / hover vehicle (e.g. "Gun Drones", "Hover
## Tank"). Hover is cosmetic only - in this sim Flying has no other effect since
## coherency reads the model wrapper at table level, not the rule.
func _should_hover(unit_name: String, rules: Array) -> bool:
	if _is_flying_from_rules(rules):
		return true
	var lowered := unit_name.to_lower()
	return "drone" in lowered or "hover" in lowered


## Berechnet Skalierung + vertikalen Offset, damit ein GLB gut zur Base passt.
##
## Regel gegen Scale-Creep:
##   - Hoehen-Ziel ~ Base-Groesse (Tough macht leicht hoeher) → schlanke Bipeds.
##   - Footprint-Cap: groesste horizontale Ausdehnung <= 125% der Base-Langseite
##     (bei Oval die lange Seite) → breite Fahrzeuge/Drohnen quellen nicht ueber.
##   - Der KLEINERE der beiden Faktoren gewinnt (min), so passt beides.
## Flying-Units schweben leicht ueber der Base.
## base_long_mm = Base-Langseite in mm (rund: Durchmesser; oval: laengere Achse).
## Returns { "scale": float, "y_offset": float, "height": float }.
func _compute_model_fit(aabb: AABB, base_long_mm: int, tough: int, is_flying: bool) -> Dictionary:
	var raw_height: float = aabb.size.y
	var raw_footprint: float = max(aabb.size.x, aabb.size.z)
	if raw_height <= 0.0 or raw_footprint <= 0.0:
		return {"scale": 0.001, "y_offset": 0.003, "height": 0.03}

	# Hoehen-Ziel: 25mm-Bases bekommen +3mm, sonst = Base; Tough skaliert mild mit.
	var height_target_mm: float = float(base_long_mm + 3 if base_long_mm <= 25 else base_long_mm)
	var target_height_m: float = height_target_mm * 0.001 * _calculate_model_scale(tough)
	var height_scale: float = target_height_m / raw_height

	# Footprint-Cap: max. 125% der Base-Langseite.
	var footprint_cap_m: float = base_long_mm * FOOTPRINT_MAX_RATIO * 0.001
	var footprint_scale: float = footprint_cap_m / raw_footprint

	var final_scale: float = min(height_scale, footprint_scale)

	# Fuesse auf Base-Oberkante (Base ist 3mm hoch); Flying schwebt zusaetzlich.
	var lift: float = base_long_mm * FLYING_HOVER_RATIO * 0.001 if is_flying else 0.0
	var y_offset: float = -aabb.position.y * final_scale + 0.003 + lift

	return {
		"scale": final_scale,
		"y_offset": y_offset,
		"height": raw_height * final_scale + lift,
	}


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
					# Crisp models up close: anisotropic mipmap filtering, and
					# regenerate mipmaps for runtime GLTF textures, which Godot loads
					# without a mip chain (godotengine/godot#100481) so they shimmer
					# and alias on small minis.
					adjusted_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					adjusted_mat.albedo_texture = _ensure_texture_mipmaps(adjusted_mat.albedo_texture)
					adjusted_mat.normal_texture = _ensure_texture_mipmaps(adjusted_mat.normal_texture)
					adjusted_mat.roughness_texture = _ensure_texture_mipmaps(adjusted_mat.roughness_texture)
					adjusted_mat.emission_texture = _ensure_texture_mipmaps(adjusted_mat.emission_texture)
					adjusted_mat.ao_texture = _ensure_texture_mipmaps(adjusted_mat.ao_texture)
					mesh_instance.mesh.surface_set_material(surface_idx, adjusted_mat)


## Returns a copy of [param tex] with a generated mipmap chain, for runtime GLTF
## textures that Godot loads without mipmaps (godotengine/godot#100481). Returns the
## texture unchanged when it already has mipmaps, is empty, or is GPU-compressed
## (mipmaps cannot be generated on compressed data).
func _ensure_texture_mipmaps(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.has_mipmaps() or img.is_compressed():
		return tex
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _on_army_loaded(army: OPRApiClient.OPRArmy) -> void:
	print("Army loaded: %s (faction: %s)" % [army.name, army.faction_name])


func _on_import_failed(error: String) -> void:
	push_error("OPR Import failed: %s" % error)

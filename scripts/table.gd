extends StaticBody3D
## Tabletop surface with configurable size
## Standard wargaming table sizes: 4x4, 4x6, 6x4 feet

@export var default_color: Color = Color(0.2, 0.35, 0.2)  # Gaming mat green
@export var grid_color: Color = Color(0.15, 0.25, 0.15)
@export var show_grid: bool = true
@export var grid_size_inches: float = 1.0
@export var default_texture_path: String = "res://assets/terrain/table_surface_default.png"

var _default_texture: Texture2D = null

var table_size: Vector2 = Vector2(4, 4)  # In feet, will be converted to meters

const FEET_TO_METERS: float = 0.3048  # 1 foot = 0.3048 meters
const INCHES_TO_METERS: float = 0.0254  # 1 inch = 0.0254 meters

# Crisp ground: the biome battlemaps are seamless tileable textures, so they are
# repeated MACRO_TILING times across the table for high effective resolution, with a
# densely-tiled procedural micro-relief on top for close-up surface detail.
const GROUND_SHADER: Shader = preload("res://shaders/table_ground.gdshader")
const MACRO_TILING: float = 3.0
const DETAIL_TILING: float = 28.0
const DETAIL_NOISE_SIZE: int = 512

# Nano-Banana biome battlemaps (assets/terrain/biomes/). The standard map is the default.
const DEFAULT_BIOME: String = "temperate_grassland"
const BIOME_TEXTURES: Dictionary = {
	"temperate_grassland": "res://assets/terrain/biomes/temperate_grassland.png",
	"arid_desert": "res://assets/terrain/biomes/arid_desert.png",
	"frozen_tundra": "res://assets/terrain/biomes/frozen_tundra.png",
	"volcanic_ash": "res://assets/terrain/biomes/volcanic_ash.png",
	"alien_jungle": "res://assets/terrain/biomes/alien_jungle.png",
	"urban_ruins": "res://assets/terrain/biomes/urban_ruins.png",
}

## Currently selected biome (key into BIOME_TEXTURES).
var biome: String = DEFAULT_BIOME

@onready var mesh_instance: MeshInstance3D = $TableMesh
@onready var collision_shape: CollisionShape3D = $TableCollision


func _ready() -> void:
	# Add to table group for raycasting
	add_to_group("table")
	# Ensure collision layer is set
	collision_layer = 1
	collision_mask = 1

	# Physics material for table surface (stable values)
	var table_physics = PhysicsMaterial.new()
	table_physics.friction = 0.9  # High friction for stability
	table_physics.bounce = 0.1  # Very low bounce
	physics_material_override = table_physics

	# Load the selected biome battlemap (falls back to the legacy mat if missing).
	_load_biome_texture()


## Setup table with given size in feet
func setup_table(size_feet: Vector2) -> void:
	table_size = size_feet
	var size_meters = size_feet * FEET_TO_METERS

	# Remove old borders if any, but preserve overlay nodes
	for child in get_children():
		if child != mesh_instance and child != collision_shape:
			# Preserve terrain overlay and other overlay nodes
			if child.name == "TerrainOverlay" or child.is_in_group("table_overlay"):
				continue
			child.queue_free()

	# Create table mesh
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = size_meters
	plane_mesh.subdivide_width = int(size_feet.x * 12 / grid_size_inches) if show_grid else 1
	plane_mesh.subdivide_depth = int(size_feet.y * 12 / grid_size_inches) if show_grid else 1

	mesh_instance.mesh = plane_mesh

	mesh_instance.material_override = _build_ground_material()

	# Create collision shape - MUCH larger to catch falling dice
	# Top surface at y=0 (same as visual mesh)
	var box_shape = BoxShape3D.new()
	# Extend collision 1 meter beyond table edges on all sides
	box_shape.size = Vector3(size_meters.x + 2.0, 0.5, size_meters.y + 2.0)  # 50cm thick, extended
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0, -0.25, 0)  # Top at y=0 (aligned with visual)

	# Add table edge/border
	_create_table_border(size_meters)

	print("Table setup: %.1fx%.1f feet (%.2fx%.2f meters)" % [size_feet.x, size_feet.y, size_meters.x, size_meters.y])


## Build the play-surface material: macro battlefield mat + tiled procedural micro-relief
## (anisotropic mipmaps + a seamless detail normal/height so it stays crisp up close).
func _build_ground_material() -> Material:
	if not _default_texture:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = default_color
		fallback.roughness = 0.9
		fallback.metallic = 0.0
		return fallback

	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("albedo_tex", _default_texture)
	mat.set_shader_parameter("macro_tiling", MACRO_TILING)
	mat.set_shader_parameter("detail_normal", _make_detail_noise(true))
	mat.set_shader_parameter("detail_height", _make_detail_noise(false))
	mat.set_shader_parameter("detail_tiling", DETAIL_TILING)
	mat.set_shader_parameter("detail_normal_strength", 0.35)
	mat.set_shader_parameter("detail_albedo_strength", 0.12)
	mat.set_shader_parameter("roughness_value", 0.9)
	return mat


## Load the current biome's battlemap into _default_texture (legacy mat as fallback).
func _load_biome_texture() -> void:
	var path: String = BIOME_TEXTURES.get(biome, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		path = default_texture_path
	_default_texture = load(path) if ResourceLoader.exists(path) else null


## Switch the play-surface biome (key into BIOME_TEXTURES) and rebuild the material.
func set_biome(biome_name: String) -> void:
	if not BIOME_TEXTURES.has(biome_name):
		push_warning("Unknown biome '%s' (known: %s)" % [biome_name, ", ".join(BIOME_TEXTURES.keys())])
		return
	biome = biome_name
	_load_biome_texture()
	mesh_instance.material_override = _build_ground_material()


## Available biome keys (for a selection UI).
func get_biomes() -> Array:
	return BIOME_TEXTURES.keys()


## Generate a seamless tiling noise texture for ground micro-detail. As a normal map
## when `as_normal` is true (surface relief), otherwise a height field (albedo variation).
func _make_detail_noise(as_normal: bool) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05 if as_normal else 0.035
	noise.fractal_octaves = 4

	var tex := NoiseTexture2D.new()
	tex.width = DETAIL_NOISE_SIZE
	tex.height = DETAIL_NOISE_SIZE
	tex.seamless = true
	tex.noise = noise
	if as_normal:
		tex.as_normal_map = true
		tex.bump_strength = 6.0
	return tex


func _create_table_border(size_meters: Vector2) -> void:
	var border_height = 0.05
	var border_width = 0.015  # thin rim (halved from 0.03)
	var wall_height = 0.15  # Invisible wall height to catch dice
	var border_material = StandardMaterial3D.new()
	border_material.albedo_color = Color(0.3, 0.2, 0.1)  # Wood color
	border_material.roughness = 0.7

	var positions = [
		Vector3(0, border_height / 2, -size_meters.y / 2 - border_width / 2),  # Front
		Vector3(0, border_height / 2, size_meters.y / 2 + border_width / 2),   # Back
		Vector3(-size_meters.x / 2 - border_width / 2, border_height / 2, 0),  # Left
		Vector3(size_meters.x / 2 + border_width / 2, border_height / 2, 0),   # Right
	]

	var sizes = [
		Vector3(size_meters.x + border_width * 2, border_height, border_width),
		Vector3(size_meters.x + border_width * 2, border_height, border_width),
		Vector3(border_width, border_height, size_meters.y),
		Vector3(border_width, border_height, size_meters.y),
	]

	# Wall collision positions (taller invisible walls)
	var wall_positions = [
		Vector3(0, wall_height / 2, -size_meters.y / 2 - border_width / 2),
		Vector3(0, wall_height / 2, size_meters.y / 2 + border_width / 2),
		Vector3(-size_meters.x / 2 - border_width / 2, wall_height / 2, 0),
		Vector3(size_meters.x / 2 + border_width / 2, wall_height / 2, 0),
	]

	var wall_sizes = [
		Vector3(size_meters.x + border_width * 2, wall_height, border_width),
		Vector3(size_meters.x + border_width * 2, wall_height, border_width),
		Vector3(border_width, wall_height, size_meters.y),
		Vector3(border_width, wall_height, size_meters.y),
	]

	for i in range(4):
		# Visual border
		var border_mesh = BoxMesh.new()
		border_mesh.size = sizes[i]

		var border_instance = MeshInstance3D.new()
		border_instance.mesh = border_mesh
		border_instance.material_override = border_material
		border_instance.position = positions[i]
		add_child(border_instance)

		# Invisible collision wall
		var wall = StaticBody3D.new()
		wall.name = "Wall_%d" % i
		wall.collision_layer = 1
		wall.collision_mask = 1

		var wall_collision = CollisionShape3D.new()
		var wall_shape = BoxShape3D.new()
		wall_shape.size = wall_sizes[i]
		wall_collision.shape = wall_shape
		wall.add_child(wall_collision)

		wall.position = wall_positions[i]
		add_child(wall)


## Convert inches to table coordinates
func inches_to_position(inches_x: float, inches_z: float) -> Vector3:
	return Vector3(inches_x * INCHES_TO_METERS, 0, inches_z * INCHES_TO_METERS)


## Check if a position is on the table
func is_on_table(world_position: Vector3) -> bool:
	var size_meters = table_size * FEET_TO_METERS
	return abs(world_position.x) <= size_meters.x / 2 and abs(world_position.z) <= size_meters.y / 2

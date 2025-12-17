extends StaticBody3D
## Tabletop surface with configurable size
## Standard wargaming table sizes: 4x4, 4x6, 6x4 feet

@export var default_color: Color = Color(0.2, 0.35, 0.2)  # Gaming mat green
@export var grid_color: Color = Color(0.15, 0.25, 0.15)
@export var show_grid: bool = true
@export var grid_size_inches: float = 1.0

var table_size: Vector2 = Vector2(4, 4)  # In feet, will be converted to meters

const FEET_TO_METERS: float = 0.3048
const INCHES_TO_METERS: float = 0.0254

@onready var mesh_instance: MeshInstance3D = $TableMesh
@onready var collision_shape: CollisionShape3D = $TableCollision


func _ready() -> void:
	# Add to table group for raycasting
	add_to_group("table")
	# Ensure collision layer is set
	collision_layer = 1
	collision_mask = 1


## Setup table with given size in feet
func setup_table(size_feet: Vector2) -> void:
	table_size = size_feet
	var size_meters = size_feet * FEET_TO_METERS

	# Create table mesh
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = size_meters
	plane_mesh.subdivide_width = int(size_feet.x * 12 / grid_size_inches) if show_grid else 1
	plane_mesh.subdivide_depth = int(size_feet.y * 12 / grid_size_inches) if show_grid else 1

	mesh_instance.mesh = plane_mesh

	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = default_color
	material.roughness = 0.9
	material.metallic = 0.0
	mesh_instance.material_override = material

	# Create collision shape
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(size_meters.x, 0.1, size_meters.y)
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0, -0.05, 0)

	# Add table edge/border
	_create_table_border(size_meters)

	print("Table setup: %.1fx%.1f feet (%.2fx%.2f meters)" % [size_feet.x, size_feet.y, size_meters.x, size_meters.y])


func _create_table_border(size_meters: Vector2) -> void:
	var border_height = 0.05
	var border_width = 0.03
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

	for i in range(4):
		var border_mesh = BoxMesh.new()
		border_mesh.size = sizes[i]

		var border_instance = MeshInstance3D.new()
		border_instance.mesh = border_mesh
		border_instance.material_override = border_material
		border_instance.position = positions[i]
		add_child(border_instance)


## Convert inches to table coordinates
func inches_to_position(inches_x: float, inches_z: float) -> Vector3:
	return Vector3(inches_x * INCHES_TO_METERS, 0, inches_z * INCHES_TO_METERS)


## Check if a position is on the table
func is_on_table(world_position: Vector3) -> bool:
	var size_meters = table_size * FEET_TO_METERS
	return abs(world_position.x) <= size_meters.x / 2 and abs(world_position.z) <= size_meters.y / 2

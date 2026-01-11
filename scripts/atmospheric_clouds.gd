extends Node3D
## Atmospheric Clouds System
## Creates drifting cloud layers that appear at high camera zoom levels
## Inspired by grand strategy games like Victoria, EU4, etc.

## Minimum zoom level where clouds start to appear
@export var min_zoom_for_clouds: float = 2.0
## Zoom level where clouds are fully visible
@export var full_visibility_zoom: float = 4.0
## Height offset above camera target
@export var cloud_height: float = 2.0
## Cloud layer size (width/depth of each cloud plane)
@export var cloud_layer_size: float = 30.0
## Number of cloud layers
@export var num_layers: int = 3
## Vertical spacing between layers
@export var layer_spacing: float = 0.5

# Cloud materials for each layer
var cloud_materials: Array[ShaderMaterial] = []
var cloud_meshes: Array[MeshInstance3D] = []
var camera_controller: Node3D = null

# Different settings per layer for variation
const LAYER_SETTINGS = [
	{"density": 0.35, "scroll_speed": 0.015, "scroll_dir": Vector2(1.0, 0.2), "scale1": 1.2, "scale2": 2.5},
	{"density": 0.25, "scroll_speed": 0.022, "scroll_dir": Vector2(0.8, -0.4), "scale1": 1.8, "scale2": 3.5},
	{"density": 0.20, "scroll_speed": 0.018, "scroll_dir": Vector2(-0.5, 0.8), "scale1": 2.2, "scale2": 4.0},
]


func _ready() -> void:
	_create_cloud_layers()
	# Find camera controller
	await get_tree().process_frame
	_find_camera_controller()


func _find_camera_controller() -> void:
	# Try to find camera controller in scene
	var cameras = get_tree().get_nodes_in_group("camera_controller")
	if cameras.size() > 0:
		camera_controller = cameras[0]
		return

	# Try to find by path
	camera_controller = get_node_or_null("/root/Main/CameraController")
	if camera_controller:
		return

	# Search all nodes for any with get_zoom method (recursive search)
	camera_controller = _find_node_with_method(get_tree().root, "get_zoom")


func _find_node_with_method(node: Node, method_name: String) -> Node:
	if node.has_method(method_name):
		return node
	for child in node.get_children():
		var result = _find_node_with_method(child, method_name)
		if result:
			return result
	return null


func _create_cloud_layers() -> void:
	# Load shader
	var shader = load("res://shaders/atmospheric_clouds.gdshader")
	if not shader:
		push_error("Could not load atmospheric_clouds.gdshader")
		return

	for i in range(num_layers):
		var settings = LAYER_SETTINGS[i % LAYER_SETTINGS.size()]

		# Create material for this layer
		var material = ShaderMaterial.new()
		material.shader = shader

		# Set layer-specific parameters
		material.set_shader_parameter("cloud_density", settings["density"])
		material.set_shader_parameter("scroll_speed", settings["scroll_speed"])
		material.set_shader_parameter("scroll_direction", settings["scroll_dir"])
		material.set_shader_parameter("noise_scale_1", settings["scale1"])
		material.set_shader_parameter("noise_scale_2", settings["scale2"])
		material.set_shader_parameter("visibility", 0.0)  # Start invisible

		# Slightly different colors per layer for depth
		var base_color = Color(0.85, 0.88, 0.95, 0.25)
		base_color.a = 0.25 - (i * 0.05)  # Higher layers more transparent
		material.set_shader_parameter("cloud_color", base_color)

		cloud_materials.append(material)

		# Create mesh
		var mesh_instance = MeshInstance3D.new()
		var plane_mesh = PlaneMesh.new()
		plane_mesh.size = Vector2(cloud_layer_size, cloud_layer_size)
		plane_mesh.subdivide_width = 1
		plane_mesh.subdivide_depth = 1
		mesh_instance.mesh = plane_mesh
		mesh_instance.material_override = material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		# Position at different heights
		mesh_instance.position.y = cloud_height + (i * layer_spacing)

		# Slight rotation offset per layer
		mesh_instance.rotation.y = deg_to_rad(i * 30)

		add_child(mesh_instance)
		cloud_meshes.append(mesh_instance)


func _process(_delta: float) -> void:
	if not camera_controller:
		_find_camera_controller()
		return

	# Get current zoom level
	var current_zoom: float = 10.0
	if camera_controller.has_method("get_zoom"):
		current_zoom = camera_controller.get_zoom()
	elif "zoom" in camera_controller:
		current_zoom = camera_controller.zoom
	elif "_current_zoom" in camera_controller:
		current_zoom = camera_controller._current_zoom

	# Calculate visibility based on zoom
	var visibility = 0.0
	if current_zoom >= min_zoom_for_clouds:
		visibility = clamp(
			(current_zoom - min_zoom_for_clouds) / (full_visibility_zoom - min_zoom_for_clouds),
			0.0,
			1.0
		)

	# Update material visibility
	for material in cloud_materials:
		material.set_shader_parameter("visibility", visibility)

	# Follow camera target position (stay above the table)
	if camera_controller:
		var target_pos = Vector3.ZERO
		if "_target_position" in camera_controller:
			target_pos = camera_controller._target_position
		elif "target_position" in camera_controller:
			target_pos = camera_controller.target_position

		global_position.x = target_pos.x
		global_position.z = target_pos.z


## Set cloud color theme
func set_cloud_color(color: Color) -> void:
	for i in range(cloud_materials.size()):
		var adjusted_color = color
		adjusted_color.a = 0.25 - (i * 0.05)
		cloud_materials[i].set_shader_parameter("cloud_color", adjusted_color)


## Set wind direction (affects all layers differently)
func set_wind_direction(direction: Vector2) -> void:
	for i in range(cloud_materials.size()):
		var layer_dir = direction.rotated(deg_to_rad(i * 20))
		cloud_materials[i].set_shader_parameter("scroll_direction", layer_dir)


## Enable/disable clouds
func set_enabled(enabled: bool) -> void:
	visible = enabled


## Adjust for different times of day (optional)
func set_time_of_day(hour: float) -> void:
	# Adjust cloud color based on time
	var color: Color
	if hour < 6.0 or hour > 20.0:
		# Night - darker, slightly blue
		color = Color(0.4, 0.45, 0.6, 0.2)
	elif hour < 8.0 or hour > 18.0:
		# Dawn/Dusk - warm orange tint
		color = Color(0.95, 0.8, 0.7, 0.3)
	else:
		# Day - bright white-blue
		color = Color(0.9, 0.92, 0.98, 0.25)

	set_cloud_color(color)

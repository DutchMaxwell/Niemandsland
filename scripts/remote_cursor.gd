extends Node3D
## Visualizes a remote player's cursor position on the table surface.
##
## Renders as a colored ring that smoothly follows the remote player's
## mouse position on the table. Fades out after a brief idle period.

var peer_id: int = 0
var player_color: Color = Color.RED

var _ring_mesh: MeshInstance3D
var _last_update_time: float = 0.0
var _target_pos: Vector3 = Vector3.ZERO
var _fade_delay: float = 3.0  # Seconds of inactivity before fading
var _material: StandardMaterial3D


func _ready() -> void:
	_build_cursor()


func _process(delta: float) -> void:
	# Smooth interpolation to target position
	position = position.lerp(_target_pos, delta * 15.0)

	# Fade out after inactivity
	if _material:
		var elapsed = Time.get_ticks_msec() / 1000.0 - _last_update_time
		if elapsed > _fade_delay:
			var fade = clamp(1.0 - (elapsed - _fade_delay) / 1.0, 0.0, 1.0)
			_material.albedo_color.a = fade * 0.8
		else:
			_material.albedo_color.a = 0.8


## Initialize the cursor for a specific peer
func setup(p_peer_id: int, color: Color) -> void:
	peer_id = p_peer_id
	player_color = color
	_build_cursor()


## Update cursor position on the table
func update_position(pos_x: float, pos_z: float) -> void:
	_target_pos = Vector3(pos_x, 0.005, pos_z)  # Slightly above table
	_last_update_time = Time.get_ticks_msec() / 1000.0


## Build the visual cursor (ring on table surface)
func _build_cursor() -> void:
	for child in get_children():
		child.queue_free()

	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(player_color.r, player_color.g, player_color.b, 0.8)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.emission_enabled = true
	_material.emission = player_color
	_material.emission_energy_multiplier = 2.0
	_material.no_depth_test = true
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Outer ring
	_ring_mesh = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.03
	torus.outer_radius = 0.05
	torus.rings = 16
	torus.ring_segments = 12
	torus.material = _material
	_ring_mesh.mesh = torus
	_ring_mesh.rotation_degrees.x = 90  # Flat on table
	add_child(_ring_mesh)

	# Center dot
	var dot = MeshInstance3D.new()
	var dot_mesh = SphereMesh.new()
	dot_mesh.radius = 0.01
	dot_mesh.height = 0.02
	dot_mesh.material = _material
	dot.mesh = dot_mesh
	add_child(dot)

	# Peer label (tiny, near cursor)
	var label = Label3D.new()
	label.text = "P%d" % peer_id
	label.font_size = 20
	label.modulate = player_color
	label.outline_modulate = Color.BLACK
	label.outline_size = 3
	label.position = Vector3(0.08, 0.01, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)

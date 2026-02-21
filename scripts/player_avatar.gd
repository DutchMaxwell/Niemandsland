extends Node3D
## Represents a remote player at the table.
##
## Displays a stylized avatar (body + head) that follows the remote player's
## camera position. The head rotates to show where the remote player
## is looking. A name label floats above the avatar.

const PLAYER_COLORS := {
	1: Color(0.2, 0.4, 0.9),  # Blue (host)
	2: Color(0.9, 0.2, 0.2),  # Red (guest 1)
	3: Color(0.2, 0.8, 0.3),  # Green (guest 2)
	4: Color(0.9, 0.7, 0.1),  # Yellow (guest 3)
}

var peer_id: int = 0
var player_color: Color = Color.WHITE

var _body_mesh: MeshInstance3D
var _head_mesh: MeshInstance3D
var _name_label: Label3D

# Smooth interpolation for head rotation
var _target_yaw: float = 0.0
var _target_pitch: float = -45.0
var _current_yaw: float = 0.0
var _current_pitch: float = -45.0

# Smooth interpolation for position (follows remote camera)
var _target_position: Vector3 = Vector3.ZERO
var _position_initialized: bool = false

# Body rotation stored for head yaw correction
var _body_rotation_y: float = 0.0

# Dice roll animation
var _is_rolling: bool = false
var _roll_timer: float = 0.0
var _roll_duration: float = 1.2
var _original_head_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	_build_avatar()


func _process(delta: float) -> void:
	# Smooth head rotation interpolation
	_current_yaw = lerp(_current_yaw, _target_yaw, delta * 5.0)
	_current_pitch = lerp(_current_pitch, _target_pitch, delta * 5.0)
	if _head_mesh:
		# Convert world yaw to avatar-local yaw by subtracting body rotation
		_head_mesh.rotation_degrees = Vector3(_current_pitch * 0.3, _current_yaw - _body_rotation_y, 0)

	# Smooth position interpolation (follows remote camera)
	if _position_initialized:
		position = position.lerp(_target_position, delta * 5.0)

	# Dice roll animation
	if _is_rolling:
		_roll_timer += delta
		var t = _roll_timer / _roll_duration
		if t >= 1.0:
			_is_rolling = false
			_roll_timer = 0.0
			if _head_mesh:
				_head_mesh.position = _original_head_pos
		else:
			# Bob head up and down during roll (simulating throw motion)
			var bob = sin(t * PI * 3.0) * 0.05 * (1.0 - t)
			if _head_mesh:
				_head_mesh.position = _original_head_pos + Vector3(0, bob, 0)


## Initialize the avatar for a specific peer
func setup(p_peer_id: int, table_size_feet: Vector2) -> void:
	peer_id = p_peer_id
	player_color = PLAYER_COLORS.get(peer_id, Color.WHITE)
	_build_avatar()
	_position_at_table(table_size_feet)


## Update the remote player's camera look direction
func update_look_direction(yaw: float, pitch: float) -> void:
	_target_yaw = yaw
	_target_pitch = pitch


## Update avatar position to follow remote camera pivot
func update_position(pos_x: float, pos_z: float) -> void:
	_target_position = Vector3(pos_x, 0, pos_z)
	if not _position_initialized:
		position = _target_position
		_position_initialized = true


## Play dice roll animation
func play_dice_roll_animation() -> void:
	if _head_mesh:
		_is_rolling = true
		_roll_timer = 0.0
		_original_head_pos = _head_mesh.position


## Build the 3D avatar from primitives
func _build_avatar() -> void:
	# Clean up existing meshes
	for child in get_children():
		child.queue_free()

	var mat = StandardMaterial3D.new()
	mat.albedo_color = player_color
	mat.roughness = 0.6
	mat.metallic = 0.1

	# Body: Cylinder
	_body_mesh = MeshInstance3D.new()
	var body = CylinderMesh.new()
	body.top_radius = 0.06
	body.bottom_radius = 0.08
	body.height = 0.2
	body.material = mat
	_body_mesh.mesh = body
	_body_mesh.position = Vector3(0, 0.1, 0)
	add_child(_body_mesh)

	# Head: Sphere
	_head_mesh = MeshInstance3D.new()
	var head = SphereMesh.new()
	head.radius = 0.07
	head.height = 0.14
	head.material = mat
	_head_mesh.mesh = head
	_head_mesh.position = Vector3(0, 0.27, 0)
	add_child(_head_mesh)
	_original_head_pos = _head_mesh.position

	# Eye dots (to show facing direction)
	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color.WHITE
	eye_mat.emission_enabled = true
	eye_mat.emission = Color.WHITE
	eye_mat.emission_energy_multiplier = 0.5

	for side in [-1, 1]:
		var eye = MeshInstance3D.new()
		var eye_mesh = SphereMesh.new()
		eye_mesh.radius = 0.015
		eye_mesh.height = 0.03
		eye_mesh.material = eye_mat
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.03, 0.01, -0.06)
		_head_mesh.add_child(eye)

	# Name label
	_name_label = Label3D.new()
	_name_label.text = "Player %d" % peer_id
	_name_label.font_size = 32
	_name_label.modulate = player_color
	_name_label.outline_modulate = Color.BLACK
	_name_label.outline_size = 4
	_name_label.position = Vector3(0, 0.42, 0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	add_child(_name_label)


## Position avatar at the opposite side of the table from the local player
func _position_at_table(table_size_feet: Vector2) -> void:
	var half_z = table_size_feet.y * 0.3048 / 2.0  # feet to meters
	# Peer 1 (host) sits at +Z, peer 2 at -Z, etc.
	# Godot's -Z is the default forward direction.
	# Peer 1 at +Z should face -Z (toward table center) → rotation 0°
	# Peer 2 at -Z should face +Z (toward table center) → rotation 180°
	if peer_id == 1:
		position = Vector3(0, 0, half_z + 0.15)
		rotation_degrees.y = 0.0
		_body_rotation_y = 0.0
	else:
		position = Vector3(0, 0, -(half_z + 0.15))
		rotation_degrees.y = 180.0
		_body_rotation_y = 180.0
	_target_position = position

class_name DiceD6
extends RigidBody3D
## A single six-sided physics die with up-face detection. Our own MIT implementation
## (replaces the AGPL dice_roller addon). Pip faces reuse DieFaceIcon.PIP_LAYOUT so
## the rolling dice and the success readout share one look.

# === Constants ===

## Local outward normal per face value. Opposite faces sum to 7.
const FACE_NORMALS: Dictionary = {
	1: Vector3.UP, 6: Vector3.DOWN,
	2: Vector3.RIGHT, 5: Vector3.LEFT,
	3: Vector3.BACK, 4: Vector3.FORWARD,
}
## Rotation (deg) that turns a QuadMesh's +Z face to sit on each face, facing out.
const FACE_ROTATIONS: Dictionary = {
	1: Vector3(-90, 0, 0), 6: Vector3(90, 0, 0),
	2: Vector3(0, 90, 0), 5: Vector3(0, -90, 0),
	3: Vector3(0, 0, 0), 4: Vector3(0, 180, 0),
}
const BODY_COLOR: Color = Color(0.93, 0.93, 0.90)
const PIP_COLOR: Color = Color(0.12, 0.12, 0.14)
const PIP_RADIUS_FACTOR: float = 0.11
const TEXTURE_SIZE: int = 96

# === Public variables ===

## Edge length in viewport units. Set before adding to the tree.
var size: float = 2.0

# === Lifecycle ===

func _ready() -> void:
	mass = 1.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.12
	physics_material_override = pm

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, size, size)
	shape.shape = box
	add_child(shape)

	var body := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(size, size, size)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = BODY_COLOR
	box_mesh.material = body_mat
	body.mesh = box_mesh
	add_child(body)

	_add_pip_faces()

# === Public API ===

## The face value currently pointing up (world space).
func top_face() -> int:
	var best_value: int = 1
	var best_dot: float = -INF
	for value: int in FACE_NORMALS:
		var world_normal: Vector3 = global_transform.basis * FACE_NORMALS[value]
		var d: float = world_normal.dot(Vector3.UP)
		if d > best_dot:
			best_dot = d
			best_value = value
	return best_value


func is_settled(linear_threshold: float, angular_threshold: float) -> bool:
	return linear_velocity.length() < linear_threshold \
		and angular_velocity.length() < angular_threshold


## Orients the die so [param value] points up (for quick-roll / showing a result).
func set_top_face(value: int) -> void:
	var normal: Vector3 = FACE_NORMALS.get(value, Vector3.UP)
	var b: Basis
	if normal.is_equal_approx(Vector3.UP):
		b = Basis()
	elif normal.is_equal_approx(Vector3.DOWN):
		b = Basis(Vector3.RIGHT, PI)
	else:
		b = Basis(normal.cross(Vector3.UP).normalized(), normal.angle_to(Vector3.UP))
	b = Basis(Vector3.UP, randf() * TAU) * b  # random yaw for variety (top face unchanged)
	global_transform = Transform3D(b, global_position)

# === Private helpers ===

func _add_pip_faces() -> void:
	var half: float = size * 0.5 + 0.001
	for value: int in FACE_NORMALS:
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(size, size)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _make_face_texture(value)
		mat.roughness = 0.85
		mesh.material = mat
		quad.mesh = mesh
		quad.position = FACE_NORMALS[value] * half
		quad.rotation_degrees = FACE_ROTATIONS[value]
		add_child(quad)


static func _make_face_texture(value: int) -> Texture2D:
	var s: int = TEXTURE_SIZE
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(BODY_COLOR)
	var r: int = int(s * PIP_RADIUS_FACTOR)
	for cell: Vector2 in DieFaceIcon.PIP_LAYOUT[value]:
		var cx: int = int(cell.x * s)
		var cy: int = int(cell.y * s)
		for y: int in range(maxi(0, cy - r), mini(s, cy + r + 1)):
			for x: int in range(maxi(0, cx - r), mini(s, cx + r + 1)):
				var dx: int = x - cx
				var dy: int = y - cy
				if dx * dx + dy * dy <= r * r:
					img.set_pixel(x, y, PIP_COLOR)
	return ImageTexture.create_from_image(img)

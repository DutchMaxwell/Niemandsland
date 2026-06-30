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

## Per-die colour tags the player can cycle through by clicking a die. Index 0 is the
## default (untagged) BODY_COLOR; 1..4 are the four distinct tag colours. The interaction
## is a simple cycle (default -> 1 -> 2 -> 3 -> 4 -> default); tags persist through a roll's
## result display and reset when a new roll starts (DiceTray drives the reset).
const TAG_COLORS: Array[Color] = [
	Color(0.86, 0.20, 0.20),  # red
	Color(0.20, 0.45, 0.90),  # blue
	Color(0.25, 0.70, 0.30),  # green
	Color(0.92, 0.78, 0.16),  # yellow
]
## Body luminance below this reads as "dark" → use light pips for contrast (and vice versa).
const PIP_CONTRAST_LUMINANCE: float = 0.5
## High-contrast pip colours chosen per body luminance (Rec. 709 weights).
const PIP_COLOR_ON_DARK: Color = Color(0.95, 0.95, 0.95)
const PIP_COLOR_ON_LIGHT: Color = Color(0.10, 0.10, 0.12)
const DEFAULT_COLOR_TAG: int = 0

# === Public variables ===

## Edge length in viewport units. Set before adding to the tree.
var size: float = 2.0

## Current colour tag: 0 = untagged (BODY_COLOR), 1..TAG_COLORS.size() = a tag colour.
var color_tag: int = DEFAULT_COLOR_TAG

# === Private variables ===

## The body's material, kept so the tag colour can be re-applied at runtime.
var _body_mat: StandardMaterial3D = null
## One material per face value, kept so the tag colour re-fills the pip textures at runtime.
var _face_mats: Dictionary = {}  # Dictionary[int, StandardMaterial3D]
## Floating "?" shown while the die has NOT yet been rolled (issue #80); lazily created.
var _unrolled_label: Label3D = null

# === Lifecycle ===

func _ready() -> void:
	mass = 1.0
	gravity_scale = 2.0          # snappier fall + settle at this viewport scale
	linear_damp = 0.3
	angular_damp = 1.0           # bleed off spin so the die stops tumbling quickly
	continuous_cd = true         # stop fast dice from tunnelling through thin walls
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	physics_material_override = pm

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, size, size)
	shape.shape = box
	add_child(shape)

	var body := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(size, size, size)
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = BODY_COLOR
	box_mesh.material = _body_mat
	body.mesh = box_mesh
	add_child(body)

	_add_pip_faces()
	_apply_color_tag()

# === Public API ===

## Advance the colour tag one step: default -> 1 -> 2 -> 3 -> 4 -> default.
func cycle_color_tag() -> void:
	set_color_tag((color_tag + 1) % (TAG_COLORS.size() + 1))


## Set the colour tag directly (0 = untagged, 1..TAG_COLORS.size() = a tag colour).
## Out-of-range values clear the tag (defensive — keeps an untagged default).
func set_color_tag(tag: int) -> void:
	color_tag = tag if tag >= 0 and tag <= TAG_COLORS.size() else DEFAULT_COLOR_TAG
	_apply_color_tag()


## Reset to the untagged default colour.
func clear_color_tag() -> void:
	set_color_tag(DEFAULT_COLOR_TAG)


## The body colour for a given tag (0 = default BODY_COLOR, 1..N = TAG_COLORS).
static func body_color_for_tag(tag: int) -> Color:
	if tag >= 1 and tag <= TAG_COLORS.size():
		return TAG_COLORS[tag - 1]
	return BODY_COLOR


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


func is_settled(linear_threshold: float) -> bool:
	# Down on the floor (resting on a face or teetering on an edge) and not sliding.
	# A teetering die still counts, so the result can be forced rather than waited out.
	return linear_velocity.length() < linear_threshold and global_position.y < size * 0.95


## Forces the die flat onto [param value]'s face (minimal rotation, keeps yaw) and
## freezes it — ends the end-of-roll teetering.
func settle_to_face(value: int) -> void:
	var normal: Vector3 = FACE_NORMALS.get(value, Vector3.UP)
	var current: Vector3 = (global_transform.basis * normal).normalized()
	var b: Basis = global_transform.basis
	var axis: Vector3 = current.cross(Vector3.UP)
	if axis.length() > 0.0001:
		b = Basis(axis.normalized(), current.angle_to(Vector3.UP)) * b
	elif current.dot(Vector3.UP) < 0.0:
		# Face points straight down: cross() degenerates to zero, so flip 180° about a
		# fixed horizontal axis (same antiparallel handling as set_top_face).
		b = Basis(Vector3.RIGHT, PI) * b
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(b.orthonormalized(), Vector3(global_position.x, size * 0.5, global_position.z))


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
	# Taking a real face clears the "not yet rolled" marker (a physics roll spawns fresh dice anyway).
	if _unrolled_label != null and is_instance_valid(_unrolled_label):
		_unrolled_label.visible = false


## Mark this die as NOT YET ROLLED: a floating "?" instead of a face value, so selecting a dice
## COUNT (which spawns resting dice) doesn't look like a roll result (issue #80). Cleared when the
## die takes a real face (set_top_face) or a physics roll spawns a fresh die.
func set_unrolled() -> void:
	set_top_face(1)  # rest flat in a deterministic orientation under the marker
	if _unrolled_label == null:
		_unrolled_label = Label3D.new()
		_unrolled_label.name = "UnrolledMarker"
		_unrolled_label.text = "?"
		_unrolled_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_unrolled_label.no_depth_test = true
		_unrolled_label.font_size = 96
		_unrolled_label.pixel_size = size * 0.012
		_unrolled_label.modulate = Color.WHITE
		_unrolled_label.outline_size = 24
		_unrolled_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
		add_child(_unrolled_label)
	_unrolled_label.position = Vector3(0.0, size * 0.55, 0.0)
	_unrolled_label.visible = true

# === Private helpers ===

func _add_pip_faces() -> void:
	var half: float = size * 0.5 + 0.001
	_face_mats.clear()
	for value: int in FACE_NORMALS:
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(size, size)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _make_face_texture(value, BODY_COLOR, PIP_COLOR)
		mat.roughness = 0.85
		mesh.material = mat
		quad.mesh = mesh
		quad.position = FACE_NORMALS[value] * half
		quad.rotation_degrees = FACE_ROTATIONS[value]
		add_child(quad)
		_face_mats[value] = mat


## Recolours the body + every face texture to match the current colour tag. The pip colour
## is derived from the body luminance so the pips stay readable on light AND dark tags.
func _apply_color_tag() -> void:
	var body: Color = body_color_for_tag(color_tag)
	var pip: Color = _pip_color_for_body(body)
	if _body_mat != null:
		_body_mat.albedo_color = body
	for value: int in _face_mats:
		var mat: StandardMaterial3D = _face_mats[value]
		if mat != null:
			mat.albedo_texture = _make_face_texture(value, body, pip)


## Pip colour with enough contrast against the given body colour (Rec. 709 luminance).
static func _pip_color_for_body(body: Color) -> Color:
	var luminance: float = 0.2126 * body.r + 0.7152 * body.g + 0.0722 * body.b
	return PIP_COLOR_ON_DARK if luminance < PIP_CONTRAST_LUMINANCE else PIP_COLOR_ON_LIGHT


static func _make_face_texture(value: int, body: Color, pip: Color) -> Texture2D:
	var s: int = TEXTURE_SIZE
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(body)
	var r: int = int(s * PIP_RADIUS_FACTOR)
	for cell: Vector2 in DieFaceIcon.PIP_LAYOUT[value]:
		var cx: int = int(cell.x * s)
		var cy: int = int(cell.y * s)
		for y: int in range(maxi(0, cy - r), mini(s, cy + r + 1)):
			for x: int in range(maxi(0, cx - r), mini(s, cx + r + 1)):
				var dx: int = x - cx
				var dy: int = y - cy
				if dx * dx + dy * dy <= r * r:
					img.set_pixel(x, y, pip)
	return ImageTexture.create_from_image(img)

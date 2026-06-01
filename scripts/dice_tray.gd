class_name DiceTray
extends SubViewportContainer
## Rolls N six-sided dice with physics in a scaled SubViewport and reports the
## result. Our own MIT replacement for the AGPL dice_roller addon — a drop-in for
## the dice UI: same API (dice_count, roller_size, roll/quick_roll/show_faces/
## per_dice_result) and signals (roll_started, roll_finnished).

# === Signals ===

signal roll_started()
signal roll_finnished(total: int)

# === Exports ===

@export var dice_count: int = 6:
	set(value):
		dice_count = maxi(1, value)
		if is_node_ready() and not _rolling:
			_show_resting_dice()

@export var roller_size: Vector3 = Vector3(18, 15, 12):
	set(value):
		roller_size = value
		if is_node_ready():
			_rebuild_environment()
			if not _rolling:
				_show_resting_dice()

# === Constants ===

const DIE_SIZE: float = 2.2
const SETTLE_LINEAR: float = 0.6  # max horizontal motion to count a die as "down and calm"
const SETTLE_HOLD: float = 0.2    # seconds calm before the result is forced
const MAX_ROLL_TIME: float = 2.5  # safety cap
const WALL_THICKNESS: float = 1.5

# === Private variables ===

var _viewport: SubViewport
var _root: Node3D
var _camera: Camera3D
var _environment: Node3D
var _dice: Array[DiceD6] = []
var _rolling: bool = false
var _roll_time: float = 0.0
var _still_time: float = 0.0
var _result: Dictionary = {}

# === Lifecycle ===

func _ready() -> void:
	stretch = true
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	add_child(_viewport)
	_root = Node3D.new()
	_viewport.add_child(_root)
	_setup_lighting()
	_rebuild_environment()
	_show_resting_dice()


func _physics_process(delta: float) -> void:
	if not _rolling:
		return
	_roll_time += delta
	var settled: bool = true
	for d: DiceD6 in _dice:
		if not is_instance_valid(d) or not d.is_settled(SETTLE_LINEAR):
			settled = false
			break
	_still_time = _still_time + delta if settled else 0.0
	if _still_time >= SETTLE_HOLD or _roll_time >= MAX_ROLL_TIME:
		_finalize_roll()

# === Public API ===

## Physics roll: tosses the dice and reports the result once they settle.
func roll() -> void:
	_spawn_dice(false)
	for d: DiceD6 in _dice:
		d.freeze = false
		d.linear_velocity = Vector3(randf_range(-2, 2), randf_range(-2, 0), randf_range(-2, 2))
		d.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	_rolling = true
	_roll_time = 0.0
	_still_time = 0.0
	roll_started.emit()


## Instant (non-physics) roll: pick random faces and show them.
func quick_roll() -> void:
	var faces: Array[int] = []
	for _i in maxi(1, dice_count):
		faces.append(randi_range(1, 6))
	show_faces(faces)


## Shows specific faces without physics (used for quick rolls + remote results).
func show_faces(faces: Array) -> void:
	dice_count = faces.size()
	_spawn_dice(true)
	var ints: Array[int] = []
	for i: int in _dice.size():
		var v: int = int(faces[i])
		_dice[i].set_top_face(v)
		ints.append(v)
	_rolling = false
	_apply_result(ints)
	roll_started.emit()
	roll_finnished.emit(_total(ints))


func per_dice_result() -> Dictionary:
	return _result

# === Private: roll lifecycle ===

func _finalize_roll() -> void:
	_rolling = false
	var faces: Array[int] = []
	for d: DiceD6 in _dice:
		if not is_instance_valid(d):
			faces.append(1)
			continue
		var value: int = d.top_face()
		d.settle_to_face(value)  # snap flat + freeze → no more teetering
		faces.append(value)
	_apply_result(faces)
	roll_finnished.emit(_total(faces))


func _apply_result(faces: Array[int]) -> void:
	_result = {}
	for i: int in faces.size():
		_result["die_%d" % i] = faces[i]


func _total(faces: Array[int]) -> int:
	var sum: int = 0
	for v: int in faces:
		sum += v
	return sum

# === Private: dice + environment ===

func _show_resting_dice() -> void:
	_spawn_dice(true)
	for d: DiceD6 in _dice:
		d.set_top_face(randi_range(1, 6))


func _spawn_dice(resting: bool) -> void:
	for d: DiceD6 in _dice:
		if is_instance_valid(d):
			d.queue_free()
	_dice.clear()

	var count: int = maxi(1, dice_count)
	var cols: int = int(ceil(sqrt(float(count))))
	var rows: int = int(ceil(float(count) / float(cols)))
	var half_x: float = roller_size.x * 0.5 - DIE_SIZE
	var half_z: float = roller_size.z * 0.5 - DIE_SIZE
	# Maximum spacing: spread the grid across the full usable box footprint.
	var spacing_x: float = (2.0 * half_x / float(cols - 1)) if cols > 1 else 0.0
	var spacing_z: float = (2.0 * half_z / float(rows - 1)) if rows > 1 else 0.0

	for i: int in count:
		var d := DiceD6.new()
		d.size = DIE_SIZE
		d.freeze = resting
		_root.add_child(d)
		var col: int = i % cols
		var row: int = i / cols
		var gx: float = (col - (cols - 1) * 0.5) * spacing_x
		var gz: float = (row - (rows - 1) * 0.5) * spacing_z
		if resting:
			d.position = Vector3(gx, DIE_SIZE * 0.5 + 0.05, gz)
		else:
			# Drop from a high grid, capped below the wall top so nothing escapes.
			var drop_y: float = minf(roller_size.y * 0.7 + (i % 3) * DIE_SIZE, roller_size.y - DIE_SIZE)
			d.position = Vector3(gx, drop_y, gz)
			d.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		_dice.append(d)


func _setup_lighting() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -35, 0)
	light.light_energy = 1.2
	_root.add_child(light)


func _rebuild_environment() -> void:
	if _environment and is_instance_valid(_environment):
		_environment.queue_free()
	_environment = Node3D.new()
	_root.add_child(_environment)

	var hx: float = roller_size.x * 0.5
	var hz: float = roller_size.z * 0.5
	var h: float = roller_size.y

	# Visible floor.
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(roller_size.x, roller_size.z)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.12, 0.13, 0.16)
	floor_mat.roughness = 0.95
	plane.material = floor_mat
	floor_mesh.mesh = plane
	_environment.add_child(floor_mesh)

	# Colliders: floor + four walls (invisible) keep the dice in the box.
	_add_collider(Vector3(roller_size.x, WALL_THICKNESS, roller_size.z), Vector3(0, -WALL_THICKNESS * 0.5, 0))
	_add_collider(Vector3(WALL_THICKNESS, h, roller_size.z), Vector3(hx, h * 0.5, 0))
	_add_collider(Vector3(WALL_THICKNESS, h, roller_size.z), Vector3(-hx, h * 0.5, 0))
	_add_collider(Vector3(roller_size.x, h, WALL_THICKNESS), Vector3(0, h * 0.5, hz))
	_add_collider(Vector3(roller_size.x, h, WALL_THICKNESS), Vector3(0, h * 0.5, -hz))

	_setup_camera()


func _add_collider(box_size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	body.add_child(shape)
	_environment.add_child(body)


func _setup_camera() -> void:
	if _camera and is_instance_valid(_camera):
		_camera.queue_free()
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = maxf(roller_size.x, roller_size.z) * 1.1
	_camera.position = Vector3(0, roller_size.y * 1.5, 0)
	_camera.rotation_degrees = Vector3(-90, 0, 0)
	_root.add_child(_camera)

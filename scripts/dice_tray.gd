class_name DiceTray
extends SubViewportContainer
## Rolls N six-sided dice with physics in a scaled SubViewport and reports the
## result. Our own MIT replacement for the AGPL dice_roller addon — a drop-in for
## the dice UI: same API (dice_count, roller_size, roll/quick_roll/show_faces/
## per_dice_result) and signals (roll_started, roll_finnished).

# === Signals ===

signal roll_started()
signal roll_finnished(total: int)
## A die's colour tag was changed by a click (index in the tray, new tag 0..4). main.gd
## broadcasts this so the opponent's mirrored tray shows the same colour on the same die.
signal color_tag_changed(index: int, tag: int)

# === Exports ===

@export var dice_count: int = 6:
	set(value):
		var clamped: int = maxi(1, value)
		if clamped == dice_count:
			return  # no-op: respawning here would drop the player's colour tags before a roll
		dice_count = clamped
		if is_node_ready() and not _rolling:
			_show_resting_dice()

@export var roller_size: Vector3 = Vector3(18, 15, 12):
	set(value):
		if value == roller_size:
			return  # no-op: avoid an unnecessary respawn that would clear colour tags
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
const SEPARATION_PASSES: int = 6  # relaxation iterations for the cosmetic de-overlap
const PICK_RADIUS_SCALE: float = 1.4  # accept a click within 1.4x a die's on-screen half-size

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
	tooltip_text = "Click a die to tag it with a colour (cycles through 4 colours). Tags reset on the next roll."
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


## Click a die to cycle its colour tag (default -> red -> blue -> green -> yellow -> default).
## Tags persist through the result display and reset on the next roll. Disabled mid-roll so a
## click can't recolour a tumbling die. Only consumes the event when a die is actually hit, so
## clicks on empty tray area still fall through.
func _gui_input(event: InputEvent) -> void:
	if _rolling:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var index: int = _die_index_at_local_pos(mb.position)
	if index >= 0:
		var die: DiceD6 = _dice[index]
		die.cycle_color_tag()
		color_tag_changed.emit(index, die.color_tag)
		accept_event()

# === Public API ===

## Physics roll: tosses the dice and reports the result once they settle. The colour tags the
## player set on the resting dice are carried onto the rolled dice, so "red = Rending" survives
## the toss and is visible on the result (matching get_color_tags() at any time during the roll).
func roll() -> void:
	var tags: Array[int] = get_color_tags()
	_spawn_dice(false)
	for i: int in _dice.size():
		var d: DiceD6 = _dice[i]
		if i < tags.size():
			d.set_color_tag(tags[i])
		d.freeze = false
		d.linear_velocity = Vector3(randf_range(-2, 2), randf_range(-2, 0), randf_range(-2, 2))
		d.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	_rolling = true
	_roll_time = 0.0
	_still_time = 0.0
	roll_started.emit()


## Re-tosses only the dice at `indices`; every other die stays frozen on its
## current face (frozen RigidBodies are static colliders, so they sit still
## while the others roll). The settle loop then reports the COMBINED result of
## kept + rerolled faces through the usual roll_finnished signal.
func reroll(indices: Array[int]) -> void:
	if _rolling:
		return
	var tossed := false
	for idx: int in indices:
		if idx < 0 or idx >= _dice.size():
			continue
		var d: DiceD6 = _dice[idx]
		if not is_instance_valid(d):
			continue
		var slot: Vector2 = _grid_slot(idx, _dice.size())
		var drop_y: float = minf(roller_size.y * 0.7 + (idx % 3) * DIE_SIZE, roller_size.y - DIE_SIZE)
		d.freeze = false
		d.position = Vector3(slot.x, drop_y, slot.y)
		d.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		d.linear_velocity = Vector3(randf_range(-2, 2), randf_range(-2, 0), randf_range(-2, 2))
		d.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		tossed = true
	if not tossed:
		return
	_rolling = true
	_roll_time = 0.0
	_still_time = 0.0
	roll_started.emit()


## Instant (non-physics) roll: pick random faces and show them, keeping the player's colour tags.
func quick_roll() -> void:
	var tags: Array[int] = get_color_tags()
	var faces: Array[int] = []
	for _i in maxi(1, dice_count):
		faces.append(randi_range(1, 6))
	show_faces(faces, tags)


## Shows specific faces without physics (used for quick rolls + remote results). Optional
## `tags` (one colour tag per die) recolours the dice so a SYNCED remote roll keeps the
## sender's per-die colours through the result display.
func show_faces(faces: Array, tags: Array = []) -> void:
	dice_count = faces.size()
	_spawn_dice(true)
	var ints: Array[int] = []
	for i: int in _dice.size():
		var v: int = int(faces[i])
		_dice[i].set_top_face(v)
		if i < tags.size():
			_dice[i].set_color_tag(int(tags[i]))
		ints.append(v)
	_rolling = false
	_apply_result(ints)
	roll_started.emit()
	roll_finnished.emit(_total(ints))


## The colour tag of every die currently in the tray, in die order (0 = untagged, 1..4 = a tag).
## Used to broadcast the cup's current colouring to a peer.
func get_color_tags() -> Array[int]:
	var tags: Array[int] = []
	for d: DiceD6 in _dice:
		tags.append(d.color_tag if is_instance_valid(d) else DiceD6.DEFAULT_COLOR_TAG)
	return tags


## Apply a full set of colour tags (one per die, in order) to the current dice. Extra/short
## arrays are tolerated: only the overlapping range is applied. Used to mirror a peer's cup.
func apply_color_tags(tags: Array) -> void:
	for i: int in mini(_dice.size(), tags.size()):
		if is_instance_valid(_dice[i]):
			_dice[i].set_color_tag(int(tags[i]))


## Set one die's colour tag by index (no-op if out of range). Used to mirror a peer's click.
func set_die_color_tag(index: int, tag: int) -> void:
	if index >= 0 and index < _dice.size() and is_instance_valid(_dice[index]):
		_dice[index].set_color_tag(tag)


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
	_separate_settled_dice()
	_apply_result(faces)
	roll_finnished.emit(_total(faces))


## Settled dice all snap to y = DIE_SIZE/2, so a die that came to rest ON
## another (possible when a reroll drops onto a frozen die) would interpenetrate
## it — push overlapping pairs apart in XZ and keep them inside the walls.
## A single sweep can shove a die back onto a lower-indexed one, so relax over a
## few passes and stop early once a pass changes nothing. Cosmetic only: faces
## are already read before this runs.
func _separate_settled_dice() -> void:
	var half_x: float = roller_size.x * 0.5 - DIE_SIZE
	var half_z: float = roller_size.z * 0.5 - DIE_SIZE
	for _pass: int in SEPARATION_PASSES:
		var moved_any := false
		for i: int in _dice.size():
			for j: int in range(i + 1, _dice.size()):
				if not is_instance_valid(_dice[i]) or not is_instance_valid(_dice[j]):
					continue
				var a: Vector3 = _dice[i].position
				var b: Vector3 = _dice[j].position
				var offset := Vector2(b.x - a.x, b.z - a.z)
				if offset.length() >= DIE_SIZE:
					continue
				# Degenerate overlap (same spot): pick a fixed push direction.
				var push: Vector2 = offset.normalized() if offset.length() > 0.001 else Vector2.RIGHT
				var moved: Vector2 = Vector2(a.x, a.z) + push * DIE_SIZE
				_dice[j].position.x = clampf(moved.x, -half_x, half_x)
				_dice[j].position.z = clampf(moved.y, -half_z, half_z)
				moved_any = true
		if not moved_any:
			break


func _apply_result(faces: Array[int]) -> void:
	_result = {}
	for i: int in faces.size():
		_result["die_%d" % i] = faces[i]


func _total(faces: Array[int]) -> int:
	var sum: int = 0
	for v: int in faces:
		sum += v
	return sum

# === Private: picking ===

## Index in `_dice` of the die under a container-local click position, or -1. Maps the click
## into SubViewport pixels (this container stretches the viewport to fit), then raycasts in the
## dice world. Returns the index (not the node) so callers can address the same die remotely.
func _die_index_at_local_pos(local_pos: Vector2) -> int:
	if _viewport == null or _camera == null or _dice.is_empty():
		return -1
	var container_size: Vector2 = size
	if container_size.x <= 0.0 or container_size.y <= 0.0:
		return -1
	# stretch=true scales the SubViewport to the container, so rescale the click back to
	# viewport pixels before projecting through the camera.
	var vp_size: Vector2 = Vector2(_viewport.size)
	var vp_pos: Vector2 = Vector2(
		local_pos.x / container_size.x * vp_size.x,
		local_pos.y / container_size.y * vp_size.y)
	# Pick the die whose centre projects nearest the click, within its on-screen size. Projecting
	# is robust to physics state — resting dice are frozen, where a collider raycast was unreliable.
	var cam_right: Vector3 = _camera.global_transform.basis.x
	var best: int = -1
	var best_dist: float = INF
	for i: int in _dice.size():
		var d: DiceD6 = _dice[i]
		if d == null or not is_instance_valid(d):
			continue
		var centre: Vector2 = _camera.unproject_position(d.global_position)
		var edge: Vector2 = _camera.unproject_position(d.global_position + cam_right * (d.size * 0.5))
		var radius_px: float = maxf(centre.distance_to(edge), 1.0) * PICK_RADIUS_SCALE
		var dist: float = centre.distance_to(vp_pos)
		if dist <= radius_px and dist < best_dist:
			best_dist = dist
			best = i
	return best

# === Private: dice + environment ===

func _show_resting_dice() -> void:
	_spawn_dice(true)
	for d: DiceD6 in _dice:
		d.set_unrolled()  # show "?" until rolled, not a random face that looks like a result (issue #80)


## Frees the current dice and spawns a fresh (untagged) set. Callers that must preserve the
## per-die colour tags across the respawn — roll() (carry tags through the toss) and
## show_faces(tags) (apply the sender's tags to the result) — re-apply them right after.
## A dice_count CHANGE respawns through here without re-applying, which is what resets the cup.
func _spawn_dice(resting: bool) -> void:
	for d: DiceD6 in _dice:
		if is_instance_valid(d):
			d.queue_free()
	_dice.clear()

	var count: int = maxi(1, dice_count)
	for i: int in count:
		var d := DiceD6.new()
		d.size = DIE_SIZE
		d.freeze = resting
		_root.add_child(d)
		var slot: Vector2 = _grid_slot(i, count)
		if resting:
			d.position = Vector3(slot.x, DIE_SIZE * 0.5 + 0.05, slot.y)
		else:
			# Drop from a high grid, capped below the wall top so nothing escapes.
			var drop_y: float = minf(roller_size.y * 0.7 + (i % 3) * DIE_SIZE, roller_size.y - DIE_SIZE)
			d.position = Vector3(slot.x, drop_y, slot.y)
			d.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		_dice.append(d)


## XZ grid slot of die `i` in a set of `count`: maximum spacing, spreading the
## grid across the full usable box footprint (shared by spawn and reroll drops).
func _grid_slot(i: int, count: int) -> Vector2:
	var cols: int = int(ceil(sqrt(float(maxi(1, count)))))
	var rows: int = int(ceil(float(maxi(1, count)) / float(cols)))
	var half_x: float = roller_size.x * 0.5 - DIE_SIZE
	var half_z: float = roller_size.z * 0.5 - DIE_SIZE
	var spacing_x: float = (2.0 * half_x / float(cols - 1)) if cols > 1 else 0.0
	var spacing_z: float = (2.0 * half_z / float(rows - 1)) if rows > 1 else 0.0
	var col: int = i % cols
	var row: int = i / cols
	return Vector2((col - (cols - 1) * 0.5) * spacing_x, (row - (rows - 1) * 0.5) * spacing_z)


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

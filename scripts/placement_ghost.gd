class_name PlacementGhost
extends Node3D
## #210 (grilled 2026-07-30) — the cursor-placement ghost for transport exits: the unit's
## auto-formation SHAPE hangs at the mouse cursor, R rotates it in 15° steps, and every
## spot is validated live — each base FULLY within 6" of the transport's base edge
## (GF v3.5.1 p.15), no base overlap, inside the table. Green = legal, red = not.
## LMB commits all models at once, RMB/ESC cancels. Pure visuals + input — the commit
## callback owns state, battle log and MP sync; cancel leaves the unit inside.

const ROT_STEP := deg_to_rad(15.0)
const GHOST_Y := 0.012

var _shape: Array = []        # [{off: Vector2 (from formation centroid), r: float}] — chain order
var _zone_c := Vector3.ZERO   # transport's table position
var _zone_m := 0.0            # 6" + transport base radius (metres)
var _blockers: Array = []     # [{p: Vector3, r: float}] — every other live base
var _bounds := Rect2()
var _commit: Callable
var _cancel: Callable
var _rot := 0.0
var _cursor := Vector3.ZERO
var _discs: Array = []


## The rule check, pure and static for the unit test: every model of the rotated shape at
## `at` must sit fully within the zone, off every blocker, inside the table rect.
static func validate(shape: Array, at: Vector3, rot: float, zone_c: Vector3, zone_m: float,
		blockers: Array, bounds: Rect2) -> bool:
	for s in shape:
		var sd := s as Dictionary
		var off := (sd["off"] as Vector2).rotated(rot)
		var r := float(sd["r"])
		var p := Vector3(at.x + off.x, 0.0, at.z + off.y)
		if p.distance_to(Vector3(zone_c.x, 0.0, zone_c.z)) + r > zone_m:
			return false   # base not FULLY within 6" of the transport (GF v3.5.1 p.15)
		if not bounds.has_point(Vector2(p.x, p.z)):
			return false
		for b in blockers:
			var bd := b as Dictionary
			var bp := bd["p"] as Vector3
			if Vector2(p.x, p.z).distance_to(Vector2(bp.x, bp.z)) < r + float(bd["r"]):
				return false
	return true


func begin(shape: Array, zone_c: Vector3, zone_m: float, blockers: Array, bounds: Rect2,
		commit: Callable, cancel: Callable) -> void:
	_shape = shape
	_zone_c = zone_c
	_zone_m = zone_m
	_blockers = blockers
	_bounds = bounds
	_commit = commit
	_cancel = cancel
	_cursor = zone_c
	for s in shape:
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = float((s as Dictionary)["r"])
		cyl.bottom_radius = cyl.top_radius
		cyl.height = 0.004
		disc.mesh = cyl
		disc.material_override = _mat(Color(0.3, 1.0, 0.4, 0.45))
		add_child(disc)
		_discs.append(disc)
	# The rule zone as a flat ring around the transport (the base-edge 6" boundary).
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(_zone_m - 0.004, 0.001)
	torus.outer_radius = _zone_m
	ring.mesh = torus
	ring.material_override = _mat(Color(0.4, 0.9, 1.0, 0.5))
	ring.position = Vector3(_zone_c.x, GHOST_Y, _zone_c.z)
	add_child(ring)
	set_process_unhandled_input(true)
	_refresh()


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func is_valid_now() -> bool:
	return validate(_shape, _cursor, _rot, _zone_c, _zone_m, _blockers, _bounds)


func placement_positions() -> Array:
	var out: Array = []
	for s in _shape:
		var off := ((s as Dictionary)["off"] as Vector2).rotated(_rot)
		out.append(Vector3(_cursor.x + off.x, 0.0, _cursor.z + off.y))
	return out


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var hit = Plane(Vector3.UP, 0.0).intersects_ray(
				cam.project_ray_origin((event as InputEventMouseMotion).position),
				cam.project_ray_normal((event as InputEventMouseMotion).position))
			if hit != null:
				_cursor = hit
				_refresh()
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key := event as InputEventKey
		if key.keycode == KEY_R:
			_rot = wrapf(_rot + ROT_STEP, 0.0, TAU)
			_refresh()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_ESCAPE:
			_finish(false)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and is_valid_now():
			_finish(true)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_finish(false)
			get_viewport().set_input_as_handled()


func _refresh() -> void:
	var ok := is_valid_now()
	var col := Color(0.3, 1.0, 0.4, 0.45) if ok else Color(1.0, 0.25, 0.2, 0.5)
	var pts := placement_positions()
	for i in _discs.size():
		var disc := _discs[i] as MeshInstance3D
		(disc.material_override as StandardMaterial3D).albedo_color = col
		if i < pts.size():
			var p := pts[i] as Vector3
			disc.position = Vector3(p.x, GHOST_Y, p.z)


func _finish(committed: bool) -> void:
	set_process_unhandled_input(false)
	if committed and _commit.is_valid():
		_commit.call(placement_positions())
	elif not committed and _cancel.is_valid():
		_cancel.call()
	queue_free()

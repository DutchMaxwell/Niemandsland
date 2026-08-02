class_name PlacementGhost
extends Node3D
## #210 (grilled 2026-07-30) — the cursor-placement ghost: a unit's formation SHAPE hangs at the
## mouse cursor, R rotates it in 15° steps, and every spot is validated live — each base fully
## inside the legal ZONE, off every other base, inside the table. Green = legal, red = not.
## LMB commits all models at once, RMB/ESC cancels. Pure visuals + input — the commit callback owns
## state, battle log and MP sync.
##
## The zone is DATA, not a hardcoded shape (see circle_zone / edge_strip_zone), because the two rules
## that place models at the cursor measure different things: a transport exit is "fully within 6\" of
## the transport" (a circle, GF v3.5.1 p.15), Reinforcement is "fully within 12\" of any table edge"
## (a border strip). The bounds and blocker clauses are shared by both.

const ROT_STEP := deg_to_rad(15.0)
const GHOST_Y := 0.012

var _shape: Array = []        # [{off: Vector2 (from formation centroid), r: float}] — chain order
var _zone: Dictionary = {}    # zone descriptor — see circle_zone()/edge_strip_zone()
var _blockers: Array = []     # [{p: Vector3, r: float}] — every other live base
var _bounds := Rect2()
var _commit: Callable
var _cancel: Callable
var _rot := 0.0
var _cursor := Vector3.ZERO
var _discs: Array = []
var _zone_visuals: Array = []   # ring/strip meshes — visual only, not touched by _refresh()


## Zone: the base must sit FULLY within `m` metres of the point `c` (transport disembark, GF v3.5.1 p.15).
## `m` must already include the anchor's own base radius, exactly as the disembark call site inflates it.
static func circle_zone(c: Vector3, m: float) -> Dictionary:
	return {"kind": "circle", "c": c, "m": m}


## Zone: the base must sit FULLY on the table AND FULLY within `m` metres of at least one table edge
## (the 12" border strip of the OPR rule "Reinforcement"). The strip is derived from the `bounds` rect
## validate() already carries, so the zone itself needs no extra geometry.
static func edge_strip_zone(m: float) -> Dictionary:
	return {"kind": "edge_strip", "m": m}


## Whether a base of radius `r` centred at `p` (world XZ) satisfies `zone`. Pure; `bounds` is the
## table rect (only the edge-strip zone reads it). An unknown/empty zone kind places no restriction.
static func zone_contains(zone: Dictionary, p: Vector3, r: float, bounds: Rect2) -> bool:
	var kind: String = String(zone.get("kind", ""))
	match kind:
		"circle":
			var c := zone["c"] as Vector3
			var m := float(zone["m"])
			return p.distance_to(Vector3(c.x, 0.0, c.z)) + r <= m
		"edge_strip":
			var m2 := float(zone["m"])
			if p.x - r < bounds.position.x or p.x + r > bounds.end.x:
				return false   # a model may not hang off the table
			if p.z - r < bounds.position.y or p.z + r > bounds.end.y:
				return false
			if (p.x + r) - bounds.position.x <= m2:   # left edge
				return true
			if bounds.end.x - (p.x - r) <= m2:         # right edge
				return true
			if (p.z + r) - bounds.position.y <= m2:    # top/near edge
				return true
			if bounds.end.y - (p.z - r) <= m2:         # bottom/far edge
				return true
			return false
		_:
			return true


## The rule check, pure and static for the unit test: every model of the rotated shape at
## `at` must sit fully within the zone, off every blocker, inside the table rect.
static func validate(shape: Array, at: Vector3, rot: float, zone: Dictionary,
		blockers: Array, bounds: Rect2) -> bool:
	for s in shape:
		var sd := s as Dictionary
		var off := (sd["off"] as Vector2).rotated(rot)
		var r := float(sd["r"])
		var p := Vector3(at.x + off.x, 0.0, at.z + off.y)
		if not zone_contains(zone, p, r, bounds):
			return false   # base not FULLY within the zone (GF v3.5.1 p.15 / OPR "Reinforcement")
		if not bounds.has_point(Vector2(p.x, p.z)):
			return false
		for b in blockers:
			var bd := b as Dictionary
			var bp := bd["p"] as Vector3
			if Vector2(p.x, p.z).distance_to(Vector2(bp.x, bp.z)) < r + float(bd["r"]):
				return false
	return true


func begin(shape: Array, zone: Dictionary, blockers: Array, bounds: Rect2,
		commit: Callable, cancel: Callable) -> void:
	_shape = shape
	_zone = zone
	_blockers = blockers
	_bounds = bounds
	_commit = commit
	_cancel = cancel
	match String(_zone.get("kind", "")):
		"circle":
			_cursor = _zone["c"] as Vector3
		_:
			_cursor = Vector3((bounds.position.x + bounds.end.x) / 2.0, 0.0,
				(bounds.position.y + bounds.end.y) / 2.0)
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
	match String(_zone.get("kind", "")):
		"circle":
			# The rule zone as a flat ring around the transport (the base-edge 6" boundary).
			var zone_c := _zone["c"] as Vector3
			var zone_m := float(_zone["m"])
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = maxf(zone_m - 0.004, 0.001)
			torus.outer_radius = zone_m
			ring.mesh = torus
			ring.material_override = _mat(Color(0.4, 0.9, 1.0, 0.5))
			ring.position = Vector3(zone_c.x, GHOST_Y, zone_c.z)
			add_child(ring)
			_zone_visuals.append(ring)
		"edge_strip":
			# The rule zone as four flat bands hugging each table edge (the 12" Reinforcement strip).
			var m := float(_zone["m"])
			var w: float = bounds.size.x
			var d: float = bounds.size.y
			var bands := [
				# [size (x depth, z span), position]
				[Vector2(m, d), Vector3(bounds.position.x + m / 2.0, GHOST_Y, bounds.position.y + d / 2.0)],
				[Vector2(m, d), Vector3(bounds.end.x - m / 2.0, GHOST_Y, bounds.position.y + d / 2.0)],
				[Vector2(w, m), Vector3(bounds.position.x + w / 2.0, GHOST_Y, bounds.position.y + m / 2.0)],
				[Vector2(w, m), Vector3(bounds.position.x + w / 2.0, GHOST_Y, bounds.end.y - m / 2.0)],
			]
			for band in bands:
				var sz := band[0] as Vector2
				var pos := band[1] as Vector3
				var strip := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(sz.x, 0.004, sz.y)
				strip.mesh = box
				strip.material_override = _mat(Color(0.4, 0.9, 1.0, 0.5))
				strip.position = pos
				add_child(strip)
				_zone_visuals.append(strip)
	set_process_unhandled_input(true)
	_refresh()


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func is_valid_now() -> bool:
	return validate(_shape, _cursor, _rot, _zone, _blockers, _bounds)


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

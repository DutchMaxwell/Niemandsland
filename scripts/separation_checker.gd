class_name SeparationChecker
extends RefCounted
## OPR enemy-separation distance math: edge-to-edge distance between two models'
## BASES (round / oval / rectangular regiment tray), and the 1" "too close to an
## enemy" test that drives the non-modal proximity hint.
##
## OPR RULE (authoritative wording): "Models may never be within 1” of models from
## other units, unless they are taking a Charge action, and may never move through
## other models or units (friendly or enemy), even if they are taking a Charge
## action." — Grimdark Future: Advanced Rules v3.5.1, p.7 ("General Movement");
## identical wording in Age of Fantasy: Advanced Rules v3.5.1, p.7 ("General
## Movement"). This module MEASURES that 1" gap; it never enforces it — Niemandsland
## is a "show, don't decide" simulator (see CODING_STANDARDS §4).
##
## MELEE EXCEPTION: base contact (edge gap <= BASE_CONTACT_EPSILON_INCHES) is an
## intentional Charge into melee, which the rule explicitly exempts ("...unless they
## are taking a Charge action"). A model is only flagged when it sits within 1" of an
## enemy base WITHOUT touching it.
##
## OWNERSHIP SEAM (enemy determination): army affiliation is read from
## GameUnit.unit_properties["player_id"] — the durable per-army slot stamped at OPR
## import (opr_army_manager.import_army_for_player / _spawn_unit). Two models are
## enemies iff their units carry DIFFERENT, KNOWN player_ids (are_enemy_players).
## This is deliberately army-affiliation, NOT multiplayer peer ownership: in
## hotseat/sandbox one human moves both armies, yet the 1" rule binds both sides, so
## the hint must fire regardless of who holds the mouse (works identically in SP,
## hotseat and MP; strictly local — no RPCs). Unknown affiliation (missing / <= 0
## player_id) is treated as not-comparable -> no warning (never a false warning).
##
## PURE + STATELESS + REUSABLE: every function is static. The per-pair geometry path
## (edge_distance / is_base_contact / is_separation_violation for round, oval and
## round-vs-rect) is allocation-free — only stack floats / Vector2 — so the upcoming
## solo-AI movement planner can call it at scale. Build one BaseShape per model up
## front (shape_for_model), cache it, and only refresh center/yaw as the model moves.
##
## PRECISION: round-vs-round and round-vs-rect are exact. Oval-involved pairs
## (oval-oval, oval-round, oval-rect) use the directional support-function measured
## along the line joining the two base centres — the same base-edge-to-base-edge
## convention the in-game measurement tool and CoherencyChecker already use. It is
## exact when the closest approach lies on that centre line (always for two circles;
## for elongated bases when they face along it) and stays sub-2 mm for real base
## sizes at oblique offsets. Rect-vs-rect is exact (convex geometry). See
## _edge_distance_meters for the case split.

# ===== Constants =====

## Inches -> metres (CODING_STANDARDS §2.2; shared with coherency_checker.gd et al.).
const INCHES_TO_METERS := 0.0254

## Millimetres -> metres (base sizes are authored in mm; see OPRUnit.get_base_radius_meters).
const MM_TO_METERS := 0.001

## OPR enemy-separation threshold. GF/AoF Advanced Rules v3.5.1, p.7 "General
## Movement": models may never be within 1" of models from other units (unless
## charging). A gap of exactly 1" or more is compliant.
const SEPARATION_DISTANCE_INCHES := 1.0

## Base-contact tolerance (inches). An edge gap at or below this counts as base-to-
## base contact = an intentional Charge into melee, which the 1" rule exempts
## ("...unless they are taking a Charge action"). Kept small (~1.3 mm) so a genuine
## sub-1" illegal gap still registers, while float noise, the drag-lift, and hand-
## placement jitter at true contact do not read as a violation.
const BASE_CONTACT_EPSILON_INCHES := 0.05

## Default base radius (metres) when a model's unit properties are unknown — 32 mm
## diameter, matching CoherencyChecker's fallback so the two systems agree.
const DEFAULT_BASE_RADIUS_M := 0.016

## Fallback base long edge (mm) when unit properties are missing.
const DEFAULT_BASE_MM := 32

## Numerical guard for near-zero lengths / denominators (metres).
const EPSILON_M := 0.00001


# ===== Base Shape =====

## Description of a model's base footprint on the table, in metres in world XZ.
## Round infantry, oval cavalry/vehicles, and rectangular regiment trays. `center`
## and `yaw` change as the model moves; the extents are fixed per model — so callers
## build one BaseShape per model and only refresh center/yaw each frame.
class BaseShape:
	enum Kind { ROUND, OVAL, RECT }

	var kind: int = Kind.ROUND
	var center: Vector2 = Vector2.ZERO   # world XZ (metres)
	var yaw: float = 0.0                  # rotation about world Y (radians); OVAL/RECT only
	var radius: float = 0.0             # ROUND: base radius (metres)
	var semi_x: float = 0.0            # OVAL/RECT: half-extent along local X (metres)
	var semi_z: float = 0.0            # OVAL/RECT: half-extent along local Z (metres)

	## Round base of the given radius (metres).
	static func make_round(center_xz: Vector2, radius_m: float) -> BaseShape:
		var s := BaseShape.new()
		s.kind = Kind.ROUND
		s.center = center_xz
		s.radius = maxf(0.0, radius_m)
		return s

	## Oval base with half-axes semi_x (local X) / semi_z (local Z), rotated by yaw.
	static func make_oval(center_xz: Vector2, yaw_rad: float, semi_x_m: float, semi_z_m: float) -> BaseShape:
		var s := BaseShape.new()
		s.kind = Kind.OVAL
		s.center = center_xz
		s.yaw = yaw_rad
		s.semi_x = maxf(0.0, semi_x_m)
		s.semi_z = maxf(0.0, semi_z_m)
		return s

	## Rectangular base with half-extents semi_x (local X) / semi_z (local Z), rotated by yaw.
	static func make_rect(center_xz: Vector2, yaw_rad: float, semi_x_m: float, semi_z_m: float) -> BaseShape:
		var s := BaseShape.new()
		s.kind = Kind.RECT
		s.center = center_xz
		s.yaw = yaw_rad
		s.semi_x = maxf(0.0, semi_x_m)
		s.semi_z = maxf(0.0, semi_z_m)
		return s

	## Radius of a circle centred on `center` that fully encloses the base (metres).
	## Used for the O(1) spatial pre-filter so far-apart bases are pruned with a
	## distance_squared compare before any exact geometry runs.
	func bounding_radius() -> float:
		if kind == Kind.ROUND:
			return radius
		return sqrt(semi_x * semi_x + semi_z * semi_z)


# ===== Public API (pure geometry) =====

## Edge-to-edge gap between two bases, in INCHES. Negative when the bases overlap.
## See the class header for the per-shape precision guarantees.
static func edge_distance(a: BaseShape, b: BaseShape) -> float:
	if a == null or b == null:
		return INF
	return _edge_distance_meters(a, b) / INCHES_TO_METERS


## True when the two bases touch (edge gap <= epsilon inches) — i.e. base contact,
## which the OPR rule treats as an intentional Charge into melee (exempt from the 1"
## separation). Overlap (negative gap) also counts as contact.
static func is_base_contact(a: BaseShape, b: BaseShape, epsilon_inches: float = BASE_CONTACT_EPSILON_INCHES) -> bool:
	if a == null or b == null:
		return false
	return edge_distance(a, b) <= epsilon_inches


## True when `b` is an enemy-separation VIOLATION relative to `a`: within 1" but not
## in base contact (the melee exception). This is exactly the proximity-hint trigger.
## Geometry only — the caller decides enemy affiliation via are_enemy_players().
static func is_separation_violation(a: BaseShape, b: BaseShape, epsilon_inches: float = BASE_CONTACT_EPSILON_INCHES) -> bool:
	if a == null or b == null:
		return false
	var gap := edge_distance(a, b)
	return gap > epsilon_inches and gap < SEPARATION_DISTANCE_INCHES


## Whether two army-affiliation slots are enemies: different AND both known.
## player_id <= 0 (or missing) is "unknown" -> not comparable -> false, so an
## un-affiliated model never produces a false warning (deliverable requirement).
static func are_enemy_players(player_id_a: int, player_id_b: int) -> bool:
	if player_id_a <= 0 or player_id_b <= 0:
		return false
	return player_id_a != player_id_b


## Builds the BaseShape for a live ModelInstance from its unit's base properties,
## mirroring CoherencyChecker's per-model base sizing (a Tough / weapon-team upgrade
## enlarges THIS model's base above the unit baseline; plain models scale 1.0). The
## world position and yaw come from the model's node. Returns null if the node is
## gone. This is the seam the game integration and the AI planner use to obtain a
## shape they can then cache.
static func shape_for_model(model: ModelInstance) -> BaseShape:
	if model == null or model.node == null or not is_instance_valid(model.node):
		return null
	var node := model.node
	var center := Vector2(node.global_position.x, node.global_position.z)
	var yaw := node.global_rotation.y

	var game_unit := model.unit as GameUnit
	if game_unit == null or game_unit.unit_properties == null:
		return BaseShape.make_round(center, DEFAULT_BASE_RADIUS_M)

	var props: Dictionary = game_unit.unit_properties
	var model_tough: int = int(model.properties.get("tough", 1)) if model.properties else 1

	if props.get("base_is_oval", false):
		var width_mm: int = int(props.get("base_width_mm", DEFAULT_BASE_MM))
		var depth_mm: int = int(props.get("base_depth_mm", DEFAULT_BASE_MM))
		var unit_long: int = maxi(width_mm, depth_mm)
		var scale: float = float(OPRArmyManager.model_base_long_mm(unit_long, model_tough)) / float(maxi(1, unit_long))
		var semi_x: float = (width_mm / 2.0) * MM_TO_METERS * scale
		var semi_z: float = (depth_mm / 2.0) * MM_TO_METERS * scale
		return BaseShape.make_oval(center, yaw, semi_x, semi_z)

	var base_mm: int = int(props.get("base_size_round", DEFAULT_BASE_MM))
	var scale_round: float = float(OPRArmyManager.model_base_long_mm(base_mm, model_tough)) / float(maxi(1, base_mm))
	var radius: float = (base_mm / 2.0) * MM_TO_METERS * scale_round
	return BaseShape.make_round(center, radius)


# ===== Private Geometry =====

## Edge-to-edge gap in METRES (negative when overlapping). Case split by base kinds:
##  - round-round: exact (centre distance minus both radii).
##  - any rect: exact closest-point geometry (rects have corners the centre-line
##    method would misjudge) — see _gap_with_rect.
##  - oval-involved (oval-oval / oval-round): directional support along the centre
##    line (documented approximation, matches the measurement tool / coherency).
static func _edge_distance_meters(a: BaseShape, b: BaseShape) -> float:
	if a.kind == BaseShape.Kind.RECT or b.kind == BaseShape.Kind.RECT:
		return _gap_with_rect(a, b)

	if a.kind == BaseShape.Kind.ROUND and b.kind == BaseShape.Kind.ROUND:
		return a.center.distance_to(b.center) - a.radius - b.radius

	var d := b.center - a.center
	var center_dist := d.length()
	if center_dist < EPSILON_M:
		return -minf(_min_extent(a), _min_extent(b))  # concentric -> overlapping
	var dir := d / center_dist
	return center_dist - _support_extent(a, dir) - _support_extent(b, -dir)


## Distance (metres) from `shape`'s centre to its boundary in unit-direction `dir`
## (world XZ). Exact per shape; used by the directional (centre-line) method.
static func _support_extent(shape: BaseShape, dir: Vector2) -> float:
	match shape.kind:
		BaseShape.Kind.ROUND:
			return shape.radius
		BaseShape.Kind.OVAL:
			var local := dir.rotated(-shape.yaw)
			var a := shape.semi_x
			var b := shape.semi_z
			# Ellipse radius along local (lx,lz): (a*b) / sqrt(b^2 lx^2 + a^2 lz^2).
			var denom := sqrt(b * b * local.x * local.x + a * a * local.y * local.y)
			if denom < EPSILON_M:
				return (a + b) * 0.5
			return (a * b) / denom
		BaseShape.Kind.RECT:
			var local2 := dir.rotated(-shape.yaw)
			var lx := absf(local2.x)
			var lz := absf(local2.y)
			var tx := INF if lx < EPSILON_M else shape.semi_x / lx
			var tz := INF if lz < EPSILON_M else shape.semi_z / lz
			return minf(tx, tz)
	return 0.0


## Smallest half-extent (metres) — only used for the concentric-overlap fallback.
static func _min_extent(shape: BaseShape) -> float:
	if shape.kind == BaseShape.Kind.ROUND:
		return shape.radius
	return minf(shape.semi_x, shape.semi_z)


## Edge-to-edge gap (metres) when at least one base is a rectangle.
static func _gap_with_rect(a: BaseShape, b: BaseShape) -> float:
	if a.kind == BaseShape.Kind.RECT and b.kind == BaseShape.Kind.RECT:
		return _rect_rect_gap(a, b)

	var rect := a if a.kind == BaseShape.Kind.RECT else b
	var other := b if a.kind == BaseShape.Kind.RECT else a

	if other.kind == BaseShape.Kind.ROUND:
		# Exact: closest point on the rotated rectangle to the circle centre, minus r.
		var cp := _closest_point_on_rect(rect, other.center)
		return cp.distance_to(other.center) - other.radius

	# rect + oval: directional support (documented approximation — rare pairing).
	var d := other.center - rect.center
	var center_dist := d.length()
	if center_dist < EPSILON_M:
		return -minf(_min_extent(rect), _min_extent(other))
	var dir := d / center_dist
	return center_dist - _support_extent(rect, dir) - _support_extent(other, -dir)


## Closest point (world XZ) on a rotated rectangle to an external point.
static func _closest_point_on_rect(rect: BaseShape, point: Vector2) -> Vector2:
	var local := (point - rect.center).rotated(-rect.yaw)
	var clamped := Vector2(
		clampf(local.x, -rect.semi_x, rect.semi_x),
		clampf(local.y, -rect.semi_z, rect.semi_z))
	return rect.center + clamped.rotated(rect.yaw)


## Exact edge-to-edge gap (metres) between two rotated rectangles. 0.0 when they
## overlap (base contact). NOTE: this path builds two 4-corner arrays — it is off the
## per-frame hot path (the game drives regiments from their per-member round/oval
## bases; rect-rect is for the module's completeness and the AI planner).
static func _rect_rect_gap(a: BaseShape, b: BaseShape) -> float:
	var ca := _rect_corners(a)
	var cb := _rect_corners(b)
	if _rects_overlap(a, b, ca, cb):
		return 0.0
	var best := INF
	for p in ca:
		best = minf(best, _min_point_to_edges(p, cb))
	for p in cb:
		best = minf(best, _min_point_to_edges(p, ca))
	return best


## The four world-space corners of a rectangular base, CCW in local frame.
static func _rect_corners(rect: BaseShape) -> Array[Vector2]:
	var sx := rect.semi_x
	var sz := rect.semi_z
	return [
		rect.center + Vector2(sx, sz).rotated(rect.yaw),
		rect.center + Vector2(-sx, sz).rotated(rect.yaw),
		rect.center + Vector2(-sx, -sz).rotated(rect.yaw),
		rect.center + Vector2(sx, -sz).rotated(rect.yaw),
	]


## Separating-axis test for two rectangles (their four unique edge normals). Returns
## true when the rectangles overlap (no separating axis exists).
static func _rects_overlap(a: BaseShape, b: BaseShape, ca: Array[Vector2], cb: Array[Vector2]) -> bool:
	var axes: Array[Vector2] = [
		Vector2(1.0, 0.0).rotated(a.yaw),
		Vector2(0.0, 1.0).rotated(a.yaw),
		Vector2(1.0, 0.0).rotated(b.yaw),
		Vector2(0.0, 1.0).rotated(b.yaw),
	]
	for axis in axes:
		var a_range := _project_range(ca, axis)
		var b_range := _project_range(cb, axis)
		# Separated on this axis -> no overlap.
		if a_range.y < b_range.x or b_range.y < a_range.x:
			return false
	return true


## Projects corners onto an axis, returning Vector2(min, max) of the dot products.
static func _project_range(corners: Array[Vector2], axis: Vector2) -> Vector2:
	var lo := INF
	var hi := -INF
	for c in corners:
		var d := c.dot(axis)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return Vector2(lo, hi)


## Minimum distance from a point to the four edges of a rectangle's corner list.
static func _min_point_to_edges(p: Vector2, corners: Array[Vector2]) -> float:
	var best := INF
	var n := corners.size()
	for i in range(n):
		var s1: Vector2 = corners[i]
		var s2: Vector2 = corners[(i + 1) % n]
		best = minf(best, _point_segment_distance(p, s1, s2))
	return best


## Shortest distance from point `p` to segment `s1`-`s2`.
static func _point_segment_distance(p: Vector2, s1: Vector2, s2: Vector2) -> float:
	var seg := s2 - s1
	var len_sq := seg.length_squared()
	if len_sq < EPSILON_M * EPSILON_M:
		return p.distance_to(s1)
	var t := clampf((p - s1).dot(seg) / len_sq, 0.0, 1.0)
	var proj := s1 + seg * t
	return p.distance_to(proj)

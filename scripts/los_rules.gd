class_name LosRules
extends RefCounted
## Asgard tournament-standard line-of-sight helpers (Asgard Age of Fantasy, p.5):
## derive a model's Height category (1-6) from its profile. Pure/static so it is
## trivially testable and has no scene dependencies. The grid LOS query itself
## lives in terrain_overlay.gd (it owns the terrain grid).
##
## Height categories (Asgard p.5):
##   H1 Swarms
##   H2 Infantry / Artillery: no Tough; Heroes with Tough(3)
##   H3 Large Infantry / Cavalry / Chariots: Tough(3); Heroes with Tough(6)
##   H4 Large Cavalry / Monsters / Vehicles: Tough(6-9); Heroes with Tough(9)
##   H5 Large Monsters / Giants / Large Vehicles: Tough(12+)
##   H6 Titans: Tough(18+) and Fear

const HEIGHT_INFANTRY := 2  # default when no profile is available

## Asgard: gaps narrower than 1" between models of the SAME unit count as closed —
## a line of sight cannot thread through an (almost) closed formation.
const CLOSED_GAP_INCHES := 1.0
const INCHES_TO_METERS := 0.0254
## Fallback base radius (16 mm = half a 32 mm round base) for models without data.
const DEFAULT_BASE_RADIUS_M := 0.016


## One model considered as a 2D line-of-sight blocker on the table: base footprint
## (circle approximation; ovals use their mean radius — a display aid, not rules
## resolution), Asgard Height category and the owning unit (instance id) so a
## unit never blocks its own sight lines and gap-closure stays per-unit.
class Blocker:
	var pos: Vector2
	var radius: float
	var height: int
	var unit_key: int

	func _init(p_pos: Vector2, p_radius: float, p_height: int, p_unit_key: int) -> void:
		pos = p_pos
		radius = p_radius
		height = p_height
		unit_key = p_unit_key


## Asgard Height category (1-6) of a single model, derived from Tough + Hero/Fear.
## Category nuances we cannot read from the API (Swarm/Cavalry/Artillery) are
## approximated via Tough; this is faithful for the common cases and only matters
## for unit-as-blocker LOS (a later phase).
static func model_height_category(model: ModelInstance) -> int:
	if model == null:
		return HEIGHT_INFANTRY
	var tough: int = int(model.get_property("tough", 1))
	var is_hero: bool = model.has_special_rule("Hero")
	var has_fear: bool = model.has_special_rule("Fear")

	if tough >= 18 and has_fear:
		return 6
	if tough >= 12:
		return 5
	if tough >= 6:
		# Tough 6-11: monsters/vehicles are H4; a Hero of Tough(6) is one step smaller.
		return 3 if (is_hero and tough <= 6) else 4
	if tough >= 3:
		# Tough 3-5: large infantry/cavalry are H3; a Hero of Tough(3) is H2.
		return 2 if is_hero else 3
	return HEIGHT_INFANTRY  # no/low Tough -> infantry / artillery


## Mean base radius (metres) of a model for the 2D blocker footprint. Round bases
## use their real radius; ovals their mean semi-axis (circle approximation is
## enough for a display aid). Falls back to half a 32 mm base without unit data.
static func model_base_radius_m(model: ModelInstance) -> float:
	if model == null or model.unit == null:
		return DEFAULT_BASE_RADIUS_M
	var game_unit = model.unit
	if game_unit.unit_properties == null:
		return DEFAULT_BASE_RADIUS_M
	var props: Dictionary = game_unit.unit_properties
	if props.get("base_is_oval", false):
		var width_mm: float = props.get("base_width_mm", 32)
		var depth_mm: float = props.get("base_depth_mm", 32)
		return (width_mm + depth_mm) / 4.0 * 0.001
	return float(props.get("base_size_round", 32)) / 2.0 * 0.001


## Top-down unit-as-LOS-blocker check (Asgard tournament standard: units block
## line of sight at their Height; gaps of less than 1" between models of the
## same unit count as CLOSED). A blocker stops the line only when its Height is
## >= BOTH endpoints' Height categories (the taller one sees over it), and the
## units at the line's endpoints never block their own sight line
## (exclude_units carries their instance ids). Display-only, like terrain LOS.
static func units_block_line(from_pos: Vector2, to_pos: Vector2,
		from_height: int, to_height: int,
		blockers: Array[Blocker], exclude_units: Array[int]) -> bool:
	var closed_gap_m := CLOSED_GAP_INCHES * INCHES_TO_METERS

	# Per-unit grouping for the gap-closure pass below.
	var by_unit: Dictionary = {}  # Dictionary[int, Array[Blocker]]

	for blocker: Blocker in blockers:
		if exclude_units.has(blocker.unit_key):
			continue
		if blocker.height < from_height or blocker.height < to_height:
			continue  # both endpoints see over it
		if segment_intersects_circle(from_pos, to_pos, blocker.pos, blocker.radius):
			return true
		if not by_unit.has(blocker.unit_key):
			by_unit[blocker.unit_key] = []
		by_unit[blocker.unit_key].append(blocker)

	# Closed-gap pass: a <1" gap between two models of the same unit is a wall —
	# the line is blocked even when it threads BETWEEN the two bases. The wall's
	# height is the LOWER of the pair (a line can pass over the smaller model).
	for unit_key: int in by_unit:
		var models: Array = by_unit[unit_key]
		for i: int in models.size():
			for j: int in range(i + 1, models.size()):
				var a: Blocker = models[i]
				var b: Blocker = models[j]
				var gap: float = a.pos.distance_to(b.pos) - a.radius - b.radius
				if gap >= closed_gap_m:
					continue
				if mini(a.height, b.height) < from_height or mini(a.height, b.height) < to_height:
					continue
				if segments_intersect(from_pos, to_pos, a.pos, b.pos):
					return true
	return false


## True if the segment from->to passes through (or touches) the circle.
static func segment_intersects_circle(from_pos: Vector2, to_pos: Vector2,
		center: Vector2, radius: float) -> bool:
	var seg := to_pos - from_pos
	var seg_len_sq := seg.length_squared()
	var t := 0.0
	if seg_len_sq > 0.0:
		t = clampf((center - from_pos).dot(seg) / seg_len_sq, 0.0, 1.0)
	var closest := from_pos + seg * t
	return closest.distance_to(center) <= radius


## True if segments a1->a2 and b1->b2 intersect (touching counts).
static func segments_intersect(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	return Geometry2D.segment_intersects_segment(a1, a2, b1, b2) != null


## Regiments (Age of Fantasy: Regiments): line of sight is only to the unit's FRONT.
## The front arc is the hemisphere ahead of the unit's facing (the base's front
## facing → 180° total, half-angle 90°). Tunable; this is the conventional "front
## facing" reading and is a display aid, not verified against a specific rules page.
const FRONT_ARC_HALF_ANGLE_DEG := 90.0

## True if `target` lies within `half_angle_deg` of the `facing` direction as seen
## from `origin` (all 2D / top-down XZ). Used for the Regiments "LOS toward front"
## aid. Degenerate inputs (target on the origin, zero facing) return true.
static func is_in_front_arc(origin: Vector2, facing: Vector2, target: Vector2,
		half_angle_deg: float = FRONT_ARC_HALF_ANGLE_DEG) -> bool:
	var to_target := target - origin
	if to_target.length_squared() < 0.000001:
		return true
	var f := facing.normalized()
	if f.length_squared() < 0.000001:
		return true
	return f.dot(to_target.normalized()) >= cos(deg_to_rad(half_angle_deg))

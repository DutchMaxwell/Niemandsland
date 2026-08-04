extends GdUnitTestSuite
## SightFan — the sight+range fan's ray semantics against the maintainer's sketch spec, now read off the
## ONE volumetric sight truth: rays start at the BASE EDGE, a solid volume blocks at entry, AREA volumes
## are see-INTO-not-THROUGH (one foreign zone, your own zone free), and — the elevation program's win —
## the ray is fired from the model's REAL eye height, so a model on a container roof looks over its box
## instead of being walled in by it (NML-968).
##
## Every helper is defensive (empty polygon → sentinel −1) so a broken fan fails as an ASSERTION instead
## of aborting the suite on an out-of-bounds read.

const K := VolumetricLos.INCHES_TO_METERS
const EYE_1IN := 1.0 * K        # a 1" infantry model standing on the table looks from here
const CONTAINER_IN := 2.5       # the real container height
const NO_REACH := -1.0          # sentinel: the fan produced no vertex at all


## A terrain volume as a band across the +x ray: x from `x0` to `x1`, full depth in z.
func _band(x0: float, x1: float, height_in: float, solid: bool) -> Dictionary:
	return {"kind": "box", "c": Vector2((x0 + x1) * 0.5, 0.0), "he": Vector2((x1 - x0) * 0.5, 1.0),
		"yaw": 0.0, "y0": 0.0, "y1": height_in * K, "solid": solid}


## The fan vertex pointing along +x (ray k=0) — its distance from the ray start (= the base edge).
func _reach_x(eye: Vector3, base_r: float, range_m: float, volumes: Array) -> float:
	var poly := SightFan.fan_polygon(eye, base_r, range_m, volumes, 8)
	if poly.size() < 1:
		return NO_REACH
	return (poly[0] - (Vector2(eye.x, eye.z) + Vector2(base_r, 0.0))).length()


func test_open_ground_reaches_full_range_from_base_edge() -> void:
	var reach := _reach_x(Vector3(0.0, EYE_1IN, 0.0), 0.016, 0.6, [])
	assert_float(reach).is_equal_approx(0.6, 0.001)


func test_a_solid_band_stops_the_ray_at_its_near_face() -> void:
	# A 2.5"-tall wall slab at x = 0.30: the ray ends there, one march-refinement (~2.4mm) short.
	var reach := _reach_x(Vector3(0.0, EYE_1IN, 0.0), 0.016, 0.6, [_band(0.30, 0.31, CONTAINER_IN, true)])
	assert_float(reach).is_equal_approx(0.30 - 0.016, 0.004)


func test_container_blocks_at_entry_no_see_into() -> void:
	var reach := _reach_x(Vector3(0.0, EYE_1IN, 0.0), 0.0, 0.6, [_band(0.3, 0.5, CONTAINER_IN, true)])
	assert_float(reach).is_less(0.31)
	assert_float(reach).is_greater(0.2)


func test_forest_is_seen_into_but_not_through() -> void:
	# Forest band 0.2..0.4 (3.4" tall AREA volume): visible INTO it (the fan reaches past 0.25) but it
	# ends at the far edge (< 0.45), never the full 0.8 range — "Ziele mit Deckung" inside, "nicht
	# gesehen" beyond (the sketch).
	var reach := _reach_x(Vector3(0.0, EYE_1IN, 0.0), 0.0, 0.8, [_band(0.2, 0.4, 3.4, false)])
	assert_float(reach).is_greater(0.25)
	assert_float(reach).is_less(0.45)


func test_second_foreign_zone_is_not_entered() -> void:
	# Two forest bands with a gap: the ray sees into band 1, stops at its far edge — it must never reach
	# band 2 (that would be "through" the first zone to a spot before the second).
	var reach := _reach_x(Vector3(0.0, EYE_1IN, 0.0), 0.0, 1.2,
		[_band(0.2, 0.4, 3.4, false), _band(0.6, 0.8, 3.4, false)])
	assert_float(reach).is_less(0.45)


func test_origin_inside_forest_sees_out_and_into_one_more_zone() -> void:
	# Eye at x=0.1 INSIDE forest band 0.0..0.2 (see out of the own zone), open until 0.5, ruin band
	# 0.5..0.7 (see INTO it), stop at its far edge — not the full 1.2 range.
	var reach := _reach_x(Vector3(0.1, EYE_1IN, 0.0), 0.0, 1.2,
		[_band(0.0, 0.2, 3.4, false), _band(0.5, 0.7, 6.0, false)])
	assert_float(reach).is_greater(0.45)   # sees out + across the open ground + into the ruin
	assert_float(reach).is_less(0.75)      # but never beyond the ruin's far edge


# =====================================================================================
# NML-968 (elevation program, Phase A / W4.18) — the fan reads the height it looks from.
# =====================================================================================
# The container below spans x ∈ [-0.20, 0.00]; the model stands ON its roof 5 mm inside the far edge,
# so along +x its own box lies BEHIND the eye. The eye-to-target line only sinks under the 2.5" roof
# line well past that edge, so it clears the box geometrically — no exemption involved. (A model in the
# MIDDLE of a roof still loses the strip of ground hugging its box: that shadow is real, and the ray
# stops at the first blocked sample by design.)

const ROOF_BOX := {"kind": "box", "c": Vector2(-0.1, 0.0), "he": Vector2(0.1, 0.1), "yaw": 0.0,
	"y0": 0.0, "y1": CONTAINER_IN * K, "solid": true}


func test_a_ground_model_before_the_container_stays_blocked() -> void:
	# CONTROL — same box, a model on the TABLE in front of it: still walled in, before and after the
	# migration. Without this the elevated case below could pass on an empty volume list.
	var reach := _reach_x(Vector3(-0.35, EYE_1IN, 0.0), 0.016, 0.6, [ROOF_BOX])
	assert_float(reach) \
		.override_failure_message("control fixture: a ground model must not see through a solid container") \
		.is_less(0.15)


func test_a_model_on_the_container_roof_sees_beyond_its_own_box() -> void:
	var eye := Vector3(-0.005, CONTAINER_IN * K + EYE_1IN, 0.0)   # standing on the roof, 1" tall
	var reach := _reach_x(eye, 0.016, 0.6, [ROOF_BOX])
	assert_float(reach) \
		.override_failure_message("NML-968 — the fan fires every ray from table level, so a model standing " +
			"ON a container is walled in by the very box it stands on and gets no fan at all " +
			"(SightFan.fan_polygon ignores the eye's height).") \
		.is_greater(0.5)


func test_union_merges_overlapping_fans() -> void:
	var a := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var b := PackedVector2Array([Vector2(0.5, 0), Vector2(1.5, 0), Vector2(1.5, 1), Vector2(0.5, 1)])
	var far := PackedVector2Array([Vector2(5, 5), Vector2(6, 5), Vector2(6, 6), Vector2(5, 6)])
	var merged := SightFan.union_fans([a, b, far])
	assert_int(merged.size()).is_equal(2)   # a+b merge into one outline; far stays separate

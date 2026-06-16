extends GdUnitTestSuite
## Persistent shared rulers: PinnedRuler's segment-distance helper (right-click hit-test)
## and the PinnedRulers manager (add/remove/clear-by-owner/nearest/colour/serialize).
## Pure logic — instantiates nodes but needs no rendering.

const PinnedRulerScript := preload("res://scripts/pinned_ruler.gd")
const PinnedRulersScript := preload("res://scripts/pinned_rulers.gd")


func _manager() -> PinnedRulers:
	var m: PinnedRulers = auto_free(PinnedRulersScript.new())
	add_child(m)
	return m


func _ruler(from_pos: Vector3, to_pos: Vector3) -> PinnedRuler:
	var r: PinnedRuler = auto_free(PinnedRulerScript.new())
	r.setup(1, 1, from_pos, to_pos, 39.4, false, Color.WHITE)
	return r


func _add(m: PinnedRulers, id: int, owner: int, from_pos: Vector3, to_pos: Vector3,
		blocked: bool = false) -> void:
	m.add_ruler(id, owner, from_pos, to_pos, 6.0, blocked)


# === PinnedRuler.distance_to_point (XZ segment distance) ===

func test_distance_on_segment_is_zero() -> void:
	var r := _ruler(Vector3(0, 0.02, 0), Vector3(1, 0.02, 0))
	assert_float(r.distance_to_point(Vector3(0.5, 0.0, 0.0))).is_less(0.0001)


func test_distance_perpendicular_offset() -> void:
	var r := _ruler(Vector3(0, 0.02, 0), Vector3(1, 0.02, 0))
	assert_float(r.distance_to_point(Vector3(0.5, 0.0, 0.1))).is_equal_approx(0.1, 0.0001)


func test_distance_beyond_endpoint_clamps() -> void:
	var r := _ruler(Vector3(0, 0.02, 0), Vector3(1, 0.02, 0))
	assert_float(r.distance_to_point(Vector3(1.2, 0.0, 0.0))).is_equal_approx(0.2, 0.0001)


# === PinnedRulers manager ===

func test_add_and_count() -> void:
	var m := _manager()
	_add(m, 1, 1, Vector3.ZERO, Vector3(0.1, 0, 0))
	_add(m, 2, 2, Vector3.ZERO, Vector3(0.1, 0, 0))
	assert_int(m.ruler_count()).is_equal(2)


func test_add_same_id_replaces() -> void:
	var m := _manager()
	_add(m, 7, 1, Vector3.ZERO, Vector3(0.1, 0, 0))
	_add(m, 7, 1, Vector3.ZERO, Vector3(0.2, 0, 0))
	assert_int(m.ruler_count()).is_equal(1)


func test_remove() -> void:
	var m := _manager()
	_add(m, 1, 1, Vector3.ZERO, Vector3(0.1, 0, 0))
	m.remove_ruler(1)
	assert_int(m.ruler_count()).is_equal(0)


func test_clear_owner_removes_only_that_owner() -> void:
	var m := _manager()
	_add(m, 1, 1, Vector3.ZERO, Vector3(0.1, 0, 0))
	_add(m, 2, 2, Vector3.ZERO, Vector3(0.1, 0, 0))
	_add(m, 3, 1, Vector3.ZERO, Vector3(0.1, 0, 0))
	m.clear_owner(1)
	assert_int(m.ruler_count()).is_equal(1)
	assert_int(m.ruler_owner(2)).is_equal(2)


func test_clear_all() -> void:
	var m := _manager()
	_add(m, 1, 1, Vector3.ZERO, Vector3(0.1, 0, 0))
	_add(m, 2, 2, Vector3.ZERO, Vector3(0.1, 0, 0))
	m.clear_all()
	assert_int(m.ruler_count()).is_equal(0)


func test_color_for_owner() -> void:
	var m := _manager()
	assert_bool(m.color_for_owner(1) == PinnedRulers.OWNER_COLORS[1]).is_true()
	assert_bool(m.color_for_owner(99) == PinnedRulers.SOLO_COLOR).is_true()


func test_nearest_ruler_within_tolerance() -> void:
	var m := _manager()
	_add(m, 5, 1, Vector3(0, 0.02, 0), Vector3(1, 0.02, 0))
	# 1 cm off the segment is within a 2 cm pick tolerance; 10 cm off is not.
	assert_int(m.nearest_ruler_at(Vector3(0.5, 0, 0.01), 0.02)).is_equal(5)
	assert_int(m.nearest_ruler_at(Vector3(0.5, 0, 0.1), 0.02)).is_equal(-1)


func test_nearest_ruler_owner_filter() -> void:
	var m := _manager()
	_add(m, 1, 1, Vector3(0, 0.02, 0), Vector3(1, 0.02, 0))  # owner 1
	# Filtering to owner 2 finds nothing on owner 1's line; filtering to owner 1 finds it.
	assert_int(m.nearest_ruler_at(Vector3(0.5, 0, 0.0), 0.02, 2)).is_equal(-1)
	assert_int(m.nearest_ruler_at(Vector3(0.5, 0, 0.0), 0.02, 1)).is_equal(1)


func test_serialize_restore_roundtrip() -> void:
	var m := _manager()
	_add(m, 10, 2, Vector3(0, 0.02, 0.3), Vector3(0.5, 0.02, 0.3), true)
	var data := m.serialize()
	var m2 := _manager()
	m2.restore(data)
	assert_int(m2.ruler_count()).is_equal(1)
	assert_int(m2.ruler_owner(10)).is_equal(2)

extends GdUnitTestSuite
## Base-anchored range rings: pure geometry/colour/cycle helpers + per-model ring state.
## Pure logic — instantiates nodes but needs no rendering.

const RangeRingScript := preload("res://scripts/range_ring_controller.gd")


func _controller() -> RangeRingController:
	var c: RangeRingController = auto_free(RangeRingScript.new())
	add_child(c)
	return c


func _model() -> Node3D:
	var n: Node3D = auto_free(Node3D.new())
	add_child(n)
	return n


# === pure helpers ===

func test_base_radius_round() -> void:
	# 40 mm round base → 20 mm radius = 0.02 m
	assert_float(_controller().base_radius_for_props({"base_size_round": 40})).is_equal_approx(0.02, 0.0001)


func test_base_radius_oval_average() -> void:
	# oval 60 × 35 → (60+35)/4 mm = 23.75 mm = 0.02375 m
	assert_float(_controller().base_radius_for_props(
			{"base_is_oval": true, "base_width_mm": 60, "base_depth_mm": 35})).is_equal_approx(0.02375, 0.0001)


func test_base_radius_default_when_empty() -> void:
	assert_float(_controller().base_radius_for_props({})).is_equal_approx(0.016, 0.0001)


func test_ring_outer_radius_adds_range() -> void:
	# 32 mm base (0.016) + 6" (0.1524) = 0.1684 m
	assert_float(_controller().ring_outer_radius_for_props({}, 6)).is_equal_approx(0.016 + 6 * 0.0254, 0.0001)


func test_color_by_player_id() -> void:
	assert_bool(_controller().color_for_props({"player_id": 2}) == OPRArmyManager.PLAYER_COLORS[2]).is_true()


func test_color_neutral_without_player() -> void:
	assert_bool(_controller().color_for_props({}) == RangeRingController.NEUTRAL_COLOR).is_true()


func test_cycle_next_index_progression() -> void:
	var c := _controller()
	assert_int(c.cycle_next_index(-1)).is_equal(0)  # off → first (3")
	assert_int(c.cycle_next_index(0)).is_equal(1)
	assert_int(c.cycle_next_index(4)).is_equal(5)   # → last (24")
	assert_int(c.cycle_next_index(5)).is_equal(-1)  # last → off


# === per-model ring state ===

func test_cycle_turns_on_then_wraps_off() -> void:
	var c := _controller()
	var m := _model()
	c.cycle([m])
	assert_int(c.current_range_inches(m)).is_equal(3)  # off → 3"
	assert_int(c.active_count()).is_equal(1)
	assert_object(m.get_node_or_null("RangeRing")).is_not_null()
	# six more steps walk 3→6→9→12→18→24→off
	for i in range(6):
		c.cycle([m])
	assert_int(c.current_range_inches(m)).is_equal(0)
	assert_int(c.active_count()).is_equal(0)
	assert_object(m.get_node_or_null("RangeRing")).is_null()


func test_set_range_rebuilds_single_ring() -> void:
	var c := _controller()
	var m := _model()
	c.set_range_for(m, 0)
	c.set_range_for(m, 2)  # 9"
	assert_int(c.current_range_inches(m)).is_equal(9)
	var count := 0
	for child in m.get_children():
		if child.name == "RangeRing":
			count += 1
	assert_int(count).is_equal(1)  # rebuilt, not stacked


func test_clear_all() -> void:
	var c := _controller()
	var a := _model()
	var b := _model()
	c.set_range_for(a, 0)
	c.set_range_for(b, 1)
	c.clear_all()
	assert_int(c.active_count()).is_equal(0)
	assert_object(a.get_node_or_null("RangeRing")).is_null()
	assert_object(b.get_node_or_null("RangeRing")).is_null()

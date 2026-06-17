extends GdUnitTestSuite
## Movement reach indicator: OPR Advance/Rush bands (incl. Fast/Slow), base-anchored radii,
## colour, and per-model toggle state. Pure logic — instantiates nodes, needs no rendering.

const MovementScript := preload("res://scripts/movement_range_controller.gd")


func _controller() -> MovementRangeController:
	var c: MovementRangeController = auto_free(MovementScript.new())
	add_child(c)
	return c


func _model() -> Node3D:
	var n: Node3D = auto_free(Node3D.new())
	add_child(n)
	return n


# === move bands (OPR Advance 6" / Rush+Charge 12", Fast +2/+4, Slow -2/-4) ===

func test_move_bands_normal() -> void:
	var b := _controller().move_bands_for_props({})
	assert_int(b["advance"]).is_equal(6)
	assert_int(b["rush"]).is_equal(12)


func test_move_bands_fast() -> void:
	var b := _controller().move_bands_for_props({"special_rules": ["Fast", "Tough(3)"]})
	assert_int(b["advance"]).is_equal(8)   # 6 + 2
	assert_int(b["rush"]).is_equal(16)      # 12 + 4


func test_move_bands_slow() -> void:
	var b := _controller().move_bands_for_props({"special_rules": ["Slow"]})
	assert_int(b["advance"]).is_equal(4)   # 6 - 2
	assert_int(b["rush"]).is_equal(8)       # 12 - 4


func test_move_bands_unrelated_rule_is_normal() -> void:
	var b := _controller().move_bands_for_props({"special_rules": ["Fearless", "Caster(2)"]})
	assert_int(b["advance"]).is_equal(6)
	assert_int(b["rush"]).is_equal(12)


# === radii / colour (base-anchored, reused from the range-ring approximation) ===

func test_base_radius_round() -> void:
	assert_float(_controller().base_radius_for_props({"base_size_round": 40})).is_equal_approx(0.02, 0.0001)


func test_band_radius_adds_distance() -> void:
	# 32 mm base (0.016) + 12" (0.3048) = 0.3208 m
	assert_float(_controller().band_radius_for_props({}, 12)).is_equal_approx(0.016 + 12 * 0.0254, 0.0001)


func test_color_by_player_id() -> void:
	assert_bool(_controller().color_for_props({"player_id": 2}) == OPRArmyManager.PLAYER_COLORS[2]).is_true()


func test_color_neutral_without_player() -> void:
	assert_bool(_controller().color_for_props({}) == MovementRangeController.NEUTRAL_COLOR).is_true()


# === per-model toggle ===

func test_toggle_shows_then_hides() -> void:
	var c := _controller()
	var m := _model()
	c.toggle([m])
	assert_bool(c.is_active(m)).is_true()
	assert_int(c.active_count()).is_equal(1)
	assert_bool(m.get_node_or_null(MovementRangeController.ROOT_NODE_NAME) != null).is_true()
	c.toggle([m])
	assert_bool(c.is_active(m)).is_false()
	assert_int(c.active_count()).is_equal(0)


func test_clear_all_removes_every_indicator() -> void:
	var c := _controller()
	var a := _model()
	var b := _model()
	c.toggle([a, b])
	assert_int(c.active_count()).is_equal(2)
	c.clear_all()
	assert_int(c.active_count()).is_equal(0)

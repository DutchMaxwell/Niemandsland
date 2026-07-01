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


# === movement modifiers parsed from the rule description (issue #79) ===

func test_parse_modifier_fast_text() -> void:
	var d := "This model moves +2\" when using Advance, and +4\" when using Rush/Charge."
	var mod := MovementRangeController.move_modifier_from_description(d)
	assert_int(mod["advance"]).is_equal(2)
	assert_int(mod["rush"]).is_equal(4)


func test_parse_modifier_slow_text_negative() -> void:
	var d := "This model moves -2\" when using Advance, and -4\" when using Rush/Charge."
	var mod := MovementRangeController.move_modifier_from_description(d)
	assert_int(mod["advance"]).is_equal(-2)
	assert_int(mod["rush"]).is_equal(-4)


func test_parse_modifier_curly_quotes_and_inflections() -> void:
	# Curly inch marks + inflected actions ("Advancing"/"Charging") must still parse.
	var d := "Gets +1” when Advancing, and +3” when Rushing or Charging."
	var mod := MovementRangeController.move_modifier_from_description(d)
	assert_int(mod["advance"]).is_equal(1)
	assert_int(mod["rush"]).is_equal(3)


func test_parse_modifier_ignores_unsigned_distances() -> void:
	# A plain range like 12" (no sign) is not a movement modifier.
	var d := "Enemies within 12\" must take a test; this has nothing to do with moving."
	var mod := MovementRangeController.move_modifier_from_description(d)
	assert_int(mod["advance"]).is_equal(0)
	assert_int(mod["rush"]).is_equal(0)


func test_parse_modifier_empty_description() -> void:
	var mod := MovementRangeController.move_modifier_from_description("")
	assert_int(mod["advance"]).is_equal(0)
	assert_int(mod["rush"]).is_equal(0)


func test_move_bands_swift_from_description() -> void:
	# "Swift" is unknown to the constants but its description carries the modifier (issue #79).
	var b := _controller().move_bands_for_props({
		"special_rules": ["Swift"],
		"rule_descriptions": {"Swift": "Moves +1\" when using Advance, and +2\" when using Rush/Charge."},
	})
	assert_int(b["advance"]).is_equal(7)   # 6 + 1
	assert_int(b["rush"]).is_equal(14)      # 12 + 2


func test_move_bands_rule_rating_is_stripped() -> void:
	# A rated rule "Swift(2)" still matches its "Swift" description key.
	var b := _controller().move_bands_for_props({
		"special_rules": ["Swift(2)"],
		"rule_descriptions": {"Swift": "Moves +1\" when using Advance, and +2\" when using Rush/Charge."},
	})
	assert_int(b["advance"]).is_equal(7)
	assert_int(b["rush"]).is_equal(14)


func test_move_bands_description_overrides_constant() -> void:
	# When Fast carries a description, the parsed value is used (not double-applied with the constant).
	var b := _controller().move_bands_for_props({
		"special_rules": ["Fast"],
		"rule_descriptions": {"Fast": "Moves +2\" when using Advance, and +4\" when using Rush/Charge."},
	})
	assert_int(b["advance"]).is_equal(8)
	assert_int(b["rush"]).is_equal(16)


func test_move_bands_swift_negates_slow() -> void:
	# Dwarf Guilds case: the unit is Slow but gains Swift ("may ignore the Slow rule"), so Slow is
	# cancelled -> normal 6"/12" instead of the slowed 4"/8" (issue #79).
	var b := _controller().move_bands_for_props({
		"special_rules": ["Slow", "Swift"],
		"rule_descriptions": {
			"Slow": "Moves -2\" when using Advance, and -4\" when using Rush/Charge.",
			"Swift": "This model may ignore the Slow rule.",
		},
	})
	assert_int(b["advance"]).is_equal(6)
	assert_int(b["rush"]).is_equal(12)


func test_move_bands_negation_is_targeted() -> void:
	# Swift cancels Slow, but an unrelated Fast bonus still applies.
	var b := _controller().move_bands_for_props({
		"special_rules": ["Slow", "Swift", "Fast"],
		"rule_descriptions": {
			"Slow": "Moves -2\" when using Advance, and -4\" when using Rush/Charge.",
			"Swift": "This model may ignore the Slow rule.",
			"Fast": "Moves +2\" when using Advance, and +4\" when using Rush/Charge.",
		},
	})
	assert_int(b["advance"]).is_equal(8)   # Slow negated, Fast applies: 6 + 2
	assert_int(b["rush"]).is_equal(16)      # 12 + 4


func test_move_bands_granted_rule_modifier_applies() -> void:
	# A direct ability "Fleetfoot" grants Swift; spawn-time expansion puts BOTH descriptions in the
	# dict. The granting rule carries no modifier text; Swift's does — it must still apply (#79).
	var b := _controller().move_bands_for_props({
		"special_rules": ["Fleetfoot"],
		"rule_descriptions": {
			"Fleetfoot": "This model has the Swift special rule.",
			"Swift": "Moves +1\" when using Advance, and +2\" when using Rush/Charge.",
		},
	})
	assert_int(b["advance"]).is_equal(7)   # 6 + 1
	assert_int(b["rush"]).is_equal(14)      # 12 + 2


func test_move_bands_clamps_at_zero() -> void:
	# A very heavy Slow can't drive the bands negative.
	var b := _controller().move_bands_for_props({
		"special_rules": ["Slow"],
		"rule_descriptions": {"Slow": "Moves -9\" when using Advance, and -99\" when using Rush/Charge."},
	})
	assert_int(b["advance"]).is_equal(0)
	assert_int(b["rush"]).is_equal(0)


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
	# World-anchored: the indicator is a child of the CONTROLLER, not of the model.
	assert_bool(c.get_node_or_null(MovementRangeController.ROOT_NODE_NAME) != null).is_true()
	assert_bool(m.get_node_or_null(MovementRangeController.ROOT_NODE_NAME) == null).is_true()
	c.toggle([m])
	assert_bool(c.is_active(m)).is_false()
	assert_int(c.active_count()).is_equal(0)
	await get_tree().process_frame  # clear() uses queue_free (deferred) — let the node be removed
	assert_bool(c.get_node_or_null(MovementRangeController.ROOT_NODE_NAME) == null).is_true()


func test_indicator_stays_put_when_model_moves() -> void:
	# The indicator anchors at the model's spot and must NOT follow it, so the player can drag
	# the mini toward a band edge to judge reach.
	var c := _controller()
	var m := _model()
	m.global_position = Vector3(0.5, 0.0, 0.3)
	c.toggle([m])
	var ring := c.get_node_or_null(MovementRangeController.ROOT_NODE_NAME) as Node3D
	assert_bool(ring != null).is_true()
	assert_float(ring.global_position.x).is_equal_approx(0.5, 0.001)
	assert_float(ring.global_position.z).is_equal_approx(0.3, 0.001)
	# Move the mini — the world-anchored indicator stays put.
	m.global_position = Vector3(1.0, 0.0, 0.8)
	assert_float(ring.global_position.x).is_equal_approx(0.5, 0.001)
	assert_float(ring.global_position.z).is_equal_approx(0.3, 0.001)


func test_clear_all_removes_every_indicator() -> void:
	var c := _controller()
	var a := _model()
	var b := _model()
	c.toggle([a, b])
	assert_int(c.active_count()).is_equal(2)
	c.clear_all()
	assert_int(c.active_count()).is_equal(0)

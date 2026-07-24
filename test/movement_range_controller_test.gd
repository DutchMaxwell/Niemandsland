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


# === NML-006: spell movement stamps ("spell_move_mod", set by the solo layer) join the band math ===

func test_move_bands_spell_stamp_buff_and_debuff() -> void:
	var buff := _controller().move_bands_for_props({"spell_move_mod": {"advance": 2, "rush": 4}})
	assert_int(buff["advance"]).is_equal(8)
	assert_int(buff["rush"]).is_equal(16)
	# Debuff stapelt mit Slow und clampt bei 0 (nie negative Bänder).
	var slowed := _controller().move_bands_for_props({
		"special_rules": ["Slow"], "spell_move_mod": {"advance": -2, "rush": -4}})
	assert_int(slowed["advance"]).is_equal(2)   # 6 - 2 (Slow) - 2 (spell)
	assert_int(slowed["rush"]).is_equal(4)      # 12 - 4 (Slow) - 4 (spell)
	var floored := _controller().move_bands_for_props({"spell_move_mod": {"advance": -9, "rush": -20}})
	assert_int(floored["advance"]).is_equal(0)
	assert_int(floored["rush"]).is_equal(0)


func test_move_bands_granted_rule_string_counts() -> void:
	# NML-006 Grant-Overlay: eine zaubergewährte Regel liegt suffix-markiert in special_rules —
	# der Basisnamen-Scan (Klammer-Split) MUSS sie wie die gedruckte Regel zählen.
	var b := _controller().move_bands_for_props({"special_rules": ["Rapid Rush (spell)"]})
	assert_int(b["advance"]).is_equal(6)
	assert_bool(b["rush"] > 12).is_true()


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


func test_move_bands_scurry_adds_two_each() -> void:
	# Ratmen Clans "Scurry": +2" Advance AND +2" Rush/Charge (a direct additive rule, +2/+2 —
	# unlike Fast's +2/+4). Parsed straight from its description (issue #79).
	var b := _controller().move_bands_for_props({
		"special_rules": ["Scurry"],
		"rule_descriptions": {"Scurry": "Moves +2\" when using Advance, and +2\" when using Rush/Charge."},
	})
	assert_int(b["advance"]).is_equal(8)   # 6 + 2
	assert_int(b["rush"]).is_equal(14)      # 12 + 2


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


# === aura rules from combined-unit members (#79 aura) ===

func test_has_aura_rule() -> void:
	assert_bool(MovementRangeController._has_aura_rule(["Hero", "Swift Aura"])).is_true()
	assert_bool(MovementRangeController._has_aura_rule(["Hero", "Fast"])).is_false()


func test_merge_aura_pulls_in_aura_member_rules() -> void:
	var own := {"Slow": "Moves -2\" when using Advance, and -4\" when using Rush/Charge."}
	var members := [{
		"rules": ["Hero", "Swift Aura"],
		"descriptions": {"Swift Aura": "This model and its unit get Swift.", "Swift": "may ignore the Slow rule."},
	}]
	var merged := MovementRangeController.merge_aura_descriptions(own, members)
	assert_bool(merged.has("Swift")).is_true()   # granted by the aura member
	assert_bool(merged.has("Slow")).is_true()    # own kept


func test_merge_aura_ignores_non_aura_member() -> void:
	# A hero's PERSONAL Fast (no aura) must not leak to the unit.
	var members := [{"rules": ["Hero", "Fast"], "descriptions": {"Fast": "Moves +2\"..."}}]
	var merged := MovementRangeController.merge_aura_descriptions({}, members)
	assert_bool(merged.has("Fast")).is_false()


func test_aura_swift_cancels_unit_slow_end_to_end() -> void:
	# The Dwarf case: a Slow unit with no Swift of its own gains it from the hero's Swift Aura,
	# so the whole unit ignores Slow -> normal 6"/12" (#79 aura).
	var own := {"Slow": "Moves -2\" when using Advance, and -4\" when using Rush/Charge."}
	var members := [{
		"rules": ["Hero", "Swift Aura"],
		"descriptions": {"Swift Aura": "This model and its unit get Swift.", "Swift": "This model may ignore the Slow rule."},
	}]
	var merged := MovementRangeController.merge_aura_descriptions(own, members)
	var b := _controller().move_bands_for_props({"special_rules": ["Slow"], "rule_descriptions": merged})
	assert_int(b["advance"]).is_equal(6)
	assert_int(b["rush"]).is_equal(12)


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


## Rapid Rush (army-book rule, quick-win batch): "This model moves +6" when using Rush actions." —
## the Rush/Charge band gains 6", Advance stays untouched. Parsed from the official description text.
func test_move_bands_rapid_rush_from_description() -> void:
	var desc := {"Rapid Rush": "This model moves +6\" when using Rush actions."}
	var b := _controller().move_bands_for_props({"special_rules": ["Rapid Rush"], "rule_descriptions": desc})
	assert_int(b["advance"]).is_equal(6)
	assert_int(b["rush"]).is_equal(18)       # 12 + 6


func test_move_bands_rapid_rush_name_fallback() -> void:
	# Without (parseable) description text the constant fallback still applies — same seam as Fast/Slow.
	var b := _controller().move_bands_for_props({"special_rules": ["Rapid Rush"]})
	assert_int(b["advance"]).is_equal(6)
	assert_int(b["rush"]).is_equal(18)


## Autonomous wave 2026-07-19: Quick (+2/+2), Rapid Advance (+4 Advance only), Swift name-fallback.
func test_move_bands_quick_and_rapid_advance_fallbacks() -> void:
	var q := _controller().move_bands_for_props({"special_rules": ["Quick"]})
	assert_int(q["advance"]).is_equal(8)
	assert_int(q["rush"]).is_equal(14)
	var ra := _controller().move_bands_for_props({"special_rules": ["Rapid Advance"]})
	assert_int(ra["advance"]).is_equal(10)
	assert_int(ra["rush"]).is_equal(12)


func test_move_bands_swift_name_fallback_cancels_slow() -> void:
	# Without any descriptions the bare NAME pair must still cancel (the description-negation
	# path is covered by test_move_bands_swift_negates_slow).
	var b := _controller().move_bands_for_props({"special_rules": ["Slow", "Swift"]})
	assert_int(b["advance"]).is_equal(6)
	assert_int(b["rush"]).is_equal(12)


## Wave-4 Royal Legion (Mummified Undead army-book rule): "+4" range when shooting and moves +2" when
## using Charge actions." The move parser must apply ONLY the +2" Charge (the Rush/Charge band), never the
## +4" range — so a Royal Legion unit reads Advance 6", Rush/Charge 14".
func test_move_bands_royal_legion_charge_bonus_only() -> void:
	var desc := {"Royal Legion": "This model gets +4\" range when shooting and moves +2\" when using Charge actions."}
	var b := _controller().move_bands_for_props({"special_rules": ["Royal Legion"], "rule_descriptions": desc})
	assert_int(b["advance"]).is_equal(6)    # +4" range is NOT a move modifier
	assert_int(b["rush"]).is_equal(14)       # 12 + 2 (Charge shares the Rush/Charge band)


# === B10 (test game 2): movement-mod audit — partial parses must not eat a band ===

func test_parse_modifier_one_value_naming_both_actions() -> void:
	# ONE modifier naming BOTH actions applies to both bands (old: first-stem-wins dropped rush).
	var d := "This model moves +2\" when using Advance or Rush/Charge actions."
	var mod := MovementRangeController.move_modifier_from_description(d)
	assert_int(mod["advance"]).is_equal(2)
	assert_int(mod["rush"]).is_equal(2)
	# The classic Fast pair is UNAFFECTED (windows end at the next modifier).
	var fast := MovementRangeController.move_modifier_from_description(
		"Moves +2\" when using Advance, and +4\" when using Rush/Charge.")
	assert_int(fast["advance"]).is_equal(2)
	assert_int(fast["rush"]).is_equal(4)


func test_move_bands_fast_partial_description_fills_missing_band() -> void:
	# A Fast description whose rush half is unparseable used to mark the WHOLE rule counted and
	# suppress the name fallback — the +4" rush/charge bonus vanished (the maintainer's cap read
	# 12" on a Fast vehicle). The fallback now fills exactly the missing band.
	var b := _controller().move_bands_for_props({
		"special_rules": ["Fast"],
		"rule_descriptions": {"Fast": "Moves +2\" when Advancing. It is very fast."},
	})
	assert_int(b["advance"]).is_equal(8)    # 6 + 2 from the description
	assert_int(b["rush"]).is_equal(16)       # 12 + 4 from the per-band name fallback
	# Mirror case: only the rush half parses — advance comes from the fallback.
	var b2 := _controller().move_bands_for_props({
		"special_rules": ["Fast"],
		"rule_descriptions": {"Fast": "Moves +4\" when using Rush or Charge actions."},
	})
	assert_int(b2["advance"]).is_equal(8)
	assert_int(b2["rush"]).is_equal(16)


func test_move_bands_slow_partial_description_fills_missing_band() -> void:
	var b := _controller().move_bands_for_props({
		"special_rules": ["Slow"],
		"rule_descriptions": {"Slow": "Moves -2\" when Advancing."},
	})
	assert_int(b["advance"]).is_equal(4)    # 6 - 2 from the description
	assert_int(b["rush"]).is_equal(8)        # 12 - 4 from the per-band fallback


func test_bands_for_model_resolves_unit_via_parent_meta() -> void:
	# B10: a nested pickable child (mount part / proxy mesh) resolves its unit through the PARENT's
	# game_unit meta instead of silently reading bare 6"/12" bands.
	var c := _controller()
	var gu := GameUnit.new()
	gu.unit_properties = {"special_rules": ["Fast"], "player_id": 1, "name": "F", "quality": 4, "defense": 4}
	var parent: Node3D = auto_free(Node3D.new())
	add_child(parent)
	parent.set_meta("game_unit", gu)
	var child := Node3D.new()
	parent.add_child(child)
	var b := c.bands_for_model(child)
	assert_int(b["advance"]).is_equal(8)
	assert_int(b["rush"]).is_equal(16)

extends GdUnitTestSuite
## "Indirect when Shooting" — the table port of the core's unit-level stamp.
##
## Book text (gf + aof): "This model gets Indirect when shooting." The core stamps the plain
## `indirect` flag on the model's SHOOT profiles from the unit-level name at profile build
## (core/nml-core/src/unit.rs build_for, epoch 6); the save gate, EV and the sight waiver read it.
## On the table the ONLY reader was weapon-level (AiShooting._profile's `indirect` facet) — a unit
## that PRINTS "Indirect when Shooting" therefore shot as if it had no Indirect: it needed line of
## sight, cover applied, no moved penalty waiver. These tests pin the unit-level half: the facet
## builder the shooting profiles feed (AiEv.stamp_sergeant — the same unit-aware seam every
## unit-level facet stamp rides) sets `indirect` on the ranged profiles when the unit carries the
## entry, resolved by (system, faction, name) — never by the bare Indirect primitive token, whose
## other entries carry their own scopes.


func _unit(rules: Array, system: String = "gf", faction: String = "robot_legions") -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "t_iws"
	u.unit_properties = {"player_id": 2, "name": "T", "quality": 4, "defense": 4,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


func _w(rules: Array = []) -> Dictionary:
	return {"name": "Gun", "range_value": 24, "attacks": 2, "count": 3, "special_rules": rules}


func _melee_w() -> Dictionary:
	return {"name": "CCW", "range_value": 0, "attacks": 2, "count": 3, "special_rules": []}


func test_unit_level_entry_stamps_indirect_on_the_shooting_profiles() -> void:
	var u := _unit(["Indirect when Shooting"])
	assert_bool(RulesRegistry.unit_rule_active(u, "Indirect when Shooting")) \
		.override_failure_message("gf/robot_legions: the printed entry resolves nowhere").is_true()
	var profiles: Array = AiEv.stamp_sergeant(AiShooting.profiles_in_range([_w()], 12.0), u)
	assert_int(profiles.size()).is_equal(1)
	assert_bool(bool((profiles[0] as Dictionary).get("indirect", false))) \
		.override_failure_message("the unit prints Indirect when Shooting but its volley still needs LOS + cover") \
		.is_true()


func test_unit_without_the_entry_keeps_the_weapon_level_path_only() -> void:
	# A weapon carrying the REAL "Indirect" tag reads through AiShooting._profile and must keep it;
	# a plain unit must NOT gain the facet from nowhere.
	var weapon_indirect: Array = AiEv.stamp_sergeant(
		AiShooting.profiles_in_range([_w(["Indirect"])], 12.0), _unit([]))
	assert_bool(bool((weapon_indirect[0] as Dictionary).get("indirect", false))).is_true()
	var without: Array = AiEv.stamp_sergeant(AiShooting.profiles_in_range([_w()], 12.0), _unit([]))
	assert_bool(bool((without[0] as Dictionary).get("indirect", false))).is_false()


func test_melee_profiles_stay_silent() -> void:
	# The core stamps only the SHOOT profiles — the melee twin never gains the flag.
	var melee: Array = AiEv.stamp_sergeant(AiShooting.melee_profiles([_melee_w()]),
		_unit(["Indirect when Shooting"]))
	assert_bool(bool((melee[0] as Dictionary).get("indirect", false))).is_false()


func test_no_cross_entry_bleed_through_the_bare_primitive() -> void:
	# A DIFFERENT Indirect-family entry (the cover_only alias form ai_ev already reads) must not
	# grant the full facet — the gate is the NAME, not the primitive token.
	var u := _unit(["Ignores Cover when Shooting"], "gf", "machine_cults")
	if not RulesRegistry.unit_rule_active(u, "Ignores Cover when Shooting"):
		return   # book does not field the alias here — nothing to bleed
	var profiles: Array = AiEv.stamp_sergeant(AiShooting.profiles_in_range([_w()], 12.0), u)
	assert_bool(bool((profiles[0] as Dictionary).get("indirect", false))).is_false()
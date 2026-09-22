extends GdUnitTestSuite

func _fixtures() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://test/fixtures/ratmen_standalone_teams_export.json"))

func _profiles(parsed: OPRApiClient.OPRUnit) -> Array:
	var unit := GameUnit.new()
	for i in range(parsed.size):
		unit.models.append(ModelInstance.new())
	EquipmentDistributor.distribute(unit, EquipmentDistributor.build_loadout(parsed), parsed.special_rules)
	var out: Array = []
	for model in unit.models:
		out.append(model.properties.weapons.map(func(w): return w.name))
		assert_int(model.wounds_max).is_equal(3)
	return out

func test_any_replacement_crosses_range_without_sharing_a_model() -> void:
	var api: OPRApiClient = auto_free(OPRApiClient.new())
	var parsed := api._parse_tts_unit(_fixtures().mixed, "aof", true)
	assert_array(_profiles(parsed.duplicate_unit())).is_equal([
		["Crew", "Heavy Drill"], ["Crew", "Flamethrower"], ["Crew", "Gatling Gun"]])
	assert_int(parsed.base_width_mm).is_equal(35)
	assert_int(parsed.base_depth_mm).is_equal(60)
	assert_bool(parsed.base_is_oval).is_true()

func test_combined_unmodified_half_joins_replacement_group_in_both_orders() -> void:
	var api: OPRApiClient = auto_free(OPRApiClient.new())
	for reverse in [false, true]:
		var data: Array = _fixtures().combined
		if reverse:
			data.reverse()
		var halves: Array[OPRApiClient.OPRUnit] = []
		for i in range(2):
			data[i].merge({"combined": true, "selectionId": "half" + str(i),
				"joinToUnit": "half0" if i == 1 else ""}, true)
			halves.append(api._parse_tts_unit(data[i], "aof", true))
		var merged := api._merge_combined_units(halves, true)[0].duplicate_unit()
		var profiles := _profiles(merged)
		assert_int(profiles.size()).is_equal(6)
		for i in range(3):
			assert_array(profiles[i]).is_equal(["Crew", "Heavy Drill"])
		var guns := profiles.slice(3).map(func(p): return p[1])
		assert_array(guns).contains_exactly(["Flamethrower", "Toxin Mortar", "Gatling Gun"])

func test_weapon_target_survives_serialization() -> void:
	var api: OPRApiClient = auto_free(OPRApiClient.new())
	var parsed := api._parse_tts_unit(_fixtures().mixed, "aof", true)
	for weapon in parsed.weapons:
		var restored := OPRApiClient.OPRWeapon.from_dict(weapon.to_dict())
		assert_str(restored.replacement_target).is_equal(weapon.replacement_target)
		assert_bool(restored.replacement_target.is_empty()).is_equal(weapon.name == "Crew")

func test_additive_cross_range_upgrade_keeps_normal_slots() -> void:
	var api: OPRApiClient = auto_free(OPRApiClient.new())
	var data: Dictionary = _fixtures().mixed
	for selected in data.selectedUpgrades:
		selected.upgrade.variant = "upgrade"
	var parsed := api._parse_tts_unit(data, "aof", true)
	for weapon in parsed.weapons:
		assert_str(weapon.replacement_target).is_empty()

extends GdUnitTestSuite
## Multi-target "replace any X and Y" swaps (Storm Ogre fist pairs) parse into atomic per-model
## bundles, transactionally: an export the bundle logic cannot fully account for stays untouched.
## (Ported from Model Forge's storm_ogres_bundle_contract.gd.)

func _data() -> Dictionary:
	return {"name": "Bundle contract", "size": 3, "quality": 4, "defense": 3,
		"loadout": [
			{"name": "Flame-Fists", "range": 12, "attacks": 1, "count": 2},
			{"name": "Bash", "attacks": 2, "count": 2},
			{"name": "Gatling-Fist", "range": 18, "attacks": 4, "count": 1},
			{"name": "Bash", "attacks": 1, "count": 1}],
		"selectedUpgrades": [{
			"upgrade": {"variant": "replace", "model": false,
				"affects": {"type": "any"}, "targets": ["Flame-Fist", "Bash"]},
			"option": {"gains": [
				{"type": "ArmyBookWeapon", "name": "Gatling-Fist", "range": 18, "attacks": 4},
				{"type": "ArmyBookWeapon", "name": "Bash", "attacks": 1}]}}]}


func test_replacement_forms_one_atomic_bundle_per_pair() -> void:
	var api: OPRApiClient = auto_free(OPRApiClient.new())
	var unit := api._parse_tts_unit(_data(), "aof", true)
	var loadout := EquipmentDistributor.build_loadout(unit)
	assert_int(loadout.size()).is_equal(2)
	# A remaining Bash(A2) never becomes the gained Bash(A1).
	assert_int(loadout[0].weapons[1].attacks).is_equal(2)
	assert_int(loadout[1].weapons[1].attacks).is_equal(1)
	assert_array(EquipmentDistributor.build_loadout(unit.duplicate_unit())).is_equal(loadout)
	assert_array(EquipmentDistributor.per_model_labels(3, loadout)).is_equal(
		[["Flame-Fists", "Bash"], ["Flame-Fists", "Bash"], ["Gatling-Fist", "Bash"]])


func test_unaccountable_exports_create_no_bundle() -> void:
	var api: OPRApiClient = auto_free(OPRApiClient.new())
	for mutation in ["missing_gain", "partial_count", "model_upgrade", "limited_selection", "non_weapon"]:
		var input := _data()
		match mutation:
			"missing_gain": input.loadout.pop_back()
			"partial_count": input.loadout[2].count = 2
			"model_upgrade": input.selectedUpgrades[0].upgrade.model = true
			"limited_selection": input.selectedUpgrades[0].upgrade.select = {"type": "exactly", "value": 1}
			"non_weapon": input.selectedUpgrades[0].option.gains[1].type = "ArmyBookRule"
		var unchanged := api._parse_tts_unit(input, "aof", true)
		for item in unchanged.equipment_items:
			assert_bool(item.get("bundle_only", false)).override_failure_message(mutation).is_false()
		for weapon in unchanged.weapons:
			assert_bool(weapon.from_item.begins_with("__weapon_bundle__")).override_failure_message(mutation).is_false()


func test_without_bundles_the_same_export_parses_as_before() -> void:
	var api: OPRApiClient = auto_free(OPRApiClient.new())
	var unit := api._parse_tts_unit(_data(), "aof")
	assert_array(unit.equipment_items).is_empty()
	for weapon in unit.weapons:
		assert_str(weapon.from_item).is_empty()
		assert_str(weapon.replacement_target).is_empty()

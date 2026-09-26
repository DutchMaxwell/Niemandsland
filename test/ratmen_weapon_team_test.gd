extends GdUnitTestSuite
## Actual Forge exports: nested weapon profiles, commands and combined half B.

func _parse(key: String) -> OPRApiClient.OPRUnit:
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://test/fixtures/ratmen_warriors_export.json"))
	return auto_free(OPRApiClient.new())._parse_tts_unit(fixtures[key], "aof", true)

func _models(parsed: OPRApiClient.OPRUnit) -> GameUnit:
	var result := GameUnit.new()
	for i in range(parsed.size):
		var model := ModelInstance.new()
		model.model_index = i
		model.unit = result
		result.models.append(model)
	EquipmentDistributor.distribute(result, EquipmentDistributor.build_loadout(parsed), parsed.special_rules)
	return result

func _names(model: ModelInstance) -> Array:
	return model.properties.get("weapons", []).map(func(w): return w.name)

func test_team_replaces_the_tenth_weapon_and_keeps_both_profiles() -> void:
	var parsed := _parse("drill")
	var unit := _models(parsed)
	for i in range(9):
		assert_array(_names(unit.models[i])).is_equal(["Hand Weapon"])
		assert_int(unit.models[i].wounds_max).is_equal(1)
	assert_array(_names(unit.models[9])).is_equal(["Heavy Drill", "Crew"])
	assert_int(unit.models[9].wounds_max).is_equal(3)
	var labels := EquipmentDistributor.per_model_labels(10, EquipmentDistributor.build_loadout(parsed))
	assert_array(labels[9]).contains(["Weapon Team", "Heavy Drill", "Crew"])
	for i in range(3):
		assert_array(unit.models[i].properties.get("equipment", [])).is_equal([["Sergeant"], ["Banner"], ["Musician"]][i])

func test_combined_different_teams_and_half_b_command_survive() -> void:
	var parsed := _parse("mixed")
	var unit := _models(parsed.duplicate_unit())
	for i in range(18):
		assert_array(_names(unit.models[i])).is_equal(["Halberd"])
		assert_int(unit.models[i].wounds_max).is_equal(1)
	assert_array(_names(unit.models[18])).is_equal(["Heavy Drill", "Crew"])
	assert_array(_names(unit.models[19])).is_equal(["Gatling Gun", "Crew"])
	assert_int(unit.models[18].wounds_max).is_equal(3)
	assert_int(unit.models[19].wounds_max).is_equal(3)
	assert_array(unit.models[0].properties.get("equipment", [])).is_equal(["Sergeant"])
	assert_array(unit.models[1].properties.get("equipment", [])).is_equal(["Sergeant"])
	assert_array(unit.models[2].properties.get("equipment", [])).is_equal(["Banner"])
	assert_array(unit.models[3].properties.get("equipment", [])).is_equal(["Musician"])

## One real Ratmen Warriors half (the `drill` export: Weapon Team = Tough(3) on ONE model) re-labelled as a
## combined half — the shape `_merge_combined_units` folds. `join_to` null = the anchor half.
func _half(selection_id: String, join_to: Variant) -> OPRApiClient.OPRUnit:
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://test/fixtures/ratmen_warriors_export.json"))
	var raw: Dictionary = (fixtures["drill"] as Dictionary).duplicate(true)
	raw["combined"] = true
	raw["selectionId"] = selection_id
	raw["joinToUnit"] = join_to
	return auto_free(OPRApiClient.new())._parse_tts_unit(raw, "aof", true)

func test_two_half_merge_keeps_the_teams_tough_on_the_team_models_only() -> void:
	# D13 / NML-1107: the ONLY per-model Tough on a multi-model unit in the real AoF/GF army books is a Weapon
	# Team (item content Tough(3), "exactly 1" model — 16 options, 41 books). Fold two REAL halves and prove the
	# squad does not inherit it: no unit-level Tough line, wounds 3 on the two team models, 1 on the other 18.
	var client: OPRApiClient = auto_free(OPRApiClient.new())
	var halves: Array[OPRApiClient.OPRUnit] = [_half("W-A", null), _half("W-B", "W-A")]
	var merged := client._merge_combined_units(halves, true)
	assert_int(merged.size()).is_equal(1)
	assert_int(merged[0].size).is_equal(20)
	var tough_lines: Array = merged[0].special_rules.filter(func(r): return str(r).begins_with("Tough("))
	assert_array(tough_lines).is_empty()
	var unit := _models(merged[0])
	var wounds: Array = unit.models.map(func(m): return m.wounds_max)
	assert_int(wounds.count(3)).is_equal(2)
	assert_int(wounds.count(1)).is_equal(18)

func test_combined_merge_preserves_different_item_profiles() -> void:
	var parsed := _parse("mixed")
	var teams: Array = parsed.equipment_items.filter(func(i): return i.name == "Weapon Team")
	assert_int(teams.size()).is_equal(2)
	var target: Array = [teams[0].duplicate(true)]
	OPRApiClient._merge_equipment_items(target, [teams[1]], true)
	assert_int(target.size()).is_equal(2)
	OPRApiClient._merge_equipment_items(target, [teams[0]], true)
	assert_int(target[0].count).is_equal(2)
	assert_int(target[1].count).is_equal(1)

func test_universal_item_weapons_stay_as_every_faction_parses_them() -> void:
	# Bundles cover SUBSET items only (a team on one model). A universal mount's weapons keep the
	# shared behaviour (display-only, item name on the rule line), identical with or without bundles.
	var client: OPRApiClient = auto_free(OPRApiClient.new())
	var hero := {"name": "Mounted Hero", "size": 1,
		"bases": {"round": "40"}, "loadout": [
			{"type": "ArmyBookWeapon", "name": "Sword", "attacks": 3, "count": 1},
			{"type": "ArmyBookItem", "name": "Mount", "count": 1, "content": [
				{"type": "ArmyBookWeapon", "name": "Claws", "attacks": 2, "count": 2}]}]}
	var bundled := client._parse_tts_unit(hero.duplicate(true), "aof", true)
	var plain := client._parse_tts_unit(hero.duplicate(true), "aof")
	assert_array(_names(_models(bundled).models[0])).is_equal(_names(_models(plain).models[0]))
	assert_array(bundled.special_rules).is_equal(plain.special_rules)
	assert_array(bundled.equipment_items).is_equal(plain.equipment_items)

func test_additive_weapon_bundle_keeps_the_base_weapon() -> void:
	var client: OPRApiClient = auto_free(OPRApiClient.new())
	var parsed := client._parse_tts_unit({"name": "Squad", "size": 3,
		"bases": {"round": "25"}, "loadout": [
			{"type": "ArmyBookWeapon", "name": "Sword", "attacks": 1, "count": 3},
			{"type": "ArmyBookItem", "name": "Support", "count": 1, "content": [
				{"type": "ArmyBookWeapon", "name": "Pistol", "range": 12, "attacks": 1}]}]}, "aof", true)
	var unit := _models(parsed)
	assert_array(_names(unit.models[0])).is_equal(["Sword", "Pistol"])
	assert_array(_names(unit.models[1])).is_equal(["Sword"])
	assert_array(_names(unit.models[2])).is_equal(["Sword"])

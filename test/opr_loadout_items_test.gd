extends GdUnitTestSuite
## Verifies _parse_tts_unit routes non-weapon loadout items the way the real Army
## Forge TTS export encodes them (type / count / content): a subset tool
## (count < size) becomes structured per-model equipment so the base ring can label
## it, while a unit-wide tool (count == size) stays a unit special rule. Abilities the
## item GRANTS always fold into the unit's rules, independent of where it is shown.


func _parse(unit_data: Dictionary) -> OPRApiClient.OPRUnit:
	var client: OPRApiClient = auto_free(OPRApiClient.new())
	return client._parse_tts_unit(unit_data)


func test_subset_tool_becomes_per_model_equipment() -> void:
	# 10-model unit: base weapon on all + a single-model "Synaptic Relay (Spell Conduit)".
	var unit := _parse({
		"name": "Psycho-Grunts", "size": 10, "quality": 5, "defense": 5,
		"rules": [{"name": "Hive Bond"}],
		"loadout": [
			{"name": "Rending Claws", "type": "ArmyBookWeapon", "attacks": 1, "count": 10},
			{"name": "Synaptic Relay", "type": "ArmyBookItem", "count": 1,
				"content": [{"name": "Spell Conduit", "type": "ArmyBookRule"}]},
		],
	})
	# Captured as structured per-model equipment, not a unit-wide rule.
	assert_int(unit.equipment_items.size()).is_equal(1)
	assert_str(unit.equipment_items[0]["name"]).is_equal("Synaptic Relay")
	assert_int(unit.equipment_items[0]["count"]).is_equal(1)
	assert_array(unit.equipment).contains(["Synaptic Relay"])
	assert_bool("Synaptic Relay" in unit.special_rules).is_false()
	# The ability it grants still folds into the unit's rules (card / rules engine).
	assert_array(unit.special_rules).contains(["Spell Conduit"])


func test_unit_wide_tool_stays_a_special_rule() -> void:
	var unit := _parse({
		"name": "Assault Grunts", "size": 10, "quality": 5, "defense": 5,
		"rules": [{"name": "Hive Bond"}],
		"loadout": [
			{"name": "Razor Claws", "type": "ArmyBookWeapon", "attacks": 2, "count": 10},
			{"name": "Toxic Cysts", "type": "ArmyBookItem", "count": 10,
				"content": [{"name": "Bane in Melee", "type": "ArmyBookRule"}]},
		],
	})
	# Applies to all models -> not per-model equipment ...
	assert_array(unit.equipment_items).is_empty()
	# ... it stays in the unit's rule line, and its granted ability too.
	assert_array(unit.special_rules).contains(["Toxic Cysts"])
	assert_array(unit.special_rules).contains(["Bane in Melee"])


func test_weapon_swaps_split_into_separate_counts() -> void:
	# Two 1-of-10 weapon swaps arrive as separate count-1 entries (real AF behaviour).
	var unit := _parse({
		"name": "Assault Grunts", "size": 10, "quality": 5, "defense": 5,
		"rules": [],
		"loadout": [
			{"name": "Razor Claws", "type": "ArmyBookWeapon", "attacks": 2, "count": 8},
			{"name": "Slashing Claws", "type": "ArmyBookWeapon", "attacks": 2, "count": 1},
			{"name": "Serrated Claws", "type": "ArmyBookWeapon", "attacks": 2, "count": 1},
		],
	})
	assert_int(unit.weapons.size()).is_equal(3)
	assert_array(unit.equipment_items).is_empty()


func test_single_model_hero_item_is_not_per_model() -> void:
	# A size-1 hero's item (count 1 == size) is never a per-model special (no ring),
	# but its granted ability still shows on the unit.
	var unit := _parse({
		"name": "Hive Lord", "size": 1, "quality": 3, "defense": 2,
		"rules": [{"name": "Tough", "rating": 12}],
		"loadout": [
			{"name": "Stomp", "type": "ArmyBookWeapon", "attacks": 4, "count": 1},
			{"name": "Wings", "type": "ArmyBookItem", "count": 1,
				"content": [{"name": "Flying", "type": "ArmyBookRule"}]},
		],
	})
	assert_array(unit.equipment_items).is_empty()
	assert_array(unit.special_rules).contains(["Wings"])
	assert_array(unit.special_rules).contains(["Flying"])

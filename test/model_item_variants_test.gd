extends GdUnitTestSuite
## Regression: a universal AF companion is absent from distributed weapons.
## Exercise real parsing and data-driven visual selection without networking.

func _lib() -> ModelLibrary:
	var library := auto_free(ModelLibrary.new()) as ModelLibrary
	library._load_label_slug_map()
	return library


func test_universal_companion_selects_shipped_complete_variant() -> void:
	var lib := _lib()
	lib.apply_manifest_text(JSON.stringify({"models": {"ratmen/battle master#heavy+petrat": {}}}))
	var original := ["Heavy Hand Weapon"]
	var labels := lib.labels_with_available_items("ratmen", "Battle Master", original, ["Pet Giant Rat"])
	assert_str(lib.variant_slug(labels, "ratmen")).is_equal("heavy+petrat")
	assert_array(original).contains_exactly(["Heavy Hand Weapon"])


func test_unshipped_companion_preserves_existing_weapon_variant() -> void:
	var lib := _lib()
	lib.apply_manifest_text(JSON.stringify({"models": {"ratmen/battle master#heavy": {}}}))
	var labels := lib.labels_with_available_items("ratmen", "Battle Master", ["Heavy Hand Weapon"], ["Pet Giant Rat"])
	assert_str(lib.variant_slug(labels, "ratmen")).is_equal("heavy")


func test_rule_only_priest_does_not_hide_shipped_companion() -> void:
	var lib := _lib()
	lib.apply_manifest_text(JSON.stringify({"models": {"ratmen/champion#dual+petrat": {}}}))
	for items in [["Priest", "Pet Giant Rat"], ["Pet Giant Rat", "Priest"]]:
		var labels := lib.labels_with_available_items("ratmen", "Champion", ["Dual Hand Weapons"], items)
		assert_str(lib.variant_slug(labels, "ratmen")).is_equal("dual+petrat")


func test_universal_item_labels_keep_companions_but_exclude_limited_equipment() -> void:
	var api := auto_free(OPRApiClient.new()) as OPRApiClient
	var item := {"type": "ArmyBookItem", "name": "Pet Giant Rat", "count": 1,
		"content": [{"type": "ArmyBookRule", "name": "Repel Ambushers"}]}
	var hero := api._parse_tts_unit({"name": "hero", "size": 1, "bases": {"round": "32"}, "loadout": [item]}, "aof")
	assert_array(EquipmentDistributor.universal_item_labels(hero.duplicate_unit())).contains_exactly(["Pet Giant Rat"])
	var squad := api._parse_tts_unit({"name": "squad", "size": 3, "bases": {"round": "32"}, "loadout": [item]}, "aof")
	assert_array(EquipmentDistributor.universal_item_labels(squad)).is_empty()
	var labels := EquipmentDistributor.per_model_labels(3, EquipmentDistributor.build_loadout(squad))
	assert_array(labels[0]).contains_exactly(["Pet Giant Rat"])
	assert_array(labels[1]).is_empty()
	assert_array(labels[2]).is_empty()


func test_ratmen_vocabulary_is_scoped_to_ratmen() -> void:
	var lib := _lib()
	assert_str(lib.variant_slug(["Flamethrower"])).is_empty()
	assert_str(lib.variant_slug(["Flamethrower"], "ratmen_clans")).is_empty()
	assert_str(lib.variant_slug(["Flamethrower"], "ratmen")).is_equal("flamethrower")
	# The shared vocabulary still applies to Ratmen.
	assert_str(lib.variant_slug(["Spear", "Pet Giant Rat"], "ratmen")).is_equal("petrat+spear")


func test_other_faction_items_never_join_the_labels() -> void:
	var lib := _lib()
	lib.apply_manifest_text(JSON.stringify({"models": {"mummified_undead/skeleton leader#staff": {}}}))
	var labels := lib.labels_with_available_items("mummified_undead", "Skeleton Leader", ["Hand Weapon"], ["Priest"])
	assert_array(labels).is_equal(["Hand Weapon"])

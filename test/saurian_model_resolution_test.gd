extends GdUnitTestSuite
## Saurians (AoF) vocabulary: the army-book words of the Saurian upgrades resolve to the baked
## `saurians/<unit>#<slug>` variants. Words are spelled exactly as the army book spells them.

const SAURIAN_ARMY := "BubhE1kUpgYbqZvW"


func _manager(keys: Array) -> OPRArmyManager:
	var lib: ModelLibrary = auto_free(ModelLibrary.new())
	lib._load_label_slug_map()
	var models := {}
	for key in keys:
		models[key] = {"url": "x.glb", "sha256": "x", "size": 1}
	lib.apply_manifest_text(JSON.stringify({"version": 1, "models": models}))
	var manager: OPRArmyManager = auto_free(OPRArmyManager.new())
	manager.model_library = lib
	return manager


func _army(units: Array) -> OPRApiClient.OPRArmy:
	var api: OPRApiClient = auto_free(OPRApiClient.new())
	return api.build_army_offline({"gameSystem": "aof", "units": units})


func _titan(form: String) -> Dictionary:
	return {"armyId": SAURIAN_ARMY, "name": "Dread Titan", "size": 1, "bases": {"round": "120x92"},
		"loadout": [
			{"type": "ArmyBookWeapon", "name": "Stomp", "attacks": 6, "count": 1},
			{"type": "ArmyBookWeapon", "name": "Vicious Jaws", "attacks": 4, "count": 1},
			{"type": "ArmyBookItem", "name": form, "count": 1,
				"content": [{"type": "ArmyBookRule", "name": "Tough", "rating": 6}]}]}


func test_dread_titan_forms_resolve_their_variants() -> void:
	var manager := _manager(["saurians/dread titan#behemoth", "saurians/dread titan#carrier"])
	var fighter := _army([_titan("Dread Behemoth Fighter")])
	assert_str(fighter.faction_folder).is_equal("saurians")
	assert_array(manager._unit_model_variant_names(fighter.units[0], "saurians")) \
		.is_equal(["Dread Titan#behemoth"])
	var carrier := _army([_titan("Dread Behemoth Carrier")])
	assert_array(manager._unit_model_variant_names(carrier.units[0], "saurians")) \
		.is_equal(["Dread Titan#carrier"])


func test_deinonychus_javelin_replaces_the_lance() -> void:
	var army := _army([{"armyId": SAURIAN_ARMY, "name": "Deinonychus Riders", "size": 2,
		"bases": {"round": "60x35"}, "loadout": [
			{"type": "ArmyBookWeapon", "name": "Javelin", "range": 12, "attacks": 1, "count": 2},
			{"type": "ArmyBookWeapon", "name": "Hand Weapon", "attacks": 1, "count": 2}]}])
	var manager := _manager(["saurians/deinonychus riders#javelin"])
	assert_array(manager._unit_model_variant_names(army.units[0], "saurians")) \
		.is_equal(["Deinonychus Riders#javelin", "Deinonychus Riders#javelin"])


func test_saurian_upgrade_words_map_to_the_plan_slugs() -> void:
	var lib: ModelLibrary = auto_free(ModelLibrary.new())
	lib._load_label_slug_map()
	var expected := {"Javelin": "javelin", "Blowpipe": "blowpipe", "Fire Bolas": "bolas",
		"Rock Barrage": "rocks", "Priest Rider": "priestrider", "Javelin Crew": "javelins",
		"Serpent Ark": "serpentark", "Solar Beam": "solarbeam", "Mace Tail": "macetail",
		"Dread Behemoth Fighter": "behemoth", "Dread Behemoth Carrier": "carrier",
		"Champion Javelin": "javelin", "Champion Blowpipe": "blowpipe", "Champion Fire Bolas": "bolas",
		"Deinonychus": "deinonychus", "Pterodactyl": "pterodactyl", "Ripjawdactyl": "ripjawdactyl",
		"Ancient Palanquin": "palanquin"}
	for word in expected:
		assert_str(lib.variant_slug([word], "saurians")).is_equal(expected[word])
	# Scoped: another faction does not read the Saurian words.
	assert_str(lib.variant_slug(["Serpent Ark"], "ratmen")).is_equal("")

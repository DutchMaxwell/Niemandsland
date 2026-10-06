extends GdUnitTestSuite
## Vampiric Undead (AoF) vocabulary: the army-book words of the Vampiric Undead upgrades resolve to the
## baked `vampiric_undead/<unit>#<slug>` variants. The Vampiric Undead bakes name their command models
## sergeant / banner / musician and their weapons and mounts by the book word, so the faction section
## overrides the shared crest / horn / heavy / heavylance / steed slugs for this faction only.

const VU_ARMY := "qABIfXYbYxmA75yL"


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


func _command(role: String) -> Dictionary:
	return {"upgrade": {"uid": "E1", "label": "Upgrade up to three models with one", "variant": "upgrade",
			"model": true, "affects": {"type": "up to", "value": 3}, "select": {"type": "exactly", "value": 1},
			"targets": [], "isCommandGroup": true},
		"option": {"label": role, "gains": [{"type": "ArmyBookRule", "name": role, "count": 1}]}}


func test_vampiric_undead_words_map_to_the_baked_slugs() -> void:
	var lib: ModelLibrary = auto_free(ModelLibrary.new())
	lib._load_label_slug_map()
	var expected := {"Sergeant": "sergeant", "Banner": "banner", "Musician": "musician",
		"Halberd": "halberd", "Cursed Halberd": "halberd", "Heavy Halberd": "halberd",
		"Cursed Spear": "spear", "Heavy Spear": "spear", "Cursed Lance": "lance", "Heavy Lance": "heavy_lance",
		"Heavy Hand Weapon": "heavy_hand_weapon", "Cursed Dual Hand Weapons": "dual",
		"Dual Heavy Hand Weapons": "dual", "Cursed Greatsword": "greatsword", "Heavy Great Weapon": "great_weapon",
		"Champion Cursed Crossbow": "crossbow", "Carving Tool": "carving_tool",
		"Skeletal Steed": "skeletal_steed", "Abyssal Beast": "abyssal_beast", "Steed": "steed",
		"Hunting Pet": "hunting_pet", "Pet Ghoul": "pet_ghoul", "Stitched Leader": "stitched_leader",
		"Cursed Mace": "mace", "Sling": "sling",
		"Wings": "wings", "Heavy Rending Claws": "claws", "Great Sword": "greatsword"}
	for word in expected:
		assert_str(lib.variant_slug([word], "vampiric_undead")).is_equal(expected[word])
	# Scoped: the other factions keep the shared slugs.
	assert_str(lib.variant_slug(["Sergeant"], "ratmen")).is_equal("crest")
	assert_str(lib.variant_slug(["Heavy Hand Weapon"], "ratmen")).is_equal("heavy")


func test_command_models_with_the_default_heavy_weapon_resolve_their_bakes() -> void:
	var army := _army([{"armyId": VU_ARMY, "name": "Vampire Knights", "size": 5, "bases": {"round": "60x35"},
		"loadout": [{"type": "ArmyBookWeapon", "name": "Heavy Hand Weapon", "attacks": 1, "count": 5,
			"specialRules": [{"name": "AP", "rating": 1}]}],
		"selectedUpgrades": [_command("Sergeant"), _command("Banner"), _command("Musician")]}])
	assert_str(army.faction_folder).is_equal("vampiric_undead")
	var manager := _manager(["vampiric_undead/vampire knights#heavy_hand_weapon+sergeant",
		"vampiric_undead/vampire knights#banner+heavy_hand_weapon",
		"vampiric_undead/vampire knights#heavy_hand_weapon+musician"])
	assert_array(manager._unit_model_variant_names(army.units[0], "vampiric_undead")).is_equal([
		"Vampire Knights#heavy_hand_weapon+sergeant", "Vampire Knights#banner+heavy_hand_weapon",
		"Vampire Knights#heavy_hand_weapon+musician", "", ""])


func test_hero_book_weapon_on_a_mount_resolves_the_composed_bake() -> void:
	var army := _army([{"armyId": VU_ARMY, "name": "Skeleton Champion", "size": 1, "bases": {"round": "25"},
		"loadout": [
			{"type": "ArmyBookWeapon", "name": "Cursed Halberd", "attacks": 3, "count": 1},
			{"type": "ArmyBookItem", "name": "Skeletal Steed", "count": 1,
				"content": [{"type": "ArmyBookRule", "name": "Fast"}, {"type": "ArmyBookRule", "name": "Impact", "rating": 1}]}]}])
	var manager := _manager(["vampiric_undead/skeleton champion#halberd",
		"vampiric_undead/skeleton champion#halberd+skeletal_steed"])
	assert_array(manager._unit_model_variant_names(army.units[0], "vampiric_undead")) \
		.is_equal(["Skeleton Champion#halberd+skeletal_steed"])


func test_replaced_heavy_hand_weapon_resolves_the_werewolf_cleaver() -> void:
	var army := _army([{"armyId": VU_ARMY, "name": "Werewolves", "size": 3, "bases": {"round": "40"},
		"loadout": [{"type": "ArmyBookWeapon", "name": "Heavy Hand Weapon", "attacks": 3, "count": 3,
			"specialRules": [{"name": "AP", "rating": 1}]}]}])
	var manager := _manager(["vampiric_undead/werewolves#heavy_hand_weapon"])
	assert_array(manager._unit_model_variant_names(army.units[0], "vampiric_undead")).is_equal([
		"Werewolves#heavy_hand_weapon", "Werewolves#heavy_hand_weapon", "Werewolves#heavy_hand_weapon"])


func _drained_leader_with_pet() -> OPRApiClient.OPRArmy:
	return _army([{"armyId": VU_ARMY, "name": "Drained Leader", "size": 1, "bases": {"round": "25"},
		"loadout": [
			{"type": "ArmyBookWeapon", "name": "Great Weapon", "attacks": 3, "count": 1},
			{"type": "ArmyBookWeapon", "name": "Bow", "attacks": 2, "count": 1},
			{"type": "ArmyBookItem", "name": "Pet Ghoul", "count": 1,
				"content": [{"type": "ArmyBookRule", "name": "Repel Ambushers"}]}]}])


func test_hero_item_pet_resolves_the_composed_bake_when_shipped() -> void:
	var manager := _manager(["vampiric_undead/drained leader#bow+greatweapon",
		"vampiric_undead/drained leader#bow+greatweapon+pet_ghoul"])
	assert_array(manager._unit_model_variant_names(_drained_leader_with_pet().units[0], "vampiric_undead")) 		.is_equal(["Drained Leader#bow+greatweapon+pet_ghoul"])


func test_hero_item_pet_falls_back_to_the_weapon_bake_when_not_shipped() -> void:
	var manager := _manager(["vampiric_undead/drained leader#bow+greatweapon"])
	assert_array(manager._unit_model_variant_names(_drained_leader_with_pet().units[0], "vampiric_undead")) 		.is_equal(["Drained Leader#bow+greatweapon"])


func test_bat_beast_wings_item_resolves_the_spread_wings_bake() -> void:
	var army := _army([{"armyId": VU_ARMY, "name": "Bat Beast", "size": 1, "bases": {"round": "60"},
		"loadout": [
			{"type": "ArmyBookWeapon", "name": "Deadly Fangs", "attacks": 6, "count": 1},
			{"type": "ArmyBookItem", "name": "Wings", "count": 1,
				"content": [{"type": "ArmyBookRule", "name": "Flying"}]}]}])
	var manager := _manager(["vampiric_undead/bat beast", "vampiric_undead/bat beast#wings"])
	assert_array(manager._unit_model_variant_names(army.units[0], "vampiric_undead")).is_equal(["Bat Beast#wings"])


func test_werewolf_champion_claws_resolve_their_bake() -> void:
	var army := _army([{"armyId": VU_ARMY, "name": "Werewolf Champion", "size": 1, "bases": {"round": "50"},
		"loadout": [{"type": "ArmyBookWeapon", "name": "Heavy Rending Claws", "attacks": 6, "count": 1}]}])
	var manager := _manager(["vampiric_undead/werewolf champion", "vampiric_undead/werewolf champion#claws"])
	assert_array(manager._unit_model_variant_names(army.units[0], "vampiric_undead")).is_equal(["Werewolf Champion#claws"])


func test_werewolves_default_claws_fall_back_to_the_base_model() -> void:
	# 'heavy rending claws' -> claws also covers the Werewolves' default: no werewolves#claws bake -> the base model.
	var army := _army([{"armyId": VU_ARMY, "name": "Werewolves", "size": 3, "bases": {"round": "40"},
		"loadout": [{"type": "ArmyBookWeapon", "name": "Heavy Rending Claws", "attacks": 3, "count": 3}]}])
	var manager := _manager(["vampiric_undead/werewolves", "vampiric_undead/werewolves#heavy_hand_weapon"])
	assert_array(manager._unit_model_variant_names(army.units[0], "vampiric_undead")).is_equal(["", "", ""])

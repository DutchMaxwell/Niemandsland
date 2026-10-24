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


func _corpse_wagon(item: String) -> OPRApiClient.OPRArmy:
	var loadout: Array = [{"type": "ArmyBookWeapon", "name": "Crew Attacks", "attacks": 8, "count": 1}]
	if not item.is_empty():
		loadout.append({"type": "ArmyBookItem", "name": item, "count": 1,
			"content": [{"type": "ArmyBookRule", "name": "Regeneration"}]})
	return _army([{"armyId": VU_ARMY, "name": "Corpse Wagon", "size": 1, "bases": {"round": "120x92"},
		"loadout": loadout}])


func test_corpse_wagon_options_resolve_their_machine_bakes() -> void:
	# Each Corpse Wagon option is its own machine composition (faction doctrine rule 6).
	var manager := _manager(["vampiric_undead/corpse wagon", "vampiric_undead/corpse wagon#monolith",
		"vampiric_undead/corpse wagon#brazier", "vampiric_undead/corpse wagon#corpse_pile"])
	for pair in [["Cursed Monolith", "Corpse Wagon#monolith"], ["Unholy Brazier", "Corpse Wagon#brazier"],
			["Corpse Pile", "Corpse Wagon#corpse_pile"]]:
		assert_array(manager._unit_model_variant_names(_corpse_wagon(pair[0]).units[0], "vampiric_undead")) \
			.is_equal([pair[1]])


func test_corpse_wagon_without_an_option_is_the_base_model() -> void:
	var manager := _manager(["vampiric_undead/corpse wagon", "vampiric_undead/corpse wagon#monolith"])
	assert_array(manager._unit_model_variant_names(_corpse_wagon("").units[0], "vampiric_undead")).is_equal([""])


# ===== Hero dragon mounts (Vampire Master: Zombie / Skeleton Dragon, Ghoul Champion: Bat Dragon) =====
# The mount word folds into the carrier's labels like a weapon, so a composed `<hero>#<weapon>+<mountslug>`
# bake resolves once the manifest ships it; until then the hero keeps its weapon-only bake.

func _hero_on_dragon(unit: String, weapons: Array, dragon: String) -> OPRApiClient.OPRArmy:
	var loadout: Array = []
	for w in weapons:
		loadout.append({"type": "ArmyBookWeapon", "name": w, "attacks": 3, "count": 1})
	loadout.append({"type": "ArmyBookItem", "name": dragon, "count": 1,
		"content": [{"type": "ArmyBookRule", "name": "Flying"}]})
	return _army([{"armyId": VU_ARMY, "name": unit, "size": 1, "bases": {"round": "120x92"}, "loadout": loadout}])


func test_dragon_mount_words_map_to_the_baked_slugs() -> void:
	var lib: ModelLibrary = auto_free(ModelLibrary.new())
	lib._load_label_slug_map()
	assert_str(lib.variant_slug(["Zombie Dragon"], "vampiric_undead")).is_equal("zombie_dragon")
	assert_str(lib.variant_slug(["Skeleton Dragon"], "vampiric_undead")).is_equal("skeleton_dragon")
	assert_str(lib.variant_slug(["Bat Dragon"], "vampiric_undead")).is_equal("bat_dragon")
	# Scoped: other factions do not get the dragon slugs.
	assert_str(lib.variant_slug(["Zombie Dragon"], "mummified_undead")).is_equal("")


func test_vampire_master_on_a_dragon_resolves_the_composed_bake() -> void:
	var manager := _manager(["vampiric_undead/vampire master#heavy_hand_weapon+zombie_dragon",
		"vampiric_undead/vampire master#heavy_lance+skeleton_dragon",
		"vampiric_undead/vampire master#skeleton_dragon+spear"])
	var zombie := _hero_on_dragon("Vampire Master", ["Heavy Hand Weapon"], "Zombie Dragon")
	assert_array(manager._unit_model_variant_names(zombie.units[0], "vampiric_undead")) \
		.is_equal(["Vampire Master#heavy_hand_weapon+zombie_dragon"])
	var lance := _hero_on_dragon("Vampire Master", ["Heavy Lance"], "Skeleton Dragon")
	assert_array(manager._unit_model_variant_names(lance.units[0], "vampiric_undead")) \
		.is_equal(["Vampire Master#heavy_lance+skeleton_dragon"])
	# Slugs are SORTED: skeleton_dragon sorts before spear.
	var spear := _hero_on_dragon("Vampire Master", ["Heavy Spear"], "Skeleton Dragon")
	assert_array(manager._unit_model_variant_names(spear.units[0], "vampiric_undead")) \
		.is_equal(["Vampire Master#skeleton_dragon+spear"])


func test_ghoul_champion_on_a_bat_dragon_resolves_the_composed_bake() -> void:
	var manager := _manager(["vampiric_undead/ghoul champion#bat_dragon+greatweapon+sling"])
	var army := _hero_on_dragon("Ghoul Champion", ["Great Weapon", "Sling"], "Bat Dragon")
	assert_array(manager._unit_model_variant_names(army.units[0], "vampiric_undead")) \
		.is_equal(["Ghoul Champion#bat_dragon+greatweapon+sling"])


func test_dragon_mount_without_a_shipped_bake_keeps_the_weapon_bake() -> void:
	# The dragon keys are not live yet: the hero must resolve exactly as before (weapon-only bake).
	var manager := _manager(["vampiric_undead/vampire master#heavy_lance"])
	var army := _hero_on_dragon("Vampire Master", ["Heavy Lance"], "Zombie Dragon")
	assert_array(manager._unit_model_variant_names(army.units[0], "vampiric_undead")) \
		.is_equal(["Vampire Master#heavy_lance"])


# ===== Hero winged mounts (Vampire Master: Winged Steed / Winged Terror) =====
# Same pattern as the dragon mounts: the book word folds into the carrier's labels, so a composed
# `<hero>#<weapon>+<mountslug>` bake resolves once the manifest ships it; until then the hero keeps its weapon-only bake.

func test_winged_mount_words_map_to_the_baked_slugs() -> void:
	var lib: ModelLibrary = auto_free(ModelLibrary.new())
	lib._load_label_slug_map()
	assert_str(lib.variant_slug(["Winged Steed"], "vampiric_undead")).is_equal("winged_steed")
	assert_str(lib.variant_slug(["Winged Terror"], "vampiric_undead")).is_equal("winged_terror")
	# Scoped: other factions do not get the winged slugs.
	assert_str(lib.variant_slug(["Winged Steed"], "mummified_undead")).is_equal("")


func test_vampire_master_on_a_winged_steed_resolves_the_composed_bake() -> void:
	var manager := _manager(["vampiric_undead/vampire master#heavy_hand_weapon+winged_steed",
		"vampiric_undead/vampire master#dual+winged_steed",
		"vampiric_undead/vampire master#spear+winged_steed"])
	var base := _hero_on_dragon("Vampire Master", ["Heavy Hand Weapon"], "Winged Steed")
	assert_array(manager._unit_model_variant_names(base.units[0], "vampiric_undead")) \
		.is_equal(["Vampire Master#heavy_hand_weapon+winged_steed"])
	var spear := _hero_on_dragon("Vampire Master", ["Heavy Spear"], "Winged Steed")
	assert_array(manager._unit_model_variant_names(spear.units[0], "vampiric_undead")) \
		.is_equal(["Vampire Master#spear+winged_steed"])


func test_vampire_master_on_a_winged_terror_resolves_the_composed_bake() -> void:
	var manager := _manager(["vampiric_undead/vampire master#heavy_lance+winged_terror",
		"vampiric_undead/vampire master#great_weapon+winged_terror"])
	var lance := _hero_on_dragon("Vampire Master", ["Heavy Lance"], "Winged Terror")
	assert_array(manager._unit_model_variant_names(lance.units[0], "vampiric_undead")) \
		.is_equal(["Vampire Master#heavy_lance+winged_terror"])
	# Slugs are SORTED: great_weapon sorts before winged_terror.
	var great := _hero_on_dragon("Vampire Master", ["Heavy Great Weapon"], "Winged Terror")
	assert_array(manager._unit_model_variant_names(great.units[0], "vampiric_undead")) \
		.is_equal(["Vampire Master#great_weapon+winged_terror"])


func test_winged_mount_without_a_shipped_bake_keeps_the_weapon_bake() -> void:
	# The winged keys are not live yet: the hero must resolve exactly as before (weapon-only bake).
	var manager := _manager(["vampiric_undead/vampire master#heavy_lance"])
	var army := _hero_on_dragon("Vampire Master", ["Heavy Lance"], "Winged Terror")
	assert_array(manager._unit_model_variant_names(army.units[0], "vampiric_undead")) \
		.is_equal(["Vampire Master#heavy_lance"])


# ===== Ghoul Champion on a Bat Beast =====
# Same pattern as the dragon / winged mounts: the book word folds into the carrier's labels, so a composed
# `ghoul champion#<weapons>+bat_beast` bake resolves once the manifest ships it. Slugs are SORTED:
# bat_beast sorts before greatweapon, lance and sling.

func test_bat_beast_mount_word_maps_to_the_baked_slug() -> void:
	var lib: ModelLibrary = auto_free(ModelLibrary.new())
	lib._load_label_slug_map()
	assert_str(lib.variant_slug(["Bat Beast"], "vampiric_undead")).is_equal("bat_beast")
	assert_str(lib.variant_slug(["Great Weapon", "Bat Beast", "Sling"], "vampiric_undead")).is_equal("bat_beast+greatweapon+sling")
	# Scoped: other factions do not get the slug.
	assert_str(lib.variant_slug(["Bat Beast"], "mummified_undead")).is_equal("")


func test_ghoul_champion_on_a_bat_beast_resolves_the_six_composed_bakes() -> void:
	var manager := _manager(["vampiric_undead/ghoul champion#bat_beast", "vampiric_undead/ghoul champion#bat_beast+greatweapon",
		"vampiric_undead/ghoul champion#bat_beast+lance", "vampiric_undead/ghoul champion#bat_beast+sling",
		"vampiric_undead/ghoul champion#bat_beast+greatweapon+sling", "vampiric_undead/ghoul champion#bat_beast+lance+sling"])
	var cases := {
		"Ghoul Champion#bat_beast": [],
		"Ghoul Champion#bat_beast+greatweapon": ["Great Weapon"],
		"Ghoul Champion#bat_beast+lance": ["Lance"],
		"Ghoul Champion#bat_beast+sling": ["Sling"],
		"Ghoul Champion#bat_beast+greatweapon+sling": ["Great Weapon", "Sling"],
		"Ghoul Champion#bat_beast+lance+sling": ["Lance", "Sling"],
	}
	for want in cases:
		var army := _hero_on_dragon("Ghoul Champion", cases[want], "Bat Beast")
		assert_array(manager._unit_model_variant_names(army.units[0], "vampiric_undead")).is_equal([want])


func test_ghoul_champion_on_a_bat_beast_without_a_shipped_bake_keeps_the_weapon_bake() -> void:
	# The bat_beast keys are not shipped: the variant-name list still falls back to the weapon-only name. (The tier the whole resolver assigns
	# in that state is a separate question: exact_check against the live manifest puts these forms on the bare bat beast model until the keys ship.)
	var manager := _manager(["vampiric_undead/ghoul champion#greatweapon"])
	var army := _hero_on_dragon("Ghoul Champion", ["Great Weapon"], "Bat Beast")
	assert_array(manager._unit_model_variant_names(army.units[0], "vampiric_undead")) \
		.is_equal(["Ghoul Champion#greatweapon"])


# ===== Ghoul Champion on a Winged Beast =====
# Same pattern as the dragon / winged steed / winged terror words: the book word folds into the carrier's labels, so a composed
# `ghoul champion#<weapons>+winged_beast` bake resolves once the manifest ships it. Slugs are SORTED: greatweapon, lance and sling
# sort BEFORE winged_beast (unlike bat_beast).

func test_winged_beast_mount_word_maps_to_the_baked_slug() -> void:
	var lib: ModelLibrary = auto_free(ModelLibrary.new())
	lib._load_label_slug_map()
	assert_str(lib.variant_slug(["Winged Beast"], "vampiric_undead")).is_equal("winged_beast")
	assert_str(lib.variant_slug(["Great Weapon", "Winged Beast", "Sling"], "vampiric_undead")).is_equal("greatweapon+sling+winged_beast")
	# Scoped: other factions do not get the slug.
	assert_str(lib.variant_slug(["Winged Beast"], "mummified_undead")).is_equal("")


func test_ghoul_champion_on_a_winged_beast_resolves_the_six_composed_bakes() -> void:
	var manager := _manager(["vampiric_undead/ghoul champion#winged_beast", "vampiric_undead/ghoul champion#greatweapon+winged_beast",
		"vampiric_undead/ghoul champion#lance+winged_beast", "vampiric_undead/ghoul champion#sling+winged_beast",
		"vampiric_undead/ghoul champion#greatweapon+sling+winged_beast", "vampiric_undead/ghoul champion#lance+sling+winged_beast"])
	var cases := {
		"Ghoul Champion#winged_beast": [],
		"Ghoul Champion#greatweapon+winged_beast": ["Great Weapon"],
		"Ghoul Champion#lance+winged_beast": ["Lance"],
		"Ghoul Champion#sling+winged_beast": ["Sling"],
		"Ghoul Champion#greatweapon+sling+winged_beast": ["Great Weapon", "Sling"],
		"Ghoul Champion#lance+sling+winged_beast": ["Lance", "Sling"],
	}
	for want in cases:
		var army := _hero_on_dragon("Ghoul Champion", cases[want], "Winged Beast")
		assert_array(manager._unit_model_variant_names(army.units[0], "vampiric_undead")).is_equal([want])


func test_ghoul_champion_on_a_winged_beast_without_a_shipped_bake_keeps_the_weapon_bake() -> void:
	# The winged_beast keys are not shipped: the variant-name list still falls back to the weapon-only name. (The tier the whole resolver assigns
	# in that state is a separate question: exact_check against the live manifest puts these forms on another unit's mount model until the keys ship.)
	var manager := _manager(["vampiric_undead/ghoul champion#greatweapon"])
	var army := _hero_on_dragon("Ghoul Champion", ["Great Weapon"], "Winged Beast")
	assert_array(manager._unit_model_variant_names(army.units[0], "vampiric_undead")) \
		.is_equal(["Ghoul Champion#greatweapon"])


# ===== Vampire Master on a Stitched Zombie Horde =====
# Same pattern as the dragon / winged mount words: the book word folds into the carrier's labels, so a composed
# `vampire master#<weapon>+stitched_zombie_horde` bake resolves once the manifest ships it. Slugs are SORTED: every Vampire Master
# weapon slug (dual, great_weapon, halberd, heavy_hand_weapon, heavy_lance, spear) sorts BEFORE stitched_zombie_horde.

func test_stitched_zombie_horde_mount_word_maps_to_the_baked_slug() -> void:
	var lib: ModelLibrary = auto_free(ModelLibrary.new())
	lib._load_label_slug_map()
	assert_str(lib.variant_slug(["Stitched Zombie Horde"], "vampiric_undead")).is_equal("stitched_zombie_horde")
	assert_str(lib.variant_slug(["Heavy Spear", "Stitched Zombie Horde"], "vampiric_undead")).is_equal("spear+stitched_zombie_horde")
	# Scoped: other factions do not get the slug.
	assert_str(lib.variant_slug(["Stitched Zombie Horde"], "mummified_undead")).is_equal("")


func test_vampire_master_on_a_stitched_zombie_horde_resolves_the_six_composed_bakes() -> void:
	var manager := _manager(["vampiric_undead/vampire master#heavy_hand_weapon+stitched_zombie_horde",
		"vampiric_undead/vampire master#dual+stitched_zombie_horde", "vampiric_undead/vampire master#great_weapon+stitched_zombie_horde",
		"vampiric_undead/vampire master#halberd+stitched_zombie_horde", "vampiric_undead/vampire master#heavy_lance+stitched_zombie_horde",
		"vampiric_undead/vampire master#spear+stitched_zombie_horde"])
	var cases := {
		"Vampire Master#heavy_hand_weapon+stitched_zombie_horde": ["Heavy Hand Weapon"],
		"Vampire Master#dual+stitched_zombie_horde": ["Dual Heavy Hand Weapons"],
		"Vampire Master#great_weapon+stitched_zombie_horde": ["Heavy Great Weapon"],
		"Vampire Master#halberd+stitched_zombie_horde": ["Heavy Halberd"],
		"Vampire Master#heavy_lance+stitched_zombie_horde": ["Heavy Lance"],
		"Vampire Master#spear+stitched_zombie_horde": ["Heavy Spear"],
	}
	for want in cases:
		var army := _hero_on_dragon("Vampire Master", cases[want], "Stitched Zombie Horde")
		assert_array(manager._unit_model_variant_names(army.units[0], "vampiric_undead")).is_equal([want])


func test_stitched_zombie_horde_without_a_shipped_bake_keeps_the_weapon_bake() -> void:
	# The stitched_zombie_horde keys are not shipped: the variant-name list still falls back to the weapon-only name.
	var manager := _manager(["vampiric_undead/vampire master#halberd"])
	var army := _hero_on_dragon("Vampire Master", ["Heavy Halberd"], "Stitched Zombie Horde")
	assert_array(manager._unit_model_variant_names(army.units[0], "vampiric_undead")) \
		.is_equal(["Vampire Master#halberd"])

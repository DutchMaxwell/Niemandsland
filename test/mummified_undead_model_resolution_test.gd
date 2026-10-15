extends GdUnitTestSuite
## Mummified Undead (AoF): the Sphinx Champion's Wings and the God-Titan's Godly Spear resolve to the
## baked `mummified_undead/<unit>#<slug>` variants. "Wings" is an ArmyBookItem (not a weapon), so it only
## reaches the slug through the faction-scoped section of label_slug_map.json.
## The fixture manifest holds the four keys of the Mummified review (not live yet).

const MU_ARMY := "t-sIke2snonFSL6Q"

const KEYS := [
	"mummified_undead/sphinx champion",
	"mummified_undead/sphinx champion#greatweapon",
	"mummified_undead/sphinx champion#dual+wings",
	"mummified_undead/sphinx champion#greatweapon+wings",
	"mummified_undead/god-titan",
	"mummified_undead/god-titan#spear",
]


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


func _weapon(wname: String, attacks: int) -> Dictionary:
	return {"type": "ArmyBookWeapon", "name": wname, "attacks": attacks, "range": 0, "count": 1}


func _sphinx(weapon: Dictionary, with_wings: bool) -> Dictionary:
	var loadout := [weapon, _weapon("Stomp", 4)]
	if with_wings:
		loadout.append({"type": "ArmyBookItem", "name": "Wings", "count": 1,
			"content": [{"type": "ArmyBookRule", "name": "Flying"}]})
	return {"armyId": MU_ARMY, "name": "Sphinx Champion", "size": 1, "bases": {"round": "120x92"},
		"loadout": loadout}


func _titan(weapon_name: String) -> Dictionary:
	return {"armyId": MU_ARMY, "name": "God-Titan", "size": 1, "bases": {"round": "none"},
		"loadout": [_weapon(weapon_name, 4), _weapon("Stomp", 8)]}


func test_wings_and_godly_spear_words_map_to_their_slugs() -> void:
	var lib: ModelLibrary = auto_free(ModelLibrary.new())
	lib._load_label_slug_map()
	assert_str(lib.variant_slug(["Wings"], "mummified_undead")).is_equal("wings")
	assert_str(lib.variant_slug(["Godly Spear"], "mummified_undead")).is_equal("spear")
	# Scoped: another faction's "Godly Spear" / "Wings" gain is not re-slugged by the Mummified section.
	assert_str(lib.variant_slug(["Godly Spear"], "ratmen")).is_equal("")
	assert_str(lib.variant_slug(["Wings"], "ratmen")).is_equal("")


func test_sphinx_with_wings_resolves_the_dual_wings_variant() -> void:
	# The default Dual Hand Weapons slug (dual) stays in the key: the Wings-only Sphinx asks for #dual+wings.
	var manager := _manager(KEYS)
	var army := _army([_sphinx(_weapon("Dual Hand Weapons", 10), true)])
	assert_str(army.faction_folder).is_equal("mummified_undead")
	assert_array(manager._unit_model_variant_names(army.units[0], "mummified_undead")) \
		.is_equal(["Sphinx Champion#dual+wings"])


func test_sphinx_with_great_weapon_and_wings_resolves_the_combined_variant() -> void:
	var manager := _manager(KEYS)
	var army := _army([_sphinx(_weapon("Great Weapon", 6), true)])
	assert_array(manager._unit_model_variant_names(army.units[0], "mummified_undead")) \
		.is_equal(["Sphinx Champion#greatweapon+wings"])


func test_sphinx_with_great_weapon_alone_keeps_resolving() -> void:
	var manager := _manager(KEYS)
	var army := _army([_sphinx(_weapon("Great Weapon", 6), false)])
	assert_array(manager._unit_model_variant_names(army.units[0], "mummified_undead")) \
		.is_equal(["Sphinx Champion#greatweapon"])


func test_god_titan_with_the_godly_spear_resolves_the_spear_variant() -> void:
	var manager := _manager(KEYS)
	var army := _army([_titan("Godly Spear")])
	assert_array(manager._unit_model_variant_names(army.units[0], "mummified_undead")) \
		.is_equal(["God-Titan#spear"])
	var default_army := _army([_titan("Godly Battle-Axe")])
	assert_array(manager._unit_model_variant_names(default_army.units[0], "mummified_undead")) \
		.is_equal([""])

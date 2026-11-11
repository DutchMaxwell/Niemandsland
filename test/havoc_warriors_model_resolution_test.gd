extends GdUnitTestSuite
## Havoc Warriors (AoF): the faction-scoped label section makes the planned `#great` bakes resolve
## without renaming the package. Without `_faction_havoc_warriors`, "Heavy Great Weapon" falls back to
## the shared `sword` slug and every Havoc expectation below fails.
##
## The control case is declared FIRST: the gate runs with fail-fast, so it must pass before the one
## proving case fails without the section.

const HAVOC_ARMY := "PGxKcq4R571OtwqD"

const KEYS := [
	"havoc_warriors/warriors#great",
	"havoc_warriors/havoc master#great",
	"havoc_warriors/chosen havoc master#great",
	"havoc_warriors/chosen warriors#great",
]

const HAVOC_SLUGS := {
	"great weapon": "great",
	"heavy great weapon": "great",
	"heavy halberd": "halberd",
	"heavy lance": "lance",
	"heavy hand weapon": "",
	"sergeant": "plume",
	"musician": "horn",
	"banner": "banner",
	"dual heavy hand weapons": "dual",
	"horse": "horse",
	"beast chariot": "beastchariot",
	"chariot": "chariot",
	"daemon mount": "daemonmount",
	"daemon chain": "chain",
	"daemon gauntlet": "gauntlet",
	"daemon hammer": "hammer",
	"daemon spear": "spear",
	"daemon sword": "sword",
	"doom fire": "doomfire",
	"flail": "flail",
	"havoc dragon": "dragon",
	"heavy havoc sword": "sword",
	"horse master": "horse",
	"manticore": "manticore",
	"shortbow": "bow",
	"wings": "wings",
	# Rules 3.6 names for the same bakes.
	"master great weapon": "great",
	"master halberd": "halberd",
	"master lance": "lance",
	"havoc chariot": "chariot",
	"great beast chariot": "beastchariot",
	"javelins": "javelin",
	"barbed javelins": "javelin",
	"rapid shortbow": "bow",
	"doom-fire bombard": "doomfire",
}


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


func _unit(unit_name: String, weapon: String) -> Dictionary:
	return {"armyId": HAVOC_ARMY, "name": unit_name, "size": 1, "bases": {"round": "32"},
		"loadout": [{"type": "ArmyBookWeapon", "name": weapon, "attacks": 3, "range": 0, "count": 1}]}


func _library() -> ModelLibrary:
	var lib: ModelLibrary = auto_free(ModelLibrary.new())
	lib._load_label_slug_map()
	return lib


# --- CONTROL: the section is scoped, other factions keep the shared vocabulary -------------------

func test_control_other_faction_keeps_the_shared_slugs() -> void:
	var lib := _library()
	assert_str(lib.variant_slug(["Heavy Great Weapon"], "ratmen")).is_equal("sword")
	assert_str(lib.variant_slug(["Heavy Great Weapon"], "")).is_equal("sword")
	assert_str(lib.variant_slug(["Sergeant"], "ratmen")).is_equal("crest")
	assert_str(lib.variant_slug(["Heavy Hand Weapon"], "ratmen")).is_equal("heavy")


# --- The planned keys resolve (RED on the pre-section label map) --------------------------------

func test_havoc_label_section_maps_the_planned_keys() -> void:
	var manager := _manager(KEYS)
	var lib := _library()
	for case in [["Warriors", "Heavy Great Weapon"], ["Havoc Master", "Heavy Great Weapon"],
			["Chosen Havoc Master", "Heavy Great Weapon"], ["Chosen Warriors", "Heavy Great Weapon"]]:
		var army := _army([_unit(case[0], case[1])])
		assert_str(army.faction_folder).is_equal("havoc_warriors")
		assert_array(manager._unit_model_variant_names(army.units[0], "havoc_warriors")) \
			.is_equal([case[0] + "#great"])
	for label in HAVOC_SLUGS:
		assert_str(lib.variant_slug([label], "havoc_warriors")).is_equal(HAVOC_SLUGS[label])


# --- Rules 3.6: the Masters' weapons are "Master X" and two mounts were renamed ---------------------

func test_rules_3_6_master_weapons_resolve_the_live_great_keys() -> void:
	var manager := _manager(KEYS)
	var lib := _library()
	for unit_name in ["Havoc Master", "Chosen Havoc Master"]:
		var army := _army([_unit(unit_name, "Master Great Weapon")])
		assert_str(army.faction_folder).is_equal("havoc_warriors")
		assert_array(manager._unit_model_variant_names(army.units[0], "havoc_warriors")) \
			.is_equal([unit_name + "#great"])
	# Weapon and renamed mount compose the same slugs as their 3.5 names.
	assert_str(lib.variant_slug(["Master Halberd", "Havoc Chariot"], "havoc_warriors")) \
		.is_equal(lib.variant_slug(["Heavy Halberd", "Chariot"], "havoc_warriors"))
	assert_str(lib.variant_slug(["Master Lance", "Great Beast Chariot"], "havoc_warriors")).is_equal("beastchariot+lance")
	# Scoped: another faction does not learn the Havoc names.
	assert_str(lib.variant_slug(["Master Great Weapon", "Havoc Chariot"], "beastmen")).is_equal("")

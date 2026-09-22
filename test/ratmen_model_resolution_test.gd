extends GdUnitTestSuite
## Ratmen (AoF) go-live: a Ratmen army imported through the game's own list path
## (OPRApiClient.build_army_offline) resolves each model to its pre-baked Ratmen variant — and an
## army of any other faction resolves and distributes exactly as before.

const RATMEN_ARMY := "tOWt5fgqK2nfpoBN"
const MUMMIFIED_ARMY := "t-sIke2snonFSL6Q"
const RATMEN_CLANS_ARMY := "hk70l4d471plza00"


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


func _army(system: String, units: Array) -> OPRApiClient.OPRArmy:
	var api: OPRApiClient = auto_free(OPRApiClient.new())
	return api.build_army_offline({"gameSystem": system, "units": units})


func _weapons_per_model(unit: OPRApiClient.OPRUnit) -> Array:
	var game_unit := GameUnit.new()
	for i in range(unit.size):
		var model := ModelInstance.new()
		model.model_index = i
		model.unit = game_unit
		game_unit.models.append(model)
	EquipmentDistributor.distribute(game_unit, EquipmentDistributor.build_loadout(unit), unit.special_rules)
	return game_unit.models.map(func(m): return m.properties.get("weapons", []).map(func(w): return w.name))


func _warriors_with_drill_team(army_id: String) -> Dictionary:
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://test/fixtures/ratmen_warriors_export.json"))
	var unit: Dictionary = fixtures.drill
	unit["armyId"] = army_id
	return unit


func _storm_ogres(army_id: String) -> Dictionary:
	return {"armyId": army_id, "name": "Storm Ogres", "size": 3, "bases": {"round": "50"},
		"loadout": [
			{"type": "ArmyBookWeapon", "name": "Flame-Fists", "range": 12, "attacks": 1, "count": 2},
			{"type": "ArmyBookWeapon", "name": "Bash", "attacks": 2, "count": 2},
			{"type": "ArmyBookWeapon", "name": "Gatling-Fist", "range": 18, "attacks": 4, "count": 1},
			{"type": "ArmyBookWeapon", "name": "Bash", "attacks": 1, "count": 1}],
		"selectedUpgrades": [{
			"upgrade": {"variant": "replace", "model": false, "affects": {"type": "any"},
				"targets": ["Flame-Fist", "Bash"]},
			"option": {"gains": [
				{"type": "ArmyBookWeapon", "name": "Gatling-Fist", "range": 18, "attacks": 4},
				{"type": "ArmyBookWeapon", "name": "Bash", "attacks": 1}]}}]}


# --- Ratmen resolve (RED on the pre-Ratmen client) ---------------------------------------------

func test_companion_item_resolves_the_composed_variant() -> void:
	var army := _army("aof", [{"armyId": RATMEN_ARMY, "name": "Battle Master", "size": 1,
		"bases": {"round": "32"}, "loadout": [
			{"type": "ArmyBookWeapon", "name": "Heavy Hand Weapon", "attacks": 3, "count": 1,
				"specialRules": [{"name": "AP", "rating": 1}]},
			{"type": "ArmyBookItem", "name": "Pet Giant Rat", "count": 1,
				"content": [{"type": "ArmyBookRule", "name": "Repel Ambushers"}]}]}])
	assert_str(army.faction_folder).is_equal("ratmen")
	var manager := _manager(["ratmen/battle master#heavy", "ratmen/battle master#heavy+petrat"])
	assert_array(manager._unit_model_variant_names(army.units[0], "ratmen")) \
		.is_equal(["Battle Master#heavy+petrat"])


func test_weapon_team_rides_the_model_whose_hand_weapon_it_replaced() -> void:
	var army := _army("aof", [_warriors_with_drill_team(RATMEN_ARMY)])
	var unit: OPRApiClient.OPRUnit = army.units[0]
	var manager := _manager(["ratmen/warriors", "ratmen/warriors#crest", "ratmen/warriors#banner",
		"ratmen/warriors#horn", "ratmen/warriors#drill"])
	assert_array(manager._unit_model_variant_names(unit, "ratmen")).is_equal([
		"Warriors#crest", "Warriors#banner", "Warriors#horn", "", "", "", "", "", "", "Warriors#drill"])
	# The drill model is also the one that fights with the drill and carries the team's Tough.
	assert_array(_weapons_per_model(unit)[9]).is_equal(["Heavy Drill", "Crew"])
	var toughs := EquipmentDistributor.per_model_toughs(unit.size, EquipmentDistributor.build_loadout(unit), unit.special_rules)
	assert_int(toughs[9]).is_equal(3)
	assert_int(toughs[0]).is_equal(1)


func test_storm_ogre_fist_pairs_stay_on_one_model_each() -> void:
	var army := _army("aof", [_storm_ogres(RATMEN_ARMY)])
	var manager := _manager(["ratmen/storm ogres#flame", "ratmen/storm ogres#gatling"])
	assert_array(manager._unit_model_variant_names(army.units[0], "ratmen")).is_equal([
		"Storm Ogres#flame", "Storm Ogres#flame", "Storm Ogres#gatling"])


# --- Every other faction: unchanged (GREEN before and after) ------------------------------------

func test_other_faction_priest_item_keeps_its_base_model() -> void:
	# A shipped `#staff` bake exists and "priest" maps to it in the SHARED vocabulary, but a
	# universal item only joins the labels through its own faction's scoped vocabulary.
	var army := _army("aof", [{"armyId": MUMMIFIED_ARMY, "name": "Skeleton Leader", "size": 1,
		"bases": {"round": "25"}, "loadout": [
			{"type": "ArmyBookWeapon", "name": "Hand Weapon", "attacks": 3, "count": 1},
			{"type": "ArmyBookItem", "name": "Priest", "count": 1,
				"content": [{"type": "ArmyBookRule", "name": "Caster", "rating": 2}]}]}])
	var manager := _manager(["mummified_undead/skeleton leader", "mummified_undead/skeleton leader#staff"])
	assert_array(manager._unit_model_variant_names(army.units[0], "mummified_undead")).is_equal([""])


func test_other_faction_does_not_read_ratmen_gain_vocabulary() -> void:
	var army := _army("gf", [{"armyId": RATMEN_CLANS_ARMY, "name": "Clan Warriors", "size": 2,
		"bases": {"round": "25"}, "loadout": [
			{"type": "ArmyBookWeapon", "name": "Flamethrower", "range": 12, "attacks": 1, "count": 1},
			{"type": "ArmyBookWeapon", "name": "Sniper Rifle", "range": 30, "attacks": 1, "count": 1}]}])
	assert_str(army.faction_folder).is_equal("ratmen_clans")
	var manager := _manager(["ratmen_clans/clan warriors#flamethrower", "ratmen_clans/clan warriors#rifle"])
	assert_array(manager._unit_model_variant_names(army.units[0], "ratmen_clans")).is_equal(["", ""])


func test_other_faction_replace_any_plus_replace_one_keeps_every_model_armed() -> void:
	var army := _army("aof", [{"armyId": MUMMIFIED_ARMY, "name": "Skeleton Warriors", "size": 10,
		"bases": {"round": "25"}, "loadout": [
			{"type": "ArmyBookWeapon", "name": "Hand Weapon", "attacks": 1, "count": 7},
			{"type": "ArmyBookWeapon", "name": "Spear", "attacks": 1, "count": 2},
			{"type": "ArmyBookWeapon", "name": "Great Weapon", "attacks": 1, "count": 1}],
		"selectedUpgrades": [
			{"upgrade": {"variant": "replace", "affects": {"type": "any"}, "targets": ["Hand Weapon"]},
				"option": {"gains": [{"type": "ArmyBookWeapon", "name": "Spear", "attacks": 1, "count": 1}]}},
			{"upgrade": {"variant": "replace", "affects": {"type": "exactly", "value": 1}, "targets": ["Hand Weapon"]},
				"option": {"gains": [{"type": "ArmyBookWeapon", "name": "Great Weapon", "attacks": 1, "count": 1}]}}]}])
	var weapons := _weapons_per_model(army.units[0])
	assert_array(weapons[0]).is_equal(["Hand Weapon"])
	assert_array(weapons[9]).is_equal(["Great Weapon"])


func test_other_faction_weapon_team_parses_without_bundle_metadata() -> void:
	var army := _army("aof", [_warriors_with_drill_team(MUMMIFIED_ARMY)])
	var unit: OPRApiClient.OPRUnit = army.units[0]
	for item in unit.equipment_items:
		assert_bool(item.has("weapons")).is_false()
	for weapon in unit.weapons:
		assert_bool(weapon.to_dict().has("replacement_target")).is_false()

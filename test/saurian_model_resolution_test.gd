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


func test_saurian_veteran_on_a_raptor_never_resolves_the_on_foot_form() -> void:
	# Once the on-foot #heavy form is live, a Veteran on a Raptor must ask for #heavy+raptor, not #heavy.
	var manager := _manager(["saurians/saurian veteran#heavy", "saurians/saurian veteran#heavy+raptor"])
	var army := _army([{"armyId": SAURIAN_ARMY, "name": "Saurian Veteran", "size": 1, "bases": {"round": "60x35"},
		"loadout": [
			{"type": "ArmyBookWeapon", "name": "Heavy Hand Weapon", "attacks": 3, "count": 1},
			{"type": "ArmyBookItem", "name": "Raptor", "count": 1, "bases": {"round": "60x35", "square": "50x25"},
				"content": [{"type": "ArmyBookRule", "name": "Fast"}]}]}])
	assert_array(manager._unit_model_variant_names(army.units[0], "saurians")) \
		.is_equal(["Saurian Veteran#heavy+raptor"])


func _veteran_on_the_tyrannosaur() -> OPRApiClient.OPRArmy:
	return _army([{"armyId": SAURIAN_ARMY, "name": "Saurian Veteran", "size": 1, "bases": {"round": "120x92"},
		"loadout": [
			{"type": "ArmyBookWeapon", "name": "Heavy Hand Weapon", "attacks": 3, "count": 1},
			{"type": "ArmyBookItem", "name": "Tyrannosaur", "count": 1, "bases": {"round": "120x92", "square": "100x50"},
				"content": [{"type": "ArmyBookRule", "name": "Tough", "rating": 12}]}]}])


func test_saurian_veteran_on_a_tyrannosaur_never_resolves_the_on_foot_form() -> void:
	# The on-foot #heavy form may be live while the mounted one is not: the rider must not stand on foot.
	var manager := _manager(["saurians/saurian veteran#heavy"])
	assert_array(manager._unit_model_variant_names(_veteran_on_the_tyrannosaur().units[0], "saurians")).is_equal([""])


func test_saurian_veteran_on_the_tyrannosaur_resolves_the_composed_variant() -> void:
	var manager := _manager(["saurians/saurian veteran#heavy", "saurians/saurian veteran#heavy+tyrannosaur"])
	assert_array(manager._unit_model_variant_names(_veteran_on_the_tyrannosaur().units[0], "saurians")) \
		.is_equal(["Saurian Veteran#heavy+tyrannosaur"])


func test_saurian_veteran_obsidian_great_weapon_resolves_its_form() -> void:
	var manager := _manager(["saurians/saurian veteran#heavy", "saurians/saurian veteran#obsidian"])
	var army := _army([{"armyId": SAURIAN_ARMY, "name": "Saurian Veteran", "size": 1, "bases": {"round": "32"},
		"loadout": [{"type": "ArmyBookWeapon", "name": "Obsidian Great Weapon", "attacks": 3, "count": 1}]}])
	assert_array(manager._unit_model_variant_names(army.units[0], "saurians")) \
		.is_equal(["Saurian Veteran#obsidian"])


func test_saurian_guardians_banner_keeps_its_badge_with_the_obsidian_word() -> void:
	# Guardians carry the Obsidian Great Weapon by default, so the banner model asks for #banner+obsidian:
	# the live manifest carries that key (and #crest/#horn+obsidian) as copies of #banner etc. since 05.10.
	var manager := _manager(["saurians/saurian guardians", "saurians/saurian guardians#banner",
		"saurians/saurian guardians#banner+obsidian"])
	var army := _army([{"armyId": SAURIAN_ARMY, "name": "Saurian Guardians", "size": 5, "bases": {"round": "32"},
		"loadout": [
			{"type": "ArmyBookWeapon", "name": "Obsidian Great Weapon", "attacks": 1, "count": 5},
			{"type": "ArmyBookItem", "name": "Banner", "count": 1, "content": []}]}])
	var names: Array = manager._unit_model_variant_names(army.units[0], "saurians")
	assert_int(names.count("Saurian Guardians#banner+obsidian")).is_equal(1)
	assert_int(names.count("")).is_equal(4)


func test_saurian_upgrade_words_map_to_the_plan_slugs() -> void:
	var lib: ModelLibrary = auto_free(ModelLibrary.new())
	lib._load_label_slug_map()
	var expected := {"Javelin": "javelin", "Blowpipe": "blowpipe", "Fire Bolas": "bolas",
		"Rock Barrage": "rocks", "Priest Rider": "priestrider", "Javelin Crew": "javelins",
		"Serpent Ark": "serpentark", "Solar Beam": "solarbeam", "Mace Tail": "macetail",
		"Dread Behemoth Fighter": "behemoth", "Dread Behemoth Carrier": "carrier", "Dread Pterodactyl": "pterodactyl",
		"Champion Javelin": "javelin", "Champion Blowpipe": "blowpipe", "Champion Fire Bolas": "bolas",
		"Deinonychus": "deinonychus", "Pterodactyl": "pterodactyl", "Ripjawdactyl": "ripjawdactyl",
		"Ancient Palanquin": "palanquin", "Starseer Palanquin": "palanquin",
		"Queztalcoatl": "skyserpent", "Raptor": "raptor", "Obsidian Great Weapon": "obsidian",
		"Tyrannosaur": "tyrannosaur"}
	for word in expected:
		assert_str(lib.variant_slug([word], "saurians")).is_equal(expected[word])
	# Scoped: another faction does not read the Saurian words.
	assert_str(lib.variant_slug(["Serpent Ark"], "ratmen")).is_equal("")


# --- Rules 3.6 weapon names: plain renames of the 3.5 words keep their bakes ----------------------------

func _one(unit_name: String, weapons: Array) -> OPRApiClient.OPRArmy:
	var loadout: Array = []
	for weapon in weapons:
		loadout.append({"type": "ArmyBookWeapon", "name": weapon, "range": 12, "attacks": 1, "count": 1})
	return _army([{"armyId": SAURIAN_ARMY, "name": unit_name, "size": 1, "bases": {"round": "32"}, "loadout": loadout}])


func test_rules_3_6_weapon_names_resolve_the_live_variants() -> void:
	var manager := _manager(["saurians/deinonychus riders#javelin", "saurians/geckos#blowpipe",
		"saurians/gecko champion#blowpipe", "saurians/gecko champion#deinonychus+javelin", "saurians/triceratops#blowpipe"])
	var cases := [
		["Deinonychus Riders", ["Javelins"], "Deinonychus Riders#javelin"],
		["Geckos", ["Toxin Blowpipe", "Strike"], "Geckos#blowpipe"],
		["Geckos", ["Scatter Blowpipe", "Strike"], "Geckos#blowpipe"],
		["Gecko Champion", ["Rapid Toxin Blowpipe", "Strike"], "Gecko Champion#blowpipe"],
		["Triceratops", ["Stomp", "Giant Toxin Blowpipes"], "Triceratops#blowpipe"],
		["Triceratops", ["Stomp", "Giant Scatter Blowpipes"], "Triceratops#blowpipe"],
	]
	for case in cases:
		assert_array(manager._unit_model_variant_names(_one(case[0], case[1]).units[0], "saurians")) \
			.is_equal([case[2]])
	var lib: ModelLibrary = manager.model_library
	assert_str(lib.variant_slug(["Javelins", "Toxin Club", "Deinonychus"], "saurians")).is_equal("deinonychus+javelin")
	# Scoped: another faction does not read the 3.6 Saurian words.
	assert_str(lib.variant_slug(["Javelins", "Toxin Blowpipe"], "ratmen")).is_equal("")


# --- Rules 3.6 Master weapons: the 3.5 weapon words under their Master names ------------------------------

func _on_a_mount(unit_name: String, weapon: String, mount: String) -> OPRApiClient.OPRArmy:
	return _army([{"armyId": SAURIAN_ARMY, "name": unit_name, "size": 1, "bases": {"round": "25"}, "loadout": [
		{"type": "ArmyBookWeapon", "name": weapon, "attacks": 3, "count": 1},
		{"type": "ArmyBookItem", "name": mount, "count": 1, "bases": {"round": "60x35"},
			"content": [{"type": "ArmyBookRule", "name": "Fast"}]}]}])


func test_rules_3_6_master_weapons_resolve_the_weapon_variants() -> void:
	# No Gecko Champion #greatweapon bake is live, so on the table that form keeps the base sculpt like the plain
	# Great Weapon; the key here proves the Master word reaches the great-weapon slug.
	var manager := _manager(["saurians/gecko champion#lance", "saurians/gecko champion#deinonychus+lance",
		"saurians/gecko champion#greatweapon", "saurians/saurian veteran#greatweapon+raptor"])
	var cases := [
		[_one("Gecko Champion", ["Master Lance"]), "Gecko Champion#lance"],
		[_on_a_mount("Gecko Champion", "Master Lance", "Deinonychus"), "Gecko Champion#deinonychus+lance"],
		[_one("Gecko Champion", ["Master Great Weapon"]), "Gecko Champion#greatweapon"],
		[_on_a_mount("Saurian Veteran", "Master Great Weapon", "Raptor"), "Saurian Veteran#greatweapon+raptor"],
	]
	for case in cases:
		assert_array(manager._unit_model_variant_names(case[0].units[0], "saurians")).is_equal([case[1]])


func test_rules_3_6_master_weapons_keep_the_mount_without_a_weapon_bake() -> void:
	# Live today: the mount bake only. The Master Great Weapon must not cost the Gecko Champion its Deinonychus,
	# and the Master Toxin Club (no model word, like the Toxin Club) resolves exactly like the Toxin Club.
	var manager := _manager(["saurians/gecko champion#deinonychus"])
	for weapon in ["Master Great Weapon", "Toxin Club", "Master Toxin Club"]:
		assert_array(manager._unit_model_variant_names(_on_a_mount("Gecko Champion", weapon, "Deinonychus").units[0],
			"saurians")).is_equal(["Gecko Champion#deinonychus"])
	var lib: ModelLibrary = manager.model_library
	assert_str(lib.variant_slug(["Toxin Club"], "saurians")).is_equal("")
	assert_str(lib.variant_slug(["Master Toxin Club"], "saurians")).is_equal("")

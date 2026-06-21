# gdUnit4 tests: an upgrade item that grants a special rule (Combat Shield -> Shielded) records the
# item -> granted-rules mapping for the unit-card hover cascade, while the granted rule still folds
# into special_rules for the rules engine.
extends GdUnitTestSuite


func _parse(loadout: Array, rules: Array = []) -> OPRApiClient.OPRUnit:
	var api: OPRApiClient = auto_free(OPRApiClient.new())
	var data := {
		"name": "Master Destroyer", "size": 1, "quality": 3, "defense": 3,
		"rules": rules, "loadout": loadout,
	}
	return api._parse_tts_unit(data)


func test_item_grants_maps_item_to_its_granted_rule() -> void:
	var unit := _parse([
		{"name": "Combat Shield", "content": [{"name": "Shielded"}]},
		{"name": "Preacher", "content": [{"name": "Bane in Melee Aura"}]},
	], [{"name": "Hero"}, {"name": "Fearless"}])

	assert_that(unit.item_grants.get("Combat Shield", [])).is_equal(["Shielded"])
	assert_that(unit.item_grants.get("Preacher", [])).is_equal(["Bane in Melee Aura"])
	# Granted rules + the item names still live in special_rules (functional + legacy display).
	assert_array(unit.special_rules).contains(
		["Combat Shield", "Shielded", "Preacher", "Bane in Melee Aura", "Hero", "Fearless"])


func test_rated_grant_is_formatted() -> void:
	var unit := _parse([{"name": "Power Source", "content": [{"name": "Caster", "rating": 2}]}])
	assert_that(unit.item_grants.get("Power Source", [])).is_equal(["Caster(2)"])


func test_plain_item_records_no_grant() -> void:
	var unit := _parse([{"name": "Plain Tool"}])  # no content / specialRules -> grants nothing
	assert_bool(unit.item_grants.has("Plain Tool")).is_false()


func test_item_granted_weapon_surfaces_as_weapon_not_rule() -> void:
	# A Weapon Team item carries a real weapon profile (HE Autocannon) in its content — it must show
	# in the unit's weapons (with range/attacks), NOT as a profile-less name in the rules line.
	var unit := _parse([
		{"name": "Weapon Team", "content": [
			{"name": "HE Autocannon", "type": "ArmyBookWeapon", "range": 36, "attacks": 3,
				"specialRules": [{"name": "AP", "rating": 1}]},
			{"name": "Tough", "type": "ArmyBookRule", "rating": 3},
		]},
	])
	var ac: OPRApiClient.OPRWeapon = null
	for w in unit.weapons:
		if w.name == "HE Autocannon":
			ac = w
	assert_object(ac).is_not_null()
	assert_int(ac.range_value).is_equal(36)
	assert_int(ac.attacks).is_equal(3)
	assert_str(ac.from_item).is_equal("Weapon Team")  # marked → build_loadout won't distribute it
	assert_bool("HE Autocannon" in unit.special_rules).is_false()  # not a rule anymore


func test_mount_item_records_its_own_oval_base() -> void:
	# A mount/vehicle upgrade (Combat Bike) brings its own base — recorded so the carrier model gets
	# that base (60x35 oval) + a mount GLB instead of the foot base/model.
	var unit := _parse([
		{"name": "Combat Bike", "bases": {"round": "60x35", "square": "50x25"}, "content": [
			{"name": "Tough", "type": "ArmyBookRule", "rating": 3},
			{"name": "Twin Heavy Rifle", "type": "ArmyBookWeapon", "range": 24, "attacks": 2},
		]},
	])
	assert_array(unit.mount_base).is_equal([true, 35, 60])  # [is_oval, width_mm, depth_mm]
	assert_str(unit.mount_name).is_equal("Combat Bike")
	# Single-model unit: the mount base REPLACES the foot base, so it persists via unit properties
	# (save/load + MP) and drives the model fit — not just an import-time override.
	assert_bool(unit.base_is_oval).is_true()
	assert_int(unit.base_width_mm).is_equal(35)
	assert_int(unit.base_depth_mm).is_equal(60)


func test_extract_spells_parses_faction_spell_list() -> void:
	var api: OPRApiClient = auto_free(OPRApiClient.new())
	var army := OPRApiClient.OPRArmy.new()
	api._extract_spells(army, {"spells": [
		{"name": "Animate Spirit", "threshold": 1, "effect": "Pick one friendly unit within 12\"."},
		{"name": "Frenzy", "threshold": 2, "effect": "Target gets Furious."},
		{"name": "", "effect": "ignored (no name)"},
	]})
	assert_int(army.spells.size()).is_equal(2)  # the nameless one is dropped
	assert_that(army.spells[0].get("name")).is_equal("Animate Spirit")
	assert_int(army.spells[0].get("threshold")).is_equal(1)
	assert_that(army.spells[1].get("name")).is_equal("Frenzy")


func test_spell_radius_parsed_from_effect() -> void:
	assert_int(OPRApiClient.spell_radius_inches("Pick one friendly unit within 12\", which gets X.")).is_equal(12)
	assert_int(OPRApiClient.spell_radius_inches("Target enemy unit within 6\" takes 3 hits.")).is_equal(6)
	assert_int(OPRApiClient.spell_radius_inches("Target gets Furious next time it fights.")).is_equal(0)


func test_rules_referenced_in_finds_granted_rules() -> void:
	var oam: OPRArmyManager = auto_free(OPRArmyManager.new())
	oam.rule_descriptions = {"Shred": "Ignores Regeneration.", "Furious": "Extra hit on 6s.", "AP": "x"}
	var found: Array = oam.rules_referenced_in("Target gets Shred and Furious this round.")
	assert_array(found).contains(["Shred", "Furious"])
	# No false positive on a mere substring (not a whole word), nor on a < 4-char rule name.
	assert_bool(oam.rules_referenced_in("Shredded plating").has("Shred")).is_false()
	assert_bool(found.has("AP")).is_false()

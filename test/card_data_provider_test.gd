extends GdUnitTestSuite
## D8: UnitDock._card_data is the bridge from a GameUnit to the plain data Dictionary CardFace renders.
## It must REUSE the unit's own accessors + OPR source data (weapons/rules), not re-derive them. These
## tests pin the data shape CardFace depends on.


func _opr_unit() -> GameUnit:
	var u := GameUnit.new()
	u.unit_properties = {"name": "Test Unit", "cost": 215, "quality": 3, "defense": 3,
		"special_rules": ["Fearless", "Relentless"]}
	u.is_activated = true
	var m1 := ModelInstance.new()
	m1.is_alive = true
	var m2 := ModelInstance.new()
	m2.is_alive = false
	u.models = [m1, m2]
	u.source_type = "opr"
	var opr := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Spear"
	w.range_value = 0
	w.attacks = 1
	w.count = 2
	w.special_rules = ["Counter"]
	opr.weapons = [w]
	u.source_data = opr
	return u


func test_card_data_reuses_accessors_and_opr_weapons() -> void:
	var dock: UnitDock = auto_free(UnitDock.new())
	var d: Dictionary = dock._card_data(_opr_unit())
	assert_int(int(d["points"])).is_equal(215)
	assert_int(int(d["quality"])).is_equal(3)
	assert_int(int(d["defense"])).is_equal(3)
	assert_int(int(d["alive"])).is_equal(1)
	assert_int(int(d["total"])).is_equal(2)
	assert_bool(bool(d["activated"])).is_true()
	assert_bool(bool(d["dead"])).is_false()
	assert_bool(bool(d["coherent"])).is_true()
	assert_array(d["rules_list"]).contains_exactly(["Fearless", "Relentless"])   # hoverable rules list (033)
	var weapons: Array = d["weapons"]
	assert_int(weapons.size()).is_equal(1)
	var w: Dictionary = weapons[0]
	assert_str(str(w["name"])).is_equal("2x Spear")
	assert_str(str(w["meta"])).is_equal("A1")   # melee → no range token (bus 027)
	assert_str(str(w["rules"])).is_equal("Counter")


func test_card_data_without_opr_source_has_no_weapons_or_rules() -> void:
	var dock: UnitDock = auto_free(UnitDock.new())
	var u := GameUnit.new()
	u.unit_properties = {"name": "Plain", "cost": 10, "quality": 4, "defense": 4}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models = [m]
	var d: Dictionary = dock._card_data(u)
	assert_array(d["weapons"]).is_empty()
	assert_array(d["rules_list"]).is_empty()
	assert_bool(bool(d["dead"])).is_false()


## The old UnitCard's tooltip cascades, ported to the dock (issue #74): a spell/rule that references
## another known rule reveals it, an item shows what it grants, and granted rules are hidden from the
## flat rules list (reached through the item's tooltip instead).
func test_rule_tooltip_cascades_referenced_rules_and_item_grants() -> void:
	var dock: UnitDock = auto_free(UnitDock.new())
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.rule_descriptions = {"Blast": "Ignores cover.", "Shielded": "Gets +1 to defense rolls."}
	dock.army_manager = army
	var u := GameUnit.new()
	u.unit_properties = {"name": "Mage", "cost": 50, "quality": 4, "defense": 4, "player_id": 1,
		"special_rules": ["Caster(2)", "Combat Shield", "Shielded"],
		"item_grants": {"Combat Shield": ["Shielded"]}}
	army._session_spells[1] = [{"name": "Fireball", "threshold": 2, "effect": "Target takes 6 hits with Blast(3)."}]
	dock._presented_unit = u
	# Spell tooltip reveals the referenced Blast rule.
	var spell_tip := dock._rule_description("spell:Fireball", u)
	assert_bool(spell_tip.contains("Blast — Ignores cover.")).is_true()
	# Item tooltip lists what it grants instead of its own (empty) description.
	var item_tip := dock._rule_description("Combat Shield", u)
	assert_bool(item_tip.contains("grants:")).is_true()
	assert_bool(item_tip.contains("Shielded — Gets +1 to defense rolls.")).is_true()
	# The granted rule is hidden from the flat rules list.
	var m := ModelInstance.new()
	m.is_alive = true
	u.models = [m]
	var d: Dictionary = dock._card_data(u)
	assert_array(d["rules_list"]).contains_exactly(["Caster(2)", "Combat Shield"])


func _weapon(nm: String, rng: int, atk: int, count: int, rules: Array) -> OPRApiClient.OPRWeapon:
	var w := OPRApiClient.OPRWeapon.new()
	w.name = nm
	w.range_value = rng
	w.attacks = atk
	w.count = count
	w.special_rules.assign(rules)
	return w


## Pins the APPROVED weapon stat-string format (bus 027): no "Melee" token, AP inline in the stat
## column (no parens), the cyan sub-line only for named rules.
func test_weapon_entry_format_melee_ranged_ap_and_named_rules() -> void:
	var dock: UnitDock = auto_free(UnitDock.new())

	# Plain melee → attacks only, no range token, no rules.
	var melee: Dictionary = dock._weapon_entry(_weapon("CCW", 0, 2, 1, []))
	assert_str(str(melee["name"])).is_equal("CCW")
	assert_str(str(melee["meta"])).is_equal("A2")
	assert_str(str(melee["rules"])).is_equal("")

	# Ranged + AP → range, attacks, AP inline in the stat AND listed as a hoverable rule (bus feedback).
	var ranged: Dictionary = dock._weapon_entry(_weapon("Heavy Rifle", 30, 1, 1, ["AP(1)"]))
	assert_str(str(ranged["meta"])).is_equal("30\" A1 AP1")
	assert_str(str(ranged["rules"])).is_equal("AP(1)")

	# Melee + AP → no range, attacks, AP inline.
	var melee_ap: Dictionary = dock._weapon_entry(_weapon("Great Weapon", 0, 2, 1, ["AP(2)"]))
	assert_str(str(melee_ap["meta"])).is_equal("A2 AP2")
	assert_str(str(melee_ap["rules"])).is_equal("AP(2)")

	# Count prefix + AP inline in the stat + every rule (incl. AP) on the hoverable rule line.
	var multi: Dictionary = dock._weapon_entry(_weapon("Daemon Claws", 0, 4, 2, ["AP(1)", "Counter", "Deadly(2)"]))
	assert_str(str(multi["name"])).is_equal("2x Daemon Claws")
	assert_str(str(multi["meta"])).is_equal("A4 AP1")
	assert_str(str(multi["rules"])).is_equal("AP(1), Counter, Deadly(2)")

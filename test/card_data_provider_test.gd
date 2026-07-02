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
	assert_str(str(d["rules"])).is_equal("Fearless · Relentless")
	var weapons: Array = d["weapons"]
	assert_int(weapons.size()).is_equal(1)
	var w: Dictionary = weapons[0]
	assert_str(str(w["name"])).is_equal("2x Spear")
	assert_str(str(w["meta"])).is_equal("Melee A1")
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
	assert_str(str(d["rules"])).is_equal("")
	assert_bool(bool(d["dead"])).is_false()


func test_card_data_ranged_weapon_meta() -> void:
	var dock: UnitDock = auto_free(UnitDock.new())
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Heavy Rifle"
	w.range_value = 30
	w.attacks = 1
	w.count = 1
	w.special_rules = ["AP(1)"]
	var e: Dictionary = dock._weapon_entry(w)
	assert_str(str(e["name"])).is_equal("Heavy Rifle")
	assert_str(str(e["meta"])).is_equal("30\" A1")
	assert_str(str(e["rules"])).is_equal("AP(1)")
